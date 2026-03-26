#Requires -Version 5.1
<#
.SYNOPSIS
    Removes the Azure DNS Security Policy Lab resource group and all resources.
.EXAMPLE
    .\Remove-Lab.ps1
#>

[CmdletBinding(SupportsShouldProcess)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host '========================================' -ForegroundColor Cyan
Write-Host ' Azure DNS Security Policy Lab Removal  ' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan

# ── Read configuration ────────────────────────────────────────────────────────
$answersFile = Join-Path $PSScriptRoot 'answers.json'
if (-not (Test-Path $answersFile)) {
    Write-Error "answers.json not found."
}

$config = Get-Content $answersFile -Raw | ConvertFrom-Json
$subscriptionId    = $config.subscriptionId
$resourceGroupName = $config.resourceGroupName

if ([string]::IsNullOrWhiteSpace($subscriptionId) -or $subscriptionId -eq 'YOUR-SUBSCRIPTION-ID-HERE') {
    Write-Error "Please set a valid subscriptionId in answers.json."
}

# ── Azure login ───────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Logging into Azure..." -ForegroundColor Cyan
az login --use-device-code

Write-Host "Setting subscription: $subscriptionId"
az account set --subscription $subscriptionId

$currentSub = (az account show --query id -o tsv).Trim()
if ($currentSub -ne $subscriptionId) {
    Write-Error "Failed to set subscription context."
}
Write-Host "Active subscription: $((az account show --query name -o tsv).Trim())" -ForegroundColor Green

# ── Check resource group exists ───────────────────────────────────────────────
Write-Host ""
$rgExists = az group exists --name $resourceGroupName
if ($rgExists -eq 'false') {
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
az group delete --name $resourceGroupName --yes --no-wait

Write-Host ""
Write-Host "Deletion initiated. The resource group is being removed in the background." -ForegroundColor Green
Write-Host "You can monitor progress in the Azure Portal under Resource Groups." -ForegroundColor Green
