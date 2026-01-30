# PPT Generator Service - Configuration Guide

## Table of Contents

1. [Configuration Overview](#1-configuration-overview)
2. [AZURE_CONFIG.json Structure](#2-azure_configjson-structure)
3. [Environment Variables](#3-environment-variables)
4. [Azure Service Configurations](#4-azure-service-configurations)
5. [Application Configurations](#5-application-configurations)
6. [Security Configuration](#6-security-configuration)
7. [Networking Configuration](#7-networking-configuration)
8. [Monitoring Configuration](#8-monitoring-configuration)
9. [Configuration by Environment](#9-configuration-by-environment)

---

## 1. Configuration Overview

### Configuration Sources

| Source | Location | Purpose |
|--------|----------|---------|
| AZURE_CONFIG.json | `AZURE_CONFIG.json` | Central configuration for all Azure resources (owned by `cloud-architect`) |
| Bicep Templates | `infrastructure/bicep/*.bicep` | IaC deployment parameters |
| Deployment Script | `infrastructure/deploy.sh` | Orchestrates staged deployments |
| Key Vault | `kv-{prefix}-{suffix}` | Secrets and sensitive configuration |
| Environment Variables | Container/Function App Settings | Runtime configuration for applications |

### Configuration Hierarchy

```
Environment Variables (highest priority)
    ↓
App Settings / Configuration Files
    ↓
Key Vault References (via Managed Identity)
    ↓
AZURE_CONFIG.json Values
    ↓
Default Values (lowest priority)
```

### Required Tags

All resources must include the following tags:

| Tag | Description | Example |
|-----|-------------|---------|
| `Environment` | Deployment environment | `dev`, `staging`, `prod` |
| `Stage` | Deployment stage | `1`, `2`, `3`, `4`, `5`, `6` |
| `Purpose` | Resource purpose | `Foundation`, `Data`, `Compute`, `Functions`, `AI`, `Web` |
| `Application` | Application name | `PPT-Generator` |
| `ManagedBy` | IaC tool | `Bicep` or `Terraform` |

---

## 2. AZURE_CONFIG.json Structure

The `AZURE_CONFIG.json` file is the central configuration maintained by the deployment script and `cloud-architect`. All agents reference this file for resource details.

### Schema Overview

```json
{
  "project": {
    "name": "pptgen",
    "customer": "<customer-name>",
    "environment": "dev",
    "createdDate": "2025-01-05",
    "lastModified": "2025-01-12"
  },
  "subscription": {
    "id": "<subscription-id>",
    "name": "<subscription-name>",
    "tenantId": "<tenant-id>",
    "resourceProviders": [
      "Microsoft.App",
      "Microsoft.CognitiveServices",
      "Microsoft.ContainerRegistry",
      "Microsoft.DocumentDB",
      "Microsoft.KeyVault",
      "Microsoft.ServiceBus",
      "Microsoft.Sql",
      "Microsoft.Storage",
      "Microsoft.Web",
      "Microsoft.OperationalInsights",
      "Microsoft.Insights",
      "Microsoft.ManagedIdentity"
    ]
  },
  "tags": {
    "required": ["Environment", "Stage", "Purpose"],
    "optional": []
  },
  "locations": {
    "primary": "eastus2",
    "secondary": ""
  },
  "resourcePrefix": "pptgen-dev",
  "uniqueSuffix": "<generated-suffix>",
  "stages": {
    "stage1": { ... },
    "stage2": { ... },
    "stage3": { ... },
    "stage4": { ... },
    "stage5": { ... },
    "stage6": { ... }
  }
}
```

### Stage Structure

Each stage in `AZURE_CONFIG.json` follows this pattern:

```json
{
  "stages": {
    "stage1": {
      "name": "Foundation",
      "description": "Foundational components: Log Analytics, App Insights, Key Vault, Managed Identities",
      "resourceGroups": {
        "foundation": {
          "name": "rg-pptgen-foundation",
          "location": "eastus2",
          "tags": {
            "Environment": "dev",
            "Stage": "1",
            "Purpose": "Foundation"
          }
        }
      },
      "managedIdentities": {
        "containerApp": {
          "name": "pptgen-dev-container-app-id",
          "id": "/subscriptions/.../pptgen-dev-container-app-id",
          "clientId": "<client-id>",
          "principalId": "<principal-id>"
        }
      },
      "resources": {
        "keyVault": {
          "name": "kvpptgendev4vxbc4",
          "uri": "https://kvpptgendev4vxbc4.vault.azure.net/",
          "resourceGroup": "rg-pptgen-foundation"
        }
      }
    }
  }
}
```

### Querying Configuration

Use `jq` to query values from `AZURE_CONFIG.json`:

```bash
# Get resource group name for stage 1
jq -r '.stages.stage1.resourceGroups.foundation.name' AZURE_CONFIG.json

# Get Key Vault name
jq -r '.stages.stage1.resources.keyVault.name' AZURE_CONFIG.json

# Get managed identity principal ID
jq -r '.stages.stage1.managedIdentities.containerApp.principalId' AZURE_CONFIG.json

# Get all resource names in stage 2
jq -r '.stages.stage2.resources | keys[]' AZURE_CONFIG.json

# Get Azure OpenAI endpoint
jq -r '.stages.stage5.resources.openAi.endpoint' AZURE_CONFIG.json
```

---

## 3. Environment Variables

### Orchestrator (Container App) - Environment Variables

The orchestrator container app runs the V3 Assistants API pipeline and consumes Service Bus messages.

| Variable | Description | Example | Required |
|----------|-------------|---------|----------|
| `SERVICEBUS_NAMESPACE` | Service Bus namespace FQDN | `pptgen-dev-servicebus.servicebus.windows.net` | Yes |
| `SERVICEBUS_QUEUE_NAME` | Queue name for job messages | `ppt-generation-jobs` | Yes |
| `COSMOS_ENDPOINT` | Cosmos DB account endpoint | `https://pptgen-dev-cosmos.documents.azure.com:443/` | Yes |
| `COSMOS_DATABASE` | Cosmos DB database name | `ppt-generator` | Yes |
| `STORAGE_ACCOUNT_NAME` | Storage account name (no protocol) | `pptgendevqskhmc2dhedgg` | Yes |
| `TEMPLATES_CONTAINER` | Blob container for templates | `ppt-templates` | Yes |
| `OUTPUT_CONTAINER` | Blob container for outputs | `ppt-outputs` | Yes |
| `AZURE_OPENAI_ENDPOINT` | Azure OpenAI endpoint | `https://pptgen-dev-openai-nwyhzr.openai.azure.com/` | Yes |
| `AZURE_OPENAI_GPT_DEPLOYMENT` | GPT model deployment name | `gpt-4o` | Yes |
| `AZURE_OPENAI_MINI_DEPLOYMENT` | GPT mini model deployment name | `gpt-4o-mini` | Yes |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | App Insights connection string | `InstrumentationKey=...;IngestionEndpoint=...` | No |
| `SQL_SERVER_NAME` | SQL Server FQDN | `pptgen-dev-sql.database.windows.net` | No |
| `SQL_DATABASE_NAME` | SQL database name | `telemetry` | No |

**Authentication Pattern (Orchestrator):**
```bash
# All services use Managed Identity (DefaultAzureCredential)
# No connection strings or API keys required in environment variables
# The Container App's user-assigned managed identity authenticates to:
# - Service Bus (Azure Service Bus Data Receiver role)
# - Cosmos DB (Cosmos DB Data Contributor role)
# - Blob Storage (Storage Blob Data Contributor role)
# - Azure OpenAI (Cognitive Services OpenAI User role)
# - SQL Database (SQL DB Contributor via Entra ID)
```

### Azure Functions API - Environment Variables

The Functions API layer handles HTTP requests and queues jobs for processing.

| Variable | Description | Example | Required |
|----------|-------------|---------|----------|
| `SERVICEBUS_NAMESPACE` | Service Bus namespace FQDN | `pptgen-dev-servicebus.servicebus.windows.net` | Yes |
| `SERVICEBUS_QUEUE_NAME` | Queue name for job messages | `ppt-generation-jobs` | Yes |
| `COSMOS_ENDPOINT` | Cosmos DB account endpoint | `https://pptgen-dev-cosmos.documents.azure.com:443/` | Yes |
| `COSMOS_DATABASE` | Cosmos DB database name | `ppt-generator` | Yes |
| `STORAGE_ACCOUNT_NAME` | Storage account name (no protocol) | `pptgendevqskhmc2dhedgg` | Yes |
| `SQL_SERVER_NAME` | SQL Server FQDN | `pptgen-dev-sql.database.windows.net` | No |
| `SQL_DATABASE_NAME` | SQL database name | `telemetry` | No |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | App Insights connection string | `InstrumentationKey=...;IngestionEndpoint=...` | No |

**Azure Functions Storage Configuration (Managed Identity):**

Functions require special configuration to use managed identity for internal storage:

```bash
# Internal Function Runtime Storage (Stage 4 storage account)
AzureWebJobsStorage__blobServiceUri=https://pptgendevfuncqskh.blob.core.windows.net
AzureWebJobsStorage__queueServiceUri=https://pptgendevfuncqskh.queue.core.windows.net
AzureWebJobsStorage__tableServiceUri=https://pptgendevfuncqskh.table.core.windows.net
AzureWebJobsStorage__credential=managedidentity
AzureWebJobsSecretStorageType=files

# External Blob Storage (Stage 2 storage account for templates/outputs)
BlobStorage__blobServiceUri=https://pptgendevqskhmc2dhedgg.blob.core.windows.net
BlobStorage__queueServiceUri=https://pptgendevqskhmc2dhedgg.queue.core.windows.net
BlobStorage__credential=managedidentity
```

**Required Role Assignments for Function App:**

On internal storage account (Stage 4):
- Storage Blob Data Owner
- Storage Queue Data Contributor
- Storage Table Data Contributor
- Storage Account Contributor

On Stage 2 storage account:
- Storage Blob Data Contributor
- Storage Blob Delegator (for SAS token generation)
- Storage Queue Data Contributor

### Optional Environment Variables

| Variable | Description | Default | Used By |
|----------|-------------|---------|---------|
| `LOG_LEVEL` | Logging level | `INFO` | All applications |
| `CACHE_TTL_SECONDS` | Cache TTL in seconds | `86400` (24 hours) | Functions API |
| `MAX_CONCURRENT_JOBS` | Max concurrent pipeline runs | `10` | Orchestrator |
| `OPENAI_TEMPERATURE` | AI temperature setting | `0.7` | Orchestrator |

---

## 4. Azure Service Configurations

### Stage 1: Foundation

**Purpose:** Foundational monitoring, identity, and secrets management

#### Log Analytics Workspace

**Resource Details (from AZURE_CONFIG.json):**
```bash
jq -r '.stages.stage1.resources.logAnalytics' AZURE_CONFIG.json
```

- **Resource Name:** `pptgen-dev-logs`
- **SKU:** `PerGB2018`
- **Location:** `eastus2`
- **Retention:** 30 days

**Configuration:**

| Setting | Value | Description |
|---------|-------|-------------|
| Data Retention | 30 days | Log retention period (adjustable 30-730 days) |
| Daily Cap | None | No ingestion limit (consider for cost control) |
| Public Network Access | Enabled | Required for Application Insights ingestion |

---

#### Application Insights

**Resource Details (from AZURE_CONFIG.json):**
```bash
jq -r '.stages.stage1.resources.appInsights' AZURE_CONFIG.json
```

- **Resource Name:** `pptgen-dev-insights`
- **Type:** Workspace-based
- **Location:** `eastus2`
- **Linked Workspace:** `pptgen-dev-logs`

**Configuration:**

| Setting | Value | Description |
|---------|-------|-------------|
| Sampling | Adaptive | Reduces telemetry volume automatically |
| Daily Cap | 100 GB | Prevents runaway costs |
| Retention | 30 days | Inherited from Log Analytics workspace |
| Connection String | Stored in AZURE_CONFIG.json | Used by apps for telemetry |

**Instrumentation Key Reference:**
```bash
INSTRUMENTATION_KEY=$(jq -r '.stages.stage1.resources.appInsights.instrumentationKey' AZURE_CONFIG.json)
CONNECTION_STRING=$(jq -r '.stages.stage1.resources.appInsights.connectionString' AZURE_CONFIG.json)
```

---

#### Key Vault

**Resource Details (from AZURE_CONFIG.json):**
```bash
jq -r '.stages.stage1.resources.keyVault' AZURE_CONFIG.json
```

- **Resource Name:** `kvpptgendev4vxbc4` (generated with suffix)
- **SKU:** `Standard`
- **Location:** `eastus2`
- **RBAC Model:** Azure RBAC (not access policies)

**Configuration:**

| Setting | Value | Description |
|---------|-------|-------------|
| Access Model | RBAC | Azure role-based access control |
| Soft Delete | Enabled (90 days) | Protects against accidental deletion |
| Purge Protection | Disabled | Can be enabled for production |
| Public Network Access | Enabled | Required for Function App access |
| Private Endpoints | Not configured | Consider for production |

**Secrets (if SQL authentication used):**

| Secret Name | Description | Rotation Policy |
|-------------|-------------|-----------------|
| `sql-admin-password` | SQL admin password (if not using Entra-only) | Manual |

**RBAC Configuration:**

| Identity | Role | Purpose |
|----------|------|---------|
| Container App MI | Key Vault Secrets User | Read secrets for SQL connection |
| Function App MI | Key Vault Secrets User | Read secrets if needed |
| Deployer Identity | Key Vault Administrator | Manage secrets during deployment |

---

#### User-Assigned Managed Identities

**Container App Identity:**
```bash
jq -r '.stages.stage1.managedIdentities.containerApp' AZURE_CONFIG.json
```

- **Name:** `pptgen-dev-container-app-id`
- **Principal ID:** Used for RBAC assignments
- **Client ID:** Used in managed identity auth flows

**Role Assignments:**

| Resource | Role | Justification |
|----------|------|---------------|
| Service Bus Namespace | Azure Service Bus Data Receiver | Consume messages from queue |
| Cosmos DB Account | Cosmos DB Data Contributor | Read/write jobs, cache, templates, errors |
| Storage Account (Stage 2) | Storage Blob Data Contributor | Read templates, write outputs |
| Storage Account (Stage 2) | Storage Blob Delegator | Generate SAS tokens for downloads |
| Azure OpenAI | Cognitive Services OpenAI User | Call GPT models |
| SQL Database | SQL DB Contributor (via Entra) | Write telemetry data |

**Function App Identity:**
```bash
jq -r '.stages.stage1.managedIdentities.functionApp' AZURE_CONFIG.json
```

- **Name:** `pptgen-dev-func-id`
- **Principal ID:** Used for RBAC assignments
- **Client ID:** Used in managed identity auth flows

**Role Assignments:**

| Resource | Role | Justification |
|----------|------|---------------|
| Service Bus Namespace | Azure Service Bus Data Sender | Queue job messages |
| Cosmos DB Account | Cosmos DB Data Contributor | Manage jobs, cache |
| Storage Account (Stage 2) | Storage Blob Data Contributor | List templates, read metadata |
| Storage Account (Stage 4) | Storage Blob Data Owner | Function runtime storage (internal) |
| Storage Account (Stage 4) | Storage Queue Data Contributor | Function runtime queues |
| Storage Account (Stage 4) | Storage Table Data Contributor | Function runtime tables |
| SQL Database | SQL DB Contributor (via Entra) | Write telemetry data |

**SQL Managed Identity (for Entra-only auth):**
```bash
jq -r '.stages.stage1.managedIdentities.sql' AZURE_CONFIG.json
```

- **Name:** `pptgen-dev-sql-id`
- **Purpose:** SQL Server admin identity for Entra-only authentication

---

### Stage 2: Data

**Purpose:** Data persistence layer (storage, database, messaging)

#### Storage Account

**Resource Details (from AZURE_CONFIG.json):**
```bash
jq -r '.stages.stage2.resources.storageAccount' AZURE_CONFIG.json
```

- **Resource Name:** `pptgendevqskhmc2dhedgg` (no hyphens, lowercase)
- **SKU:** `Standard_LRS` (Locally Redundant Storage)
- **Location:** `eastus2`
- **Kind:** `StorageV2`

**Configuration:**

| Setting | Value | Description |
|---------|-------|-------------|
| Access Tier | Hot | Optimized for frequent access |
| TLS Version | 1.2 minimum | Security requirement |
| Public Access | Disabled for blobs | All access via managed identity |
| Public Network Access | Enabled | Required for Function App with MI |
| Shared Key Access | Disabled | Forces managed identity authentication |
| Hierarchical Namespace | Disabled | Not using Data Lake features |

**Containers:**

| Container | Access Level | Purpose |
|-----------|--------------|---------|
| `ppt-templates` | Private | PowerPoint templates and metadata.json files |
| `ppt-outputs` | Private | Generated presentations and charts |
| `ppt-temp` | Private | Temporary working files (auto-cleaned) |

**Template Structure:**

Each template folder must contain:
- `template.pptx` - PowerPoint template file
- `metadata.json` - Auto-generated layout metadata (see Template Metadata System below)

**Template Metadata System:**

The `metadata.json` file is automatically generated by the **Template Introspection Service** when templates are uploaded to blob storage. This metadata enables dynamic layout selection without hardcoded indices.

**Key Metadata Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `templateId` | string | Unique identifier for the template |
| `layouts` | array | Complete list of slide layouts with indices, names, dimensions, placeholders |
| `layoutSelectionGuide` | object | Maps content types to layout indices for dynamic assembly |
| `contentLayouts` | array | Filtered list of layout indices used for content (excludes boilerplate) |
| `supportedContentTypes` | array | Data types this template can visualize |

**Layout Selection Guide Structure:**

```json
{
  "layoutSelectionGuide": {
    "title_slide": [0],
    "section_header": [11],
    "bulleted_text": [4],
    "chart_or_graph": [3],
    "text_with_graphic": [5],
    "paragraph_text": [3]
  }
}
```

**Content Type Mappings:**

| Content Type | Purpose | Used By |
|--------------|---------|---------|
| `title_slide` | Deck title page | PPT Assembler (deck initialization) |
| `section_header` | Section dividers | PPT Assembler |
| `bulleted_text` | Text-based slides | PPT Assembler |
| `chart_or_graph` | Data visualizations | ChartRenderer + PPT Assembler |
| `text_with_graphic` | Hybrid text + image | ChartRenderer + PPT Assembler |
| `paragraph_text` | Long-form narrative | PPT Assembler (FREE_FORM_TEXT) |

**Template Upload Process:**

1. Upload `template.pptx` to blob storage (`ppt-templates/{template-id}/`)
2. Timer function (`poll_for_templates`) detects new template
3. `TemplateIntrospectionService` analyzes PPTX structure
4. `_generate_layout_selection_guide()` creates content-type mappings
5. `metadata.json` uploaded to same folder
6. Metadata cached in Cosmos DB (`templates` container)

**Configuration for Custom Templates:**

To add a new template:
1. Create folder in `ppt-templates` container
2. Upload `template.pptx` file
3. Wait 1 minute for automatic metadata generation
4. Verify `metadata.json` was created
5. Template is now available for generation requests

**Lifecycle Management Policies:**

| Rule | Scope | Action | Condition |
|------|-------|--------|-----------|
| Clean temp files | `ppt-temp` | Delete | Files older than 7 days |
| Archive old outputs | `ppt-outputs` | Move to Cool tier | Files older than 90 days |

**Authentication (Managed Identity):**
```bash
# No shared keys — storage account configured with:
# allowSharedKeyAccess: false
# publicNetworkAccess: Enabled (for Managed Identity access)

# App Settings Pattern for Applications:
STORAGE_ACCOUNT_NAME=pptgendevqskhmc2dhedgg
# Applications use DefaultAzureCredential to authenticate
```

---

#### Cosmos DB

**Resource Details (from AZURE_CONFIG.json):**
```bash
jq -r '.stages.stage2.resources.cosmosDb' AZURE_CONFIG.json
```

- **Account Name:** `pptgen-dev-cosmos`
- **API:** Core (SQL)
- **Location:** `eastus2`
- **Capacity Mode:** Serverless
- **Consistency Level:** Session

**Configuration:**

| Setting | Value | Description |
|---------|-------|-------------|
| Database Name | `ppt-generator` | Single database for all collections |
| Capacity Mode | Serverless | Pay-per-request (no provisioned RUs) |
| Consistency Level | Session | Balance of consistency and performance |
| Multi-region Writes | Disabled | Single-region for dev |
| Automatic Failover | Disabled | Not needed for single-region |

**Collections:**

| Collection | Partition Key | TTL | Purpose |
|------------|---------------|-----|---------|
| `jobs` | `/jobId` | 7 days | Job state tracking |
| `cache` | `/contentHash` | 24 hours | Cached generation results |
| `errors` | `/jobId` | 30 days | Error logs and malformed data |
| `templates` | `/templateId` | None | Template metadata cache |

**Authentication Pattern (Managed Identity):**
```bash
# No connection strings — use Managed Identity
COSMOS_ENDPOINT=$(jq -r '.stages.stage2.resources.cosmosDb.endpoint' AZURE_CONFIG.json)
# Application authenticates via DefaultAzureCredential or ManagedIdentityCredential
```

**Indexing Policies:**

All containers use default indexing (all properties indexed) for maximum query flexibility in this POC. For production, consider selective indexing for cost optimization.

---

#### Azure SQL Database

**Resource Details (from AZURE_CONFIG.json):**
```bash
jq -r '.stages.stage2.resources.sqlServer' AZURE_CONFIG.json
```

- **Server Name:** `pptgen-dev-sql`
- **FQDN:** `pptgen-dev-sql.database.windows.net`
- **Database Name:** `telemetry`
- **SKU:** `Basic` (5 DTUs, 2GB)
- **Location:** `eastus2`
- **Authentication:** Entra-only (no SQL authentication)

**Configuration:**

| Setting | Value | Description |
|---------|-------|-------------|
| Authentication Mode | Entra-only | No SQL username/password |
| TLS Version | 1.2 minimum | Security requirement |
| Public Network Access | Enabled | Required for deployment and Functions access |
| Firewall Rules | Azure services allowed | Allows Function App and Container App access |
| Entra Admin | SQL Managed Identity | `pptgen-dev-sql-id` |
| Transparent Data Encryption | Enabled | Data encrypted at rest |

**Schema Overview:**

| Table | Purpose | Key Columns |
|-------|---------|-------------|
| `JobRequests` | Request metadata | JobId, RequestId, Status, TemplateUsed |
| `ProcessingMetrics` | Per-node performance | JobId, NodeName, DurationMs, TokensUsed |
| `DataCollectionStats` | Data source analysis | JobId, CollectionId, InferredDataType |
| `TemplateUsage` | Template selection tracking | JobId, TemplateId, WasAISelected |
| `ErrorLog` | Error tracking | JobId, ErrorCode, NodeName |

**Authentication (Entra ID / Managed Identity):**

```bash
# SQL Server configured for Entra-only authentication
# Applications connect using managed identity:

# Connection string pattern (no password):
Server=pptgen-dev-sql.database.windows.net;Database=telemetry;Authentication=Active Directory Managed Identity;

# Grant access to managed identities via SQL:
CREATE USER [pptgen-dev-container-app-id] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [pptgen-dev-container-app-id];
ALTER ROLE db_datawriter ADD MEMBER [pptgen-dev-container-app-id];
```

**Scaling Configuration:**

| SKU | DTUs | Max Size | Use Case |
|-----|------|----------|----------|
| Basic | 5 | 2 GB | Dev/POC |
| Standard S1 | 20 | 250 GB | Staging |
| Standard S3 | 100 | 1 TB | Production |

---

#### Service Bus Namespace

**Resource Details (from AZURE_CONFIG.json):**
```bash
jq -r '.stages.stage2.resources.serviceBus' AZURE_CONFIG.json
```

- **Namespace Name:** `pptgen-dev-servicebus`
- **SKU:** `Premium` (1 Messaging Unit)
- **Location:** `eastus2`
- **TLS Version:** 1.2 minimum

**Configuration:**

| Setting | Value | Description |
|---------|-------|-------------|
| SKU | Premium | Required for managed identity support |
| Messaging Units | 1 | Can scale to 4 MU (manual) |
| Throughput | ~1000 messages/sec | Per messaging unit |
| Public Network Access | Enabled | Required for managed identity access |
| Private Endpoints | Not configured | Consider for production |

**Queue: ppt-generation-jobs**

| Setting | Value | Description |
|---------|-------|-------------|
| Lock Duration | 5 minutes | Time for message processing |
| Max Size | 5 GB | Maximum queue size |
| Default TTL | 1 hour | Messages expire after 1 hour |
| Max Delivery Count | 3 | Retries before dead-lettering |
| Dead-lettering | Enabled | Failed messages moved to DLQ |
| Duplicate Detection | Disabled | Not needed for this use case |
| Sessions | Disabled | No ordering requirements |
| Partitioning | Disabled | Not available in Premium |

**Authentication (Managed Identity):**
```bash
# No connection strings — use Managed Identity
SERVICEBUS_NAMESPACE=pptgen-dev-servicebus.servicebus.windows.net
# Applications authenticate via DefaultAzureCredential
```

---

### Stage 3: Compute

**Purpose:** Container hosting and orchestration

#### Container Registry

**Resource Details (from AZURE_CONFIG.json):**
```bash
jq -r '.stages.stage3.resources.containerRegistry' AZURE_CONFIG.json
```

- **Registry Name:** `pptgendevqskhmc2dhedggacr`
- **Login Server:** `pptgendevqskhmc2dhedggacr.azurecr.io`
- **SKU:** `Basic` (upgradable to Standard/Premium)
- **Location:** `eastus2`

**Configuration:**

| Setting | Value | Description |
|---------|-------|-------------|
| Admin User | Disabled | Use managed identity |
| Public Network Access | Enabled | Required for Container Apps to pull images |
| Content Trust | Disabled | Not required for POC |
| Retention Policy | None | Keep all images |

**Images:**

| Image | Tag | Purpose |
|-------|-----|---------|
| `pptgen-orchestrator` | `v1.0.0`, `latest` | LangGraph pipeline orchestrator |

**Authentication:**
```bash
# Container Apps use managed identity to pull images
# Deployment uses Azure CLI login:
az acr login --name pptgendevqskhmc2dhedggacr
```

---

#### Container Apps Environment

**Resource Details (from AZURE_CONFIG.json):**
```bash
jq -r '.stages.stage3.resources.containerAppsEnvironment' AZURE_CONFIG.json
```

- **Environment Name:** `pptgen-dev-cae`
- **Location:** `eastus2`
- **Log Analytics Workspace:** `pptgen-dev-logs`

**Configuration:**

| Setting | Value | Description |
|---------|-------|-------------|
| Workload Profiles | Consumption | Serverless, no dedicated compute |
| VNet Integration | None | Public endpoint (consider VNet for production) |
| Zone Redundancy | Disabled | Single-zone deployment |
| Diagnostics | Enabled | Logs to Log Analytics |

---

#### Container App: Orchestrator

**Resource Details (from AZURE_CONFIG.json):**
```bash
jq -r '.stages.stage3.resources.containerApp' AZURE_CONFIG.json
```

- **App Name:** `pptgen-dev-orchestrator`
- **FQDN:** `pptgen-dev-orchestrator.bluedune-c6a878ee.eastus2.azurecontainerapps.io`
- **URL:** `https://pptgen-dev-orchestrator.bluedune-c6a878ee.eastus2.azurecontainerapps.io`
- **Image:** `pptgendevqskhmc2dhedggacr.azurecr.io/pptgen-orchestrator:v1.0.0`

**Configuration:**

| Setting | Value | Description |
|---------|-------|-------------|
| CPU | 1.0 vCPU | Per replica |
| Memory | 2.0 GB | Per replica |
| Min Replicas | 1 | Always-on for Service Bus consumption |
| Max Replicas | 100 | KEDA autoscaling based on queue depth |
| Ingress | Enabled (HTTPS only) | For health checks and status endpoints |
| Port | 8000 | FastAPI app port |
| Managed Identity | User-assigned | `pptgen-dev-container-app-id` |

**Scaling Configuration:**

| Parameter | Value | Description |
|-----------|-------|-------------|
| Scale Rule Type | Azure Service Bus | KEDA queue-based autoscaling |
| Queue Name | `ppt-generation-jobs` | Monitored queue |
| Message Count Threshold | 25 | Scale up when queue has 25+ messages |
| Cooldown Period | 300 seconds | Wait 5 minutes before scaling down |

**Environment Variables:** See [Section 3](#3-environment-variables) for complete list.

---

### Stage 4: Functions

**Purpose:** HTTP API layer for job submission and status queries

#### App Service Plan

**Resource Details (from AZURE_CONFIG.json):**
```bash
jq -r '.stages.stage4.resources.functionApp.planName' AZURE_CONFIG.json
```

- **Plan Name:** `pptgen-dev-func-plan`
- **SKU:** `EP1` (Elastic Premium)
- **Location:** `eastus` (separate from main resources to avoid Linux/Windows conflicts)
- **OS:** Linux
- **Reserved:** True (dedicated Linux workers)

**Configuration:**

| Setting | Value | Description |
|---------|-------|-------------|
| SKU | EP1 | Elastic Premium (always-warm, VNet integration capable) |
| Max Burst | 20 workers | Maximum scale-out |
| Pre-warmed Instances | 1 | Reduces cold start |
| OS | Linux | Required for Python 3.11 |

---

#### Function App

**Resource Details (from AZURE_CONFIG.json):**
```bash
jq -r '.stages.stage4.resources.functionApp' AZURE_CONFIG.json
```

- **Function App Name:** `pptgen-dev-func`
- **URL:** `https://pptgen-dev-func.azurewebsites.net`
- **Runtime:** Python 3.11
- **Storage Account:** `pptgendevfuncqskh` (internal, stage 4)
- **Managed Identity:** System-assigned + User-assigned

**Configuration:**

| Setting | Value | Description |
|---------|-------|-------------|
| Runtime Stack | Python | Version 3.11 |
| Runtime Version | ~4 | Functions runtime v4 |
| Always On | True | Keeps app always warm (EP1 plan) |
| HTTPS Only | True | Enforces HTTPS |
| Managed Identity | System + User-assigned | Both identities configured |
| CORS | `*` | Allow all origins (restrict for production) |

**Functions:**

| Function | Trigger | Route | Purpose |
|----------|---------|-------|---------|
| `generate_presentation` | HTTP POST | `/api/presentations/generate` | Submit generation job |
| `get_job_status` | HTTP GET | `/api/presentations/status/{job_id}` | Get job status |
| `list_templates` | HTTP GET | `/api/templates` | List available templates |
| `get_template` | HTTP GET | `/api/templates/{template_id}` | Get template metadata |
| `health_check` | HTTP GET | `/api/health` | Health check |
| `poll_for_templates` | Timer | N/A (cron) | Process new templates (every 1 minute) |

**App Settings:** See [Section 3](#3-environment-variables) for complete environment variable list.

**Storage Configuration (Managed Identity):**

```bash
# Internal Function Runtime Storage (managed identity)
AzureWebJobsStorage__blobServiceUri=https://pptgendevfuncqskh.blob.core.windows.net
AzureWebJobsStorage__queueServiceUri=https://pptgendevfuncqskh.queue.core.windows.net
AzureWebJobsStorage__tableServiceUri=https://pptgendevfuncqskh.table.core.windows.net
AzureWebJobsStorage__credential=managedidentity
AzureWebJobsSecretStorageType=files

# External Blob Storage (Stage 2 - managed identity)
BlobStorage__blobServiceUri=https://pptgendevqskhmc2dhedgg.blob.core.windows.net
BlobStorage__credential=managedidentity
STORAGE_ACCOUNT_NAME=pptgendevqskhmc2dhedgg
```

---

### Stage 5: AI

**Purpose:** Azure OpenAI service for AI-powered generation

#### Azure OpenAI

**Resource Details (from AZURE_CONFIG.json):**
```bash
jq -r '.stages.stage5.resources.openAi' AZURE_CONFIG.json
```

- **Account Name:** `pptgen-dev-openai-nwyhzr`
- **Endpoint:** `https://pptgen-dev-openai-nwyhzr.openai.azure.com/`
- **Location:** `eastus2` (or region with model availability)
- **SKU:** `S0` (Standard)

**Configuration:**

| Setting | Value | Description |
|---------|-------|-------------|
| Public Network Access | Enabled | Required for Container App access |
| Custom Subdomain | `pptgen-dev-openai-nwyhzr` | Used in endpoint URL |
| Identity-based Access | Enabled | Managed identity authentication |
| Dynamic Quota | Enabled | Auto-adjusts quota based on usage |

**Model Deployments:**

| Deployment Name | Model | Version | Capacity (TPM) | Purpose |
|-----------------|-------|---------|----------------|---------|
| `gpt-4o` | GPT-4o | `2024-08-06` | 150K | Main AI reasoning (Assistants API) |
| `text-embedding-3-small` | text-embedding-3-small | Latest | 350K | Embeddings (future use) |

> **Note:** The `gpt-4o-mini` deployment is optional and can be added for cost optimization on simpler tasks. The current V3 architecture uses `gpt-4o` for all Assistants API calls.

**Capacity Planning:**

| Deployment | Tokens/Request | Requests/Min | Total TPM |
|------------|----------------|--------------|-----------|
| `gpt-4o` | ~2000-5000 | 10-20 | 20K-100K |
| `gpt-4o-mini` | ~1000-3000 | 10-20 | 10K-60K |

**Authentication (Managed Identity):**
```bash
# No API keys — use Managed Identity
AZURE_OPENAI_ENDPOINT=https://pptgen-dev-openai-nwyhzr.openai.azure.com/
AZURE_OPENAI_GPT_DEPLOYMENT=gpt-4o
AZURE_OPENAI_MINI_DEPLOYMENT=gpt-4o-mini
# Applications authenticate via DefaultAzureCredential with scope:
# https://cognitiveservices.azure.com/.default
```

**Content Filtering:**

Default Azure content filters are enabled:
- Hate: Medium severity threshold
- Sexual: Medium severity threshold
- Violence: Medium severity threshold
- Self-harm: Medium severity threshold

---

### Stage 6: Web (Optional)

**Purpose:** Web test portal for testing the API (not required for production)

**Note:** This stage is optional and only used for local testing and demonstration.

#### App Service Plan

**Resource Details (from AZURE_CONFIG.json):**
```bash
jq -r '.stages.stage6.resources.appServicePlan' AZURE_CONFIG.json
```

- **Plan Name:** `plan-pptgen-web`
- **SKU:** `B1` (Basic)
- **Location:** `eastus`

---

#### Web App

**Resource Details (from AZURE_CONFIG.json):**
```bash
jq -r '.stages.stage6.resources.webApp' AZURE_CONFIG.json
```

- **App Name:** `pptgen-web`
- **URL:** `https://pptgen-web-bnegdaa2f6hcakck.eastus-01.azurewebsites.net`
- **Runtime:** .NET 8.0
- **Framework:** ASP.NET Core

**Configuration:**

| Setting | Value | Description |
|---------|-------|-------------|
| Runtime Stack | .NET | Version 8.0 |
| HTTPS Only | True | Enforces HTTPS |
| Always On | False | Not needed for test portal |

**App Settings:**

| Setting | Value | Description |
|---------|-------|-------------|
| `Orchestrator__BaseUrl` | `https://pptgen-dev-orchestrator.bluedune-c6a878ee.eastus2.azurecontainerapps.io` | Orchestrator endpoint |
| `FunctionApi__BaseUrl` | `https://pptgen-dev-func.azurewebsites.net` | Functions API endpoint |

---

## 5. Application Configurations

Applications are located in `apps/` as independent solutions.

### Orchestrator (V3 Assistants API Pipeline)

**Location:** `apps/orchestrator/`

**Runtime:** Python 3.11

**Key Dependencies:**
- `openai` - Azure OpenAI Assistants API integration
- `fastapi` - HTTP endpoints
- `uvicorn` - ASGI server
- `azure-identity` - Managed identity authentication
- `azure-servicebus` - Service Bus SDK
- `azure-cosmos` - Cosmos DB SDK
- `azure-storage-blob` - Blob Storage SDK
- `openai` - Azure OpenAI SDK
- `python-pptx` - PowerPoint generation
- `plotly` - Chart generation
- `kaleido` - Chart image export

**Environment Variables:** See [Section 3 - Orchestrator Environment Variables](#orchestrator-container-app---environment-variables)

**Configuration File:** None (all configuration via environment variables)

**Application Insights Integration:**
```python
# Configured via APPLICATIONINSIGHTS_CONNECTION_STRING environment variable
# Automatic instrumentation via OpenTelemetry
```

---

### Azure Functions API

**Location:** `apps/api-functions/`

**Runtime:** Python 3.11 (Linux)

**Key Dependencies:**
- `azure-functions` - Functions runtime
- `azure-identity` - Managed identity authentication
- `azure-servicebus` - Service Bus SDK
- `azure-cosmos` - Cosmos DB SDK
- `azure-storage-blob` - Blob Storage SDK
- `pydantic` - Request/response validation
- `python-pptx` - Template introspection

**Environment Variables:** See [Section 3 - Azure Functions API Environment Variables](#azure-functions-api---environment-variables)

**Configuration File:** `host.json`

```json
{
  "version": "2.0",
  "logging": {
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": true,
        "maxTelemetryItemsPerSecond": 20
      }
    }
  },
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[4.*, 5.0.0)"
  }
}
```

---

### Web Test Portal (Optional)

**Location:** `apps/web/`

**Runtime:** .NET 8.0 (ASP.NET Core)

**App Settings:**

| Setting | Value/Pattern | Description |
|---------|---------------|-------------|
| `Orchestrator__BaseUrl` | `https://<orchestrator-fqdn>` | Orchestrator endpoint |
| `FunctionApi__BaseUrl` | `https://<function-app>.azurewebsites.net` | Functions API endpoint |
| `ASPNETCORE_ENVIRONMENT` | `Development` or `Production` | Environment mode |

**Configuration File:** `appsettings.json`

```json
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning"
    }
  },
  "Orchestrator": {
    "BaseUrl": "https://pptgen-dev-orchestrator.bluedune-c6a878ee.eastus2.azurecontainerapps.io"
  },
  "FunctionApi": {
    "BaseUrl": "https://pptgen-dev-func.azurewebsites.net"
  }
}
```

---

## 6. Security Configuration

### Key Vault

**Resource (from AZURE_CONFIG.json):**
```bash
jq -r '.stages.stage1.resources.keyVault' AZURE_CONFIG.json
```

- **Resource Name:** `kvpptgendev4vxbc4`
- **URI:** `https://kvpptgendev4vxbc4.vault.azure.net/`

**Secrets:**

| Secret Name | Description | Rotation Policy |
|-------------|-------------|-----------------|
| `sql-admin-password` | SQL admin password (only if not using Entra-only auth) | Manual, 90 days |

**RBAC Configuration:**

| Identity | Type | Role | Scope |
|----------|------|------|-------|
| `pptgen-dev-container-app-id` | User-assigned MI | Key Vault Secrets User | Key Vault |
| `pptgen-dev-func-id` | User-assigned MI | Key Vault Secrets User | Key Vault |
| Deployer User | User | Key Vault Administrator | Key Vault |

---

### Managed Identities

**Identities (from AZURE_CONFIG.json):**
```bash
jq -r '.stages.stage1.managedIdentities' AZURE_CONFIG.json
```

| Identity | Type | Assigned To | Role Assignments |
|----------|------|-------------|------------------|
| `pptgen-dev-container-app-id` | User-Assigned | Container App (Orchestrator) | Service Bus Data Receiver, Cosmos DB Data Contributor, Storage Blob Data Contributor, Storage Blob Delegator, Cognitive Services OpenAI User, SQL DB Contributor |
| `pptgen-dev-func-id` | User-Assigned | Function App | Service Bus Data Sender, Cosmos DB Data Contributor, Storage Blob Data Contributor (Stage 2), Storage Blob Data Owner (Stage 4), Storage Queue Data Contributor, Storage Table Data Contributor, SQL DB Contributor |
| `pptgen-dev-sql-id` | User-Assigned | SQL Server | SQL Server Admin (via Entra) |
| Function App | System-Assigned | Function App | Same as `pptgen-dev-func-id` (redundant for flexibility) |

---

### RBAC Assignments

**CRITICAL:** All service-to-service authentication uses Managed Identity. No connection strings or access keys.

**Service Bus:**

| Principal | Resource | Role | Purpose |
|-----------|----------|------|---------|
| `pptgen-dev-container-app-id` | Service Bus Namespace | Azure Service Bus Data Receiver | Consume job messages |
| `pptgen-dev-func-id` | Service Bus Namespace | Azure Service Bus Data Sender | Queue job messages |

**Cosmos DB:**

| Principal | Resource | Role | Purpose |
|-----------|----------|------|---------|
| `pptgen-dev-container-app-id` | Cosmos DB Account | Cosmos DB Data Contributor | Read/write all containers |
| `pptgen-dev-func-id` | Cosmos DB Account | Cosmos DB Data Contributor | Manage jobs, cache, templates |

**Storage Account (Stage 2):**

| Principal | Resource | Role | Purpose |
|-----------|----------|------|---------|
| `pptgen-dev-container-app-id` | Storage Account | Storage Blob Data Contributor | Read templates, write outputs |
| `pptgen-dev-container-app-id` | Storage Account | Storage Blob Delegator | Generate SAS tokens |
| `pptgen-dev-func-id` | Storage Account | Storage Blob Data Contributor | List and read templates |

**Storage Account (Stage 4 - Function internal):**

| Principal | Resource | Role | Purpose |
|-----------|----------|------|---------|
| `pptgen-dev-func-id` | Storage Account | Storage Blob Data Owner | Function runtime storage |
| `pptgen-dev-func-id` | Storage Account | Storage Queue Data Contributor | Function runtime queues |
| `pptgen-dev-func-id` | Storage Account | Storage Table Data Contributor | Function runtime tables |
| `pptgen-dev-func-id` | Storage Account | Storage Account Contributor | Full management access |

**Azure OpenAI:**

| Principal | Resource | Role | Purpose |
|-----------|----------|------|---------|
| `pptgen-dev-container-app-id` | OpenAI Account | Cognitive Services OpenAI User | Call GPT models |

**Azure SQL:**

| Principal | Resource | Role | Purpose |
|-----------|----------|------|---------|
| `pptgen-dev-container-app-id` | SQL Database | db_datareader, db_datawriter | Read/write telemetry |
| `pptgen-dev-func-id` | SQL Database | db_datareader, db_datawriter | Read/write telemetry |

**SQL RBAC Setup (via T-SQL):**
```sql
-- Container App identity
CREATE USER [pptgen-dev-container-app-id] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [pptgen-dev-container-app-id];
ALTER ROLE db_datawriter ADD MEMBER [pptgen-dev-container-app-id];

-- Function App identity
CREATE USER [pptgen-dev-func-id] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [pptgen-dev-func-id];
ALTER ROLE db_datawriter ADD MEMBER [pptgen-dev-func-id];
```

---

## 7. Networking Configuration

### Public Endpoints

**IMPORTANT:** This POC uses public endpoints for all services. For production, consider implementing:
- Virtual Network integration for Container Apps and Functions
- Private Endpoints for PaaS services
- Azure Firewall or Network Security Groups

**Current Configuration:**

| Service | Public Access | Justification |
|---------|---------------|---------------|
| Storage Account | Enabled | Required for Function App with managed identity |
| Cosmos DB | Enabled | Required for Container App access |
| SQL Server | Enabled | Required for deployment and app access |
| Service Bus | Enabled | Required for managed identity access |
| Azure OpenAI | Enabled | Required for Container App access |
| Key Vault | Enabled | Required for Function App access |

### Firewall Rules

**SQL Server:**

| Rule Name | Source | Destination | Action |
|-----------|--------|-------------|--------|
| AllowAzureServices | Azure internal IPs | SQL Server | Allow |
| AllowDeployerIP | Deployer IP | SQL Server | Allow |

**Storage Account:**

| Rule Name | Source | Action | Notes |
|-----------|--------|--------|-------|
| AllowAzureServices | Azure internal IPs | Allow | Implicit via managed identity |

**Service Bus:**

| Rule Name | Source | Action | Notes |
|-----------|--------|--------|-------|
| AllowAzureServices | Azure internal IPs | Allow | Implicit via managed identity |

---

## 8. Monitoring Configuration

### Application Insights

**Resource (from AZURE_CONFIG.json):**
```bash
jq -r '.stages.stage1.resources.appInsights' AZURE_CONFIG.json
```

| Setting | Value | Notes |
|---------|-------|-------|
| Name | `pptgen-dev-insights` | |
| Type | Workspace-based | Logs stored in Log Analytics |
| Workspace | `pptgen-dev-logs` | Centralized log storage |
| Sampling | Adaptive | Auto-adjusts based on volume |
| Daily Cap | 100 GB | Prevents runaway costs |
| Retention | 30 days | Inherited from workspace |

**Connection String:**
```bash
CONNECTION_STRING=$(jq -r '.stages.stage1.resources.appInsights.connectionString' AZURE_CONFIG.json)
```

**Instrumented Applications:**
- Container App (Orchestrator) - via `APPLICATIONINSIGHTS_CONNECTION_STRING`
- Function App - via built-in integration
- Web App (optional) - via ASP.NET Core integration

---

### Log Analytics

**Resource (from AZURE_CONFIG.json):**
```bash
jq -r '.stages.stage1.resources.logAnalytics' AZURE_CONFIG.json
```

| Setting | Value | Notes |
|---------|-------|-------|
| Name | `pptgen-dev-logs` | |
| SKU | `PerGB2018` | Pay-as-you-go |
| Retention | 30 days | Adjustable 30-730 days |
| Daily Cap | None | No ingestion limit |

**Data Sources:**
- Application Insights (all app telemetry)
- Container Apps Environment (container logs)
- Container App (application logs)
- Function App (function logs)

---

### Diagnostic Settings

| Resource | Logs | Metrics | Destination |
|----------|------|---------|-------------|
| Storage Account | StorageRead, StorageWrite, StorageDelete | Transaction, Capacity | Log Analytics |
| Cosmos DB | DataPlaneRequests, QueryRuntimeStatistics | Requests, Storage | Log Analytics |
| SQL Database | SQLInsights, QueryStoreRuntimeStatistics | Basic | Log Analytics |
| Service Bus | OperationalLogs | AllMetrics | Log Analytics |
| Container App | ContainerAppConsoleLogs | AllMetrics | Log Analytics |
| Function App | FunctionAppLogs | AllMetrics | Log Analytics |

---

### Key Queries

**Container App Logs:**
```kusto
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == "pptgen-dev-orchestrator"
| where TimeGenerated > ago(1h)
| order by TimeGenerated desc
```

**Function App Errors:**
```kusto
FunctionAppLogs
| where Level == "Error"
| where TimeGenerated > ago(24h)
| order by TimeGenerated desc
```

**Service Bus Queue Depth:**
```kusto
AzureMetrics
| where ResourceProvider == "MICROSOFT.SERVICEBUS"
| where MetricName == "ActiveMessages"
| where TimeGenerated > ago(1h)
| summarize avg(Average) by bin(TimeGenerated, 5m)
```

**Azure OpenAI Token Usage:**
```kusto
requests
| where cloud_RoleName == "pptgen-dev-orchestrator"
| where customDimensions.["ai.operation.name"] contains "chat.completions"
| summarize TotalTokens = sum(toint(customDimensions.["ai.response.tokens"])) by bin(timestamp, 1h)
```

---

## 9. Configuration by Environment

### Development (dev)

```bash
# Deployment
./infrastructure/deploy.sh -g rg-pptgen -e dev -l eastus2 -s all --openai-location eastus2

# Core Settings
ENVIRONMENT=dev
LOCATION=eastus2
OPENAI_LOCATION=eastus2

# Sizing (minimal for cost savings)
SERVICE_BUS_SKU=Premium
SERVICE_BUS_CAPACITY=1
COSMOS_CAPACITY=Serverless
SQL_SKU=Basic
CONTAINER_APP_MIN_REPLICAS=1
CONTAINER_APP_MAX_REPLICAS=10
FUNCTION_SKU=EP1

# Features
ENTRA_ONLY_AUTH=true
SOFT_DELETE=true (90 days)
PURGE_PROTECTION=false
```

### Staging (stg)

```bash
# Deployment
./infrastructure/deploy.sh -g rg-pptgen -e stg -l eastus2 -s all --openai-location eastus2

# Core Settings
ENVIRONMENT=stg
LOCATION=eastus2
OPENAI_LOCATION=eastus2

# Sizing
SERVICE_BUS_SKU=Premium
SERVICE_BUS_CAPACITY=2
COSMOS_CAPACITY=Serverless
SQL_SKU=Standard (S1)
CONTAINER_APP_MIN_REPLICAS=1
CONTAINER_APP_MAX_REPLICAS=50
FUNCTION_SKU=EP2

# Features
ENTRA_ONLY_AUTH=true
SOFT_DELETE=true (90 days)
PURGE_PROTECTION=true
```

### Production (prd)

```bash
# Deployment
./infrastructure/deploy.sh -g rg-pptgen -e prd -l eastus2 -s all --openai-location eastus2

# Core Settings
ENVIRONMENT=prd
LOCATION=eastus2
SECONDARY_LOCATION=westus2
OPENAI_LOCATION=eastus2

# Sizing
SERVICE_BUS_SKU=Premium
SERVICE_BUS_CAPACITY=4
COSMOS_CAPACITY=Provisioned (10000 RU/s, autoscale)
SQL_SKU=Standard (S3 or higher)
CONTAINER_APP_MIN_REPLICAS=2
CONTAINER_APP_MAX_REPLICAS=100
FUNCTION_SKU=EP3

# Features
ENTRA_ONLY_AUTH=true
SOFT_DELETE=true (90 days)
PURGE_PROTECTION=true
MULTI_REGION=true (Cosmos, Storage GRS)
PRIVATE_ENDPOINTS=true
VNET_INTEGRATION=true

# Production-only
AZURE_FIREWALL=true
NSG_RULES=Enabled
DDoS_PROTECTION=true
```

### Environment Comparison

| Configuration | Dev | Stg | Prd |
|---------------|-----|-----|-----|
| Service Bus Capacity | 1 MU | 2 MU | 4 MU |
| Cosmos DB | Serverless | Serverless | Provisioned (10K RU) |
| SQL SKU | Basic | S1 | S3 |
| Container App Min | 1 | 1 | 2 |
| Container App Max | 10 | 50 | 100 |
| Function Plan | EP1 | EP2 | EP3 |
| VNet Integration | No | No | Yes |
| Private Endpoints | No | No | Yes |
| Multi-region | No | No | Yes |
| Purge Protection | No | Yes | Yes |
| Cost (monthly est.) | $200-400 | $800-1500 | $3000-6000 |

---

## Configuration Validation

### Pre-Deployment Checklist

- [ ] `AZURE_CONFIG.json` does not exist (will be created by deployment)
- [ ] All required resource providers are registered in subscription
- [ ] Azure CLI is logged in with appropriate permissions
- [ ] Docker is running (for Container Registry operations)
- [ ] Deployment script has execute permissions (`chmod +x`)
- [ ] Resource naming follows conventions: `{prefix}-{env}-{resource-type}`
- [ ] Selected Azure regions support all required services

### Post-Deployment Validation

```bash
# Verify AZURE_CONFIG.json was created and populated
cat AZURE_CONFIG.json | jq '.stages'

# Verify all stages deployed
jq -r '.stages | keys[]' AZURE_CONFIG.json

# Verify managed identity principal IDs exist
jq -r '.stages.stage1.managedIdentities[].principalId' AZURE_CONFIG.json

# Verify Storage Account configuration
STORAGE_ACCOUNT=$(jq -r '.stages.stage2.resources.storageAccount.name' AZURE_CONFIG.json)
az storage account show --name $STORAGE_ACCOUNT --query "{name:name, allowSharedKeyAccess:allowSharedKeyAccess, publicNetworkAccess:publicNetworkAccess}"

# Verify Cosmos DB endpoint
COSMOS_ENDPOINT=$(jq -r '.stages.stage2.resources.cosmosDb.endpoint' AZURE_CONFIG.json)
echo "Cosmos endpoint: $COSMOS_ENDPOINT"

# Verify SQL Server authentication mode
SQL_SERVER=$(jq -r '.stages.stage2.resources.sqlServer.name' AZURE_CONFIG.json)
az sql server show --name $SQL_SERVER --resource-group rg-pptgen-data --query "administrators.azureADOnlyAuthentication"

# Verify Container App is running
CONTAINER_APP=$(jq -r '.stages.stage3.resources.containerApp.name' AZURE_CONFIG.json)
az containerapp show --name $CONTAINER_APP --resource-group rg-pptgen-compute --query "properties.runningStatus"

# Test health endpoints
ORCHESTRATOR_URL=$(jq -r '.stages.stage3.resources.containerApp.url' AZURE_CONFIG.json)
curl -s "${ORCHESTRATOR_URL}/health" | jq '.'

FUNC_URL=$(jq -r '.stages.stage4.resources.functionApp.url' AZURE_CONFIG.json)
curl -s "${FUNC_URL}/api/health" | jq '.'

# Verify RBAC assignments (example for Container App identity)
PRINCIPAL_ID=$(jq -r '.stages.stage1.managedIdentities.containerApp.principalId' AZURE_CONFIG.json)
az role assignment list --assignee $PRINCIPAL_ID --output table
```

---

## Configuration Management

### Updating Configuration

When modifying infrastructure, always update:

1. **AZURE_CONFIG.json** - Deployment script updates automatically, or edit manually for out-of-band changes
2. **Environment Variables** - Update in Azure Portal or via CLI:
   ```bash
   az containerapp update --name <app-name> --resource-group <rg> --set-env-vars KEY=VALUE
   az functionapp config appsettings set --name <func-name> --resource-group <rg> --settings KEY=VALUE
   ```
3. **Documentation** - Update this guide and DEPLOYMENT.md
4. **IaC Templates** - Update Bicep/Terraform modules

### Configuration Backup

```bash
# Backup AZURE_CONFIG.json
cp AZURE_CONFIG.json AZURE_CONFIG.json.$(date +%Y%m%d-%H%M%S)

# Export resource group configurations
az group export --name rg-pptgen-foundation --output json > backups/foundation-$(date +%Y%m%d).json
```

### Secret Rotation

```bash
# Rotate SQL password (if using SQL auth)
NEW_PASSWORD=$(openssl rand -base64 32)
KV_NAME=$(jq -r '.stages.stage1.resources.keyVault.name' AZURE_CONFIG.json)
az keyvault secret set --vault-name $KV_NAME --name sql-admin-password --value "$NEW_PASSWORD"

# Update SQL Server (requires downtime)
SQL_SERVER=$(jq -r '.stages.stage2.resources.sqlServer.name' AZURE_CONFIG.json)
az sql server update --name $SQL_SERVER --resource-group rg-pptgen-data --admin-password "$NEW_PASSWORD"
```

---

*Last updated: January 2025*
