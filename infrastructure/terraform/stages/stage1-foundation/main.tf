# ============================================
# Stage 1: Foundation
# Log Analytics, Application Insights, Key Vault, Managed Identities
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
  features {
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
}

# ============================================
# Variables
# ============================================

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
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

variable "deployer_principal_id" {
  description = "Principal ID of the deploying user (for Key Vault RBAC)"
  type        = string
  default     = ""
}

# ============================================
# Data Sources
# ============================================

data "azurerm_client_config" "current" {}

# ============================================
# Random Suffix
# ============================================

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# ============================================
# Locals
# ============================================

locals {
  resource_prefix = "${var.base_name}-${var.environment}"
  unique_suffix   = random_string.suffix.result

  tags = {
    Environment = var.environment
    Application = "PPT-Generator"
    ManagedBy   = "Terraform"
    Stage       = "1-Foundation"
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
# Log Analytics Workspace
# ============================================

resource "azurerm_log_analytics_workspace" "main" {
  name                = "${local.resource_prefix}-logs"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = local.tags
}

# ============================================
# Application Insights
# ============================================

resource "azurerm_application_insights" "main" {
  name                = "${local.resource_prefix}-insights"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"

  tags = local.tags
}

# ============================================
# Key Vault
# ============================================

resource "azurerm_key_vault" "main" {
  name                       = "kv${var.base_name}${var.environment}${substr(local.unique_suffix, 0, 6)}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  enable_rbac_authorization  = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  tags = local.tags
}

# Key Vault Administrator role for deployer
resource "azurerm_role_assignment" "kv_admin" {
  count                = var.deployer_principal_id != "" ? 1 : 0
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = var.deployer_principal_id
}

# ============================================
# Managed Identities
# ============================================

resource "azurerm_user_assigned_identity" "container_app" {
  name                = "${local.resource_prefix}-container-app-id"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = local.tags
}

resource "azurerm_user_assigned_identity" "sql" {
  name                = "${local.resource_prefix}-sql-id"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = local.tags
}

resource "azurerm_user_assigned_identity" "function_app" {
  name                = "${local.resource_prefix}-func-id"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = local.tags
}
