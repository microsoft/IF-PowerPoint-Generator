# PPT Generator Service - Deployment Guide

## Overview

This guide covers deploying the PPT Generator Service to Azure. The service uses a microservices architecture with the following components:

- **Azure Functions** - API layer for job submission and status queries
- **Container Apps** - V3 Assistants API orchestrator for AI-powered presentation generation
- **Azure Service Bus** - Message queue for async job processing
- **Azure Cosmos DB** - Job state and caching
- **Azure SQL** - Telemetry and reporting
- **Azure Blob Storage** - Templates and generated presentations
- **Azure OpenAI** - GPT and embedding models for AI generation

## Prerequisites

### Required Tools

```bash
# Azure CLI
brew install azure-cli  # macOS
# or visit: https://docs.microsoft.com/cli/azure/install-azure-cli

# Docker
brew install --cask docker  # macOS

# jq (JSON processor)
brew install jq  # macOS

# Terraform (if using Terraform deployment)
brew install terraform  # macOS

# sqlcmd (for SQL deployment)
brew tap microsoft/mssql-release https://github.com/Microsoft/homebrew-mssql-release
HOMEBREW_ACCEPT_EULA=Y brew install msodbcsql18 mssql-tools18
```

### Azure Subscription

- Active Azure subscription with Owner or Contributor access
- Registered resource providers:
  - Microsoft.App
  - Microsoft.CognitiveServices
  - Microsoft.ContainerRegistry
  - Microsoft.DocumentDB
  - Microsoft.KeyVault
  - Microsoft.ServiceBus
  - Microsoft.Sql
  - Microsoft.Storage
  - Microsoft.Web

## Staged Deployment Architecture

The infrastructure is deployed in 6 stages, each in its own resource group for better isolation and easier troubleshooting:

| Stage | Resource Group Suffix | Location | Resources |
|-------|----------------------|----------|-----------|
| 1 - Foundation | `-foundation` | eastus2 | Log Analytics, App Insights, Key Vault, Managed Identities |
| 2 - Data | `-data` | eastus2 | Storage Account, Cosmos DB, SQL Server, Service Bus |
| 3 - Compute | `-compute` | eastus2 | Container Registry, Container Apps Environment, Orchestrator |
| 4 - Functions | `-func` | eastus | Azure Functions (Linux) API Layer |
| 5 - AI | `-ai` | eastus2 | Azure OpenAI Account, GPT & Embedding deployments |
| 6 - Web (Optional) | `-web` | eastus | Web Test Portal (not required for production) |

### Benefits of Staged Deployment

- **Isolation**: Each stage in its own resource group for easy cleanup
- **Debugging**: Failed stages can be deleted and redeployed without affecting others
- **Regional Flexibility**: AI resources can be deployed to regions with model availability
- **Incremental Deployment**: Deploy and verify each stage before proceeding

## Deployment Options

Choose either **Bicep** or **Terraform** for your deployment:

---

## Option A: Bicep Deployment

### 1. Login to Azure

```bash
az login
az account set --subscription <subscription-id>
```

### 2. Make Scripts Executable

```bash
chmod +x infrastructure/deploy.sh infrastructure/deploy-tf.sh
```

### 3. Deploy Stages

Deploy each stage individually for better control:

```bash
# Stage 1: Foundation
./infrastructure/deploy.sh -g rg-pptgen -e dev -l eastus2 -s 1

# Stage 2: Data
./infrastructure/deploy.sh -g rg-pptgen -e dev -l eastus2 -s 2

# Stage 5: AI (deploy before Compute so OpenAI values are available for stage 3)
./infrastructure/deploy.sh -g rg-pptgen -e dev -s 5 --openai-location eastus2

# Stage 3: Compute (depends on stage 5 for OpenAI configuration)
./infrastructure/deploy.sh -g rg-pptgen -e dev -l eastus2 -s 3

# Stage 4: Functions
./infrastructure/deploy.sh -g rg-pptgen -e dev -s 4 --func-location eastus

# Stage 6: Web (optional - for testing only)
./infrastructure/deploy.sh -g rg-pptgen -e dev -s 6 --func-location eastus
```

Or deploy all stages (1-5) at once:

```bash
./infrastructure/deploy.sh -g rg-pptgen -e dev -l eastus2 -s all --openai-location eastus2
# Note: Stage 6 (Web) is optional and not included in 'all'
```

### Bicep Script Options

```
Options:
  -e, --environment       Environment (dev, stg, prd) [default: dev]
  -l, --location          Azure region for main resources [default: eastus2]
  --func-location         Azure region for Functions resources [default: eastus]
  --openai-location       Azure region for OpenAI resources [default: eastus2]
  -g, --resource-group    Base resource group name [required]
  -s, --stage             Stage to deploy (1-6, or 'all') [required]
  --sql-auth              Use SQL authentication instead of Entra-only
  --skip-role-assignments Skip role assignments (if they already exist)
  -h, --help              Show this help message
```

### Outputs

Deployment outputs are saved to `AZURE_CONFIG.json`:

```bash
cat ../AZURE_CONFIG.json | jq .
```

---

## Option B: Terraform Deployment

### 1. Login to Azure

```bash
az login
az account set --subscription <subscription-id>
```

### 2. Make Scripts Executable

```bash
chmod +x infrastructure/deploy.sh infrastructure/deploy-tf.sh
```

### 3. Deploy Stages

Deploy each stage individually:

```bash
# Stage 1: Foundation
./infrastructure/deploy-tf.sh -g rg-pptgen -e dev -l eastus2 -s 1

# Stage 2: Data
./infrastructure/deploy-tf.sh -g rg-pptgen -e dev -l eastus2 -s 2

# Stage 5: AI (deploy before Compute so OpenAI values are available for stage 3)
./infrastructure/deploy-tf.sh -g rg-pptgen -e dev -s 5 --openai-location eastus2

# Stage 3: Compute (depends on stage 5 for OpenAI configuration)
./infrastructure/deploy-tf.sh -g rg-pptgen -e dev -l eastus2 -s 3

# Stage 4: Functions
./infrastructure/deploy-tf.sh -g rg-pptgen -e dev -s 4 --func-location eastus

# Stage 6: Web (optional - for testing only)
./infrastructure/deploy-tf.sh -g rg-pptgen -e dev -s 6 --func-location eastus
```

Or deploy all stages (1-5) at once:

```bash
./infrastructure/deploy-tf.sh -g rg-pptgen -e dev -l eastus2 -s all --openai-location eastus2
# Note: Stage 6 (Web) is optional and not included in 'all'
```

### Terraform Script Options

```
Options:
  -e, --environment       Environment (dev, stg, prd) [default: dev]
  -l, --location          Azure region for main resources [default: eastus2]
  --func-location         Azure region for Functions resources [default: eastus]
  --openai-location       Azure region for OpenAI resources [default: eastus2]
  -g, --resource-group    Base resource group name [required]
  -s, --stage             Stage to deploy (1-6, or 'all') [required]
  --sql-auth              Use SQL authentication instead of Entra-only
  --destroy               Destroy resources instead of creating them
  -h, --help              Show this help message
```

### Destroying Stages (Terraform)

```bash
# Destroy a specific stage
./infrastructure/deploy-tf.sh -g rg-pptgen -e dev -s 2 --destroy

# Destroy all stages (reverse order)
./infrastructure/deploy-tf.sh -g rg-pptgen -e dev -s all --destroy
```

### Outputs

Deployment outputs are saved to `AZURE_CONFIG.json`:

```bash
cat ../AZURE_CONFIG.json | jq .
```

---

## Post-Deployment Steps

### 1. Deploy SQL Schema

#### Option A: Use Azure Portal Query Editor (Recommended for macOS)

The most reliable method on macOS:

1. Go to Azure Portal → SQL Database → `telemetry`
2. Click "Query editor (preview)"
3. Login with your Azure AD account
4. Paste and run contents of `sql/001_create_tables.sql`
5. Paste and run contents of `sql/002_create_views.sql`

#### Option B: Interactive Browser Login (sqlcmd)

First, add yourself as SQL AD admin:

```bash
# Get config file
CONFIG_FILE="../AZURE_CONFIG.json"

# Get SQL server details
SQL_SERVER_NAME=$(jq -r '.stages.stage2.resources.sqlServer.name' $CONFIG_FILE)
SQL_SERVER_FQDN=$(jq -r '.stages.stage2.resources.sqlServer.fqdn' $CONFIG_FILE)
RG_DATA=$(jq -r '.stages.stage2.resourceGroups.data.name' $CONFIG_FILE)

# Get your Azure AD user info
USER_EMAIL=$(az ad signed-in-user show --query userPrincipalName -o tsv)
USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)

# Add yourself as SQL AD admin
az sql server ad-admin create \
    --resource-group $RG_DATA \
    --server-name $SQL_SERVER_NAME \
    --display-name "$USER_EMAIL" \
    --object-id $USER_OBJECT_ID

# Use interactive authentication (opens browser for login)
# The -G flag with -U (no password) triggers browser-based auth
sqlcmd -S "$SQL_SERVER_FQDN" -d telemetry -G -U "$USER_EMAIL" -i ../sql/001_create_tables.sql
sqlcmd -S "$SQL_SERVER_FQDN" -d telemetry -G -U "$USER_EMAIL" -i ../sql/002_create_views.sql
```

#### Option C: Install Go-based sqlcmd (Supports more auth methods)

The newer Go-based sqlcmd has better Azure AD support:

```bash
# Install go-sqlcmd (replaces mssql-tools)
brew install sqlcmd

# Then use with Azure CLI credentials
sqlcmd -S "$SQL_SERVER_FQDN" -d telemetry --authentication-method ActiveDirectoryDefault -i ../sql/001_create_tables.sql
sqlcmd -S "$SQL_SERVER_FQDN" -d telemetry --authentication-method ActiveDirectoryDefault -i ../sql/002_create_views.sql
```

#### Option E: SQL Authentication (if deployed with `--sql-auth` flag)

```bash
CONFIG_FILE="../AZURE_CONFIG.json"
SQL_SERVER_FQDN=$(jq -r '.stages.stage2.resources.sqlServer.fqdn' $CONFIG_FILE)
KV_NAME=$(jq -r '.stages.stage1.resources.keyVault.name' $CONFIG_FILE)
SQL_PASSWORD=$(az keyvault secret show --vault-name $KV_NAME --name sql-admin-password --query value -o tsv)

sqlcmd -S "$SQL_SERVER_FQDN" -d telemetry -U pptadmin -P "$SQL_PASSWORD" -i ../sql/001_create_tables.sql
sqlcmd -S "$SQL_SERVER_FQDN" -d telemetry -U pptadmin -P "$SQL_PASSWORD" -i ../sql/002_create_views.sql
```

#### Grant Access to Container App Managed Identity

After deploying the schema, grant the Container App's managed identity access.

Run this SQL in the Azure Portal Query Editor (Option A), or via sqlcmd if you have Option B/C/E working:

```sql
-- Replace <CONTAINER_APP_MI_NAME> with the actual managed identity name
-- Get it from: jq -r '.stages.stage1.managedIdentities.containerApp.name' ../AZURE_CONFIG.json

CREATE USER [<CONTAINER_APP_MI_NAME>] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [<CONTAINER_APP_MI_NAME>];
ALTER ROLE db_datawriter ADD MEMBER [<CONTAINER_APP_MI_NAME>];
```

### 2. Build and Push Container Image

```bash
# Get container registry from config
CONFIG_FILE="../AZURE_CONFIG.json"
ACR_LOGIN=$(jq -r '.stages.stage3.resources.containerRegistry.loginServer' $CONFIG_FILE)

# Login to ACR
az acr login --name ${ACR_LOGIN%%.*}

# Build and push
docker build -t ${ACR_LOGIN}/pptgen-orchestrator:v1.0.0 ../apps/orchestrator
docker push ${ACR_LOGIN}/pptgen-orchestrator:v1.0.0

# Update Container App
CONTAINER_APP=$(jq -r '.stages.stage3.resources.containerApp.name' $CONFIG_FILE)
RG_COMPUTE=$(jq -r '.stages.stage3.resourceGroups.compute.name' $CONFIG_FILE)

az containerapp update \
    --name $CONTAINER_APP \
    --resource-group $RG_COMPUTE \
    --image ${ACR_LOGIN}/pptgen-orchestrator:v1.0.0
```

### 3. Upload PowerPoint Templates

Templates are automatically processed by a timer trigger that polls for new uploads every minute. When a new `.pptx` file is detected (without a corresponding `metadata.json`), the function introspects it, extracts layout and placeholder information, and generates `metadata.json` automatically.

> **Note:** The timer trigger approach was chosen over blob triggers to support managed identity authentication for storage access, which is required in tenants that disable storage account keys.

#### Uploading Templates

You can upload templates via Azure Portal, Azure Storage Explorer, or CLI:

```bash
STORAGE_ACCOUNT=$(jq -r '.stages.stage2.resources.storageAccount.name' $CONFIG_FILE)

# Upload template to blob storage
# The filename (without .pptx) becomes the template ID
az storage blob upload \
    --account-name $STORAGE_ACCOUNT \
    --container-name ppt-templates \
    --name "executive.pptx" \
    --file ./my-executive-template.pptx \
    --auth-mode login
```

**Resulting blob structure after processing (within 1 minute):**
```
ppt-templates/
├── executive.pptx          ← Your uploaded template
└── executive/
    └── metadata.json       ← Auto-generated by timer trigger
```

The filename (minus `.pptx`) becomes the **template ID** used throughout the system.

#### Template Naming Requirements

Template filenames are automatically sanitized, but following these rules ensures predictable IDs:

| Requirement | Details |
|-------------|---------|
| Characters | Lowercase letters, numbers, hyphens, underscores |
| Start/End | Must start and end with a letter or number |
| Length | Maximum 64 characters |
| Case | Converted to lowercase automatically |
| Spaces | Converted to hyphens automatically |
| Special chars | Removed automatically |

**Examples:**

| Uploaded Filename | Resulting Template ID |
|-------------------|----------------------|
| `executive.pptx` | `executive` |
| `Q4-Budget-Review.pptx` | `q4-budget-review` |
| `My Template (v2).pptx` | `my-template-v2` |
| `CISO_Briefing.pptx` | `ciso_briefing` |

**What happens automatically:**
1. Timer trigger polls `ppt-templates` container every minute
2. Detects `.pptx` files without corresponding `metadata.json`
3. Template is introspected using python-pptx
4. `metadata.json` is generated and saved alongside the template
5. Metadata is cached in Cosmos DB for fast retrieval

#### Designing Templates for the System

The system uses PowerPoint's native **slide layouts** and **placeholders** to determine where content goes. Here's how to design effective templates:

**1. Use Standard Slide Layouts**

In PowerPoint's Slide Master view (`View → Slide Master`), create layouts with meaningful names:
- `Title Slide` - For presentation title pages
- `Title and Content` - Standard content slides
- `Two Content` or `Comparison` - Side-by-side content
- `Chart` - Optimized for data visualizations
- `Table` - For tabular data
- `Section Header` - Divider slides

**2. Use Placeholder Types**

The system recognizes these PowerPoint placeholder types:

| Placeholder Type | System Use |
|-----------------|------------|
| Title | Slide titles, section headers |
| Subtitle | Secondary text on title slides |
| Content/Object | Flexible - accepts text, bullets, charts, tables, images |
| Picture | Image-only placeholders |
| Chart | Chart-only placeholders |
| Table | Table-only placeholders |
| Body | Text and bullet content |

**3. Recommended Layout Structure**

```
Slide Master
├── Title Slide (layout 0)
│   ├── Title placeholder (centered)
│   └── Subtitle placeholder
├── Title and Content (layout 1)
│   ├── Title placeholder (top)
│   └── Content placeholder (main area)
├── Two Content (layout 2)
│   ├── Title placeholder
│   ├── Left content placeholder
│   └── Right content placeholder
├── Chart Focused (layout 3)
│   ├── Title placeholder
│   └── Chart placeholder (large)
├── Chart with Insights (layout 4)
│   ├── Title placeholder
│   ├── Chart placeholder (left, ~60%)
│   └── Content placeholder (right, ~40%)
├── Table (layout 5)
│   ├── Title placeholder
│   └── Table placeholder
└── Section Header (layout 6)
    └── Title placeholder (centered)
```

**4. Best Practices**

- **Name layouts clearly** - The system uses layout names to infer purpose
- **Size placeholders appropriately** - Charts need adequate space (~5" x 5" minimum)
- **Use Content/Object placeholders** for flexibility - they accept multiple content types
- **Apply your branding** - Colors, fonts, and logos are preserved from the template
- **Test with sample content** - Verify placeholders work before uploading

**5. Template Naming Convention**

Use kebab-case for template IDs:
- `executive-summary`
- `quarterly-review`
- `technical-deep-dive`
- `budget-proposal`

The template ID becomes the folder name in blob storage.

### 4. Deploy Function App Code

```bash
FUNC_APP=$(jq -r '.stages.stage4.resources.functionApp.name' $CONFIG_FILE)

cd ../apps/api-functions
func azure functionapp publish $FUNC_APP
```

---

## Troubleshooting Deployments

### Cleaning Up Failed Stages

If a stage fails, delete its resource group and retry:

```bash
# Delete a specific stage's resource group
az group delete --name rg-pptgen-foundation --yes --no-wait  # Stage 1
az group delete --name rg-pptgen-data --yes --no-wait        # Stage 2
az group delete --name rg-pptgen-compute --yes --no-wait     # Stage 3
az group delete --name rg-pptgen-func --yes --no-wait        # Stage 4
az group delete --name rg-pptgen-ai --yes --no-wait          # Stage 5
az group delete --name rg-pptgen-web --yes --no-wait         # Stage 6 (optional)
```

### Purging Soft-Deleted Resources

Some resources (Key Vault, OpenAI) go into soft-delete state. Purge before redeploying:

```bash
# List and purge deleted Key Vaults
az keyvault list-deleted --query "[].{name:name, location:properties.location}" -o table
az keyvault purge --name <vault-name> --location <location>

# List and purge deleted OpenAI accounts
az cognitiveservices account list-deleted -o table
az cognitiveservices account purge --name <account-name> --resource-group <rg> --location <location>
```

### Regional Availability Issues

If you encounter quota or availability errors:

1. **Cosmos DB**: Try `westus2`, `northcentralus`, or `northeurope`
2. **SQL Server**: Check subscription restrictions, try different regions
3. **Azure OpenAI**: Use `eastus2`, `swedencentral`, or `canadaeast` for model availability
4. **Functions (Linux)**: Ensure no Windows App Service resources in the same RG

### Common Errors

| Error | Solution |
|-------|----------|
| `LinuxWorkersNotAllowedInResourceGroup` | Delete RG with Windows workers, or use separate RG (staged deployment does this) |
| `VaultAlreadyExists` | Purge soft-deleted Key Vault |
| `CustomDomainInUse` | Purge soft-deleted OpenAI account |
| `ServiceUnavailable` (Cosmos) | Try a different region |
| `ProvisioningDisabled` (SQL) | Try a different region or request quota |

---

## Environment-Specific Configurations

### Development

```bash
./infrastructure/deploy.sh -g rg-pptgen-dev -e dev -l eastus2 -s all --openai-location eastus2
```

### Staging

```bash
./infrastructure/deploy.sh -g rg-pptgen-stg -e stg -l eastus2 -s all --openai-location eastus2
```

### Production

```bash
./infrastructure/deploy.sh -g rg-pptgen-prd -e prd -l eastus2 -s all --openai-location eastus2
```

---

## Resource Sizing by Environment

| Resource | Dev | Staging | Prod |
|----------|-----|---------|------|
| Service Bus | Premium (1 MU) | Premium (2 MU) | Premium (4 MU) |
| Cosmos DB | Serverless | Serverless | Provisioned (10K RU) |
| SQL Database | Basic | Standard S1 | Standard S3 |
| Container Apps | 1-10 replicas | 1-50 replicas | 1-100 replicas |
| Function App Plan | EP1 | EP2 | EP3 |

> **Note:** Service Bus Premium SKU is required for Managed Identity authentication support.

---

## Monitoring

### Application Insights

Access via Azure Portal: Application Insights → `pptgen-{env}-insights`

### Log Analytics Queries

```kusto
// Container App logs
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == "pptgen-dev-orchestrator"
| where TimeGenerated > ago(1h)
| order by TimeGenerated desc

// Function App errors
FunctionAppLogs
| where Level == "Error"
| where TimeGenerated > ago(24h)
```

---

## Security

- All resources use TLS 1.2+
- SQL Server uses Entra-only authentication by default
- Blob storage has public access disabled (but publicNetworkAccess enabled for Functions)
- Key Vault uses RBAC authorization
- Managed identities used for service-to-service auth

### Azure Functions Managed Identity Configuration

The Function App uses system-assigned managed identity for storage access. This is required in tenants that disable storage account keys. The following app settings are configured:

**Internal Storage (Function Runtime):**
```
AzureWebJobsStorage__blobServiceUri=https://{internal-storage}.blob.core.windows.net
AzureWebJobsStorage__queueServiceUri=https://{internal-storage}.queue.core.windows.net
AzureWebJobsStorage__tableServiceUri=https://{internal-storage}.table.core.windows.net
AzureWebJobsStorage__credential=managedidentity
AzureWebJobsSecretStorageType=files
```

**External Storage (Stage 2 - Templates/Outputs):**
```
BlobStorage__blobServiceUri=https://{stage2-storage}.blob.core.windows.net
BlobStorage__queueServiceUri=https://{stage2-storage}.queue.core.windows.net
BlobStorage__credential=managedidentity
```

**Required Role Assignments:**

On internal storage account:
- Storage Blob Data Owner
- Storage Queue Data Contributor
- Storage Table Data Contributor
- Storage Account Contributor

On Stage 2 storage account:
- Storage Blob Data Contributor
- Storage Blob Delegator (for SAS token generation)
- Storage Queue Data Contributor

**Important Storage Account Settings:**
- `allowSharedKeyAccess: false` - Disables storage keys
- `publicNetworkAccess: Enabled` - Required for Function App to access storage with managed identity

### Production Recommendations

1. Enable VNet integration for Container Apps
2. Configure Private Endpoints for PaaS services
3. Use Managed Identity for all service connections
4. Enable Azure Defender for all services
5. Rotate Azure OpenAI keys regularly

---

## Cleanup

Delete all resource groups:

```bash
az group delete --name rg-pptgen-foundation --yes --no-wait  # Stage 1
az group delete --name rg-pptgen-data --yes --no-wait        # Stage 2
az group delete --name rg-pptgen-compute --yes --no-wait     # Stage 3
az group delete --name rg-pptgen-func --yes --no-wait        # Stage 4
az group delete --name rg-pptgen-ai --yes --no-wait          # Stage 5
az group delete --name rg-pptgen-web --yes --no-wait         # Stage 6 (optional)
```

Or use Terraform destroy:

```bash
./infrastructure/deploy-tf.sh -g rg-pptgen -e dev -s all --destroy
```
