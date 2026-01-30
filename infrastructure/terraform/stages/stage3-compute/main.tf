# ============================================
# Stage 3: Compute
# Container Registry, Container Apps Environment, Container App
# ============================================

terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
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

variable "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID from stage 1"
  type        = string
}

variable "log_analytics_workspace_customer_id" {
  description = "Log Analytics Workspace customer ID from stage 1"
  type        = string
}

variable "log_analytics_primary_shared_key" {
  description = "Log Analytics primary shared key from stage 1"
  type        = string
  sensitive   = true
}

variable "app_insights_connection_string" {
  description = "App Insights Connection String from stage 1"
  type        = string
  sensitive   = true
}

variable "container_app_identity_id" {
  description = "Container App Identity ID from stage 1"
  type        = string
}

variable "container_app_identity_client_id" {
  description = "Container App Identity Client ID from stage 1"
  type        = string
}

variable "container_app_identity_principal_id" {
  description = "Container App Identity Principal ID (Object ID) from stage 1"
  type        = string
}

variable "storage_account_name" {
  description = "Storage Account Name from stage 2 (for managed identity)"
  type        = string
}

variable "servicebus_namespace" {
  description = "Service Bus Namespace FQDN from stage 2 (for managed identity)"
  type        = string
}

variable "servicebus_namespace_id" {
  description = "Service Bus Namespace Resource ID for role assignments"
  type        = string
}

variable "cosmos_endpoint" {
  description = "Cosmos Endpoint from stage 2"
  type        = string
}

variable "cosmos_account_name" {
  description = "Cosmos Account Name from stage 2 (for role assignments)"
  type        = string
}

variable "cosmos_account_id" {
  description = "Cosmos Account Resource ID for role assignments"
  type        = string
}

variable "storage_account_id" {
  description = "Storage Account Resource ID for role assignments"
  type        = string
}

variable "openai_endpoint" {
  description = "Azure OpenAI Endpoint from stage 5"
  type        = string
}

variable "openai_account_name" {
  description = "Azure OpenAI Account Name from stage 5"
  type        = string
}

variable "openai_account_id" {
  description = "Azure OpenAI Account Resource ID for role assignments"
  type        = string
}

variable "openai_gpt_deployment" {
  description = "Azure OpenAI GPT deployment name"
  type        = string
  default     = "gpt-4o"
}

variable "openai_mini_deployment" {
  description = "Azure OpenAI Mini deployment name"
  type        = string
  default     = "gpt-4o-mini"
}

variable "container_image" {
  description = "Container image for the orchestrator"
  type        = string
  default     = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
}

# ============================================
# Locals
# ============================================

locals {
  tags = {
    Environment = var.environment
    Application = "PPT-Generator"
    ManagedBy   = "Terraform"
    Stage       = "3-Compute"
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
# Container Registry
# ============================================

resource "azurerm_container_registry" "main" {
  name                = "${var.base_name}${var.environment}${var.unique_suffix}acr"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = true

  tags = local.tags
}

# ============================================
# Container Apps Environment
# ============================================

resource "azurerm_container_app_environment" "main" {
  name                       = "${var.resource_prefix}-cae"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = var.log_analytics_workspace_id

  tags = local.tags
}

# ============================================
# Container App (Orchestrator)
# ============================================

resource "azurerm_container_app" "orchestrator" {
  name                         = "${var.resource_prefix}-orchestrator"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [var.container_app_identity_id]
  }

  registry {
    server               = azurerm_container_registry.main.login_server
    username             = azurerm_container_registry.main.admin_username
    password_secret_name = "acr-password"
  }

  secret {
    name  = "acr-password"
    value = azurerm_container_registry.main.admin_password
  }

  ingress {
    external_enabled = true
    target_port      = 8080
    transport        = "http"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  template {
    min_replicas = 1
    max_replicas = 10

    container {
      name   = "orchestrator"
      image  = var.container_image
      cpu    = 0.5
      memory = "1Gi"

      # Service Bus (managed identity)
      env {
        name  = "SERVICEBUS_NAMESPACE"
        value = var.servicebus_namespace
      }

      env {
        name  = "SERVICEBUS_QUEUE_NAME"
        value = "ppt-generation-jobs"
      }

      # Cosmos DB (managed identity)
      env {
        name  = "COSMOS_ENDPOINT"
        value = var.cosmos_endpoint
      }

      env {
        name  = "COSMOS_DATABASE"
        value = "ppt-generator"
      }

      # Blob Storage (managed identity)
      env {
        name  = "STORAGE_ACCOUNT_NAME"
        value = var.storage_account_name
      }

      env {
        name  = "TEMPLATES_CONTAINER"
        value = "ppt-templates"
      }

      env {
        name  = "OUTPUT_CONTAINER"
        value = "ppt-outputs"
      }

      # Azure OpenAI (managed identity)
      env {
        name  = "AZURE_OPENAI_ENDPOINT"
        value = var.openai_endpoint
      }

      env {
        name  = "AZURE_OPENAI_GPT_DEPLOYMENT"
        value = var.openai_gpt_deployment
      }

      env {
        name  = "AZURE_OPENAI_MINI_DEPLOYMENT"
        value = var.openai_mini_deployment
      }

      # Managed identity client ID for DefaultAzureCredential
      env {
        name  = "AZURE_CLIENT_ID"
        value = var.container_app_identity_client_id
      }

      # Application Insights
      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = var.app_insights_connection_string
      }
    }
  }

  tags = local.tags
}

# ============================================
# Role Assignments for Container App Managed Identity
# ============================================

# Storage Blob Data Contributor - read/write blobs
resource "azurerm_role_assignment" "storage_blob_contributor" {
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.container_app_identity_principal_id
}

# Storage Blob Delegator - generate SAS tokens with managed identity
resource "azurerm_role_assignment" "storage_blob_delegator" {
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Delegator"
  principal_id         = var.container_app_identity_principal_id
}

# Azure Service Bus Data Receiver - receive messages from queue
resource "azurerm_role_assignment" "servicebus_receiver" {
  scope                = var.servicebus_namespace_id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = var.container_app_identity_principal_id
}

# Cosmos DB Built-in Data Contributor - read/write data
resource "azurerm_cosmosdb_sql_role_assignment" "cosmos_data_contributor" {
  resource_group_name = azurerm_resource_group.main.name
  account_name        = var.cosmos_account_name
  role_definition_id  = "${var.cosmos_account_id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = var.container_app_identity_principal_id
  scope               = var.cosmos_account_id
}

# Cognitive Services OpenAI User - use OpenAI models
resource "azurerm_role_assignment" "openai_user" {
  scope                = var.openai_account_id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = var.container_app_identity_principal_id
}
