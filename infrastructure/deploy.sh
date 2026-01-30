#!/bin/bash
# ============================================
# PPT Generator Service - Bicep Staged Deployment Script
# Deploys infrastructure in stages for better control
# ============================================
#
# This script deploys Azure infrastructure using Bicep templates
# in a staged approach. Each stage can be deployed independently,
# allowing for incremental deployment and easier troubleshooting.
#
# Stages:
#   1 - Foundation: Log Analytics, App Insights, Key Vault, Managed Identities
#   2 - Data: Storage, Cosmos DB, SQL Server, Service Bus
#   3 - Compute: Container Registry, Container Apps Environment, Orchestrator
#   4 - Functions: Azure Functions (Linux) API Layer
#   5 - AI: Azure OpenAI Service
#   6 - Web: Test Web Portal (optional - not required for production)
#
# Usage:
#   ./deploy.sh -g rg-pptgen -e dev -l eastus2 -s 1
#   ./deploy.sh -g rg-pptgen -e dev -l eastus2 -s all
#   ./deploy.sh -g rg-pptgen -e dev -l eastus2 -s 6  # Optional web stage
#
# ============================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT="dev"
LOCATION="eastus2"
FUNC_LOCATION="eastus"
OPENAI_LOCATION="eastus2"
RESOURCE_GROUP=""
STAGE=""
SQL_ENTRA_ONLY_AUTH="true"
SKIP_ROLE_ASSIGNMENTS="false"

# Script directory and paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BICEP_DIR="$SCRIPT_DIR/bicep/stages"
CONFIG_FILE="$SCRIPT_DIR/../AZURE_CONFIG.json"

# Usage function
usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -e, --environment       Environment (dev, stg, prd) [default: dev]"
    echo "  -l, --location          Azure region for main resources [default: eastus2]"
    echo "  --func-location         Azure region for Functions resources [default: eastus]"
    echo "  --openai-location       Azure region for OpenAI resources [default: eastus2]"
    echo "  -g, --resource-group    Base resource group name (e.g., rg-pptgen) [required]"
    echo "  -s, --stage             Stage to deploy (1-6, or 'all') [required]"
    echo "  --sql-auth              Use SQL authentication instead of Entra-only"
    echo "  --skip-role-assignments Skip role assignments (if they already exist)"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Stages:"
    echo "  1 - Foundation: Log Analytics, App Insights, Key Vault, Managed Identities"
    echo "  2 - Data: Storage, Cosmos DB, SQL Server, Service Bus"
    echo "  3 - Compute: Container Registry, Container Apps Environment, Orchestrator"
    echo "  4 - Functions: Azure Functions (Linux) API Layer"
    echo "  5 - AI: Azure OpenAI Service"
    echo "  6 - Web: Test Web Portal (optional - not required for production)"
    echo "  all - Deploy stages 1-5 in order (excludes optional stage 6)"
    echo ""
    echo "Resource Group Naming:"
    echo "  Stage 1: <base>-foundation"
    echo "  Stage 2: <base>-data"
    echo "  Stage 3: <base>-compute"
    echo "  Stage 4: <base>-func"
    echo "  Stage 5: <base>-ai"
    echo "  Stage 6: <base>-web"
    echo ""
    echo "Examples:"
    echo "  $0 -g rg-pptgen -e dev -l eastus2 -s 1          # Deploy stage 1"
    echo "  $0 -g rg-pptgen -e dev -l eastus2 -s all        # Deploy stages 1-5"
    echo "  $0 -g rg-pptgen -e dev -l eastus2 -s 6          # Deploy optional web stage"
    echo "  $0 -g rg-pptgen -e dev -s 5 --openai-location swedencentral"
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        --func-location)
            FUNC_LOCATION="$2"
            shift 2
            ;;
        --openai-location)
            OPENAI_LOCATION="$2"
            shift 2
            ;;
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -s|--stage)
            STAGE="$2"
            shift 2
            ;;
        --sql-auth)
            SQL_ENTRA_ONLY_AUTH="false"
            shift
            ;;
        --skip-role-assignments)
            SKIP_ROLE_ASSIGNMENTS="true"
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            ;;
    esac
done

# Validate required parameters
if [ -z "$RESOURCE_GROUP" ]; then
    echo -e "${RED}Error: Resource group is required${NC}"
    usage
fi

if [ -z "$STAGE" ]; then
    echo -e "${RED}Error: Stage is required${NC}"
    usage
fi

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|stg|prd)$ ]]; then
    echo -e "${RED}Error: Environment must be dev, stg, or prd${NC}"
    exit 1
fi

# Validate stage
if [[ ! "$STAGE" =~ ^(1|2|3|4|5|6|all)$ ]]; then
    echo -e "${RED}Error: Stage must be 1, 2, 3, 4, 5, 6, or 'all'${NC}"
    exit 1
fi

# Resource group names - each stage gets its own RG for easy cleanup
RG_FOUNDATION="${RESOURCE_GROUP}-foundation"
RG_DATA="${RESOURCE_GROUP}-data"
RG_COMPUTE="${RESOURCE_GROUP}-compute"
RG_FUNC="${RESOURCE_GROUP}-func"
RG_AI="${RESOURCE_GROUP}-ai"
RG_WEB="${RESOURCE_GROUP}-web"

# Initialize AZURE_CONFIG.json if it doesn't exist
init_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}Initializing AZURE_CONFIG.json...${NC}"

        # Get subscription info
        local sub_id=$(az account show --query id -o tsv)
        local sub_name=$(az account show --query name -o tsv)
        local tenant_id=$(az account show --query tenantId -o tsv)
        local current_date=$(date -u +%Y-%m-%d)

        cat > "$CONFIG_FILE" << EOF
{
  "project": {
    "name": "pptgen",
    "customer": "",
    "environment": "$ENVIRONMENT",
    "createdDate": "$current_date",
    "lastModified": "$current_date"
  },
  "subscription": {
    "id": "$sub_id",
    "name": "$sub_name",
    "tenantId": "$tenant_id",
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
    "primary": "$LOCATION",
    "secondary": ""
  },
  "resourcePrefix": "",
  "uniqueSuffix": "",
  "stages": {}
}
EOF
        echo -e "${GREEN}Created AZURE_CONFIG.json${NC}"
    fi
}

# Read value from config file
read_config() {
    local key="$1"
    jq -r "$key // empty" "$CONFIG_FILE" 2>/dev/null || echo ""
}

# Update config file with stage results
update_config() {
    local stage="$1"
    local stage_name="$2"
    local stage_description="$3"
    local rg_name="$4"
    local rg_location="$5"
    local outputs="$6"
    local is_optional="${7:-false}"

    local current_date=$(date -u +%Y-%m-%d)

    # Build the stage object
    local stage_json=$(cat << EOF
{
  "name": "$stage_name",
  "description": "$stage_description",
  "optional": $is_optional,
  "resourceGroups": {
    "$(echo "$stage_name" | tr '[:upper:]' '[:lower:]')": {
      "name": "$rg_name",
      "location": "$rg_location",
      "tags": {
        "Environment": "$ENVIRONMENT",
        "Stage": "$stage",
        "Purpose": "$stage_name"
      }
    }
  },
  "managedIdentities": {},
  "resources": $outputs
}
EOF
)

    # Update the config file
    local temp_file=$(mktemp)
    jq --argjson stage_data "$stage_json" \
       --arg date "$current_date" \
       ".stages.stage${stage} = \$stage_data | .project.lastModified = \$date" \
       "$CONFIG_FILE" > "$temp_file"
    mv "$temp_file" "$CONFIG_FILE"

    echo -e "${GREEN}Updated AZURE_CONFIG.json with stage $stage results${NC}"
}

# Update config with managed identities (for stage 1)
update_config_identities() {
    local identities="$1"

    local temp_file=$(mktemp)
    jq --argjson identities "$identities" \
       ".stages.stage1.managedIdentities = \$identities" \
       "$CONFIG_FILE" > "$temp_file"
    mv "$temp_file" "$CONFIG_FILE"
}

# Update config with resource prefix and suffix (from stage 1)
update_config_prefix() {
    local prefix="$1"
    local suffix="$2"

    local temp_file=$(mktemp)
    jq --arg prefix "$prefix" --arg suffix "$suffix" \
       ".resourcePrefix = \$prefix | .uniqueSuffix = \$suffix" \
       "$CONFIG_FILE" > "$temp_file"
    mv "$temp_file" "$CONFIG_FILE"
}

# Deploy a stage using Bicep
deploy_stage() {
    local stage_num="$1"
    local rg="$2"
    local location="$3"
    local bicep_file="$4"
    local params="$5"

    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}Deploying Stage $stage_num${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo "Resource Group: $rg"
    echo "Location: $location"
    echo "Template: $bicep_file"
    echo ""

    # Create resource group
    echo -e "${YELLOW}Creating resource group if needed...${NC}"
    az group create --name "$rg" --location "$location" --output none

    # Deploy
    local deployment_name="stage${stage_num}-$(date +%Y%m%d%H%M%S)"
    echo -e "${YELLOW}Starting deployment: $deployment_name${NC}"

    if ! az deployment group create \
        --name "$deployment_name" \
        --resource-group "$rg" \
        --template-file "$bicep_file" \
        --parameters $params \
        --output json > /tmp/deployment-result.json 2>&1; then

        echo -e "${RED}============================================${NC}"
        echo -e "${RED}Stage $stage_num Deployment Failed!${NC}"
        echo -e "${RED}============================================${NC}"
        cat /tmp/deployment-result.json | jq -r '.error // .' 2>/dev/null || cat /tmp/deployment-result.json
        rm -f /tmp/deployment-result.json
        exit 1
    fi

    rm -f /tmp/deployment-result.json

    # Get outputs
    echo -e "${YELLOW}Retrieving deployment outputs...${NC}"
    local outputs=$(az deployment group show \
        --name "$deployment_name" \
        --resource-group "$rg" \
        --query properties.outputs)

    # Transform outputs to simpler format (key: value instead of key: {value: x})
    local simple_outputs=$(echo "$outputs" | jq 'to_entries | map({(.key): .value.value}) | add // {}')

    # Return the outputs
    echo "$simple_outputs"
}

# Get deployer principal ID
get_deployer_principal_id() {
    local principal_id=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "")
    if [ -z "$principal_id" ]; then
        principal_id=$(az account show --query "user.name" -o tsv 2>/dev/null | xargs -I {} az ad sp show --id {} --query id -o tsv 2>/dev/null || echo "")
    fi
    echo "$principal_id"
}

# ============================================
# Stage 1: Foundation
# ============================================
deploy_stage_1() {
    echo -e "${BLUE}Stage 1: Foundation${NC}"
    echo "Components: Log Analytics, App Insights, Key Vault, Managed Identities"
    echo ""

    local deployer_id=$(get_deployer_principal_id)

    local outputs=$(deploy_stage 1 "$RG_FOUNDATION" "$LOCATION" "$BICEP_DIR/stage1-foundation.bicep" \
        "environment=$ENVIRONMENT baseName=pptgen deployerPrincipalId=$deployer_id")

    # Extract values for config
    local resource_prefix=$(echo "$outputs" | jq -r '.resourcePrefix // empty')
    local unique_suffix=$(echo "$outputs" | jq -r '.uniqueSuffix // empty')

    # Update prefix/suffix at root level
    update_config_prefix "$resource_prefix" "$unique_suffix"

    # Build resources object for config
    local resources=$(echo "$outputs" | jq '{
        logAnalytics: {
            name: .logAnalyticsWorkspaceName,
            id: .logAnalyticsWorkspaceId,
            resourceGroup: "'"$RG_FOUNDATION"'"
        },
        appInsights: {
            name: (.resourcePrefix + "-insights"),
            instrumentationKey: .appInsightsInstrumentationKey,
            connectionString: .appInsightsConnectionString,
            resourceGroup: "'"$RG_FOUNDATION"'"
        },
        keyVault: {
            name: .keyVaultName,
            uri: .keyVaultUri,
            resourceGroup: "'"$RG_FOUNDATION"'"
        }
    }')

    # Build managed identities object
    local identities=$(echo "$outputs" | jq '{
        containerApp: {
            name: .containerAppIdentityName,
            id: .containerAppIdentityId,
            clientId: .containerAppIdentityClientId,
            principalId: .containerAppIdentityPrincipalId
        },
        functionApp: {
            name: .functionAppIdentityName,
            id: .functionAppIdentityId,
            clientId: .functionAppIdentityClientId,
            principalId: .functionAppIdentityPrincipalId
        },
        sql: {
            name: .sqlIdentityName,
            id: .sqlIdentityId,
            clientId: .sqlIdentityClientId,
            principalId: .sqlIdentityPrincipalId
        }
    }')

    update_config 1 "Foundation" "Foundational components: Log Analytics, App Insights, Key Vault, Managed Identities" \
        "$RG_FOUNDATION" "$LOCATION" "$resources"
    update_config_identities "$identities"

    echo -e "${GREEN}Stage 1 completed successfully!${NC}"
    echo ""
}

# ============================================
# Stage 2: Data
# ============================================
deploy_stage_2() {
    echo -e "${BLUE}Stage 2: Data${NC}"
    echo "Components: Storage Account, Cosmos DB, SQL Server, Service Bus"
    echo ""

    # Read required values from stage 1
    local resource_prefix=$(read_config '.resourcePrefix')
    local unique_suffix=$(read_config '.uniqueSuffix')
    local sql_identity_id=$(read_config '.stages.stage1.managedIdentities.sql.id')
    local sql_identity_principal=$(read_config '.stages.stage1.managedIdentities.sql.principalId')

    if [ -z "$resource_prefix" ] || [ -z "$unique_suffix" ]; then
        echo -e "${RED}Error: Stage 1 outputs not found. Please deploy stage 1 first.${NC}"
        exit 1
    fi

    # Generate SQL password if needed
    local sql_password=""
    if [ "$SQL_ENTRA_ONLY_AUTH" = "false" ]; then
        sql_password=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 20)
    fi

    local outputs=$(deploy_stage 2 "$RG_DATA" "$LOCATION" "$BICEP_DIR/stage2-data.bicep" \
        "environment=$ENVIRONMENT baseName=pptgen resourcePrefix=$resource_prefix uniqueSuffix=$unique_suffix sqlIdentityId=$sql_identity_id sqlIdentityPrincipalId=$sql_identity_principal sqlEntraOnlyAuth=$SQL_ENTRA_ONLY_AUTH sqlAdminUsername=pptadmin sqlAdminPassword=$sql_password")

    # Build resources object for config
    local resources=$(echo "$outputs" | jq '{
        storageAccount: {
            name: .storageAccountName,
            id: .storageAccountId,
            connectionString: .storageAccountConnectionString,
            resourceGroup: "'"$RG_DATA"'"
        },
        cosmosDb: {
            name: .cosmosAccountName,
            endpoint: .cosmosEndpoint,
            key: .cosmosKey,
            resourceGroup: "'"$RG_DATA"'"
        },
        sqlServer: {
            name: .sqlServerName,
            fqdn: .sqlServerFqdn,
            databaseName: .sqlDatabaseName,
            entraOnlyAuthentication: .sqlEntraOnlyAuthentication,
            resourceGroup: "'"$RG_DATA"'"
        },
        serviceBus: {
            name: .serviceBusNamespace,
            id: .serviceBusId,
            connectionString: .serviceBusConnectionString,
            resourceGroup: "'"$RG_DATA"'"
        }
    }')

    update_config 2 "Data" "Data layer: Storage Account, Cosmos DB, SQL Server, Service Bus" \
        "$RG_DATA" "$LOCATION" "$resources"

    echo -e "${GREEN}Stage 2 completed successfully!${NC}"
    echo ""
}

# ============================================
# Stage 3: Compute
# ============================================
deploy_stage_3() {
    echo -e "${BLUE}Stage 3: Compute${NC}"
    echo "Components: Container Registry, Container Apps Environment, Orchestrator"
    echo ""

    # Read required values from previous stages
    local resource_prefix=$(read_config '.resourcePrefix')
    local unique_suffix=$(read_config '.uniqueSuffix')
    local log_analytics_id=$(read_config '.stages.stage1.resources.logAnalytics.id')
    local app_insights_conn=$(read_config '.stages.stage1.resources.appInsights.connectionString')
    local container_app_identity_id=$(read_config '.stages.stage1.managedIdentities.containerApp.id')
    local container_app_identity_client=$(read_config '.stages.stage1.managedIdentities.containerApp.clientId')
    local container_app_identity_principal=$(read_config '.stages.stage1.managedIdentities.containerApp.principalId')

    # Stage 2 outputs
    local storage_account_name=$(read_config '.stages.stage2.resources.storageAccount.name')
    local servicebus_namespace=$(read_config '.stages.stage2.resources.serviceBus.name')
    local cosmos_endpoint=$(read_config '.stages.stage2.resources.cosmosDb.endpoint')
    local cosmos_account_name=$(read_config '.stages.stage2.resources.cosmosDb.name')

    # Stage 5 outputs (Azure OpenAI)
    local openai_endpoint=$(read_config '.stages.stage5.resources.openAi.endpoint')
    local openai_account_name=$(read_config '.stages.stage5.resources.openAi.name')
    local openai_gpt_deployment=$(read_config '.stages.stage5.resources.openAi.deployments.gpt')

    if [ -z "$resource_prefix" ] || [ -z "$storage_account_name" ]; then
        echo -e "${RED}Error: Previous stage outputs not found. Please deploy stages 1 and 2 first.${NC}"
        exit 1
    fi

    if [ -z "$openai_endpoint" ] || [ -z "$openai_account_name" ]; then
        echo -e "${RED}Error: Azure OpenAI not deployed. Please deploy stage 5 first.${NC}"
        exit 1
    fi

    # Create params file for complex parameters
    local params_file=$(mktemp)
    cat > "$params_file" << EOF
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "environment": { "value": "$ENVIRONMENT" },
    "baseName": { "value": "pptgen" },
    "resourcePrefix": { "value": "$resource_prefix" },
    "uniqueSuffix": { "value": "$unique_suffix" },
    "logAnalyticsWorkspaceId": { "value": "$log_analytics_id" },
    "appInsightsConnectionString": { "value": "$app_insights_conn" },
    "containerAppIdentityId": { "value": "$container_app_identity_id" },
    "containerAppIdentityClientId": { "value": "$container_app_identity_client" },
    "containerAppIdentityPrincipalId": { "value": "$container_app_identity_principal" },
    "storageAccountName": { "value": "$storage_account_name" },
    "serviceBusNamespace": { "value": "${servicebus_namespace}.servicebus.windows.net" },
    "cosmosEndpoint": { "value": "$cosmos_endpoint" },
    "cosmosAccountName": { "value": "$cosmos_account_name" },
    "openAiEndpoint": { "value": "$openai_endpoint" },
    "openAiAccountName": { "value": "$openai_account_name" },
    "openAiGptDeployment": { "value": "${openai_gpt_deployment:-gpt-4o}" },
    "openAiMiniDeployment": { "value": "gpt-4o-mini" },
    "openAiResourceGroup": { "value": "$RG_AI" },
    "dataResourceGroup": { "value": "$RG_DATA" }
  }
}
EOF

    local outputs=$(deploy_stage 3 "$RG_COMPUTE" "$LOCATION" "$BICEP_DIR/stage3-compute.bicep" "@$params_file")
    rm -f "$params_file"

    # Build resources object for config
    local resources=$(echo "$outputs" | jq '{
        containerRegistry: {
            name: .containerRegistryName,
            loginServer: .containerRegistryLoginServer,
            resourceGroup: "'"$RG_COMPUTE"'"
        },
        containerAppsEnvironment: {
            name: .containerAppsEnvironmentName,
            id: .containerAppsEnvironmentId,
            resourceGroup: "'"$RG_COMPUTE"'"
        },
        containerApp: {
            name: .containerAppName,
            fqdn: .containerAppFqdn,
            url: .containerAppUrl,
            resourceGroup: "'"$RG_COMPUTE"'"
        }
    }')

    update_config 3 "Compute" "Compute layer: Container Registry, Container Apps Environment, Orchestrator" \
        "$RG_COMPUTE" "$LOCATION" "$resources"

    echo -e "${GREEN}Stage 3 completed successfully!${NC}"
    echo ""
}

# ============================================
# Stage 4: Functions
# ============================================
deploy_stage_4() {
    echo -e "${BLUE}Stage 4: Functions${NC}"
    echo "Components: Azure Functions API Layer"
    echo ""

    # Read required values from previous stages
    local resource_prefix=$(read_config '.resourcePrefix')
    local unique_suffix=$(read_config '.uniqueSuffix')
    local app_insights_conn=$(read_config '.stages.stage1.resources.appInsights.connectionString')
    local cosmos_endpoint=$(read_config '.stages.stage2.resources.cosmosDb.endpoint')
    local cosmos_key=$(read_config '.stages.stage2.resources.cosmosDb.key')
    local orchestrator_url=$(read_config '.stages.stage3.resources.containerApp.url')

    # Storage account info
    local storage_account_name=$(read_config '.stages.stage2.resources.storageAccount.name')
    local storage_account_id=$(read_config '.stages.stage2.resources.storageAccount.id')

    # Service Bus info
    local servicebus_namespace=$(read_config '.stages.stage2.resources.serviceBus.name')
    local servicebus_id=$(read_config '.stages.stage2.resources.serviceBus.id')

    # OpenAI values from stage 5
    local openai_endpoint=$(read_config '.stages.stage5.resources.openAi.endpoint')
    local openai_key=$(read_config '.stages.stage5.resources.openAi.key')

    if [ -z "$resource_prefix" ] || [ -z "$orchestrator_url" ]; then
        echo -e "${RED}Error: Previous stage outputs not found. Please deploy stages 1-3 first.${NC}"
        exit 1
    fi

    # Fallback: get storage_account_id from Azure if not in config
    if [ -z "$storage_account_id" ] && [ -n "$storage_account_name" ]; then
        echo -e "${YELLOW}Fetching storage account ID from Azure...${NC}"
        storage_account_id=$(az storage account show --name "$storage_account_name" --query id -o tsv 2>/dev/null || echo "")
    fi

    # Fallback: get servicebus_id from Azure if not in config
    if [ -z "$servicebus_id" ] && [ -n "$servicebus_namespace" ]; then
        echo -e "${YELLOW}Fetching Service Bus ID from Azure...${NC}"
        servicebus_id=$(az servicebus namespace show --name "$servicebus_namespace" --resource-group "$RG_DATA" --query id -o tsv 2>/dev/null || echo "")
    fi

    # Create params file for secrets
    local params_file=$(mktemp)
    cat > "$params_file" << EOF
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "environment": { "value": "$ENVIRONMENT" },
    "baseName": { "value": "pptgen" },
    "resourcePrefix": { "value": "$resource_prefix" },
    "uniqueSuffix": { "value": "$unique_suffix" },
    "appInsightsConnectionString": { "value": "$app_insights_conn" },
    "serviceBusNamespace": { "value": "$servicebus_namespace" },
    "serviceBusId": { "value": "${servicebus_id:-}" },
    "serviceBusResourceGroupName": { "value": "$RG_DATA" },
    "cosmosEndpoint": { "value": "$cosmos_endpoint" },
    "cosmosKey": { "value": "$cosmos_key" },
    "orchestratorUrl": { "value": "$orchestrator_url" },
    "openAiEndpoint": { "value": "${openai_endpoint:-}" },
    "openAiKey": { "value": "${openai_key:-}" },
    "storageAccountName": { "value": "${storage_account_name:-}" },
    "storageAccountId": { "value": "${storage_account_id:-}" },
    "storageResourceGroupName": { "value": "$RG_DATA" },
    "skipRoleAssignments": { "value": $SKIP_ROLE_ASSIGNMENTS }
  }
}
EOF

    local outputs=$(deploy_stage 4 "$RG_FUNC" "$FUNC_LOCATION" "$BICEP_DIR/stage4-functions.bicep" "@$params_file")
    rm -f "$params_file"

    # Build resources object for config
    local resources=$(echo "$outputs" | jq '{
        functionApp: {
            name: .functionAppName,
            planName: .functionAppPlanName,
            principalId: .functionAppPrincipalId,
            storageAccountName: .functionAppStorageAccountName,
            url: .functionAppUrl,
            resourceGroup: "'"$RG_FUNC"'"
        }
    }')

    update_config 4 "Functions" "Azure Functions API layer" \
        "$RG_FUNC" "$FUNC_LOCATION" "$resources"

    echo -e "${GREEN}Stage 4 completed successfully!${NC}"
    echo ""
}

# ============================================
# Stage 5: AI
# ============================================
deploy_stage_5() {
    echo -e "${BLUE}Stage 5: AI${NC}"
    echo "Components: Azure OpenAI Service"
    echo ""

    local resource_prefix=$(read_config '.resourcePrefix')

    if [ -z "$resource_prefix" ]; then
        echo -e "${RED}Error: Stage 1 outputs not found. Please deploy stage 1 first.${NC}"
        exit 1
    fi

    local outputs=$(deploy_stage 5 "$RG_AI" "$OPENAI_LOCATION" "$BICEP_DIR/stage5-ai.bicep" \
        "environment=$ENVIRONMENT baseName=pptgen resourcePrefix=$resource_prefix")

    # Build resources object for config
    local resources=$(echo "$outputs" | jq '{
        openAi: {
            name: .openAiAccountName,
            endpoint: .openAiEndpoint,
            key: .openAiKey,
            resourceGroup: "'"$RG_AI"'",
            deployments: {
                gpt: .gptDeploymentName,
                embedding: .embeddingDeploymentName
            }
        }
    }')

    update_config 5 "AI" "Azure OpenAI Service with GPT and embedding deployments" \
        "$RG_AI" "$OPENAI_LOCATION" "$resources"

    echo -e "${GREEN}Stage 5 completed successfully!${NC}"
    echo ""
}

# ============================================
# Stage 6: Web (Optional)
# ============================================
deploy_stage_6() {
    echo -e "${BLUE}Stage 6: Web (Optional)${NC}"
    echo "Components: Test Web Portal"
    echo ""

    local resource_prefix=$(read_config '.resourcePrefix')
    local app_insights_conn=$(read_config '.stages.stage1.resources.appInsights.connectionString')
    local orchestrator_url=$(read_config '.stages.stage3.resources.containerApp.url')
    local function_url=$(read_config '.stages.stage4.resources.functionApp.url')

    if [ -z "$resource_prefix" ]; then
        echo -e "${RED}Error: Stage 1 outputs not found. Please deploy stage 1 first.${NC}"
        exit 1
    fi

    if [ -z "$orchestrator_url" ]; then
        echo -e "${YELLOW}Warning: Orchestrator URL not found. Web app may not function correctly.${NC}"
    fi

    # Check if stage6-web.bicep exists
    if [ ! -f "$BICEP_DIR/stage6-web.bicep" ]; then
        echo -e "${YELLOW}Warning: stage6-web.bicep not found. Creating resource group only.${NC}"

        # Create resource group
        az group create --name "$RG_WEB" --location "$FUNC_LOCATION" --output none

        # Create minimal config entry
        local resources='{
            "webApp": {
                "name": "",
                "url": "",
                "resourceGroup": "'"$RG_WEB"'"
            },
            "appServicePlan": {
                "name": "",
                "resourceGroup": "'"$RG_WEB"'"
            }
        }'

        update_config 6 "Web" "Web test portal for testing the application (optional - not required for production)" \
            "$RG_WEB" "$FUNC_LOCATION" "$resources" "true"

        echo -e "${YELLOW}Resource group created. Deploy web app manually or create stage6-web.bicep.${NC}"
        return
    fi

    # Create params file
    local params_file=$(mktemp)
    cat > "$params_file" << EOF
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "environment": { "value": "$ENVIRONMENT" },
    "baseName": { "value": "pptgen" },
    "resourcePrefix": { "value": "$resource_prefix" },
    "appInsightsConnectionString": { "value": "${app_insights_conn:-}" },
    "orchestratorUrl": { "value": "${orchestrator_url:-}" },
    "functionAppUrl": { "value": "${function_url:-}" }
  }
}
EOF

    local outputs=$(deploy_stage 6 "$RG_WEB" "$FUNC_LOCATION" "$BICEP_DIR/stage6-web.bicep" "@$params_file")
    rm -f "$params_file"

    # Build resources object for config
    local resources=$(echo "$outputs" | jq '{
        appServicePlan: {
            name: .appServicePlanName,
            resourceGroup: "'"$RG_WEB"'"
        },
        webApp: {
            name: .webAppName,
            url: .webAppUrl,
            resourceGroup: "'"$RG_WEB"'"
        },
        appInsights: {
            name: .appInsightsName,
            resourceGroup: "'"$RG_WEB"'"
        }
    }')

    update_config 6 "Web" "Web test portal for testing the application (optional - not required for production)" \
        "$RG_WEB" "$FUNC_LOCATION" "$resources" "true"

    echo -e "${GREEN}Stage 6 completed successfully!${NC}"
    echo ""
}

# ============================================
# Main Execution
# ============================================
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}PPT Generator - Bicep Staged Deployment${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Environment:       $ENVIRONMENT"
echo "Primary Location:  $LOCATION"
echo "Functions Location: $FUNC_LOCATION"
echo "OpenAI Location:   $OPENAI_LOCATION"
echo "Config File:       $CONFIG_FILE"
echo ""
echo "Resource Groups:"
echo "  Stage 1 (Foundation): $RG_FOUNDATION ($LOCATION)"
echo "  Stage 2 (Data):       $RG_DATA ($LOCATION)"
echo "  Stage 3 (Compute):    $RG_COMPUTE ($LOCATION)"
echo "  Stage 4 (Functions):  $RG_FUNC ($FUNC_LOCATION)"
echo "  Stage 5 (AI):         $RG_AI ($OPENAI_LOCATION)"
echo "  Stage 6 (Web):        $RG_WEB ($FUNC_LOCATION) [optional]"
echo ""
echo "Stage to deploy:   $STAGE"
echo ""

# Confirm deployment
read -p "Do you want to proceed with the deployment? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Deployment cancelled${NC}"
    exit 0
fi

# Initialize config
init_config

# Deploy requested stage(s)
case $STAGE in
    1)
        deploy_stage_1
        ;;
    2)
        deploy_stage_2
        ;;
    3)
        deploy_stage_3
        ;;
    4)
        deploy_stage_4
        ;;
    5)
        deploy_stage_5
        ;;
    6)
        deploy_stage_6
        ;;
    all)
        # Deploy stages 1-5 in correct order (5 before 3 because 3 needs OpenAI)
        deploy_stage_1
        deploy_stage_2
        deploy_stage_5  # Deploy AI before Compute (stage 3 needs OpenAI)
        deploy_stage_3
        deploy_stage_4
        # Note: Stage 6 (Web) is optional and not included in 'all'
        echo -e "${YELLOW}Note: Stage 6 (Web) is optional and was not deployed.${NC}"
        echo -e "${YELLOW}To deploy the web portal, run: $0 -g $RESOURCE_GROUP -e $ENVIRONMENT -s 6${NC}"
        ;;
esac

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Configuration saved to: $CONFIG_FILE"
echo ""
echo "To view configuration:"
echo "  cat $CONFIG_FILE | jq ."
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Deploy SQL schema: cd ../sql && sqlcmd -S <server>.database.windows.net -d telemetry -i 001_create_tables.sql"
echo "2. Upload templates to blob storage"
echo "3. Build and push container image to ACR"
echo "4. Deploy Azure Functions code"
echo ""
