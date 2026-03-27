#Requires -Version 5.1
<#
.SYNOPSIS
    Removes the Azure DNS Security Policy Lab resource group and all resources.
.EXAMPLE
    .\scripts\remove-lab.ps1
#>

[CmdletBinding(SupportsShouldProcess)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host '========================================' -ForegroundColor Cyan
Write-Host ' Azure DNS Security Policy Lab Removal  ' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan

# ── Ensure Az.Resources module is available ───────────────────────────────────
if (-not (Get-Module -ListAvailable -Name Az.Resources -ErrorAction SilentlyContinue)) {
    Write-Host "Az.Resources module not found. Installing..." -ForegroundColor Yellow
    Install-Module Az.Resources -Scope CurrentUser -Force -AllowClobber -Repository PSGallery
}
Import-Module Az.Resources -ErrorAction Stop

# ── Read configuration ────────────────────────────────────────────────────────
$repoRoot = Split-Path $PSScriptRoot -Parent
$answersFile = Join-Path $repoRoot 'answers.json'
if (-not (Test-Path $answersFile)) {
    Write-Error "answers.json not found in the repo root."
}

$config = Get-Content $answersFile -Raw | ConvertFrom-Json
$resourceGroupName = $config.resourceGroupName

# ── Azure login (reuse existing session, login only if needed) ────────────────
Write-Host ""
Write-Host "Checking for existing Azure session..." -ForegroundColor Cyan
$available = @(Get-AzSubscription -ErrorAction SilentlyContinue | Where-Object State -eq 'Enabled')

if ($available.Count -eq 0) {
    Write-Host "No active session found. Logging into Azure..." -ForegroundColor Yellow
    Connect-AzAccount -UseDeviceAuthentication | Out-Null
    $available = @(Get-AzSubscription | Where-Object State -eq 'Enabled')
}

if ($available.Count -eq 0) {
    Write-Error "No enabled Azure subscriptions found for the logged-in account."
}

Write-Host ""
Write-Host "Available subscriptions:" -ForegroundColor Yellow
for ($i = 0; $i -lt $available.Count; $i++) {
    Write-Host "  [$($i + 1)] $($available[$i].Name)" -ForegroundColor White
    Write-Host "      $($available[$i].Id)" -ForegroundColor DarkGray
}

$selectedIndex = $null
while ($null -eq $selectedIndex) {
    $input = Read-Host "`nSelect subscription (1-$($available.Count))"
    if ($input -match '^\d+$') {
        $n = [int]$input
        if ($n -ge 1 -and $n -le $available.Count) { $selectedIndex = $n - 1 }
    }
    if ($null -eq $selectedIndex) {
        Write-Host "Invalid selection. Enter a number between 1 and $($available.Count)." -ForegroundColor Red
    }
}

$selectedSub = $available[$selectedIndex]
Set-AzContext -SubscriptionId $selectedSub.Id | Out-Null
Write-Host "Using subscription: $($selectedSub.Name) ($($selectedSub.Id))" -ForegroundColor Green

# ── Check resource group exists ───────────────────────────────────────────────
Write-Host ""
if (-not (Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue)) {
    Write-Host "Resource group '$resourceGroupName' does not exist. Nothing to remove." -ForegroundColor Yellow
    exit 0
}

# ── Confirm deletion ──────────────────────────────────────────────────────────
Write-Host ""
Write-Host "WARNING: This will permanently delete resource group '$resourceGroupName'" -ForegroundColor Red
Write-Host "         and ALL resources inside it." -ForegroundColor Red
Write-Host ""
$confirm = Read-Host "Type the resource group name to confirm deletion"

if ($confirm -ne $resourceGroupName) {
    Write-Host "Confirmation did not match. Deletion cancelled." -ForegroundColor Yellow
    exit 0
}

# ── Delete resource group ─────────────────────────────────────────────────────
Write-Host ""
Write-Host "Deleting resource group '$resourceGroupName'..." -ForegroundColor Cyan
Remove-AzResourceGroup -Name $resourceGroupName -Force -AsJob | Out-Null

Write-Host ""
Write-Host "Deletion initiated. The resource group is being removed in the background." -ForegroundColor Green
Write-Host "You can monitor progress in the Azure Portal under Resource Groups." -ForegroundColor Green

