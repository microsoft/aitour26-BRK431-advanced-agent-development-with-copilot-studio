#!/usr/bin/env pwsh
<#
.SYNOPSIS
    AI Tour 2026 BRK431 - Environment Setup Script
.DESCRIPTION
    Interactive script to set up Power Platform environment for AI Tour 2026 BRK431 session.
    Walks through PAC installation, authentication, environment creation, solution installation, and data import.
#>

# Script configuration
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Check PowerShell version
$requiredVersion = [version]"7.5.0"
$currentVersion = $PSVersionTable.PSVersion

if ($currentVersion -lt $requiredVersion) {
    Write-Host "ERROR: This script requires PowerShell $requiredVersion or higher" -ForegroundColor Red
    Write-Host "Current version: $currentVersion" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Please install PowerShell 7.5 or higher from:" -ForegroundColor Yellow
    Write-Host "  https://github.com/PowerShell/PowerShell/releases" -ForegroundColor Cyan
    Write-Host ""
    exit 1
}

# Colors for output
function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "    ✓ $Message" -ForegroundColor Green
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Host "    ✗ $Message" -ForegroundColor Red
}

function Write-Info {
    param([string]$Message)
    Write-Host "    $Message" -ForegroundColor Yellow
}

function Pause-ForUser {
    param([string]$Message = "Press any key to continue...")
    Write-Host "`n$Message" -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# Welcome
Clear-Host
Write-Host @"
╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║         AI Tour 2026 - BRK431 Environment Setup               ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Magenta

Write-Host "`nThis script will guide you through:"
Write-Host "  1. Ensuring PAC CLI is installed"
Write-Host "  2. Authenticating to Power Platform"
Write-Host "  3. Creating a Sandbox environment"
Write-Host "  4. Installing the ZavaAppSharable solution"
Write-Host "  5. Importing data using Configuration Migration Tool"

Pause-ForUser

# ============================================================================
# STEP 1: Check PAC Installation
# ============================================================================
Write-Step "Step 1: Checking PAC CLI Installation"

$pacInstalled = $false
$pacVersion = $null

# Check if pac is available in PATH
$pacCommand = Get-Command pac -ErrorAction SilentlyContinue

if ($pacCommand) {
    $pacInstalled = $true
    Write-Success "PAC CLI is installed"
}

if (-not $pacInstalled) {
    Write-Info "PAC CLI is not installed or not in PATH"
    Write-Host "`nYou can install PAC CLI using one of these methods:"
    Write-Host "  A) .NET Tool (recommended)"
    Write-Host "  B) VS Code Extension (Power Platform Tools)"
    Write-Host "  C) Skip (if you already have it installed elsewhere)"
    
    $choice = Read-Host "`nChoose installation method (A/B/C)"
    
    switch ($choice.ToUpper()) {
        "A" {
            Write-Step "Installing PAC CLI via .NET Tool"
            
            # Check if dotnet is installed
            try {
                $dotnetVersion = dotnet --version 2>$null
                Write-Success ".NET SDK is installed: $dotnetVersion"
            } catch {
                Write-ErrorMsg ".NET SDK is not installed"
                Write-Info "Please install .NET SDK from: https://dotnet.microsoft.com/download"
                exit 1
            }
            
            Write-Info "Installing Microsoft.PowerApps.CLI.Tool..."
            dotnet tool install --global Microsoft.PowerApps.CLI.Tool
            
            if ($LASTEXITCODE -eq 0) {
                Write-Success "PAC CLI installed successfully"
                Write-Host ""
                Write-Host "IMPORTANT: You must open a NEW terminal window for PAC to be available!" -ForegroundColor Red
                Write-Host "The PATH has been updated, but this terminal session won't see the changes." -ForegroundColor Yellow
                Write-Host ""
                Write-Info "After opening a new terminal, run: pac --version"
                Write-Info "Then run this script again in the new terminal."
                Write-Host ""
                Pause-ForUser "Press any key to exit (then open a new terminal)..."
                exit 0
            } else {
                Write-Info "Installation may have failed. If already installed, try upgrading:"
                Write-Info "  dotnet tool update --global Microsoft.PowerApps.CLI.Tool"
                Write-Info "Note: You may need to open a new terminal after updating."
            }
        }
        "B" {
            Write-Info "Please install the 'Power Platform Tools' extension in VS Code"
            Write-Info "Extension ID: microsoft-IsvExpTools.powerplatform-vscode"
            Write-Host ""
            Write-Host "IMPORTANT: After installing the extension, close and reopen VS Code!" -ForegroundColor Red
            Write-Host "Then run this script again in a new terminal." -ForegroundColor Yellow
            Write-Host ""
            Pause-ForUser "Press any key to exit (then restart VS Code)..."
            exit 0
        }
        "C" {
            Write-Info "Skipping installation..."
        }
        default {
            Write-ErrorMsg "Invalid choice. Exiting."
            exit 1
        }
    }
}

# ============================================================================
# STEP 2: Authenticate to Power Platform
# ============================================================================
Write-Step "Step 2: Authenticating to Power Platform"

Write-Info "Checking current authentication status..."

# Get auth list output (text format)
$authListOutput = pac auth list 2>&1 | Out-String

$authProfiles = @()
$activeProfile = $null

# Parse the output more carefully - lines may wrap
$allLines = $authListOutput -split "`n"
$currentProfile = $null

Write-Host "`nAuthentication Profiles:"

foreach ($line in $allLines) {
    # Check if this is a new profile line (starts with [index])
    if ($line -match "^\s*\[(\d+)\]\s+(\*)?\s+") {
        $index = $matches[1]
        $isActive = $null -ne $matches[2] -and $matches[2] -eq "*"
        
        # Try to extract user email and environment name from this line and potentially the next
        $combinedLine = $line
        
        # Look for user email
        if ($combinedLine -match "(\S+@\S+)") {
            $user = $matches[1]
            
            # Look for environment name (text before https://)
            # Environment name typically comes after User and Type columns
            if ($combinedLine -match "$user\s+\S+\s+\S+\s+(.+?)(?:\s+https|$)") {
                $env = $matches[1].Trim()
            } else {
                $env = "Unknown Environment"
            }
            
            $activeMarker = if ($isActive) { "* ACTIVE" } else { "        " }
            
            Write-Host "  [$index] $activeMarker" -ForegroundColor $(if ($isActive) { "Green" } else { "Gray" })
            Write-Host "       Environment: $env" -ForegroundColor Gray
            Write-Host "       User: $user" -ForegroundColor Gray
            
            # Store profile info
            $profile = @{
                Index = $index
                IsActive = $isActive
                User = $user
                Environment = $env
            }
            $authProfiles += $profile
            
            if ($isActive) {
                $activeProfile = $profile
            }
        }
    }
}

if ($authProfiles.Count -eq 0) {
    Write-Host "  No authentication profiles found" -ForegroundColor Gray
}

# Check if there are any existing auth profiles
$hasActiveAuth = $authProfiles.Count -gt 0 -and $null -ne $activeProfile

if ($hasActiveAuth) {
    # Display the currently active profile
    Write-Host "`nCurrently Active Profile:" -ForegroundColor Cyan
    Write-Host "  Environment: $($activeProfile.Environment)" -ForegroundColor Green
    Write-Host "  User: $($activeProfile.User)" -ForegroundColor Green
    
    Write-Host "`nWhat would you like to do?"
    Write-Host "  1. Use current authentication"
    Write-Host "  2. Select a different authentication profile"
    Write-Host "  3. Create a new authentication profile"
    
    $authChoice = Read-Host "`nChoose option (1/2/3)"
    
    switch ($authChoice) {
        "1" {
            Write-Info "Using current authentication..."
        }
        "2" {
            Write-Info "Available authentication profiles shown above"
            $profileIndex = Read-Host "Enter the profile index number to select"
            pac auth select --index $profileIndex
            
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Authentication profile selected successfully"
            } else {
                Write-ErrorMsg "Failed to select authentication profile"
                exit 1
            }
        }
        "3" {
            Write-Info "Creating new authentication profile..."
            Write-Info "Using device code authentication..."
            Write-Info "A code will be displayed - use it to authenticate in your browser"
            pac auth create --deviceCode
            
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Authentication successful"
            } else {
                Write-ErrorMsg "Authentication failed"
                exit 1
            }
        }
        default {
            Write-ErrorMsg "Invalid choice"
            exit 1
        }
    }
} else {
    Write-Info "No active authentication found"
    Write-Info "Creating new authentication profile..."
    Write-Info "Using device code authentication..."
    Write-Info "A code will be displayed - use it to authenticate in your browser"
    pac auth create --deviceCode
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Authentication successful"
    } else {
        Write-ErrorMsg "Authentication failed"
        exit 1
    }
}

# Get current environment
Write-Info "Getting current environment information..."
$whoAmI = pac org who 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n$whoAmI"
    Write-Success "Connected to environment"
} else {
    Write-ErrorMsg "Not connected to any environment. Please authenticate first."
    exit 1
}

# ============================================================================
# STEP 3: Create Sandbox Environment
# ============================================================================
Write-Step "Step 3: Creating Sandbox Environment"

# Get username for environment name (cross-platform)
$currentUser = if ($env:USERNAME) { $env:USERNAME } else { $env:USER }
$defaultEnvName = "AI Tour26 BRK431 ($currentUser)"

$envDisplayName = Read-Host "Enter environment display name (default: $defaultEnvName)"
if ([string]::IsNullOrWhiteSpace($envDisplayName)) {
    $envDisplayName = $defaultEnvName
}

Write-Info "Environment will be named: $envDisplayName"

# Get domain name
$defaultDomain = "aitour26brk431$($currentUser.ToLower().Replace('.','').Replace('-',''))"
$envDomain = Read-Host "Enter domain name for environment (default: $defaultDomain)"

if ([string]::IsNullOrWhiteSpace($envDomain)) {
    $envDomain = $defaultDomain
}

# Check if environment already exists
Write-Info "Checking if environment already exists..."
$envList = pac admin list --json 2>&1 | ConvertFrom-Json -ErrorAction SilentlyContinue

$existingEnv = $null
if ($envList) {
    $existingEnv = $envList | Where-Object {
        $_.DisplayName -eq $envDisplayName -or
        $_.DomainName -eq $envDomain -or
        ($_.EnvironmentUrl -and $_.EnvironmentUrl -like "*$envDomain*")
    }
}

if ($existingEnv) {
    Write-Success "Environment already exists!"
    Write-Info "  Name: $($existingEnv.DisplayName)"
    Write-Info "  Domain: $($existingEnv.DomainName)"
    Write-Info "  Type: $($existingEnv.Type)"
    Write-Info "  URL: $($existingEnv.EnvironmentUrl)"
    
    # Select the existing environment
    Write-Info "Selecting the existing environment..."
    pac org select --environment $($existingEnv.EnvironmentId)
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Environment selected successfully"
    } else {
        Write-ErrorMsg "Failed to select environment. Please select it manually using: pac org select --environment $($existingEnv.EnvironmentId)"
        exit 1
    }
} else {
    $proceed = Read-Host "Environment does not exist. Create it now? (Y/N)"
    
    if ($proceed.ToUpper() -eq "Y") {
        # Fixed configuration for AI Tour
        $region = "unitedstates"
        $currency = "USD"
        $language = "1033"
        
        Write-Info "Environment configuration:"
        Write-Info "  Region: $region"
        Write-Info "  Currency: $currency"
        Write-Info "  Language: $language (English)"
        
        Write-Info "Creating environment..."
        Write-Info "This may take several minutes..."
        
        pac admin create `
            --name "$envDisplayName" `
            --domain $envDomain `
            --type Sandbox `
            --region $region `
            --currency $currency `
            --language $language
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Environment creation initiated successfully"
        
        # Poll for environment readiness
        Write-Info "Waiting for environment to be fully provisioned..."
        Write-Info "This typically takes 3-5 minutes, but can take up to 15 minutes..."
        
        $maxWaitMinutes = 20
        $maxAttempts = $maxWaitMinutes * 6  # Check every 10 seconds
        $attempt = 0
        $envReady = $false
        
        while ($attempt -lt $maxAttempts -and -not $envReady) {
            $attempt++
            Start-Sleep -Seconds 10
            
            # Check environment status
            $envListJson = pac admin list --json 2>&1 | Out-String
            
            try {
                $envList = $envListJson | ConvertFrom-Json -ErrorAction Stop
                
                if ($envList) {
                    $targetEnv = $envList | Where-Object {
                        $_.DisplayName -eq $envDisplayName -or
                        $_.DomainName -eq $envDomain -or
                        ($_.EnvironmentUrl -and $_.EnvironmentUrl -like "*$envDomain*")
                    }
                    
                    if ($targetEnv) {
                        # Check if environment has a URL (means it's provisioned)
                        $hasUrl = -not [string]::IsNullOrWhiteSpace($targetEnv.EnvironmentUrl)
                        $elapsed = [math]::Round($attempt * 10 / 60, 1)
                        
                        if ($hasUrl) {
                            Write-Host "    Environment found with URL (${elapsed} min elapsed)" -ForegroundColor Gray
                            $envReady = $true
                            Write-Success "Environment is ready!"
                            break
                        } else {
                            Write-Host "    Provisioning... (${elapsed} min elapsed)" -ForegroundColor Gray
                        }
                    } else {
                        $elapsed = [math]::Round($attempt * 10 / 60, 1)
                        Write-Host "    Provisioning... (${elapsed} min elapsed)" -ForegroundColor Gray
                    }
                }
            } catch {
                # JSON parsing failed - command might have returned an error
                $elapsed = [math]::Round($attempt * 10 / 60, 1)
                Write-Host "    Checking status... (${elapsed} min elapsed)" -ForegroundColor Gray
            }
        }
        
        if (-not $envReady) {
            Write-Info "Environment provisioning is taking longer than expected"
            Write-Info "You can monitor progress at: https://admin.powerplatform.microsoft.com"
            $continueAnyway = Read-Host "Continue with next steps? (Y/N)"
            if ($continueAnyway.ToUpper() -ne "Y") {
                exit 1
            }
        }
        
        # Select the new environment
        Write-Info "Selecting the new environment..."
        if ($targetEnv -and $targetEnv.EnvironmentId) {
            pac org select --environment $($targetEnv.EnvironmentId)
        } else {
            pac org select --environment $envDomain
        }
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Environment selected successfully"
        } else {
            Write-ErrorMsg "Failed to select environment. Please select it manually using: pac org select --environment <environment-id>"
            exit 1
        }
        } else {
            Write-ErrorMsg "Environment creation failed"
            Write-Info "You may need to create the environment manually through Power Platform Admin Center"
            $skipEnvCreation = Read-Host "Continue with existing environment? (Y/N)"
            if ($skipEnvCreation.ToUpper() -ne "Y") {
                exit 1
            }
        }
    } else {
        Write-Info "Skipping environment creation"
        Write-Info "Make sure you're connected to the correct environment"
    }
}

# ============================================================================
# STEP 4: Install ZavaAppSharable Solution
# ============================================================================
Write-Step "Step 4: Installing ZavaAppSharable Solution"

# Check if solution is already installed
Write-Info "Checking if ZavaAppShareable solution is already installed..."
$solutionListOutput = pac solution list 2>&1 | Out-String
$solutionAlreadyInstalled = $solutionListOutput -match 'ZavaAppShareable'

if ($solutionAlreadyInstalled) {
    Write-Success "ZavaAppShareable solution is already installed - skipping import"
} else {
    Write-Info "Solution not found - looking for ZavaAppShareable solution file..."
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $solutionZipPath = Get-ChildItem -Path $scriptDir -Filter "ZavaAppShareable*.zip" -ErrorAction SilentlyContinue | Select-Object -First 1

if ($solutionZipPath) {
    Write-Success "Found solution file: $($solutionZipPath.Name)"
    Write-Info "Importing solution..."
    
    pac solution import --path $solutionZipPath.FullName
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Solution import completed successfully"
        Write-Info "Publishing customizations..."
        pac solution publish
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Customizations published successfully"
        } else {
            Write-ErrorMsg "Publish failed - you can publish manually in make.powerapps.com"
        }
    } else {
        Write-ErrorMsg "Solution import failed"
        Write-Info "Please import manually through Power Platform Admin Center"
    }
} else {
    Write-Info "Solution file not found in script directory"
    $solutionName = Read-Host "Enter the solution name or AppSource ID (or press Enter to search manually)"

    if ([string]::IsNullOrWhiteSpace($solutionName)) {
    Write-Host @"

Please install the ZavaAppSharable solution manually:

Option A - AppSource:
  1. Navigate to: https://appsource.microsoft.com
  2. Search for "ZavaAppSharable"
  3. Click "Get it now"
  4. Select your environment: $envDisplayName
  5. Accept terms and install

Option B - Power Platform Admin Center:
  1. Navigate to: https://admin.powerplatform.microsoft.com
  2. Select your environment: $envDisplayName
  3. Go to Resources > Dynamics 365 apps
  4. Click "Install app" and search for "ZavaAppSharable"

Option C - Solution file:
  If you have a solution file (.zip), you can import it:
  1. Navigate to: https://make.powerapps.com
  2. Select your environment
  3. Go to Solutions
  4. Click "Import solution"
  5. Upload the ZavaAppSharable solution file

"@
    
    Pause-ForUser "Press any key after installing the solution..."
    
} else {
    Write-Info "Attempting to install solution: $solutionName"
    
    # Try to install via pac
    pac solution install --solution-name $solutionName
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Solution installation initiated"
        Write-Info "Monitor installation progress in Power Platform Admin Center"
    } else {
        Write-ErrorMsg "Automated installation failed"
        Write-Info "Please install manually using the instructions above"
        Pause-ForUser
    }    }}
}

# ============================================================================
# STEP 5: Import Data using Configuration Migration Tool
# ============================================================================
Write-Step "Step 5: Importing Data with Configuration Migration Tool"

# Check if running on Windows
$runningOnWindows = $PSVersionTable.Platform -eq 'Win32NT' -or $null -eq $PSVersionTable.Platform

if (-not $runningOnWindows) {
    Write-Info "Data import via PAC CLI is only supported on Windows"
    Write-Host @"

The Configuration Migration Tool requires Windows. Please use one of these options:

Option A - Use Windows machine or VM:
  1. Copy the zava.zip file to a Windows machine
  2. Run: pac data import --data zava.zip
  
Option B - Manual import (Windows only):
  1. Download Configuration Migration Tool: https://aka.ms/ConfigMigration
  2. Run the tool and select "Import data"
  3. Connect to your environment
  4. Select the zava.zip file
  
Option C - Use Power Platform admin portal:
  1. Navigate to: https://make.powerapps.com
  2. Select your environment
  3. Import data through the portal interface (if available)

"@
    
    Pause-ForUser "Press any key to continue (data import skipped)..."
} else {
    Write-Info "Looking for zava.zip file..."
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $zavaZipPath = Join-Path $scriptDir "zava.zip"

    if (-not (Test-Path $zavaZipPath)) {
        Write-Info "zava.zip not found in script directory"
        $zavaZipPath = Read-Host "Enter full path to zava.zip file (or press Enter to skip)"
        
        if ([string]::IsNullOrWhiteSpace($zavaZipPath)) {
            Write-Info "Skipping data import - you can import manually later"
        } elseif (-not (Test-Path $zavaZipPath)) {
            Write-ErrorMsg "File not found: $zavaZipPath"
            Write-Info "Please locate the zava.zip file and import manually"
            Pause-ForUser
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($zavaZipPath) -and (Test-Path $zavaZipPath)) {
        Write-Success "Found: $zavaZipPath"

        Write-Info "Importing data using Configuration Migration Tool..."
        Write-Info "This will import the data from zava.zip into your environment"

        pac data import --data $zavaZipPath

        if ($LASTEXITCODE -eq 0) {
            Write-Success "Data import completed successfully"
        } else {
            Write-ErrorMsg "Data import failed"
            Write-Host @"

You can import manually using Configuration Migration Tool:

1. Download Configuration Migration Tool:
   https://aka.ms/ConfigMigration

2. Run the Configuration Migration tool

3. Select "Import data"

4. Connect to your environment

5. Select the zava.zip file

6. Complete the import wizard

"@
            
            Pause-ForUser
        }
    }
}

# ============================================================================
# Completion
# ============================================================================
Write-Host @"

╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║                    Setup Complete!                             ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Green

Write-Host "Your AI Tour 2026 BRK431 environment is ready!" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Verify the environment at: https://make.powerapps.com"
Write-Host "  2. Ensure the ZavaAppSharable solution is installed"
Write-Host "  3. Verify imported data in tables"
Write-Host "  4. Begin your AI Tour session!"
Write-Host ""

Pause-ForUser "Press any key to exit..."
