<#
.SYNOPSIS
    Deploys ZavaWarehouse static website to Azure Storage
.DESCRIPTION
    Creates (or updates) an Azure Storage account with static website hosting,
    and uploads the HTML, CSS, and JavaScript files.
    Uses the same resource group as the Key Vault provisioning script.
#>

param(
    [string]$Location = "eastus",
    [string]$StorageAccountPrefix = "zavawarehouse",
    [string]$StorageSku = "Standard_LRS"
)

# Color output functions
function Write-Step { param([string]$Message) Write-Host "`n[STEP] $Message" -ForegroundColor Cyan }
function Write-Success { param([string]$Message) Write-Host "  ✓ $Message" -ForegroundColor Green }
function Write-Info { param([string]$Message) Write-Host "  ℹ $Message" -ForegroundColor Yellow }
function Write-ErrorMsg { param([string]$Message) Write-Host "  ✗ $Message" -ForegroundColor Red }

# Error handling
$ErrorActionPreference = "Stop"

# Resolve site directory for file uploads
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$SiteDir = Join-Path $ScriptDir "site"

try {
    Write-Host "============================================" -ForegroundColor Magenta
    Write-Host "  ZavaWarehouse Website Deployment Script" -ForegroundColor Magenta
    Write-Host "============================================" -ForegroundColor Magenta

    # Step 1: Verify Azure CLI & Authentication
    Write-Step "Verifying Azure CLI authentication..."

    $account = $null
    try {
        $accountJson = az account show 2>&1
        if ($LASTEXITCODE -eq 0) {
            $account = $accountJson | ConvertFrom-Json
            Write-Success "Currently authenticated as: $($account.user.name)"
            Write-Success "Subscription: $($account.name)"
            Write-Success "Tenant: $($account.tenantId)"
            Write-Host ""

            $reauth = Read-Host "Do you want to re-authenticate? (y/N)"
            if ($reauth -eq 'y' -or $reauth -eq 'Y') {
                $account = $null
            }
        }
    }
    catch {
        Write-Info "Not currently authenticated to Azure."
    }

    if ($null -eq $account) {
        Write-Info "Starting device code authentication..."
        Write-Host ""
        Write-Host "Follow these steps:" -ForegroundColor Yellow
        Write-Host "  1. Copy the code displayed below" -ForegroundColor Yellow
        Write-Host "  2. Open https://microsoft.com/devicelogin in a browser" -ForegroundColor Yellow
        Write-Host "  3. Paste the code and complete sign-in" -ForegroundColor Yellow
        Write-Host ""

        az login --use-device-code

        if ($LASTEXITCODE -ne 0) {
            throw "Azure authentication failed"
        }

        $account = az account show | ConvertFrom-Json
        Write-Success "Authentication successful!"
    }

    # Store current user info
    $currentUserId = $account.user.name
    $subscriptionId = $account.id

    # Derive resource names from username (same convention as provision-keyvault.ps1)
    $userPrefix = $currentUserId.Split('@')[0].ToLower() -replace '[^a-z0-9]', ''
    $ResourceGroup = "rg-aitour26-$userPrefix"
    # Storage account names: 3-24 chars, lowercase alphanumeric only
    $StorageAccount = "$StorageAccountPrefix$userPrefix"
    if ($StorageAccount.Length -gt 24) {
        $StorageAccount = $StorageAccount.Substring(0, 24)
    }

    Write-Info "Resource Group:   $ResourceGroup"
    Write-Info "Storage Account:  $StorageAccount"
    Write-Host ""
    $customNames = Read-Host "Use these names? (Y/n, or press Enter to accept)"
    if ($customNames -eq 'n' -or $customNames -eq 'N') {
        $ResourceGroup = Read-Host "Enter Resource Group name"
        $StorageAccount = Read-Host "Enter Storage Account name (3-24 chars, lowercase alphanumeric)"
    }

    # Step 2: Select Subscription
    Write-Step "Selecting Azure subscription..."

    $subscriptions = az account list --query "[].{Name:name, SubscriptionId:id, State:state, IsDefault:isDefault}" | ConvertFrom-Json

    if ($subscriptions.Count -eq 0) {
        throw "No Azure subscriptions found. Please ensure you have access to at least one subscription."
    }

    if ($subscriptions.Count -eq 1) {
        Write-Success "Only one subscription available: $($subscriptions[0].Name)"
        Write-Info "Subscription ID: $($subscriptions[0].SubscriptionId)"
    }
    else {
        Write-Host ""
        Write-Host "Available Subscriptions:" -ForegroundColor Cyan
        Write-Host ""

        for ($i = 0; $i -lt $subscriptions.Count; $i++) {
            $sub = $subscriptions[$i]
            $defaultMarker = if ($sub.IsDefault) { " [CURRENT]" } else { "" }
            $stateColor = if ($sub.State -eq "Enabled") { "Green" } else { "Yellow" }

            Write-Host "  $($i + 1). " -NoNewline
            Write-Host "$($sub.Name)" -ForegroundColor White -NoNewline
            Write-Host "$defaultMarker" -ForegroundColor Green
            Write-Host "     ID: $($sub.SubscriptionId)" -ForegroundColor Gray
            Write-Host "     State: " -NoNewline
            Write-Host "$($sub.State)" -ForegroundColor $stateColor
            Write-Host ""
        }

        $currentIndex = -1
        for ($i = 0; $i -lt $subscriptions.Count; $i++) {
            if ($subscriptions[$i].IsDefault) {
                $currentIndex = $i
                break
            }
        }

        $defaultChoice = $currentIndex + 1
        $selection = Read-Host "Select subscription number [default: $defaultChoice]"

        if ([string]::IsNullOrWhiteSpace($selection)) {
            $selection = $defaultChoice
        }

        $selectedIndex = [int]$selection - 1

        if ($selectedIndex -lt 0 -or $selectedIndex -ge $subscriptions.Count) {
            throw "Invalid subscription selection: $selection"
        }

        $selectedSub = $subscriptions[$selectedIndex]

        if (-not $selectedSub.IsDefault) {
            Write-Info "Switching to subscription: $($selectedSub.Name)"
            az account set --subscription $selectedSub.SubscriptionId
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to set subscription"
            }

            $account = az account show | ConvertFrom-Json
            $subscriptionId = $account.id
        }

        Write-Success "Using subscription: $($selectedSub.Name)"
        Write-Info "Subscription ID: $($selectedSub.SubscriptionId)"
    }
    Write-Host ""

    # Step 3: Check/Create Resource Group
    Write-Step "Checking resource group: $ResourceGroup"

    $rgExists = az group exists --name $ResourceGroup
    if ($rgExists -eq "false") {
        Write-Info "Resource group does not exist. Creating..."
        az group create --name $ResourceGroup --location $Location | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create resource group: $ResourceGroup"
        }
        Write-Success "Resource group created"
    }
    else {
        Write-Success "Resource group already exists"
    }

    # Step 4: Check/Create Storage Account
    Write-Step "Checking storage account: $StorageAccount"

    $saExists = az storage account show --name $StorageAccount --resource-group $ResourceGroup 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Info "Storage account does not exist. Creating (this may take 1-2 minutes)..."
        az storage account create `
            --name $StorageAccount `
            --resource-group $ResourceGroup `
            --location $Location `
            --sku $StorageSku `
            --kind StorageV2 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create storage account: $StorageAccount"
        }
        Write-Success "Storage account created"
    }
    else {
        Write-Success "Storage account already exists"
    }

    # Step 5: Enable Static Website Hosting
    Write-Step "Enabling static website hosting..."

    az storage blob service-properties update `
        --account-name $StorageAccount `
        --static-website `
        --index-document index.html `
        --404-document index.html | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to enable static website hosting"
    }
    Write-Success "Static website hosting enabled"

    # Step 6: Upload Files
    Write-Step "Uploading website files..."

    Write-Info "Uploading HTML files..."
    az storage blob upload-batch `
        --account-name $StorageAccount `
        --auth-mode key `
        --source $SiteDir `
        --destination '$web' `
        --pattern "*.html" `
        --overwrite true | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to upload HTML files"
    }
    Write-Success "HTML files uploaded"

    Write-Info "Uploading CSS files..."
    az storage blob upload `
        --account-name $StorageAccount `
        --auth-mode key `
        --container-name '$web' `
        --file (Join-Path $SiteDir "styles.css") `
        --name "styles.css" `
        --content-type "text/css" `
        --overwrite true | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to upload CSS file"
    }
    Write-Success "CSS files uploaded"

    Write-Info "Uploading JavaScript files..."
    az storage blob upload `
        --account-name $StorageAccount `
        --auth-mode key `
        --container-name '$web' `
        --file (Join-Path $SiteDir "script.js") `
        --name "script.js" `
        --content-type "application/javascript" `
        --overwrite true | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to upload JavaScript file"
    }
    Write-Success "JavaScript files uploaded"

    # Step 7: Get Website URL
    Write-Step "Getting website URL..."

    $websiteUrl = az storage account show `
        --name $StorageAccount `
        --resource-group $ResourceGroup `
        --query "primaryEndpoints.web" -o tsv

    Write-Success "Website URL: $websiteUrl"

    # Summary
    Write-Host "`n============================================" -ForegroundColor Green
    Write-Host "  DEPLOYMENT SUCCESSFUL!" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Website Details:" -ForegroundColor Cyan
    Write-Host "  URL:              $websiteUrl"
    Write-Host "  Storage Account:  $StorageAccount"
    Write-Host "  Resource Group:   $ResourceGroup"
    Write-Host "  Location:         $Location"
    Write-Host ""
}
catch {
    Write-Host "`n============================================" -ForegroundColor Red
    Write-Host "  ERROR OCCURRED" -ForegroundColor Red
    Write-Host "============================================" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Stack Trace:" -ForegroundColor Yellow
    Write-Host $_.ScriptStackTrace -ForegroundColor Yellow
    exit 1
}
