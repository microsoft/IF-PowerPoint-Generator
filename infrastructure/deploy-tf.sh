#!/bin/bash
# ============================================
# PPT Generator Service - Terraform Staged Deployment Script
# Deploys infrastructure in stages for better control
# ============================================
#
# This script deploys Azure infrastructure using Terraform
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
#   ./deploy-tf.sh -g rg-pptgen -e dev -l eastus2 -s 1
#   ./deploy-tf.sh -g rg-pptgen -e dev -l eastus2 -s all
#   ./deploy-tf.sh -g rg-pptgen -e dev -l eastus2 -s 6  # Optional web stage
#   ./deploy-tf.sh -g rg-pptgen -e dev -s 3 --destroy   # Destroy stage 3
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
ACTION="apply"  # apply or destroy

# Script directory and paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_STAGES_DIR="$SCRIPT_DIR/terraform/stages"
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
    echo "  --destroy               Destroy resources instead of creating them"
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
    echo "  $0 -g rg-pptgen -e dev -s 3 --destroy           # Destroy stage 3"
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
        --destroy)
            ACTION="destroy"
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

# Update config file with stage results from Terraform outputs
update_config_from_terraform() {
    local stage="$1"
    local stage_name="$2"
    local stage_description="$3"
    local rg_name="$4"
    local rg_location="$5"
    local stage_dir="$6"
    local is_optional="${7:-false}"

    local current_date=$(date -u +%Y-%m-%d)

    # Get terraform outputs as JSON
    local outputs=$(cd "$stage_dir" && terraform output -json 2>/dev/null || echo "{}")

    # Transform to simpler format (key: value instead of key: {value: x})
    local simple_outputs=$(echo "$outputs" | jq 'to_entries | map({(.key): .value.value}) | add // {}')

    # Build the stage object based on stage number
    local resources="{}"
    local identities="{}"

    case $stage in
        1)
            resources=$(echo "$simple_outputs" | jq '{
                logAnalytics: {
                    name: .log_analytics_workspace_name,
                    id: .log_analytics_workspace_id,
                    resourceGroup: "'"$rg_name"'"
                },
                appInsights: {
                    name: (.resource_prefix + "-insights"),
                    instrumentationKey: .app_insights_instrumentation_key,
                    connectionString: .app_insights_connection_string,
                    resourceGroup: "'"$rg_name"'"
                },
                keyVault: {
                    name: .key_vault_name,
                    uri: .key_vault_uri,
                    resourceGroup: "'"$rg_name"'"
                }
            }')
            identities=$(echo "$simple_outputs" | jq '{
                containerApp: {
                    name: .container_app_identity_name,
                    id: .container_app_identity_id,
                    clientId: .container_app_identity_client_id,
                    principalId: .container_app_identity_principal_id
                },
                functionApp: {
                    name: .function_app_identity_name,
                    id: .function_app_identity_id,
                    clientId: .function_app_identity_client_id,
                    principalId: .function_app_identity_principal_id
                },
                sql: {
                    name: .sql_identity_name,
                    id: .sql_identity_id,
                    clientId: .sql_identity_client_id,
                    principalId: .sql_identity_principal_id
                }
            }')
            # Update prefix/suffix at root level
            local prefix=$(echo "$simple_outputs" | jq -r '.resource_prefix // empty')
            local suffix=$(echo "$simple_outputs" | jq -r '.unique_suffix // empty')
            if [ -n "$prefix" ] && [ -n "$suffix" ]; then
                local temp_file=$(mktemp)
                jq --arg prefix "$prefix" --arg suffix "$suffix" \
                   ".resourcePrefix = \$prefix | .uniqueSuffix = \$suffix" \
                   "$CONFIG_FILE" > "$temp_file"
                mv "$temp_file" "$CONFIG_FILE"
            fi
            ;;
        2)
            resources=$(echo "$simple_outputs" | jq '{
                storageAccount: {
                    name: .storage_account_name,
                    id: .storage_account_id,
                    connectionString: .storage_account_connection_string,
                    resourceGroup: "'"$rg_name"'"
                },
                cosmosDb: {
                    name: .cosmos_account_name,
                    endpoint: .cosmos_endpoint,
                    key: .cosmos_key,
                    resourceGroup: "'"$rg_name"'"
                },
                sqlServer: {
                    name: .sql_server_name,
                    fqdn: .sql_server_fqdn,
                    databaseName: .sql_database_name,
                    entraOnlyAuthentication: .sql_entra_only_authentication,
                    resourceGroup: "'"$rg_name"'"
                },
                serviceBus: {
                    name: .servicebus_namespace,
                    id: .servicebus_id,
                    connectionString: .servicebus_connection_string,
                    resourceGroup: "'"$rg_name"'"
                }
            }')
            ;;
        3)
            resources=$(echo "$simple_outputs" | jq '{
                containerRegistry: {
                    name: .container_registry_name,
                    loginServer: .container_registry_login_server,
                    resourceGroup: "'"$rg_name"'"
                },
                containerAppsEnvironment: {
                    name: .container_apps_environment_name,
                    id: .container_apps_environment_id,
                    resourceGroup: "'"$rg_name"'"
                },
                containerApp: {
                    name: .container_app_name,
                    fqdn: .container_app_fqdn,
                    url: .container_app_url,
                    resourceGroup: "'"$rg_name"'"
                }
            }')
            ;;
        4)
            resources=$(echo "$simple_outputs" | jq '{
                functionApp: {
                    name: .function_app_name,
                    planName: .function_app_plan_name,
                    principalId: .function_app_principal_id,
                    storageAccountName: .function_app_storage_account_name,
                    url: .function_app_url,
                    resourceGroup: "'"$rg_name"'"
                }
            }')
            ;;
        5)
            resources=$(echo "$simple_outputs" | jq '{
                openAi: {
                    name: .openai_account_name,
                    endpoint: .openai_endpoint,
                    key: .openai_key,
                    resourceGroup: "'"$rg_name"'",
                    deployments: {
                        gpt: .gpt_deployment_name,
                        embedding: .embedding_deployment_name
                    }
                }
            }')
            ;;
        6)
            resources=$(echo "$simple_outputs" | jq '{
                appServicePlan: {
                    name: .app_service_plan_name,
                    resourceGroup: "'"$rg_name"'"
                },
                webApp: {
                    name: .web_app_name,
                    url: .web_app_url,
                    resourceGroup: "'"$rg_name"'"
                },
                appInsights: {
                    name: .app_insights_name,
                    resourceGroup: "'"$rg_name"'"
                }
            }')
            ;;
    esac

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
  "managedIdentities": $identities,
  "resources": $resources
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

# Deploy a stage using Terraform
deploy_stage() {
    local stage_num="$1"
    local stage_dir="$2"
    local tfvars_content="$3"
    local rg_name="$4"
    local rg_location="$5"

    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}Stage $stage_num: $ACTION${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo "Directory: $stage_dir"
    echo "Resource Group: $rg_name"
    echo "Location: $rg_location"
    echo ""

    # Check if stage directory exists
    if [ ! -d "$stage_dir" ]; then
        echo -e "${RED}Error: Stage directory not found: $stage_dir${NC}"
        exit 1
    fi

    cd "$stage_dir"

    # Write tfvars file
    echo "$tfvars_content" > terraform.tfvars

    # Initialize Terraform
    echo -e "${YELLOW}Initializing Terraform...${NC}"
    terraform init -upgrade

    if [ "$ACTION" = "destroy" ]; then
        echo -e "${YELLOW}Destroying stage $stage_num...${NC}"
        terraform destroy -auto-approve
        echo -e "${GREEN}Stage $stage_num destroyed!${NC}"
    else
        # Plan
        echo -e "${YELLOW}Planning...${NC}"
        terraform plan -out=tfplan

        # Apply
        echo -e "${YELLOW}Applying...${NC}"
        terraform apply tfplan
        rm -f tfplan

        echo -e "${GREEN}Stage $stage_num completed!${NC}"
    fi

    cd - > /dev/null
    echo ""
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
    local deployer_id=$(get_deployer_principal_id)

    local tfvars="
environment           = \"$ENVIRONMENT\"
location              = \"$LOCATION\"
base_name             = \"pptgen\"
resource_group_name   = \"$RG_FOUNDATION\"
deployer_principal_id = \"$deployer_id\"
"
    deploy_stage 1 "$TF_STAGES_DIR/stage1-foundation" "$tfvars" "$RG_FOUNDATION" "$LOCATION"

    if [ "$ACTION" = "apply" ]; then
        update_config_from_terraform 1 "Foundation" \
            "Foundational components: Log Analytics, App Insights, Key Vault, Managed Identities" \
            "$RG_FOUNDATION" "$LOCATION" "$TF_STAGES_DIR/stage1-foundation"
    fi
}

# ============================================
# Stage 2: Data
# ============================================
deploy_stage_2() {
    local resource_prefix=$(read_config '.resourcePrefix')
    local unique_suffix=$(read_config '.uniqueSuffix')
    local sql_identity_id=$(read_config '.stages.stage1.managedIdentities.sql.id')
    local sql_identity_principal=$(read_config '.stages.stage1.managedIdentities.sql.principalId')

    if [ -z "$resource_prefix" ] && [ "$ACTION" = "apply" ]; then
        echo -e "${RED}Error: Stage 1 outputs not found. Please deploy stage 1 first.${NC}"
        exit 1
    fi

    local tfvars="
environment               = \"$ENVIRONMENT\"
location                  = \"$LOCATION\"
base_name                 = \"pptgen\"
resource_group_name       = \"$RG_DATA\"
resource_prefix           = \"$resource_prefix\"
unique_suffix             = \"$unique_suffix\"
sql_identity_id           = \"$sql_identity_id\"
sql_identity_principal_id = \"$sql_identity_principal\"
sql_entra_only_auth       = $SQL_ENTRA_ONLY_AUTH
"
    deploy_stage 2 "$TF_STAGES_DIR/stage2-data" "$tfvars" "$RG_DATA" "$LOCATION"

    if [ "$ACTION" = "apply" ]; then
        update_config_from_terraform 2 "Data" \
            "Data layer: Storage Account, Cosmos DB, SQL Server, Service Bus" \
            "$RG_DATA" "$LOCATION" "$TF_STAGES_DIR/stage2-data"
    fi
}

# ============================================
# Stage 3: Compute
# ============================================
deploy_stage_3() {
    local resource_prefix=$(read_config '.resourcePrefix')
    local unique_suffix=$(read_config '.uniqueSuffix')
    local log_analytics_id=$(read_config '.stages.stage1.resources.logAnalytics.id')
    local log_analytics_customer_id=$(read_config '.stages.stage1.resources.logAnalytics.customerId')
    local log_analytics_key=$(read_config '.stages.stage1.resources.logAnalytics.primarySharedKey')
    local app_insights_conn=$(read_config '.stages.stage1.resources.appInsights.connectionString')
    local container_app_identity_id=$(read_config '.stages.stage1.managedIdentities.containerApp.id')
    local container_app_identity_client=$(read_config '.stages.stage1.managedIdentities.containerApp.clientId')
    local storage_conn=$(read_config '.stages.stage2.resources.storageAccount.connectionString')
    local servicebus_conn=$(read_config '.stages.stage2.resources.serviceBus.connectionString')
    local cosmos_endpoint=$(read_config '.stages.stage2.resources.cosmosDb.endpoint')
    local cosmos_key=$(read_config '.stages.stage2.resources.cosmosDb.key')
    local sql_fqdn=$(read_config '.stages.stage2.resources.sqlServer.fqdn')
    local sql_db=$(read_config '.stages.stage2.resources.sqlServer.databaseName')
    local sql_entra=$(read_config '.stages.stage2.resources.sqlServer.entraOnlyAuthentication')

    if [ -z "$resource_prefix" ] && [ "$ACTION" = "apply" ]; then
        echo -e "${RED}Error: Previous stage outputs not found. Please deploy stages 1 and 2 first.${NC}"
        exit 1
    fi

    local tfvars="
environment                         = \"$ENVIRONMENT\"
location                            = \"$LOCATION\"
base_name                           = \"pptgen\"
resource_group_name                 = \"$RG_COMPUTE\"
resource_prefix                     = \"$resource_prefix\"
unique_suffix                       = \"$unique_suffix\"
log_analytics_workspace_id          = \"$log_analytics_id\"
log_analytics_workspace_customer_id = \"${log_analytics_customer_id:-}\"
log_analytics_primary_shared_key    = \"${log_analytics_key:-}\"
app_insights_connection_string      = \"$app_insights_conn\"
container_app_identity_id           = \"$container_app_identity_id\"
container_app_identity_client_id    = \"$container_app_identity_client\"
storage_connection_string           = \"$storage_conn\"
servicebus_connection_string        = \"$servicebus_conn\"
cosmos_endpoint                     = \"$cosmos_endpoint\"
cosmos_key                          = \"$cosmos_key\"
sql_server_fqdn                     = \"$sql_fqdn\"
sql_database_name                   = \"$sql_db\"
sql_entra_only_auth                 = ${sql_entra:-true}
"
    deploy_stage 3 "$TF_STAGES_DIR/stage3-compute" "$tfvars" "$RG_COMPUTE" "$LOCATION"

    if [ "$ACTION" = "apply" ]; then
        update_config_from_terraform 3 "Compute" \
            "Compute layer: Container Registry, Container Apps Environment, Orchestrator" \
            "$RG_COMPUTE" "$LOCATION" "$TF_STAGES_DIR/stage3-compute"
    fi
}

# ============================================
# Stage 4: Functions
# ============================================
deploy_stage_4() {
    local resource_prefix=$(read_config '.resourcePrefix')
    local unique_suffix=$(read_config '.uniqueSuffix')
    local app_insights_conn=$(read_config '.stages.stage1.resources.appInsights.connectionString')
    local servicebus_conn=$(read_config '.stages.stage2.resources.serviceBus.connectionString')
    local cosmos_endpoint=$(read_config '.stages.stage2.resources.cosmosDb.endpoint')
    local cosmos_key=$(read_config '.stages.stage2.resources.cosmosDb.key')
    local orchestrator_url=$(read_config '.stages.stage3.resources.containerApp.url')
    local openai_endpoint=$(read_config '.stages.stage5.resources.openAi.endpoint')
    local openai_key=$(read_config '.stages.stage5.resources.openAi.key')

    # Get storage account info
    local storage_account=$(read_config '.stages.stage2.resources.storageAccount.name')
    local storage_account_id=$(read_config '.stages.stage2.resources.storageAccount.id')

    # Fallback: get storage_account_id from Azure if not in config
    if [ -z "$storage_account_id" ] && [ -n "$storage_account" ]; then
        echo -e "${YELLOW}Fetching storage account ID from Azure...${NC}"
        storage_account_id=$(az storage account show --name "$storage_account" --query id -o tsv 2>/dev/null || echo "")
    fi

    if [ -z "$resource_prefix" ] && [ "$ACTION" = "apply" ]; then
        echo -e "${RED}Error: Previous stage outputs not found. Please deploy stages 1-3 first.${NC}"
        exit 1
    fi

    local tfvars="
environment                    = \"$ENVIRONMENT\"
location                       = \"$FUNC_LOCATION\"
base_name                      = \"pptgen\"
resource_group_name            = \"$RG_FUNC\"
resource_prefix                = \"$resource_prefix\"
unique_suffix                  = \"$unique_suffix\"
app_insights_connection_string = \"$app_insights_conn\"
servicebus_connection_string   = \"$servicebus_conn\"
cosmos_endpoint                = \"$cosmos_endpoint\"
cosmos_key                     = \"$cosmos_key\"
orchestrator_url               = \"$orchestrator_url\"
openai_endpoint                = \"${openai_endpoint:-}\"
openai_key                     = \"${openai_key:-}\"
storage_account_name           = \"$storage_account\"
storage_account_id             = \"$storage_account_id\"
"
    deploy_stage 4 "$TF_STAGES_DIR/stage4-functions" "$tfvars" "$RG_FUNC" "$FUNC_LOCATION"

    if [ "$ACTION" = "apply" ]; then
        update_config_from_terraform 4 "Functions" \
            "Azure Functions API layer" \
            "$RG_FUNC" "$FUNC_LOCATION" "$TF_STAGES_DIR/stage4-functions"
    fi
}

# ============================================
# Stage 5: AI
# ============================================
deploy_stage_5() {
    local resource_prefix=$(read_config '.resourcePrefix')

    if [ -z "$resource_prefix" ] && [ "$ACTION" = "apply" ]; then
        echo -e "${RED}Error: Stage 1 outputs not found. Please deploy stage 1 first.${NC}"
        exit 1
    fi

    local tfvars="
environment         = \"$ENVIRONMENT\"
location            = \"$OPENAI_LOCATION\"
base_name           = \"pptgen\"
resource_group_name = \"$RG_AI\"
resource_prefix     = \"$resource_prefix\"
"
    deploy_stage 5 "$TF_STAGES_DIR/stage5-ai" "$tfvars" "$RG_AI" "$OPENAI_LOCATION"

    if [ "$ACTION" = "apply" ]; then
        update_config_from_terraform 5 "AI" \
            "Azure OpenAI Service with GPT and embedding deployments" \
            "$RG_AI" "$OPENAI_LOCATION" "$TF_STAGES_DIR/stage5-ai"
    fi
}

# ============================================
# Stage 6: Web (Optional)
# ============================================
deploy_stage_6() {
    local resource_prefix=$(read_config '.resourcePrefix')
    local app_insights_conn=$(read_config '.stages.stage1.resources.appInsights.connectionString')
    local orchestrator_url=$(read_config '.stages.stage3.resources.containerApp.url')
    local function_url=$(read_config '.stages.stage4.resources.functionApp.url')

    if [ -z "$resource_prefix" ] && [ "$ACTION" = "apply" ]; then
        echo -e "${RED}Error: Stage 1 outputs not found. Please deploy stage 1 first.${NC}"
        exit 1
    fi

    # Check if stage6-web directory exists
    if [ ! -d "$TF_STAGES_DIR/stage6-web" ]; then
        echo -e "${YELLOW}Warning: stage6-web Terraform module not found.${NC}"
        echo -e "${YELLOW}Creating resource group only...${NC}"

        if [ "$ACTION" = "apply" ]; then
            az group create --name "$RG_WEB" --location "$FUNC_LOCATION" --output none
            echo -e "${GREEN}Resource group $RG_WEB created.${NC}"
            echo -e "${YELLOW}Deploy web app manually or create stage6-web Terraform module.${NC}"

            # Create minimal config entry
            local current_date=$(date -u +%Y-%m-%d)
            local stage_json=$(cat << EOF
{
  "name": "Web",
  "description": "Web test portal for testing the application (optional - not required for production)",
  "optional": true,
  "resourceGroups": {
    "web": {
      "name": "$RG_WEB",
      "location": "$FUNC_LOCATION",
      "tags": {
        "Environment": "$ENVIRONMENT",
        "Stage": "6",
        "Purpose": "Web"
      }
    }
  },
  "managedIdentities": {},
  "resources": {
    "webApp": {
      "name": "",
      "url": "",
      "resourceGroup": "$RG_WEB"
    },
    "appServicePlan": {
      "name": "",
      "resourceGroup": "$RG_WEB"
    }
  }
}
EOF
)
            local temp_file=$(mktemp)
            jq --argjson stage_data "$stage_json" \
               --arg date "$current_date" \
               ".stages.stage6 = \$stage_data | .project.lastModified = \$date" \
               "$CONFIG_FILE" > "$temp_file"
            mv "$temp_file" "$CONFIG_FILE"
        fi
        return
    fi

    local tfvars="
environment                    = \"$ENVIRONMENT\"
location                       = \"$FUNC_LOCATION\"
base_name                      = \"pptgen\"
resource_group_name            = \"$RG_WEB\"
resource_prefix                = \"$resource_prefix\"
app_insights_connection_string = \"${app_insights_conn:-}\"
orchestrator_url               = \"${orchestrator_url:-}\"
function_app_url               = \"${function_url:-}\"
"
    deploy_stage 6 "$TF_STAGES_DIR/stage6-web" "$tfvars" "$RG_WEB" "$FUNC_LOCATION"

    if [ "$ACTION" = "apply" ]; then
        update_config_from_terraform 6 "Web" \
            "Web test portal for testing the application (optional - not required for production)" \
            "$RG_WEB" "$FUNC_LOCATION" "$TF_STAGES_DIR/stage6-web" "true"
    fi
}

# ============================================
# Main Execution
# ============================================
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}PPT Generator - Terraform Staged Deployment${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Environment:       $ENVIRONMENT"
echo "Primary Location:  $LOCATION"
echo "Functions Location: $FUNC_LOCATION"
echo "OpenAI Location:   $OPENAI_LOCATION"
echo "Action:            $ACTION"
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
        if [ "$ACTION" = "destroy" ]; then
            # Destroy in reverse order (excluding optional stage 6)
            deploy_stage_4
            deploy_stage_3
            deploy_stage_5
            deploy_stage_2
            deploy_stage_1
        else
            # Deploy stages 1-5 in correct order (5 before 3 because 3 may need OpenAI)
            deploy_stage_1
            deploy_stage_2
            deploy_stage_5  # Deploy AI before Compute
            deploy_stage_3
            deploy_stage_4
            # Note: Stage 6 (Web) is optional and not included in 'all'
            echo -e "${YELLOW}Note: Stage 6 (Web) is optional and was not deployed.${NC}"
            echo -e "${YELLOW}To deploy the web portal, run: $0 -g $RESOURCE_GROUP -e $ENVIRONMENT -s 6${NC}"
        fi
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
if [ "$ACTION" = "apply" ]; then
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "1. Deploy SQL schema: cd ../sql && sqlcmd -S <server>.database.windows.net -d telemetry -i 001_create_tables.sql"
    echo "2. Upload templates to blob storage"
    echo "3. Build and push container image to ACR"
    echo "4. Deploy Azure Functions code"
    echo ""
fi
