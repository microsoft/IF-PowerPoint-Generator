# PPT Generator Service - Development Guide

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Infrastructure Deployment](#2-infrastructure-deployment)
3. [Container Registry Setup](#3-container-registry-setup)
4. [Key Vault Configuration](#4-key-vault-configuration)
5. [AI Service Setup](#5-ai-service-setup)
6. [Application Deployment](#6-application-deployment)
7. [Database Schema Deployment](#7-database-schema-deployment)
8. [Asset Upload](#8-asset-upload)
9. [Local Development](#9-local-development)
10. [End-to-End Verification](#10-end-to-end-verification)
11. [Troubleshooting](#11-troubleshooting)

---

## 1. Prerequisites

### 1.1 Required Tools

Install the following tools on your development machine:

```bash
# Azure CLI (macOS)
brew install azure-cli

# Azure CLI (Windows) - run in PowerShell as Administrator
winget install Microsoft.AzureCLI

# Azure Functions Core Tools
brew install azure-functions-core-tools@4  # macOS
npm install -g azure-functions-core-tools@4  # Windows/Linux

# Docker Desktop
brew install --cask docker  # macOS
# Windows: Download from https://www.docker.com/products/docker-desktop

# Terraform (optional - if using Terraform instead of Bicep)
brew install terraform  # macOS
choco install terraform  # Windows

# Python 3.11
brew install python@3.11  # macOS
# Windows: Download from https://www.python.org/downloads/

# .NET 8.0 SDK (for web test interface)
brew install dotnet@8  # macOS
# Windows: Download from https://dotnet.microsoft.com/download

# jq (JSON processor)
brew install jq  # macOS
choco install jq  # Windows

# SQL Server tools
brew tap microsoft/mssql-release https://github.com/Microsoft/homebrew-mssql-release
HOMEBREW_ACCEPT_EULA=Y brew install msodbcsql18 mssql-tools18
```

### 1.2 Azure Subscription Setup

```bash
# Login to Azure
az login

# Set your subscription
az account set --subscription "<your-subscription-id>"

# Verify subscription
az account show --output table

# Register required resource providers
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.CognitiveServices
az provider register --namespace Microsoft.ContainerRegistry
az provider register --namespace Microsoft.DocumentDB
az provider register --namespace Microsoft.Insights
az provider register --namespace Microsoft.KeyVault
az provider register --namespace Microsoft.ManagedIdentity
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.ServiceBus
az provider register --namespace Microsoft.Sql
az provider register --namespace Microsoft.Storage
az provider register --namespace Microsoft.Web

# Verify registration (wait for all to show "Registered")
az provider show --namespace Microsoft.App --query "registrationState"
```

### 1.3 Clone Repository

```bash
git clone <repository-url>
cd ppt-generator
```

---

## 2. Infrastructure Deployment

Infrastructure is deployed using the `infrastructure/deploy.sh` (Bicep) or `infrastructure/deploy-tf.sh` (Terraform) scripts with staged deployments.

### Deployment Script Parameters

```
Required Parameters:
  -l, --location          Azure region for resources (e.g., eastus2)
  -g, --resource-group    Base resource group name (e.g., 'rg-pptgen')
  -e, --environment       Environment: dev, stg, or prd
  -s, --stage             Stage number to deploy (1-6) or 'all'

Optional Parameters:
  --func-location         Azure region for Functions (default: eastus)
  --openai-location       Azure region for OpenAI (default: eastus2)
  --skip-role-assignments Skip role assignments if they already exist
  --destroy               (Terraform only) Destroy resources
  -h, --help              Show help message
```

### Option A: Deploy with Bicep (via deploy.sh)

#### 2.1 Make Script Executable

```bash
chmod +x infrastructure/deploy.sh infrastructure/deploy-tf.sh
```

#### 2.2 Deploy Stages

```bash
# Set deployment variables
BASE_RG="rg-pptgen"
LOCATION="eastus2"
ENVIRONMENT="dev"

# Deploy Stage 1: Foundation (Log Analytics, App Insights, Key Vault, Managed Identities)
./infrastructure/deploy.sh -g $BASE_RG -e $ENVIRONMENT -l $LOCATION -s 1

# Deploy Stage 2: Data (Storage Account, Cosmos DB, SQL Server, Service Bus)
./infrastructure/deploy.sh -g $BASE_RG -e $ENVIRONMENT -l $LOCATION -s 2

# Deploy Stage 5: AI (Deploy before Compute so OpenAI values are available)
./infrastructure/deploy.sh -g $BASE_RG -e $ENVIRONMENT -s 5 --openai-location eastus2

# Deploy Stage 3: Compute (Container Registry, Container Apps Environment, Orchestrator)
./infrastructure/deploy.sh -g $BASE_RG -e $ENVIRONMENT -l $LOCATION -s 3

# Deploy Stage 4: Functions (Azure Functions API Layer)
./infrastructure/deploy.sh -g $BASE_RG -e $ENVIRONMENT -s 4 --func-location eastus

# Deploy Stage 6: Web (Optional - for testing only)
./infrastructure/deploy.sh -g $BASE_RG -e $ENVIRONMENT -s 6 --func-location eastus
```

Or deploy all stages (1-5) at once:

```bash
./infrastructure/deploy.sh -g $BASE_RG -e $ENVIRONMENT -l $LOCATION -s all --openai-location eastus2
# Note: Stage 6 (Web) is optional and not included in 'all'
```

#### 2.3 Verify Deployment Outputs

The deployment script automatically updates `AZURE_CONFIG.json`:

```bash
# View full configuration
cat AZURE_CONFIG.json | jq '.'

# View specific stage resources
jq '.stages.stage1.resources' AZURE_CONFIG.json

# Get resource group names
jq -r '.stages[].resourceGroups[].name' AZURE_CONFIG.json
```

### Option B: Deploy with Terraform

#### 2.1 Make Script Executable

```bash
chmod +x infrastructure/deploy.sh infrastructure/deploy-tf.sh
```

#### 2.2 Deploy Stages

```bash
# Set deployment variables
BASE_RG="rg-pptgen"
LOCATION="eastus2"
ENVIRONMENT="dev"

# Deploy Stage 1: Foundation
./infrastructure/deploy-tf.sh -g $BASE_RG -e $ENVIRONMENT -l $LOCATION -s 1

# Deploy Stage 2: Data
./infrastructure/deploy-tf.sh -g $BASE_RG -e $ENVIRONMENT -l $LOCATION -s 2

# Deploy Stage 5: AI (Deploy before Compute)
./infrastructure/deploy-tf.sh -g $BASE_RG -e $ENVIRONMENT -s 5 --openai-location eastus2

# Deploy Stage 3: Compute
./infrastructure/deploy-tf.sh -g $BASE_RG -e $ENVIRONMENT -l $LOCATION -s 3

# Deploy Stage 4: Functions
./infrastructure/deploy-tf.sh -g $BASE_RG -e $ENVIRONMENT -s 4 --func-location eastus

# Deploy Stage 6: Web (Optional)
./infrastructure/deploy-tf.sh -g $BASE_RG -e $ENVIRONMENT -s 6 --func-location eastus
```

#### 2.3 Destroying Resources (Terraform)

```bash
# Destroy a specific stage
./infrastructure/deploy-tf.sh -g $BASE_RG -e $ENVIRONMENT -s 2 --destroy

# Destroy all stages (reverse order)
./infrastructure/deploy-tf.sh -g $BASE_RG -e $ENVIRONMENT -s all --destroy
```

---

## 3. Container Registry Setup

### 3.1 Get Registry Details from AZURE_CONFIG.json

```bash
# Get ACR details
ACR_NAME=$(jq -r '.stages.stage3.resources.containerRegistry.name' AZURE_CONFIG.json)
ACR_LOGIN_SERVER=$(jq -r '.stages.stage3.resources.containerRegistry.loginServer' AZURE_CONFIG.json)

echo "ACR Name: $ACR_NAME"
echo "ACR Login Server: $ACR_LOGIN_SERVER"
```

### 3.2 Login to Container Registry

```bash
# Login with Azure CLI (recommended - uses Managed Identity pattern)
az acr login --name $ACR_NAME
```

### 3.3 Build and Push Orchestrator Image

```bash
# Navigate to application directory
cd apps/orchestrator

# Build the Docker image
docker build -t $ACR_LOGIN_SERVER/pptgen-orchestrator:v1.0.0 .

# Push to ACR
docker push $ACR_LOGIN_SERVER/pptgen-orchestrator:v1.0.0

# Verify image
az acr repository list --name $ACR_NAME --output table
az acr repository show-tags --name $ACR_NAME --repository pptgen-orchestrator --output table
```

---

## 4. Key Vault Configuration

### 4.1 Get Key Vault from AZURE_CONFIG.json

```bash
# Get Key Vault details
KV_NAME=$(jq -r '.stages.stage1.resources.keyVault.name' AZURE_CONFIG.json)
KV_URI=$(jq -r '.stages.stage1.resources.keyVault.uri' AZURE_CONFIG.json)
RG_FOUNDATION=$(jq -r '.stages.stage1.resourceGroups.foundation.name' AZURE_CONFIG.json)

echo "Key Vault: $KV_NAME"
echo "Key Vault URI: $KV_URI"
```

### 4.2 Store Secrets (if needed)

```bash
# Store additional secrets (only if not auto-configured by deployment)
az keyvault secret set \
    --vault-name $KV_NAME \
    --name "custom-secret-name" \
    --value "<secret-value>"

# List all secrets
az keyvault secret list --vault-name $KV_NAME --output table
```

### 4.3 Grant Access to Managed Identities

The deployment scripts automatically configure role assignments. To verify:

```bash
# Get managed identity principal IDs from AZURE_CONFIG.json
CONTAINER_APP_PRINCIPAL=$(jq -r '.stages.stage1.managedIdentities.containerApp.principalId' AZURE_CONFIG.json)
FUNC_PRINCIPAL=$(jq -r '.stages.stage1.managedIdentities.functionApp.principalId' AZURE_CONFIG.json)

# Verify role assignments exist
az role assignment list --assignee $CONTAINER_APP_PRINCIPAL --output table
az role assignment list --assignee $FUNC_PRINCIPAL --output table
```

---

## 5. AI Service Setup

### 5.1 Get Azure OpenAI Details from AZURE_CONFIG.json

```bash
# Get AI service details
OPENAI_NAME=$(jq -r '.stages.stage5.resources.openAi.name' AZURE_CONFIG.json)
OPENAI_ENDPOINT=$(jq -r '.stages.stage5.resources.openAi.endpoint' AZURE_CONFIG.json)
RG_AI=$(jq -r '.stages.stage5.resourceGroups.ai.name' AZURE_CONFIG.json)

echo "OpenAI Service: $OPENAI_NAME"
echo "Endpoint: $OPENAI_ENDPOINT"
```

### 5.2 Verify Model Deployments

```bash
# Get deployment names from AZURE_CONFIG.json
GPT_DEPLOYMENT=$(jq -r '.stages.stage5.resources.openAi.deployments.gpt' AZURE_CONFIG.json)
EMBEDDING_DEPLOYMENT=$(jq -r '.stages.stage5.resources.openAi.deployments.embedding' AZURE_CONFIG.json)

echo "GPT Deployment: $GPT_DEPLOYMENT"
echo "Embedding Deployment: $EMBEDDING_DEPLOYMENT"

# List deployments from Azure
az cognitiveservices account deployment list \
    --name $OPENAI_NAME \
    --resource-group $RG_AI \
    --output table
```

### 5.3 Deploy Additional Models (if needed)

```bash
# Deploy an additional model
az cognitiveservices account deployment create \
    --name $OPENAI_NAME \
    --resource-group $RG_AI \
    --deployment-name "gpt-4o-mini" \
    --model-name "gpt-4o-mini" \
    --model-version "2024-07-18" \
    --model-format OpenAI \
    --sku-capacity 150 \
    --sku-name "Standard"
```

---

## 6. Application Deployment

Applications are located in `apps/` as independent solutions.

### 6.1 Orchestrator Deployment (Container App)

#### Get Resource Details

```bash
# Get Container App details from AZURE_CONFIG.json
CONTAINER_APP=$(jq -r '.stages.stage3.resources.containerApp.name' AZURE_CONFIG.json)
CONTAINER_APP_FQDN=$(jq -r '.stages.stage3.resources.containerApp.fqdn' AZURE_CONFIG.json)
RG_COMPUTE=$(jq -r '.stages.stage3.resourceGroups.compute.name' AZURE_CONFIG.json)

echo "Container App: $CONTAINER_APP"
echo "FQDN: $CONTAINER_APP_FQDN"
```

#### Update Container App Image

```bash
# Update with new image
az containerapp update \
    --name $CONTAINER_APP \
    --resource-group $RG_COMPUTE \
    --image "${ACR_LOGIN_SERVER}/pptgen-orchestrator:v1.0.0"
```

#### Verify Deployment

```bash
# Get Container App URL
ORCHESTRATOR_URL=$(jq -r '.stages.stage3.resources.containerApp.url' AZURE_CONFIG.json)

echo "Orchestrator URL: $ORCHESTRATOR_URL"

# Test health endpoint
curl -s "${ORCHESTRATOR_URL}/health" | jq '.'
```

---

### 6.2 Azure Functions API Deployment

#### Get Resource Details

```bash
# Get Function App details from AZURE_CONFIG.json
FUNC_APP=$(jq -r '.stages.stage4.resources.functionApp.name' AZURE_CONFIG.json)
FUNC_URL=$(jq -r '.stages.stage4.resources.functionApp.url' AZURE_CONFIG.json)
RG_FUNC=$(jq -r '.stages.stage4.resourceGroups.functions.name' AZURE_CONFIG.json)

echo "Function App: $FUNC_APP"
echo "Function URL: $FUNC_URL"
```

#### Deploy Function Code

```bash
cd apps/api-functions

# Install dependencies
pip install -r requirements.txt

# Deploy to Azure
func azure functionapp publish $FUNC_APP --python

# Verify deployment
az functionapp function list \
    --name $FUNC_APP \
    --resource-group $RG_FUNC \
    --output table
```

#### Test Endpoints

```bash
# Test health endpoint
curl -s "${FUNC_URL}/api/health" | jq '.'

# Test templates endpoint
curl -s "${FUNC_URL}/api/templates" | jq '.'
```

---

### 6.3 Web Test Interface (Optional - Stage 6)

> **Note:** Stage 6 (Web) is optional and only required for testing. It is not needed for production deployments.

#### Get Resource Details

```bash
# Get Web App details from AZURE_CONFIG.json
WEB_APP=$(jq -r '.stages.stage6.resources.webApp.name' AZURE_CONFIG.json)
WEB_URL=$(jq -r '.stages.stage6.resources.webApp.url' AZURE_CONFIG.json)
RG_WEB=$(jq -r '.stages.stage6.resourceGroups.web.name' AZURE_CONFIG.json)

echo "Web App: $WEB_APP"
echo "Web URL: $WEB_URL"
```

#### Deploy Web App

```bash
cd apps/web

# Publish
dotnet publish -c Release -o ./publish

# Create deployment package
cd publish && zip -r ../deploy.zip . && cd ..

# Deploy
az webapp deployment source config-zip \
    --resource-group $RG_WEB \
    --name $WEB_APP \
    --src deploy.zip
```

---

## 7. Database Schema Deployment

Database scripts are located in `sql/` with the following naming convention:
- `001_create_tables.sql` - Table definitions
- `002_create_views.sql` - View definitions

### 7.1 Get Database Server Details

```bash
# Get SQL Server details from AZURE_CONFIG.json
SQL_SERVER_NAME=$(jq -r '.stages.stage2.resources.sqlServer.name' AZURE_CONFIG.json)
SQL_SERVER_FQDN=$(jq -r '.stages.stage2.resources.sqlServer.fqdn' AZURE_CONFIG.json)
SQL_DB=$(jq -r '.stages.stage2.resources.sqlServer.databaseName' AZURE_CONFIG.json)
RG_DATA=$(jq -r '.stages.stage2.resourceGroups.data.name' AZURE_CONFIG.json)

echo "SQL Server: $SQL_SERVER_FQDN"
echo "Database: $SQL_DB"
```

### 7.2 Configure Firewall

```bash
# Get your current IP
MY_IP=$(curl -s ifconfig.me)

# Add firewall rule
az sql server firewall-rule create \
    --resource-group $RG_DATA \
    --server $SQL_SERVER_NAME \
    --name "AllowMyIP" \
    --start-ip-address $MY_IP \
    --end-ip-address $MY_IP
```

### 7.3 Add Yourself as Entra Admin

```bash
USER_EMAIL=$(az ad signed-in-user show --query userPrincipalName -o tsv)
USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)

az sql server ad-admin create \
    --resource-group $RG_DATA \
    --server-name $SQL_SERVER_NAME \
    --display-name "$USER_EMAIL" \
    --object-id $USER_OBJECT_ID
```

### 7.4 Deploy Schema

#### Option A: Azure Portal Query Editor (Recommended for macOS)

1. Go to Azure Portal > SQL Database > `telemetry`
2. Click "Query editor (preview)"
3. Login with your Azure AD account
4. Paste and run contents of `sql/001_create_tables.sql`
5. Paste and run contents of `sql/002_create_views.sql`

#### Option B: sqlcmd with Entra Authentication

```bash
cd sql

# Deploy schema scripts using Entra authentication
sqlcmd -S "$SQL_SERVER_FQDN" -d "$SQL_DB" -G -U "$USER_EMAIL" -i 001_create_tables.sql
sqlcmd -S "$SQL_SERVER_FQDN" -d "$SQL_DB" -G -U "$USER_EMAIL" -i 002_create_views.sql
```

### 7.5 Grant Access to Managed Identity

Run this SQL in the Azure Portal Query Editor or via sqlcmd:

```sql
-- Get managed identity name from AZURE_CONFIG.json:
-- jq -r '.stages.stage1.managedIdentities.containerApp.name' AZURE_CONFIG.json

CREATE USER [pptgen-dev-container-app-id] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [pptgen-dev-container-app-id];
ALTER ROLE db_datawriter ADD MEMBER [pptgen-dev-container-app-id];
```

### 7.6 Verify Schema

```bash
# List tables
sqlcmd -S "$SQL_SERVER_FQDN" -d "$SQL_DB" -G -U "$USER_EMAIL" \
    -Q "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE'"

# List views
sqlcmd -S "$SQL_SERVER_FQDN" -d "$SQL_DB" -G -U "$USER_EMAIL" \
    -Q "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.VIEWS"
```

---

## 8. Asset Upload

### 8.1 Get Storage Account from AZURE_CONFIG.json

```bash
STORAGE_ACCOUNT=$(jq -r '.stages.stage2.resources.storageAccount.name' AZURE_CONFIG.json)

echo "Storage Account: $STORAGE_ACCOUNT"
```

### 8.2 Upload PowerPoint Templates

```bash
# Upload templates (organize by folder structure)
# Each template should be in its own folder: ppt-templates/{template-id}/template.pptx

# Example: Upload corporate template
az storage blob upload \
    --account-name $STORAGE_ACCOUNT \
    --container-name ppt-templates \
    --name "2025-corporate-template/template.pptx" \
    --file ./templates/corporate-template.pptx \
    --auth-mode login

# Verify uploads
az storage blob list \
    --account-name $STORAGE_ACCOUNT \
    --container-name ppt-templates \
    --auth-mode login \
    --output table
```

### 8.3 Verify Template Metadata Generation

After uploading templates, the Function App automatically generates metadata.

```bash
# Wait 1 minute for the timer function (poll_for_templates) to run

# Check if metadata.json was created
az storage blob list \
    --account-name $STORAGE_ACCOUNT \
    --container-name ppt-templates \
    --prefix "2025-corporate-template/" \
    --auth-mode login \
    --output table

# Should see:
# - 2025-corporate-template/template.pptx
# - 2025-corporate-template/metadata.json

# Download and inspect metadata.json
az storage blob download \
    --account-name $STORAGE_ACCOUNT \
    --container-name ppt-templates \
    --name "2025-corporate-template/metadata.json" \
    --file ./metadata.json \
    --auth-mode login

# View metadata
cat metadata.json | jq '.'

# Verify key fields exist
cat metadata.json | jq '{
  templateId,
  layoutCount: (.layouts | length),
  contentLayoutCount: (.contentLayouts | length),
  layoutGuide: .layoutSelectionGuide
}'
```

### 8.4 Manual Metadata Generation (if needed)

If automatic generation fails, trigger manually via Function App:

```bash
# Get Function App URL
FUNC_URL=$(jq -r '.stages.stage4.resources.functionApp.url' AZURE_CONFIG.json)

# Manually trigger template introspection
curl -X POST "${FUNC_URL}/api/templates/introspect" \
    -H "Content-Type: application/json" \
    -d '{
      "templateId": "2025-corporate-template"
    }'
```

---

## 9. Local Development

### 9.1 Configure Local Environment

```bash
# Navigate to application directory
cd apps/orchestrator

# Create local configuration file
# NOTE: For local dev, DefaultAzureCredential will use your az login credentials
cat > .env << EOF
AZURE_OPENAI_ENDPOINT=$(jq -r '.stages.stage5.resources.openAi.endpoint' ../../AZURE_CONFIG.json)
AZURE_OPENAI_GPT_DEPLOYMENT=$(jq -r '.stages.stage5.resources.openAi.deployments.gpt' ../../AZURE_CONFIG.json)
COSMOS_ENDPOINT=$(jq -r '.stages.stage2.resources.cosmosDb.endpoint' ../../AZURE_CONFIG.json)
COSMOS_DATABASE=ppt-generator
SERVICEBUS_NAMESPACE=$(jq -r '.stages.stage2.resources.serviceBus.name' ../../AZURE_CONFIG.json).servicebus.windows.net
SERVICEBUS_QUEUE_NAME=ppt-generation-jobs
STORAGE_ACCOUNT_NAME=$(jq -r '.stages.stage2.resources.storageAccount.name' ../../AZURE_CONFIG.json)
TEMPLATES_CONTAINER=ppt-templates
OUTPUT_CONTAINER=ppt-outputs
LOG_LEVEL=DEBUG
EOF
```

### 9.2 Authenticate for Local Development

```bash
# Login to Azure (required for DefaultAzureCredential)
az login

# Set the subscription
az account set --subscription "$(jq -r '.subscription.id' ../../AZURE_CONFIG.json)"
```

### 9.3 Run Orchestrator Locally

```bash
cd apps/orchestrator

# Create virtual environment
python -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Run the application
uvicorn main:app --reload --port 8000

# Application available at http://localhost:8000
```

### 9.4 Run Functions Locally

```bash
cd apps/api-functions

# Create virtual environment
python -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Run locally
func start

# Functions available at http://localhost:7071
```

### 9.5 Run Web Interface Locally

```bash
cd apps/web

# Update appsettings.Development.json
cat > appsettings.Development.json << EOF
{
  "Logging": {
    "LogLevel": {
      "Default": "Debug"
    }
  },
  "Orchestrator": {
    "BaseUrl": "http://localhost:8000"
  }
}
EOF

# Run the application
dotnet run

# Application available at https://localhost:5001
```

### 9.6 Test Template Metadata System Locally

#### Test Template Introspection (Function App)

```bash
cd apps/api-functions

# Activate virtual environment
source .venv/bin/activate

# Run Functions locally
func start

# In another terminal, test template introspection
# Place a test template in local storage emulator or use Azure storage

# Test template introspection endpoint
curl -X POST "http://localhost:7071/api/templates/introspect" \
    -H "Content-Type: application/json" \
    -d '{
      "templateId": "2025-corporate-template"
    }'
```

#### Test Metadata Retrieval (Orchestrator)

```bash
cd apps/orchestrator

# Activate virtual environment
source .venv/bin/activate

# Run orchestrator locally
uvicorn main:app --reload --port 8000

# In another terminal, test metadata retrieval
# The orchestrator will fetch metadata from blob storage when processing jobs

# Test with a sample generation request
curl -X POST "http://localhost:8000/api/generate" \
    -H "Content-Type: application/json" \
    -d '{
      "title": "Test Presentation",
      "audience": "Technical",
      "data": [
        {
          "collectionId": "test-001",
          "title": "Sample Data",
          "data": {"Q1": 100, "Q2": 150, "Q3": 200}
        }
      ],
      "preferences": {
        "template": "2025-corporate-template"
      }
    }'
```

#### Verify Layout Selection Logic

```python
# Create a test script: test_layout_selection.py
from ppt_assembler import PPTAssembler

# Initialize assembler with template metadata
assembler = PPTAssembler(
    template_path="path/to/template.pptx",
    metadata={
        "layoutSelectionGuide": {
            "title_slide": [0],
            "section_header": [11],
            "bulleted_text": [4],
            "chart_or_graph": [3],
            "text_with_graphic": [5],
            "paragraph_text": [3]
        }
    }
)

# Test layout resolution
print(f"Title slide layout: {assembler._get_layout_index('title_slide')}")
print(f"Chart layout: {assembler._get_layout_index('chart_or_graph')}")
print(f"Bullet layout: {assembler._get_layout_index('bulleted_text')}")
```

Run the test:
```bash
python test_layout_selection.py
```

---

## 10. End-to-End Verification

### 10.1 Health Checks

```bash
echo "=== Health Check Summary ==="

# Get URLs from AZURE_CONFIG.json
ORCHESTRATOR_URL=$(jq -r '.stages.stage3.resources.containerApp.url' AZURE_CONFIG.json)
FUNC_URL=$(jq -r '.stages.stage4.resources.functionApp.url' AZURE_CONFIG.json)

# Orchestrator
echo -n "Orchestrator: "
curl -s "${ORCHESTRATOR_URL}/health" | jq -r '.status // "ERROR"'

# Functions API
echo -n "Functions API: "
curl -s "${FUNC_URL}/api/health" | jq -r '.status // "ERROR"'
```

### 10.2 Submit Test Request

```bash
# Get API URL
FUNC_URL=$(jq -r '.stages.stage4.resources.functionApp.url' AZURE_CONFIG.json)

# Create test payload
cat > /tmp/test-request.json << 'EOF'
{
  "title": "Q4 Budget Review",
  "audience": "Executive Leadership",
  "purpose": "quarterly_review",
  "data": {
    "revenue": {"q1": 2500000, "q2": 2750000, "q3": 2900000, "q4": 3100000},
    "expenses": {"q1": 2000000, "q2": 2100000, "q3": 2200000, "q4": 2300000}
  },
  "preferences": {
    "template": "budget",
    "chart_style": "modern",
    "color_scheme": "corporate"
  }
}
EOF

# Submit request
RESPONSE=$(curl -s -X POST \
    "${FUNC_URL}/api/generate" \
    -H "Content-Type: application/json" \
    -d @/tmp/test-request.json)

JOB_ID=$(echo $RESPONSE | jq -r '.jobId')
echo "Job ID: $JOB_ID"
```

### 10.3 Monitor Status

```bash
# Poll for status
while true; do
    STATUS=$(curl -s "${FUNC_URL}/api/status/$JOB_ID")
    CURRENT_STATUS=$(echo $STATUS | jq -r '.status')
    PROGRESS=$(echo $STATUS | jq -r '.progress')

    echo "Status: $CURRENT_STATUS ($PROGRESS%)"

    if [ "$CURRENT_STATUS" == "completed" ] || [ "$CURRENT_STATUS" == "error" ]; then
        break
    fi

    sleep 5
done

# Get output
OUTPUT_URL=$(echo $STATUS | jq -r '.outputUrl')
echo "Output URL: $OUTPUT_URL"
```

### 10.4 Verify Data Storage

```bash
# Check SQL telemetry
sqlcmd -S "$SQL_SERVER_FQDN" -d "$SQL_DB" -G -U "$USER_EMAIL" \
    -Q "SELECT TOP 5 * FROM JobRequests ORDER BY ReceivedAt DESC"
```

---

## 11. Troubleshooting

### 11.1 Container App Issues

```bash
# Get Container App details
CONTAINER_APP=$(jq -r '.stages.stage3.resources.containerApp.name' AZURE_CONFIG.json)
RG_COMPUTE=$(jq -r '.stages.stage3.resourceGroups.compute.name' AZURE_CONFIG.json)

# View logs
az containerapp logs show \
    --name $CONTAINER_APP \
    --resource-group $RG_COMPUTE \
    --follow

# Check revision status
az containerapp revision list \
    --name $CONTAINER_APP \
    --resource-group $RG_COMPUTE \
    --output table

# Restart container
az containerapp revision restart \
    --name $CONTAINER_APP \
    --resource-group $RG_COMPUTE \
    --revision <revision-name>
```

### 11.2 Function App Issues

```bash
FUNC_APP=$(jq -r '.stages.stage4.resources.functionApp.name' AZURE_CONFIG.json)
RG_FUNC=$(jq -r '.stages.stage4.resourceGroups.functions.name' AZURE_CONFIG.json)

# Stream live logs
az webapp log tail \
    --name $FUNC_APP \
    --resource-group $RG_FUNC

# Check app settings
az functionapp config appsettings list \
    --name $FUNC_APP \
    --resource-group $RG_FUNC \
    --output table
```

### 11.3 Database Connection Issues

```bash
SQL_SERVER_NAME=$(jq -r '.stages.stage2.resources.sqlServer.name' AZURE_CONFIG.json)
RG_DATA=$(jq -r '.stages.stage2.resourceGroups.data.name' AZURE_CONFIG.json)

# Verify firewall rules
az sql server firewall-rule list \
    --resource-group $RG_DATA \
    --server $SQL_SERVER_NAME \
    --output table

# Verify Entra admin
az sql server ad-admin list \
    --resource-group $RG_DATA \
    --server $SQL_SERVER_NAME

# Test connectivity
sqlcmd -S "$SQL_SERVER_FQDN" -d "$SQL_DB" -G -U "$USER_EMAIL" -Q "SELECT 1"
```

### 11.4 Service Bus Issues

```bash
SB_NAMESPACE=$(jq -r '.stages.stage2.resources.serviceBus.name' AZURE_CONFIG.json)
RG_DATA=$(jq -r '.stages.stage2.resourceGroups.data.name' AZURE_CONFIG.json)

# Check queue metrics
az servicebus queue show \
    --resource-group $RG_DATA \
    --namespace-name $SB_NAMESPACE \
    --name ppt-generation-jobs \
    --query "{MessageCount: countDetails.activeMessageCount, DeadLetter: countDetails.deadLetterMessageCount}"
```

### 11.5 Cosmos DB Issues

```bash
COSMOS_NAME=$(jq -r '.stages.stage2.resources.cosmosDb.name' AZURE_CONFIG.json)
RG_DATA=$(jq -r '.stages.stage2.resourceGroups.data.name' AZURE_CONFIG.json)

# Check database
az cosmosdb sql database show \
    --account-name $COSMOS_NAME \
    --resource-group $RG_DATA \
    --name ppt-generator

# List containers
az cosmosdb sql container list \
    --account-name $COSMOS_NAME \
    --resource-group $RG_DATA \
    --database-name ppt-generator \
    --output table
```

### 11.6 Template Metadata Issues

```bash
# Problem: metadata.json not generated after template upload
# Check timer function logs
FUNC_APP=$(jq -r '.stages.stage4.resources.functionApp.name' AZURE_CONFIG.json)
RG_FUNC=$(jq -r '.stages.stage4.resourceGroups.functions.name' AZURE_CONFIG.json)

az webapp log tail \
    --name $FUNC_APP \
    --resource-group $RG_FUNC \
    | grep "poll_for_templates"

# Manually trigger introspection
FUNC_URL=$(jq -r '.stages.stage4.resources.functionApp.url' AZURE_CONFIG.json)
curl -X POST "${FUNC_URL}/api/templates/introspect" \
    -H "Content-Type: application/json" \
    -d '{"templateId": "2025-corporate-template"}'

# Problem: Orchestrator fails with "Layout index not found"
# Verify metadata.json structure
az storage blob download \
    --account-name $STORAGE_ACCOUNT \
    --container-name ppt-templates \
    --name "2025-corporate-template/metadata.json" \
    --file ./metadata.json \
    --auth-mode login

# Check that layoutSelectionGuide exists and has all required keys
cat metadata.json | jq '.layoutSelectionGuide'

# Required keys: title_slide, section_header, bulleted_text, chart_or_graph, text_with_graphic, paragraph_text

# Problem: Wrong layouts being selected
# Check contentLayouts array excludes boilerplate slides
cat metadata.json | jq '{
  allLayouts: [.layouts[].index],
  contentLayouts: .contentLayouts,
  excluded: ([.layouts[].index] - .contentLayouts)
}'

# Excluded should include: End Slide, Thank You, Disclaimer, etc.
```

### 11.7 Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `401 Unauthorized` | Missing/invalid API key | Check managed identity permissions |
| `503 Service Unavailable` | Container not started | Check container logs, verify image exists |
| `Connection timeout` | Network/firewall issue | Check VNet rules, firewall settings |
| `Cosmos 429` | Rate limiting | Increase RU/s or enable autoscale |
| `OpenAI 429` | Token quota exceeded | Wait or increase quota in Azure Portal |
| `LinuxWorkersNotAllowedInResourceGroup` | Mixed Windows/Linux resources | Use separate resource groups (staged deployment handles this) |
| `Layout index X out of range` | Missing or invalid metadata.json | Regenerate metadata via introspection endpoint |
| `KeyError: 'layoutSelectionGuide'` | Old metadata format | Delete metadata.json and regenerate with updated introspection service |
| `No layouts found for content type` | Template missing required layout category | Add missing layout or map existing layout to required category |

---

## Quick Reference

### Shell Variables from AZURE_CONFIG.json

```bash
# Export common variables for shell session
export PROJECT_NAME=$(jq -r '.project.name' AZURE_CONFIG.json)
export ENVIRONMENT=$(jq -r '.project.environment' AZURE_CONFIG.json)
export SUBSCRIPTION_ID=$(jq -r '.subscription.id' AZURE_CONFIG.json)

# Stage 1 resources (Foundation)
export KV_NAME=$(jq -r '.stages.stage1.resources.keyVault.name' AZURE_CONFIG.json)
export LOG_ANALYTICS=$(jq -r '.stages.stage1.resources.logAnalytics.name' AZURE_CONFIG.json)

# Stage 2 resources (Data)
export STORAGE_ACCOUNT=$(jq -r '.stages.stage2.resources.storageAccount.name' AZURE_CONFIG.json)
export SQL_SERVER=$(jq -r '.stages.stage2.resources.sqlServer.fqdn' AZURE_CONFIG.json)
export COSMOS_ENDPOINT=$(jq -r '.stages.stage2.resources.cosmosDb.endpoint' AZURE_CONFIG.json)

# Stage 3 resources (Compute)
export ACR_LOGIN=$(jq -r '.stages.stage3.resources.containerRegistry.loginServer' AZURE_CONFIG.json)
export ORCHESTRATOR_URL=$(jq -r '.stages.stage3.resources.containerApp.url' AZURE_CONFIG.json)

# Stage 4 resources (Functions)
export FUNC_URL=$(jq -r '.stages.stage4.resources.functionApp.url' AZURE_CONFIG.json)

# Stage 5 resources (AI)
export OPENAI_ENDPOINT=$(jq -r '.stages.stage5.resources.openAi.endpoint' AZURE_CONFIG.json)
```

### Useful Commands

```bash
# View all AZURE_CONFIG.json
cat AZURE_CONFIG.json | jq '.'

# List all resource groups
jq -r '.stages[].resourceGroups[].name' AZURE_CONFIG.json

# List all resources in a stage
jq '.stages.stage1.resources | keys[]' AZURE_CONFIG.json

# Redeploy a single stage (Bicep)
./infrastructure/deploy.sh -g rg-pptgen -e dev -l eastus2 -s 1

# Redeploy all stages (Bicep)
./infrastructure/deploy.sh -g rg-pptgen -e dev -l eastus2 -s all --openai-location eastus2

# Destroy a stage (Terraform only)
./infrastructure/deploy-tf.sh -g rg-pptgen -e dev -s 2 --destroy
```

---

*Last updated: January 2025*
