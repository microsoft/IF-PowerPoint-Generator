# ============================================
# Stage 2: Data Services
# Storage, Cosmos DB, SQL Server, Service Bus
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

variable "sql_identity_id" {
  description = "SQL Managed Identity ID from stage 1"
  type        = string
}

variable "sql_identity_principal_id" {
  description = "SQL Managed Identity Principal ID from stage 1"
  type        = string
}

variable "sql_entra_only_auth" {
  description = "Enable Microsoft Entra-only authentication for SQL Server"
  type        = bool
  default     = true
}

variable "sql_admin_username" {
  description = "SQL Admin username (only used when sql_entra_only_auth is false)"
  type        = string
  default     = "pptadmin"
  sensitive   = true
}

variable "sql_admin_password" {
  description = "SQL Admin password (only used when sql_entra_only_auth is false)"
  type        = string
  default     = ""
  sensitive   = true
}

# ============================================
# Data Sources
# ============================================

data "azurerm_client_config" "current" {}

# ============================================
# Locals
# ============================================

locals {
  tags = {
    Environment = var.environment
    Application = "PPT-Generator"
    ManagedBy   = "Terraform"
    Stage       = "2-Data"
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
# Storage Account
# ============================================

resource "azurerm_storage_account" "main" {
  name                     = "${var.base_name}${var.environment}${var.unique_suffix}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  allow_nested_items_to_be_public = false

  tags = local.tags
}

resource "azurerm_storage_container" "templates" {
  name                  = "ppt-templates"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "outputs" {
  name                  = "ppt-outputs"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "temp" {
  name                  = "ppt-temp"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# ============================================
# Service Bus
# ============================================

resource "azurerm_servicebus_namespace" "main" {
  name                = "${var.resource_prefix}-servicebus"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"

  tags = local.tags
}

resource "azurerm_servicebus_queue" "jobs" {
  name         = "ppt-generation-jobs"
  namespace_id = azurerm_servicebus_namespace.main.id

  max_delivery_count                   = 10
  default_message_ttl                  = "P1D"
  lock_duration                        = "PT5M"
  dead_lettering_on_message_expiration = true
}

# ============================================
# Cosmos DB
# ============================================

resource "azurerm_cosmosdb_account" "main" {
  name                = "${var.resource_prefix}-cosmos"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
    zone_redundant    = false
  }

  capabilities {
    name = "EnableServerless"
  }

  tags = local.tags
}

resource "azurerm_cosmosdb_sql_database" "main" {
  name                = "ppt-generator"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
}

resource "azurerm_cosmosdb_sql_container" "jobs" {
  name                = "jobs"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.main.name
  partition_key_path  = "/partitionKey"
}

resource "azurerm_cosmosdb_sql_container" "templates" {
  name                = "templates"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.main.name
  partition_key_path  = "/partitionKey"
}

# ============================================
# SQL Server
# ============================================

resource "azurerm_mssql_server" "main" {
  name                         = "${var.resource_prefix}-sql"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  version                      = "12.0"
  minimum_tls_version          = "1.2"
  public_network_access_enabled = true

  administrator_login          = var.sql_entra_only_auth ? null : var.sql_admin_username
  administrator_login_password = var.sql_entra_only_auth ? null : var.sql_admin_password

  identity {
    type         = "UserAssigned"
    identity_ids = [var.sql_identity_id]
  }

  primary_user_assigned_identity_id = var.sql_identity_id

  dynamic "azuread_administrator" {
    for_each = var.sql_entra_only_auth ? [1] : []
    content {
      login_username              = "SQL Admin"
      object_id                   = var.sql_identity_principal_id
      tenant_id                   = data.azurerm_client_config.current.tenant_id
      azuread_authentication_only = true
    }
  }

  tags = local.tags
}

resource "azurerm_mssql_firewall_rule" "allow_azure" {
  name             = "AllowAllAzureIps"
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_mssql_database" "telemetry" {
  name           = "telemetry"
  server_id      = azurerm_mssql_server.main.id
  collation      = "SQL_Latin1_General_CP1_CI_AS"
  max_size_gb    = 2
  sku_name       = "Basic"

  tags = local.tags
}
