<#
.SYNOPSIS
    Provisions Azure Key Vault for ZavaWarehouse with Power Platform integration
.DESCRIPTION
    Creates a Key Vault with RBAC authorization, sets up permissions for:
    - Current user (Key Vault Administrator)
    - Power Platform/Dataverse (Key Vault Secrets User)
    And creates the warehouse2016 password secret
#>

param(
    [string]$Location = "eastus",
    [string]$SecretName = "Password",
    [string]$SecretValue = "warehouse2016"
)

# Color output functions
function Write-Step { param([string]$Message) Write-Host "`n[STEP] $Message" -ForegroundColor Cyan }
function Write-Success { param([string]$Message) Write-Host "  ✓ $Message" -ForegroundColor Green }
function Write-Info { param([string]$Message) Write-Host "  ℹ $Message" -ForegroundColor Yellow }
function Write-ErrorMsg { param([string]$Message) Write-Host "  ✗ $Message" -ForegroundColor Red }

# Error handling
$ErrorActionPreference = "Stop"

try {
    Write-Host "============================================" -ForegroundColor Magenta
    Write-Host "  Azure Key Vault Provisioning Script" -ForegroundColor Magenta
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

    # Store current user and tenant info
    $currentUserId = $account.user.name
    $tenantId = $account.tenantId
    $subscriptionId = $account.id

    # Derive resource names from username
    $userPrefix = $currentUserId.Split('@')[0].ToLower() -replace '[^a-z0-9]', ''
    $ResourceGroup = "rg-aitour26-$userPrefix"
    $KeyVaultName = "kv-zava-$userPrefix"
    $StorageAccount = "zavawarehouse$userPrefix"
    # Key Vault names max 24 chars
    if ($KeyVaultName.Length -gt 24) {
        $KeyVaultName = $KeyVaultName.Substring(0, 24)
    }
    # Storage account names max 24 chars
    if ($StorageAccount.Length -gt 24) {
        $StorageAccount = $StorageAccount.Substring(0, 24)
    }
    $WarehouseUrl = "https://$StorageAccount.z13.web.core.windows.net"  # Note: region suffix (.z13) may vary; deploy script shows actual URL

    Write-Info "Resource Group will be: $ResourceGroup"
    Write-Info "Key Vault will be:      $KeyVaultName"
    Write-Host ""
    $customNames = Read-Host "Use these names? (Y/n, or press Enter to accept)"
    if ($customNames -eq 'n' -or $customNames -eq 'N') {
        $ResourceGroup = Read-Host "Enter Resource Group name"
        $KeyVaultName = Read-Host "Enter Key Vault name (max 24 chars, globally unique)"
    }

    # Step 2: Select Subscription
    Write-Step "Selecting Azure subscription..."
    
    # Get all available subscriptions
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
            
            # Refresh account info
            $account = az account show | ConvertFrom-Json
            $subscriptionId = $account.id
        }
        
        Write-Success "Using subscription: $($selectedSub.Name)"
        Write-Info "Subscription ID: $($selectedSub.SubscriptionId)"
    }
    Write-Host ""

    # Get current user's object ID
    Write-Step "Getting current user's object ID..."
    $userObjectId = az ad signed-in-user show --query id -o tsv
    Write-Success "User Object ID: $userObjectId"

    # Step 3: Check/Create Resource Group
    Write-Step "Checking resource group: $ResourceGroup"
    
    $rgExists = az group exists --name $ResourceGroup
    if ($rgExists -eq "false") {
        Write-Info "Resource group does not exist. Creating..."
        az group create --name $ResourceGroup --location $Location | Out-Null
        Write-Success "Resource group created"
    }
    else {
        Write-Success "Resource group exists"
    }

    # Step 4: Check if Key Vault exists
    Write-Step "Checking if Key Vault exists: $KeyVaultName"
    
    $kvExists = az keyvault show --name $KeyVaultName --resource-group $ResourceGroup 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Info "Key Vault does not exist. Creating..."
        
        # Create Key Vault with RBAC authorization enabled
        Write-Info "Creating Key Vault with RBAC authorization..."
        az keyvault create `
            --name $KeyVaultName `
            --resource-group $ResourceGroup `
            --location $Location `
            --enable-rbac-authorization true `
            --enabled-for-deployment true `
            --public-network-access Enabled `
            --sku standard | Out-Null
        
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create Key Vault"
        }
        
        Write-Success "Key Vault created successfully"
    }
    else {
        Write-Success "Key Vault already exists"
        
        # Ensure RBAC is enabled on existing vault
        Write-Info "Ensuring RBAC authorization is enabled..."
        az keyvault update `
            --name $KeyVaultName `
            --resource-group $ResourceGroup `
            --enable-rbac-authorization true | Out-Null
    }

    # Get Key Vault resource ID
    $kvId = az keyvault show --name $KeyVaultName --resource-group $ResourceGroup --query id -o tsv
    Write-Info "Key Vault ID: $kvId"

    # Step 5: Assign RBAC Roles to Current User
    Write-Step "Assigning RBAC permissions to current user..."
    
    # Check if current user already has Key Vault Administrator role
    $existingRole = az role assignment list `
        --assignee $userObjectId `
        --scope $kvId `
        --role "Key Vault Administrator" `
        --query "[0].id" -o tsv 2>&1

    if ([string]::IsNullOrWhiteSpace($existingRole)) {
        Write-Info "Assigning 'Key Vault Administrator' role to current user..."
        az role assignment create `
            --role "Key Vault Administrator" `
            --assignee-object-id $userObjectId `
            --assignee-principal-type User `
            --scope $kvId | Out-Null
        
        Write-Success "Key Vault Administrator role assigned"
    }
    else {
        Write-Success "Current user already has Key Vault Administrator role"
    }

    # Step 6: Configure Power Platform Service Principal Access
    Write-Step "Configuring Power Platform/Dataverse access..."
    
    # Power Platform service principal App ID (Microsoft first-party)
    # This is the well-known App ID for Power Platform Dataverse
    $powerPlatformAppId = "00000007-0000-0000-c000-000000000000"  # Dataverse
    
    Write-Info "Looking up Power Platform service principal..."
    $ppServicePrincipal = az ad sp show --id $powerPlatformAppId --query id -o tsv 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Info "Power Platform service principal not found in tenant. Creating..."
        az ad sp create --id $powerPlatformAppId | Out-Null
        $ppServicePrincipal = az ad sp show --id $powerPlatformAppId --query id -o tsv
    }
    
    Write-Success "Power Platform SP Object ID: $ppServicePrincipal"
    
    # Assign Key Vault Secrets User role to Power Platform
    $existingPPRole = az role assignment list `
        --assignee $ppServicePrincipal `
        --scope $kvId `
        --role "Key Vault Secrets User" `
        --query "[0].id" -o tsv 2>&1

    if ([string]::IsNullOrWhiteSpace($existingPPRole)) {
        Write-Info "Assigning 'Key Vault Secrets User' role to Power Platform..."
        az role assignment create `
            --role "Key Vault Secrets User" `
            --assignee-object-id $ppServicePrincipal `
            --assignee-principal-type ServicePrincipal `
            --scope $kvId | Out-Null
        
        Write-Success "Power Platform granted secret read access"
    }
    else {
        Write-Success "Power Platform already has Key Vault Secrets User role"
    }

    # Step 7: Create the Password Secret
    Write-Step "Checking secret: $SecretName"
    
    $existingSecret = az keyvault secret show `
        --vault-name $KeyVaultName `
        --name $SecretName `
        --query "id" -o tsv 2>&1
    
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($existingSecret)) {
        Write-Success "Secret '$SecretName' already exists"
        $secretVersion = $existingSecret
    }
    else {
        Write-Info "Secret not found. Creating..."
        
        # Wait a few seconds for RBAC permissions to propagate
        Write-Info "Waiting 10 seconds for RBAC permissions to propagate..."
        Start-Sleep -Seconds 10
        
        # Set the secret
        Write-Info "Setting secret value..."
        az keyvault secret set `
            --vault-name $KeyVaultName `
            --name $SecretName `
            --value $SecretValue `
            --content-type "text/plain" `
            --description "Warehouse management system password" | Out-Null
        
        if ($LASTEXITCODE -ne 0) {
            Write-ErrorMsg "Failed to create secret. Trying again in 5 seconds..."
            Start-Sleep -Seconds 5
            az keyvault secret set `
                --vault-name $KeyVaultName `
                --name $SecretName `
                --value $SecretValue `
                --content-type "text/plain" `
                --description "Warehouse management system password" | Out-Null
        }
        
        Write-Success "Secret '$SecretName' created successfully"

        # Verify Secret Creation
        Write-Info "Verifying secret creation..."
        
        $secretVersion = az keyvault secret show `
            --vault-name $KeyVaultName `
            --name $SecretName `
            --query "id" -o tsv
        
        Write-Success "Secret verified: $secretVersion"
    }

    # Step 8: Display Summary
    Write-Host "`n============================================" -ForegroundColor Green
    Write-Host "  PROVISIONING SUCCESSFUL!" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Key Vault Details:" -ForegroundColor Cyan
    Write-Host "  Name:            $KeyVaultName"
    Write-Host "  Resource Group:  $ResourceGroup"
    Write-Host "  Location:        $Location"
    Write-Host "  Vault URL:       https://$KeyVaultName.vault.azure.net/"
    Write-Host ""
    Write-Host "Permissions Configured:" -ForegroundColor Cyan
    Write-Host "  ✓ Current User ($currentUserId)" -ForegroundColor Green
    Write-Host "    Role: Key Vault Administrator (full access)"
    Write-Host "  ✓ Power Platform/Dataverse" -ForegroundColor Green
    Write-Host "    Role: Key Vault Secrets User (read secrets)"
    Write-Host ""
    Write-Host "Secrets Created:" -ForegroundColor Cyan
    Write-Host "  ✓ $SecretName = (hidden)" -ForegroundColor Green
    Write-Host ""
    Write-Host "Secret Reference URI:" -ForegroundColor Cyan
    Write-Host "  https://$KeyVaultName.vault.azure.net/secrets/$SecretName"
    Write-Host ""
    Write-Host "Warehouse Login URL:" -ForegroundColor Cyan
    Write-Host "  $WarehouseUrl" -ForegroundColor White
    Write-Host ""
    Write-Host "Stored Credentials Setup (Warehouse Agent):" -ForegroundColor Yellow
    Write-Host "  1. Open the Warehouse Agent in Copilot Studio" -ForegroundColor White
    Write-Host "  2. Go to Tools and select 'Record Delivery in Warehouse System'" -ForegroundColor White
    Write-Host "  3. Navigate to Stored Credentials" -ForegroundColor White
    Write-Host "  4. Remove any existing credential" -ForegroundColor White
    Write-Host "  5. Set the Login domain to the Warehouse Login URL shown above" -ForegroundColor White
    Write-Host "  6. Click Add > select 'Azure Key Vault' > select 'Add new'" -ForegroundColor White
    Write-Host "  7. Enter the following values:" -ForegroundColor White
    Write-Host ""
    Write-Host "  ─────────────────────────────────────────────────────" -ForegroundColor Cyan
    Write-Host "    Azure Subscription Id:  " -ForegroundColor Cyan -NoNewline
    Write-Host "$subscriptionId" -ForegroundColor White -NoNewline
    Write-Host "  " -ForegroundColor Cyan
    Write-Host "    Resource Group Name:    " -ForegroundColor Cyan -NoNewline
    Write-Host "$ResourceGroup" -ForegroundColor White -NoNewline
    Write-Host "  " -ForegroundColor Cyan
    Write-Host "    Azure Key Vault Name:   " -ForegroundColor Cyan -NoNewline
    Write-Host "$KeyVaultName" -ForegroundColor White -NoNewline
    Write-Host "  " -ForegroundColor Cyan
    Write-Host "  ─────────────────────────────────────────────────────" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  8. Enter the credentials:" -ForegroundColor White
    Write-Host ""
    Write-Host "  ─────────────────────────────────────────────────────" -ForegroundColor Cyan
    Write-Host "    Username:               " -ForegroundColor Cyan -NoNewline
    Write-Host "admin" -ForegroundColor White -NoNewline
    Write-Host "  " -ForegroundColor Cyan
    Write-Host "    Azure Secret Name:      " -ForegroundColor Cyan -NoNewline
    Write-Host "$SecretName" -ForegroundColor White -NoNewline
    Write-Host "  " -ForegroundColor Cyan
    Write-Host "  ─────────────────────────────────────────────────────" -ForegroundColor Cyan
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
