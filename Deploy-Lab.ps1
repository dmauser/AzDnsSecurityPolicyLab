#Requires -Version 5.1
<#
.SYNOPSIS
    Deploys the Azure DNS Security Policy Lab using Bicep.
.DESCRIPTION
    Uses the Az PowerShell module (New-AzResourceGroupDeployment) to deploy
    infra/main.bicep — the native Bicep path in PowerShell.
    Reads the resource group name from answers.json, logs in with device code,
    lets you choose a subscription interactively, and prompts for the VM password.
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

# ── Ensure Az.Resources module is available ───────────────────────────────────
if (-not (Get-Module -ListAvailable -Name Az.Resources -ErrorAction SilentlyContinue)) {
    Write-Host "Az.Resources module not found. Installing..." -ForegroundColor Yellow
    Install-Module Az.Resources -Scope CurrentUser -Force -AllowClobber -Repository PSGallery
}
Import-Module Az.Resources -ErrorAction Stop

# ── Ensure Bicep CLI is available (required by New-AzResourceGroupDeployment) ─
# The Az module calls the Bicep CLI directly to compile .bicep files.
# If not on PATH, install it via 'az bicep install' (uses the az CLI already present).
if (-not (Get-Command bicep -ErrorAction SilentlyContinue)) {
    Write-Host "Bicep CLI not found. Installing via Azure CLI..." -ForegroundColor Yellow
    az bicep install 2>&1 | Out-Null
    # az bicep installs the binary to %USERPROFILE%\.azure\bin on Windows
    $azBicepBin = Join-Path (Join-Path $env:USERPROFILE '.azure') 'bin'
    if (Test-Path (Join-Path $azBicepBin 'bicep.exe')) {
        $env:PATH = "$azBicepBin;$env:PATH"
        Write-Host "Bicep CLI installed." -ForegroundColor Green
    } else {
        Write-Error "Could not install Bicep CLI automatically. Install it manually: https://aka.ms/bicep-install"
    }
} else {
    Write-Host "Bicep CLI found: $(bicep --version 2>&1 | Select-Object -First 1)" -ForegroundColor DarkGray
}

# ── Read configuration ────────────────────────────────────────────────────────
$answersFile = Join-Path $PSScriptRoot 'answers.json'
if (-not (Test-Path $answersFile)) {
    Write-Error "answers.json not found. Copy answers.json.template to answers.json."
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

# ── Subscription selection ────────────────────────────────────────────────────
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
Set-AzContext -SubscriptionId $selectedSub.Id -TenantId $selectedSub.TenantId | Out-Null
Write-Host "Using subscription: $($selectedSub.Name) ($($selectedSub.Id))" -ForegroundColor Green

# ── Resolve caller's Azure AD Object ID (needed for Key Vault access policy) ──
Write-Host ""
Write-Host "Resolving your Azure AD Object ID for Key Vault access..." -ForegroundColor Cyan
$callerOid = $null

# 1st attempt: Az module (works for most organisational accounts)
try {
    $callerOid = (Get-AzADUser -UserPrincipalName (Get-AzContext).Account.Id -ErrorAction Stop).Id
} catch { }

# 2nd attempt: az CLI (works for Microsoft accounts, guest accounts, and MSA-backed identities)
if (-not $callerOid) {
    try {
        $callerOid = (az ad signed-in-user show --query id -o tsv 2>$null).Trim()
    } catch { }
}

if (-not $callerOid) {
    Write-Host "Could not auto-detect your Azure AD Object ID." -ForegroundColor Yellow
    Write-Host "  Run manually: az ad signed-in-user show --query id -o tsv" -ForegroundColor DarkGray
    $callerOid = Read-Host "Azure AD Object ID"
}
Write-Host "Key Vault access will be granted to OID: $callerOid" -ForegroundColor DarkGray

# ── Create resource group ─────────────────────────────────────────────────────
Write-Host ""
Write-Host "Creating resource group: $resourceGroupName" -ForegroundColor Cyan
New-AzResourceGroup `
    -Name $resourceGroupName `
    -Location 'eastus2' `
    -Tag @{ Purpose = 'DNS-Security-Lab'; Environment = 'Lab' } `
    -Force | Out-Null

# ── Deploy Bicep ──────────────────────────────────────────────────────────────
$infraDir       = Join-Path $PSScriptRoot 'infra'
$templateFile   = Join-Path $infraDir 'main.bicep'
$parametersFile = Join-Path $infraDir 'main.bicepparam'

Write-Host ""
Write-Host "Deploying Bicep template..." -ForegroundColor Cyan

# Use az deployment group create — it natively supports .bicepparam files
# and allows passing extra --parameters alongside the file (no parameter-set conflicts).
# The az CLI session is already set to the correct subscription via Set-AzContext above.
az account set --subscription $selectedSub.Id | Out-Null

# Run the deployment; write JSON to a temp file to avoid PowerShell capturing
# non-JSON stdout lines (e.g. "Bicep." from the Bicep compiler) into the variable.
$tmpOut = [System.IO.Path]::GetTempFileName()
$tmpErr = [System.IO.Path]::GetTempFileName()

$proc = Start-Process -FilePath 'az' `
    -ArgumentList @(
        'deployment', 'group', 'create',
        '--resource-group', $resourceGroupName,
        '--template-file', "`"$templateFile`"",
        '--parameters', "`"$parametersFile`"",
        '--parameters', "keyVaultAdminObjectId=$callerOid",
        '--only-show-errors',
        '--output', 'json'
    ) `
    -NoNewWindow -Wait -PassThru `
    -RedirectStandardOutput $tmpOut `
    -RedirectStandardError $tmpErr

$azExitCode = $proc.ExitCode

if ($azExitCode -ne 0) {
    $stderrText = Get-Content $tmpErr -Raw
    Remove-Item $tmpOut, $tmpErr -Force -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host '==========================================' -ForegroundColor Red
    Write-Host '         DEPLOYMENT FAILED                ' -ForegroundColor Red
    Write-Host '==========================================' -ForegroundColor Red
    Write-Host ""

    # Parse friendly messages for known error codes
    if ($stderrText -match '"code"\s*:\s*"SkuNotAvailable"') {
        $skuMatch  = [regex]::Match($stderrText, 'Standard_\w+')
        $locMatch  = [regex]::Match($stderrText, "location '([^']+)'")
        $sku = if ($skuMatch.Success) { $skuMatch.Value } else { 'the requested SKU' }
        $loc = if ($locMatch.Success) { $locMatch.Groups[1].Value } else { 'the selected region' }

        Write-Host "VM SKU '$sku' is not available in region '$loc'." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "How to fix:" -ForegroundColor Cyan
        Write-Host "  Option 1: Change the region in infra/main.bicepparam (e.g. westus2, westeurope)"
        Write-Host "  Option 2: Change vmSize in infra/main.bicepparam (e.g. Standard_B2s, Standard_DS1_v2)"
        Write-Host ""
        Write-Host "Check available SKUs for a region:" -ForegroundColor Cyan
        Write-Host "  az vm list-skus --location $loc --size Standard_B --output table"
        Write-Host ""
    }
    elseif ($stderrText -match '"code"\s*:\s*"BastionHostSkuNotAvailable"' -or $stderrText -match 'Bastion.*not available') {
        Write-Host "Azure Bastion Developer SKU is not available in this region." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "How to fix:" -ForegroundColor Cyan
        Write-Host "  Change 'location' in infra/main.bicepparam to a supported region."
        Write-Host "  Supported regions include: eastus, westus, eastus2, westeurope, northeurope"
        Write-Host "  Full list: https://aka.ms/bastionsku"
        Write-Host ""
    }
    else {
        Write-Host "Error details:" -ForegroundColor Yellow
        Write-Host $stderrText
        Write-Host ""
    }

    # Clean up the partial resource group if desired
    Write-Host "The resource group '$resourceGroupName' may contain partial resources." -ForegroundColor DarkGray
    Write-Host "To clean up: Remove-Lab.ps1  (or: az group delete -n $resourceGroupName --no-wait)" -ForegroundColor DarkGray
    Write-Host ""
    exit 1
}

# Read the output file; strip any non-JSON lines (e.g. "Bicep.") before the opening brace
$rawOutput = Get-Content $tmpOut -Raw
Remove-Item $tmpOut, $tmpErr -Force -ErrorAction SilentlyContinue

$jsonStart = $rawOutput.IndexOf('{')
if ($jsonStart -lt 0) {
    Write-Error "No JSON found in deployment output:`n$rawOutput"
}
$cleanJson = $rawOutput.Substring($jsonStart)

$deployResult = ($cleanJson | ConvertFrom-Json).properties.outputs

# ── Print summary ─────────────────────────────────────────────────────────────
function Get-Out([string]$key) { $deployResult.$key.value }

Write-Host ""
Write-Host '==========================================' -ForegroundColor Green
Write-Host '   DEPLOYMENT COMPLETED SUCCESSFULLY!     ' -ForegroundColor Green
Write-Host '==========================================' -ForegroundColor Green
Write-Host ""
Write-Host "Lab Environment Details:" -ForegroundColor Yellow
Write-Host "  Resource Group      : $(Get-Out resourceGroupName)"
Write-Host "  VM Name             : $(Get-Out vmName)"
Write-Host "  VM Username         : $(Get-Out vmAdminUsername)"
Write-Host "  Virtual Network     : $(Get-Out vnetName)"
Write-Host "  Azure Bastion       : $(Get-Out bastionName)"
Write-Host "  DNS Security Policy : $(Get-Out dnsSecurityPolicyName)"
Write-Host "  Log Analytics WS    : $(Get-Out logAnalyticsWorkspaceName)"
Write-Host "  Blocked Domains     : $($(Get-Out blockedDomains) -join ', ')"
Write-Host "  Key Vault           : $(Get-Out keyVaultName)"
Write-Host ""
Write-Host "Retrieve VM Password from Key Vault:" -ForegroundColor Yellow
Write-Host "  PowerShell: Get-AzKeyVaultSecret -VaultName '$(Get-Out keyVaultName)' -Name 'vm-admin-password' -AsPlainText" -ForegroundColor White
Write-Host "  Azure CLI : az keyvault secret show --vault-name '$(Get-Out keyVaultName)' --name 'vm-admin-password' --query value -o tsv" -ForegroundColor White
Write-Host ""
Write-Host "VM Access via Azure Bastion (Developer SKU):" -ForegroundColor Yellow
Write-Host "  1. Go to https://portal.azure.com"
Write-Host "  2. Navigate to Virtual Machines > $(Get-Out vmName)"
Write-Host "  3. Click 'Connect' > 'Connect via Bastion'"
Write-Host "  4. Authentication Type: 'Password' (NOT 'Password from Azure Key Vault')"
Write-Host "  5. Username: $(Get-Out vmAdminUsername)"
Write-Host "  6. Paste the password retrieved from Key Vault above"
Write-Host ""
Write-Host "  NOTE: 'Password from Azure Key Vault' requires Bastion Basic/Standard SKU (~`$139/mo)." -ForegroundColor DarkGray
Write-Host "        Developer SKU is free — just retrieve and paste the password manually." -ForegroundColor DarkGray
Write-Host ""
Write-Host "Test DNS blocking from the VM:" -ForegroundColor Yellow
Write-Host "  dig malicious.contoso.com   # should return blockpolicy.azuredns.invalid"
Write-Host "  dig exploit.adatum.com      # should return blockpolicy.azuredns.invalid"
Write-Host "  dig google.com              # should resolve normally"
Write-Host ""

