# ============================================
# Stage 4: Azure Functions
# Function App with Python runtime (Linux)
# ============================================

terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# ============================================
# Variables
# ============================================

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus"
}

variable "base_name" {
  description = "Base name for resources"
  type        = string
  default     = "pptgen"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "resource_prefix" {
  description = "Resource prefix from stage 1"
  type        = string
}

variable "unique_suffix" {
  description = "Unique suffix from stage 1"
  type        = string
}

variable "app_insights_connection_string" {
  description = "App Insights Connection String from stage 1"
  type        = string
  sensitive   = true
}

variable "servicebus_connection_string" {
  description = "Service Bus Connection String from stage 2 (not used - managed identity only)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "servicebus_namespace" {
  description = "Service Bus Namespace name from stage 2 (required for managed identity)"
  type        = string
}

variable "servicebus_id" {
  description = "Service Bus Namespace resource ID from stage 2 (for role assignments)"
  type        = string
  default     = ""
}

variable "cosmos_endpoint" {
  description = "Cosmos Endpoint from stage 2"
  type        = string
}

variable "cosmos_key" {
  description = "Cosmos Key from stage 2"
  type        = string
  sensitive   = true
}

variable "cosmos_account_name" {
  description = "Cosmos Account Name from stage 2 (for role assignments)"
  type        = string
  default     = ""
}

variable "cosmos_account_id" {
  description = "Cosmos Account Resource ID from stage 2 (for role assignments)"
  type        = string
  default     = ""
}

variable "orchestrator_url" {
  description = "Orchestrator URL from stage 3"
  type        = string
}

variable "openai_endpoint" {
  description = "OpenAI Endpoint from stage 5 (optional)"
  type        = string
  default     = ""
}

variable "openai_key" {
  description = "OpenAI API Key from stage 5 (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "openai_gpt_deployment_name" {
  description = "OpenAI GPT Deployment Name"
  type        = string
  default     = "gpt-4o"
}

variable "openai_embedding_deployment_name" {
  description = "OpenAI Embedding Deployment Name"
  type        = string
  default     = "text-embedding-3-small"
}

variable "storage_connection_string" {
  description = "Storage Connection String from stage 2 (for blob triggers) - optional if using managed identity"
  type        = string
  sensitive   = true
  default     = ""
}

variable "storage_account_name" {
  description = "Storage Account Name from stage 2"
  type        = string
  default     = ""
}

variable "storage_account_id" {
  description = "Storage Account Resource ID from stage 2 (for role assignments)"
  type        = string
  default     = ""
}

# ============================================
# Random suffix for storage account
# ============================================

resource "random_string" "func_suffix" {
  length  = 4
  special = false
  upper   = false
}

# ============================================
# Locals
# ============================================

locals {
  tags = {
    Environment = var.environment
    Application = "PPT-Generator"
    ManagedBy   = "Terraform"
    Stage       = "4-Functions"
  }
}

# ============================================
# Resource Group
# ============================================

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

# ============================================
# Storage Account for Function App
# ============================================

resource "azurerm_storage_account" "functions" {
  name                     = "${var.base_name}${var.environment}func${random_string.func_suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  # Required for managed identity access when key access is disabled
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  # IMPORTANT: Must be Enabled for Function App to access storage with managed identity
  public_network_access_enabled   = true

  # Allow trusted Azure services (required for Azure Functions with managed identity)
  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }

  tags = local.tags
}

# ============================================
# App Service Plan (Linux P1v4)
# ============================================

resource "azurerm_service_plan" "functions" {
  name                = "${var.resource_prefix}-func-plan"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "P1v4"

  tags = local.tags
}

# ============================================
# Function App
# ============================================

resource "azurerm_linux_function_app" "main" {
  name                = "${var.resource_prefix}-func"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  # Use managed identity for function app's internal storage
  storage_account_name          = azurerm_storage_account.functions.name
  storage_uses_managed_identity = true
  service_plan_id               = azurerm_service_plan.functions.id

  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      python_version = "3.11"
    }
  }

  app_settings = {
    "FUNCTIONS_EXTENSION_VERSION"           = "~4"
    "FUNCTIONS_WORKER_RUNTIME"              = "python"
    # Service Bus settings - managed identity only (no keys allowed)
    "SERVICEBUS_NAMESPACE"                  = "${var.servicebus_namespace}.servicebus.windows.net"
    "SERVICEBUS_QUEUE_NAME"                 = "ppt-generation-jobs"
    # Identity-based connection for ServiceBus trigger (uses managed identity)
    "ServiceBusConnection__fullyQualifiedNamespace" = "${var.servicebus_namespace}.servicebus.windows.net"
    "COSMOS_ENDPOINT"                       = var.cosmos_endpoint
    "COSMOS_KEY"                            = var.cosmos_key
    "COSMOS_DATABASE"                       = "ppt-generator"
    # Blob storage settings - use managed identity for templates/outputs storage (Stage 2)
    "STORAGE_ACCOUNT_NAME"                  = var.storage_account_name
    "TEMPLATES_CONTAINER"                   = "ppt-templates"
    "OUTPUT_CONTAINER"                      = "ppt-outputs"
    # Identity-based connection for BlobStorage (Stage 2 storage for templates/outputs)
    "BlobStorage__blobServiceUri"           = "https://${var.storage_account_name}.blob.core.windows.net"
    "BlobStorage__queueServiceUri"          = "https://${var.storage_account_name}.queue.core.windows.net"
    "BlobStorage__credential"               = "managedidentity"
    # Identity-based connection for AzureWebJobsStorage (function runtime internal storage)
    # Must use explicit service URIs + credential for managed identity to work correctly
    "AzureWebJobsStorage__blobServiceUri"   = "https://${azurerm_storage_account.functions.name}.blob.core.windows.net"
    "AzureWebJobsStorage__queueServiceUri"  = "https://${azurerm_storage_account.functions.name}.queue.core.windows.net"
    "AzureWebJobsStorage__tableServiceUri"  = "https://${azurerm_storage_account.functions.name}.table.core.windows.net"
    "AzureWebJobsStorage__credential"       = "managedidentity"
    # Use file-based secrets storage (avoids blob storage dependency for secrets)
    "AzureWebJobsSecretStorageType"         = "files"
    "AZURE_OPENAI_ENDPOINT"                 = var.openai_endpoint
    "AZURE_OPENAI_API_KEY"                  = var.openai_key
    "AZURE_OPENAI_GPT_DEPLOYMENT"           = var.openai_gpt_deployment_name
    "AZURE_OPENAI_EMBEDDING_DEPLOYMENT"     = var.openai_embedding_deployment_name
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.app_insights_connection_string
    "ORCHESTRATOR_URL"                      = var.orchestrator_url
  }

  tags = local.tags

  # Ensure the function app identity is created before role assignments
  depends_on = [azurerm_storage_account.functions]
}

# ============================================
# Role Assignments for Function App's Internal Storage
# (Required for managed identity access to function runtime storage)
# ============================================

# Storage Blob Data Owner - full blob access for function runtime
resource "azurerm_role_assignment" "func_internal_storage_blob_owner" {
  scope                = azurerm_storage_account.functions.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Storage Queue Data Contributor - Azure Functions uses queues internally
resource "azurerm_role_assignment" "func_internal_storage_queue_contributor" {
  scope                = azurerm_storage_account.functions.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Storage Table Data Contributor - Azure Functions may use tables for state
resource "azurerm_role_assignment" "func_internal_storage_table_contributor" {
  scope                = azurerm_storage_account.functions.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Storage Account Contributor - needed for some function runtime operations
resource "azurerm_role_assignment" "func_internal_storage_account_contributor" {
  scope                = azurerm_storage_account.functions.id
  role_definition_name = "Storage Account Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# ============================================
# Role Assignments for Templates/Outputs Storage (Stage 2)
# ============================================

# Storage Blob Data Contributor - allows read/write to blobs
resource "azurerm_role_assignment" "func_storage_blob_contributor" {
  count                = var.storage_account_id != "" ? 1 : 0
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Storage Blob Delegator - required for generating user delegation SAS tokens
resource "azurerm_role_assignment" "func_storage_blob_delegator" {
  count                = var.storage_account_id != "" ? 1 : 0
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Delegator"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Storage Queue Data Contributor - required for identity-based queue access
resource "azurerm_role_assignment" "func_storage_queue_contributor" {
  count                = var.storage_account_id != "" ? 1 : 0
  scope                = var.storage_account_id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# ============================================
# Role Assignments for Service Bus (Managed Identity)
# ============================================

# Azure Service Bus Data Receiver - required for receiving messages from queues
resource "azurerm_role_assignment" "func_servicebus_receiver" {
  count                = var.servicebus_id != "" ? 1 : 0
  scope                = var.servicebus_id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Azure Service Bus Data Sender - required for sending messages to queues
resource "azurerm_role_assignment" "func_servicebus_sender" {
  count                = var.servicebus_id != "" ? 1 : 0
  scope                = var.servicebus_id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# ============================================
# Role Assignments for Cosmos DB (Managed Identity)
# ============================================

# Cosmos DB Built-in Data Contributor - read/write data
resource "azurerm_cosmosdb_sql_role_assignment" "func_cosmos_contributor" {
  count               = var.cosmos_account_id != "" ? 1 : 0
  resource_group_name = split("/", var.cosmos_account_id)[4]
  account_name        = var.cosmos_account_name
  # Built-in Cosmos DB Data Contributor role
  role_definition_id  = "${var.cosmos_account_id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = azurerm_linux_function_app.main.identity[0].principal_id
  scope               = var.cosmos_account_id
}
