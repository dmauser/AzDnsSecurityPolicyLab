#Requires -Version 5.1
<#
.SYNOPSIS
    Deploys the Azure DNS Security Policy Lab using Bicep.
.DESCRIPTION
    Reads subscription/resource group from answers.json, prompts for the VM
    admin password, creates the resource group, and runs an ARM/Bicep deployment.
.EXAMPLE
    .\Deploy-Lab.ps1
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host '==========================================' -ForegroundColor Cyan
Write-Host ' Azure DNS Security Policy Lab Deployment ' -ForegroundColor Cyan
Write-Host '==========================================' -ForegroundColor Cyan

# ── Read configuration ────────────────────────────────────────────────────────
$answersFile = Join-Path $PSScriptRoot 'answers.json'
if (-not (Test-Path $answersFile)) {
    Write-Error "answers.json not found. Copy answers.json.template to answers.json and set your subscriptionId."
}

$config = Get-Content $answersFile -Raw | ConvertFrom-Json
$subscriptionId    = $config.subscriptionId
$resourceGroupName = $config.resourceGroupName

if ([string]::IsNullOrWhiteSpace($subscriptionId) -or $subscriptionId -eq 'YOUR-SUBSCRIPTION-ID-HERE') {
    Write-Error "Please set a valid subscriptionId in answers.json before deploying."
}

# ── Password prompt ───────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Password Requirements:" -ForegroundColor Yellow
Write-Host "  - 12-123 characters"
Write-Host "  - Uppercase, lowercase, number, and special character"
Write-Host ""

function Test-VmPassword {
    param([string]$Password)
    if ($Password.Length -lt 12 -or $Password.Length -gt 123) { return $false }
    if ($Password -cnotmatch '[A-Z]') { return $false }
    if ($Password -cnotmatch '[a-z]') { return $false }
    if ($Password -notmatch '[0-9]')  { return $false }
    if ($Password -notmatch '[^a-zA-Z0-9]') { return $false }
    return $true
}

$vmPassword = $null
while ($true) {
    $securePass    = Read-Host 'Enter VM admin password (azureuser)' -AsSecureString
    $securConfirm  = Read-Host 'Confirm VM admin password'           -AsSecureString

    $plain   = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                   [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass))
    $confirm = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                   [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securConfirm))

    if ($plain -ne $confirm) {
        Write-Host "Passwords do not match. Try again." -ForegroundColor Red
        continue
    }
    if (-not (Test-VmPassword $plain)) {
        Write-Host "Password does not meet complexity requirements. Try again." -ForegroundColor Red
        continue
    }
    $vmPassword = $plain
    Write-Host "Password confirmed." -ForegroundColor Green
    break
}

# ── Azure login ───────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Logging into Azure..." -ForegroundColor Cyan
az login --use-device-code

az config set extension.dynamic_install_allow_preview=true 2>$null
az config set extension.use_dynamic_install=yes_without_prompt 2>$null

Write-Host "Setting subscription: $subscriptionId"
az account set --subscription $subscriptionId

$currentSub = (az account show --query id -o tsv).Trim()
if ($currentSub -ne $subscriptionId) {
    Write-Error "Failed to set subscription context."
}
Write-Host "Active subscription: $((az account show --query name -o tsv).Trim())" -ForegroundColor Green

# ── Create resource group ─────────────────────────────────────────────────────
Write-Host ""
Write-Host "Creating resource group: $resourceGroupName" -ForegroundColor Cyan
az group create `
    --name $resourceGroupName `
    --location 'eastus2' `
    --tags Purpose=DNS-Security-Lab Environment=Lab | Out-Null

# ── Deploy Bicep ──────────────────────────────────────────────────────────────
$templateFile  = Join-Path $PSScriptRoot 'infra' 'main.bicep'
$parametersFile = Join-Path $PSScriptRoot 'infra' 'main.bicepparam'

Write-Host ""
Write-Host "Deploying Bicep template..." -ForegroundColor Cyan

$deployOutput = az deployment group create `
    --resource-group $resourceGroupName `
    --template-file $templateFile `
    --parameters $parametersFile `
    --parameters "vmAdminPassword=$vmPassword" `
    --output json | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) {
    Write-Error "Deployment failed. Check the output above for details."
}

# ── Print summary ─────────────────────────────────────────────────────────────
$outputs = $deployOutput.properties.outputs

Write-Host ""
Write-Host '==========================================' -ForegroundColor Green
Write-Host '   DEPLOYMENT COMPLETED SUCCESSFULLY!     ' -ForegroundColor Green
Write-Host '==========================================' -ForegroundColor Green
Write-Host ""
Write-Host "Lab Environment Details:" -ForegroundColor Yellow
Write-Host "  Resource Group      : $($outputs.resourceGroupName.value)"
Write-Host "  VM Name             : $($outputs.vmName.value)"
Write-Host "  VM Username         : $($outputs.vmAdminUsername.value)"
Write-Host "  Virtual Network     : $($outputs.vnetName.value)"
Write-Host "  DNS Security Policy : $($outputs.dnsSecurityPolicyName.value)"
Write-Host "  Log Analytics WS    : $($outputs.logAnalyticsWorkspaceName.value)"
Write-Host "  Blocked Domains     : $($outputs.blockedDomains.value -join ', ')"
Write-Host ""
Write-Host "VM Access (Serial Console):" -ForegroundColor Yellow
Write-Host "  1. Go to https://portal.azure.com"
Write-Host "  2. Navigate to Virtual Machines > $($outputs.vmName.value)"
Write-Host "  3. Click 'Serial console' under Help"
Write-Host "  4. Login with username: $($outputs.vmAdminUsername.value)"
Write-Host ""
Write-Host "Test DNS blocking from the VM:" -ForegroundColor Yellow
Write-Host "  dig malicious.contoso.com   # should return blockpolicy.azuredns.invalid"
Write-Host "  dig exploit.adatum.com      # should return blockpolicy.azuredns.invalid"
Write-Host "  dig google.com              # should resolve normally"
Write-Host ""
