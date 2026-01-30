# PPT Generator Service

An AI-powered presentation generation service built on Azure that transforms structured data collections into professional PowerPoint presentations using Azure OpenAI's Assistants API.

![Azure](https://img.shields.io/badge/Azure-0078D4?style=flat&logo=microsoft-azure&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.11-blue?style=flat&logo=python&logoColor=white)
![.NET](https://img.shields.io/badge/.NET-8.0-512BD4?style=flat&logo=dotnet&logoColor=white)
![Bicep](https://img.shields.io/badge/IaC-Bicep%20%7C%20Terraform-orange?style=flat)

## Overview

The PPT Generator Service is a serverless, microservices-based solution that automatically creates executive-quality PowerPoint presentations from raw data. Using a simplified V3 architecture with Azure OpenAI's Assistants API, it combines AI-driven intelligence with local chart rendering for consistent, high-quality output.

**Key Value Proposition:**
- Transform structured data into professional presentations in minutes
- AI-powered visualization selection and narrative design
- Template-based branding with automatic layout mapping
- Scalable, serverless architecture with managed identity security

## Features

### Core Capabilities
- **V3 Assistants API Integration** - Single-call AI generation with structured outputs
- **Smart Chart Generation** - AI-selected visualizations rendered locally with Plotly
- **Template System** - Automatic introspection and layout mapping for any PowerPoint template
- **Multi-Slide Narrative** - Intelligent content splitting and bullet extraction
- **Async Processing** - Queue-based architecture for long-running operations
- **Caching & Deduplication** - Content-based hashing to avoid redundant processing

### Supported Visualizations
| Chart Type | Best For |
|------------|----------|
| Horizontal Bar | Rankings, long labels |
| Grouped Bar | Multi-series comparisons |
| Stacked Bar | Part-to-whole relationships |
| Pie / Donut | Simple distributions (≤6 categories) |
| Line / Area | Time-series trends |
| Waterfall | Changes and savings analysis |
| Diverging Bar | Gap analysis (current vs. target) |

### Supported Data Types
- Time Series
- Categorical Data
- Comparisons
- Percentages & Distributions
- Rankings & Funnel Data
- Free-Form Text & Narratives

## Architecture Overview

The service uses a **6-stage deployment architecture** with isolated resource groups for better management and debugging.

```
Stage 1: Foundation     → Log Analytics, App Insights, Key Vault, Managed Identities
Stage 2: Data           → Storage, Cosmos DB, SQL Server, Service Bus
Stage 3: Compute        → Container Apps, Container Registry
Stage 4: Functions      → Azure Functions API Layer
Stage 5: AI             → Azure OpenAI (GPT-4o, GPT-4o-mini)
Stage 6: Web (Optional) → Test Portal (ASP.NET Core)
```

**Request Flow:**
1. Client submits generation request via Azure Functions API
2. Job is queued in Service Bus for async processing
3. Container App orchestrator processes job using Assistants API
4. AI generates slide specifications and chart blueprints
5. Charts rendered locally using Plotly + Kaleido
6. PowerPoint assembled and uploaded to Blob Storage
7. Client retrieves presentation via SAS URL

For detailed architecture information, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Prerequisites

### Required Tools
- **Azure CLI** - For deployment and management
- **Docker** - For building container images
- **Python 3.11** - For orchestrator and function development
- **Azure Functions Core Tools** - For local function development
- **.NET 8.0 SDK** - For web test interface (optional)
- **jq** - For JSON processing in deployment scripts
- **sqlcmd** - For database schema deployment

### Azure Subscription Requirements
- Active Azure subscription with Contributor or Owner access
- Registered resource providers (see [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md#prerequisites))
- Access to Azure OpenAI (model availability varies by region)

## Quick Start

### 1. Clone Repository
```bash
git clone <repository-url>
cd ppt-generator
```

### 2. Deploy Infrastructure

Choose either Bicep or Terraform for deployment:

**Option A: Bicep (Recommended)**
```bash
# Make scripts executable
chmod +x infrastructure/deploy.sh

# Deploy all core stages (1-5)
./infrastructure/deploy.sh \
  -g rg-pptgen \
  -e dev \
  -l eastus2 \
  -s all \
  --openai-location eastus2
```

**Option B: Terraform**
```bash
# Make scripts executable
chmod +x infrastructure/deploy-tf.sh

# Deploy all core stages (1-5)
./infrastructure/deploy-tf.sh \
  -g rg-pptgen \
  -e dev \
  -l eastus2 \
  -s all \
  --openai-location eastus2
```

### 3. Deploy Database Schema

Use Azure Portal Query Editor or sqlcmd:

```bash
# Get SQL Server details
CONFIG_FILE="AZURE_CONFIG.json"
SQL_SERVER=$(jq -r '.stages.stage2.resources.sqlServer.fqdn' $CONFIG_FILE)
USER_EMAIL=$(az ad signed-in-user show --query userPrincipalName -o tsv)

# Deploy schema
sqlcmd -S "$SQL_SERVER" -d telemetry -G -U "$USER_EMAIL" -i sql/001_create_tables.sql
sqlcmd -S "$SQL_SERVER" -d telemetry -G -U "$USER_EMAIL" -i sql/002_create_views.sql
```

### 4. Build and Deploy Applications

```bash
# Get resource details
ACR_LOGIN=$(jq -r '.stages.stage3.resources.containerRegistry.loginServer' $CONFIG_FILE)
CONTAINER_APP=$(jq -r '.stages.stage3.resources.containerApp.name' $CONFIG_FILE)
FUNC_APP=$(jq -r '.stages.stage4.resources.functionApp.name' $CONFIG_FILE)
RG_COMPUTE=$(jq -r '.stages.stage3.resourceGroups.compute.name' $CONFIG_FILE)

# Login to ACR
az acr login --name ${ACR_LOGIN%%.*}

# Build and push orchestrator
docker build -t ${ACR_LOGIN}/pptgen-orchestrator:v1.0.0 apps/orchestrator
docker push ${ACR_LOGIN}/pptgen-orchestrator:v1.0.0

# Update Container App
az containerapp update \
  --name $CONTAINER_APP \
  --resource-group $RG_COMPUTE \
  --image ${ACR_LOGIN}/pptgen-orchestrator:v1.0.0

# Deploy Function App
cd apps/api-functions
func azure functionapp publish $FUNC_APP
```

### 5. Upload Templates

```bash
STORAGE_ACCOUNT=$(jq -r '.stages.stage2.resources.storageAccount.name' $CONFIG_FILE)

# Upload PowerPoint template
az storage blob upload \
  --account-name $STORAGE_ACCOUNT \
  --container-name ppt-templates \
  --name "my-template.pptx" \
  --file ./my-template.pptx \
  --auth-mode login

# Metadata is auto-generated within 1 minute by timer function
```

For complete deployment instructions, see [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md).

## Project Structure

```
ppt-generator/
├── apps/
│   ├── api-functions/          # Azure Functions API layer
│   ├── orchestrator/           # Container App orchestrator
│   └── web/                    # ASP.NET Core test portal (optional)
├── docs/
│   ├── ARCHITECTURE.md         # Detailed architecture documentation
│   ├── CONFIGURATION.md        # Service configuration guide
│   ├── DEPLOYMENT.md           # Deployment runbooks
│   └── DEVELOPMENT.md          # Development guide
├── infrastructure/
│   ├── bicep/                  # Bicep IaC templates
│   ├── terraform/              # Terraform IaC modules
│   ├── deploy.sh               # Bicep deployment script
│   └── deploy-tf.sh            # Terraform deployment script
├── sql/
│   ├── 001_create_tables.sql   # Database schema
│   └── 002_create_views.sql    # Database views
├── samples/                    # Sample request payloads
├── AZURE_CONFIG.json           # Auto-generated config (deployment outputs)
└── README.md                   # This file
```

## Documentation

| Document | Description |
|----------|-------------|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Complete system architecture, data flows, and design decisions |
| [DEPLOYMENT.md](docs/DEPLOYMENT.md) | Step-by-step deployment instructions for Bicep and Terraform |
| [DEVELOPMENT.md](docs/DEVELOPMENT.md) | Developer onboarding, local development, and troubleshooting |
| [CONFIGURATION.md](docs/CONFIGURATION.md) | Service configurations and environment variables |

## Configuration

The service uses `AZURE_CONFIG.json` as the central configuration file, auto-generated during deployment. This file contains:
- Resource names, IDs, and endpoints
- Managed identity principal IDs
- Deployment outputs for all 6 stages
- Tags and naming conventions

**Example structure:**
```json
{
  "project": {
    "name": "pptgen",
    "environment": "dev"
  },
  "stages": {
    "stage1": { "resources": { "keyVault": {...} } },
    "stage2": { "resources": { "cosmosDb": {...}, "storageAccount": {...} } },
    ...
  }
}
```

**Security Note:** All services use **Managed Identity** authentication. No connection strings or access keys are stored in configuration files.

## Development

### Local Development Setup

```bash
# Navigate to orchestrator
cd apps/orchestrator

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure environment
cat > .env << EOF
AZURE_OPENAI_ENDPOINT=$(jq -r '.stages.stage5.resources.openAi.endpoint' ../../AZURE_CONFIG.json)
COSMOS_ENDPOINT=$(jq -r '.stages.stage2.resources.cosmosDb.endpoint' ../../AZURE_CONFIG.json)
STORAGE_ACCOUNT_NAME=$(jq -r '.stages.stage2.resources.storageAccount.name' ../../AZURE_CONFIG.json)
LOG_LEVEL=DEBUG
EOF

# Run locally (uses your Azure CLI credentials)
uvicorn main:app --reload --port 8000
```

For complete development instructions, see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

### Testing

Submit a test request:

```bash
FUNC_URL=$(jq -r '.stages.stage4.resources.functionApp.url' AZURE_CONFIG.json)

curl -X POST "${FUNC_URL}/api/generate" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Q4 Budget Review",
    "audience": "Executive Leadership",
    "data": [
      {
        "collectionId": "revenue-001",
        "title": "Quarterly Revenue",
        "data": {"Q1": 2500000, "Q2": 2750000, "Q3": 2900000, "Q4": 3100000}
      }
    ],
    "preferences": {
      "template": "executive"
    }
  }'
```

## Technology Stack

| Layer | Technology | Version |
|-------|------------|---------|
| API | Azure Functions | Python 3.11 |
| Orchestrator | Azure Container Apps + FastAPI | Python 3.11 |
| AI | Azure OpenAI Assistants API | GPT-4o, GPT-4o-mini |
| Charts | Plotly + Kaleido | Latest |
| PPTX | python-pptx | 0.6.23+ |
| Messaging | Azure Service Bus | Premium |
| State | Cosmos DB | Serverless |
| Storage | Azure Blob Storage | Standard LRS |
| Telemetry | Azure SQL Database | Basic |
| Monitoring | Application Insights | Workspace-based |
| Web Portal | ASP.NET Core | 8.0 |
| IaC | Bicep / Terraform | Latest |

## Contributing

We welcome contributions! Here's how to get started:

1. **Fork the repository**
   ```bash
   git fork <repository-url>
   ```

2. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make your changes**
   - Follow existing code style and conventions
   - Update documentation for any new features
   - Add tests where applicable

4. **Test your changes**
   - Deploy to a dev environment
   - Verify end-to-end functionality
   - Check logs for errors

5. **Submit a pull request**
   - Provide clear description of changes
   - Reference any related issues
   - Ensure all checks pass

### Development Guidelines

- **Code Style:** Follow PEP 8 for Python, Microsoft conventions for C#
- **Documentation:** Update relevant .md files in docs/ folder
- **Security:** Always use Managed Identity, never hardcode secrets
- **Testing:** Test locally before submitting PR
- **Commits:** Use clear, descriptive commit messages

## License

This project is licensed under the MIT License.

```
MIT License

Copyright (c) 2025

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Support

For issues, questions, or contributions:
- Review [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for troubleshooting
- Check existing issues in the repository
- Create a new issue with detailed description and logs

## Acknowledgments

Built on Azure's serverless platform with:
- Azure OpenAI for intelligent content generation
- Azure Container Apps for scalable orchestration
- Azure Functions for serverless API layer
- python-pptx for PowerPoint manipulation
- Plotly for high-quality chart rendering

---

**Last Updated:** January 2025
