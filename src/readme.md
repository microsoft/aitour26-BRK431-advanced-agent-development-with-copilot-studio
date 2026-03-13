# AI Tour 2026 – BRK431 Environment Setup

## Prerequisites

- **PowerShell 7.5+** — [Download](https://github.com/PowerShell/PowerShell/releases)
- **.NET SDK** — required to install PAC CLI via `dotnet tool install` ([Download](https://dotnet.microsoft.com/download))
- **PAC CLI** — the setup script can install this for you, or install manually:
  ```
  dotnet tool install --global Microsoft.PowerApps.CLI.Tool
  ```
- **Power Platform tenant** with permissions to create Sandbox environments

### Additional prerequisites (CUA demo only)

- **Azure CLI** — [Download](https://learn.microsoft.com/cli/azure/install-azure-cli)
- **Azure subscription** with permissions to create Resource Groups, Key Vaults, and Storage Accounts

## Step 1 — Core Environment Setup (Required)

The main setup script walks you through everything interactively:

```powershell
.\Setup-AITourEnvironment.ps1
```

It performs five steps:

1. **PAC CLI check** — verifies PAC is installed (offers to install if missing)
2. **Authentication** — authenticates to Power Platform via device code flow
3. **Sandbox environment** — creates a new environment named `AI Tour26 BRK431 (<username>)`, or selects it if it already exists
4. **Solution import** — imports `ZavaAppShareable_1_0_0_0.zip` into the environment and publishes customizations
5. **Data import** — imports sample data from `zava.zip` using the Configuration Migration Tool (Windows only)

> **Note:** Data import (Step 5) requires Windows. On other platforms the script provides manual import instructions.

After this step your environment has the Zava app with sample data and is ready for most demos.

---

## Step 2 — Warehouse System Setup (Optional — CUA Demo)

If you are demonstrating **Computer Use Agent (CUA)** capabilities, you need to enable Computer Use on the environment, provision an Azure Key Vault, and deploy a warehouse website. Both scripts authenticate via Azure CLI device code flow and derive resource names from your Azure username automatically.

### 2a. Enable Computer Use

1. Open the [Power Platform Admin Center](https://admin.powerplatform.microsoft.com)
2. Navigate to **Copilot** → **Settings** → **Computer Use**
3. Under **Environments**, select your **AI Tour** environment
4. Click **Edit Settings** and enable Computer Use

### 2b. Provision Azure Key Vault

```powershell
.\warehouse-system\provision-keyvault.ps1
```

This script:

- Authenticates to Azure (device code flow)
- Creates resource group `rg-aitour26-<userprefix>`
- Creates Key Vault `kv-zava-<userprefix>` with RBAC authorization
- Grants your user **Key Vault Administrator** role
- Grants the Power Platform service principal **Key Vault Secrets User** role
- Creates the `Password` secret (value: `warehouse2016`)
- Displays the values you need for stored credentials setup

### 2c. Deploy Warehouse Website

```powershell
.\warehouse-system\deploy-to-azure.ps1
```

This script:

- Authenticates to Azure (same device code flow)
- Uses the same resource group (`rg-aitour26-<userprefix>`)
- Creates storage account `zavawarehouse<userprefix>` with static website hosting
- Uploads the HTML, CSS, and JavaScript files from `warehouse-system\site\`
- Displays the website URL on completion

The website URL is what the CUA agent will navigate to during the demo.

### 2d. Configure Stored Credentials

After both scripts have run, configure stored credentials on the Warehouse Agent:

1. Open the **Warehouse Agent** in Copilot Studio
2. Go to **Tools** and select **Record Delivery in Warehouse System** (Computer Use tool)
3. Navigate to **Stored Credentials**
4. Remove any existing credential
5. Set the **Login domain** to the website URL from the deploy script (e.g. `https://zavawarehouse<userprefix>.z13.web.core.windows.net`)
6. Click **Add** → select **Azure Key Vault** → select **Add new**
7. Enter the values from the Key Vault script output:
   - **Azure Subscription Id**
   - **Resource Group Name**
   - **Azure Key Vault Name**
8. Enter the credentials:
   - **Username:** `admin`
   - **Azure Secret Name:** `Password`

---

## Troubleshooting

| Problem | Solution |
|---|---|
| `pac` not found after install | Open a **new terminal** — the PATH update requires a fresh session |
| Environment creation times out | Check [Power Platform Admin Center](https://admin.powerplatform.microsoft.com) — provisioning can take up to 15 minutes |
| Data import fails | Ensure you're on Windows; alternatively use the Configuration Migration Tool manually |
| Key Vault RBAC errors | RBAC role assignments can take 1–2 minutes to propagate; the script retries automatically |
| Storage account name taken | Storage names are globally unique; the script derives a name from your username to avoid collisions |
