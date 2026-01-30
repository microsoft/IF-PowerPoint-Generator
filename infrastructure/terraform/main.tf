# ============================================
# PPT Generator Service - Terraform Main
# Azure Infrastructure
# ============================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }

  # Uncomment for remote state storage
  # backend "azurerm" {
  #   resource_group_name  = "rg-terraform-state"
  #   storage_account_name = "tfstatepptgen"
  #   container_name       = "tfstate"
  #   key                  = "pptgen.tfstate"
  # }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = true
    }
  }
}

# ============================================
# Local Variables
# ============================================

locals {
  resource_prefix = "${var.base_name}-${var.environment}"

  tags = merge(var.tags, {
    Environment = var.environment
    Application = "PPT-Generator"
    ManagedBy   = "Terraform"
  })
}

# Random suffix for globally unique names
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# ============================================
# Resource Group (reference existing)
# ============================================

data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

# ============================================
# Storage Account
# ============================================

resource "azurerm_storage_account" "main" {
  name                     = "${var.base_name}${var.environment}${random_string.suffix.result}"
  resource_group_name      = data.azurerm_resource_group.main.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }

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
# Service Bus Namespace
# ============================================

resource "azurerm_servicebus_namespace" "main" {
  name                = "${local.resource_prefix}-servicebus"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  sku                 = var.service_bus_sku
  capacity            = var.service_bus_sku == "Premium" ? var.service_bus_capacity : 0
  minimum_tls_version = "1.2"

  tags = local.tags
}

resource "azurerm_servicebus_queue" "jobs" {
  name         = "ppt-generation-jobs"
  namespace_id = azurerm_servicebus_namespace.main.id

  lock_duration                       = "PT5M"
  max_size_in_megabytes               = 5120
  requires_duplicate_detection        = false
  requires_session                    = false
  default_message_ttl                 = "PT1H"
  dead_lettering_on_message_expiration = true
  max_delivery_count                  = 3
  enable_partitioning                 = false
}

# ============================================
# Cosmos DB Account
# ============================================

resource "azurerm_cosmosdb_account" "main" {
  name                = "${local.resource_prefix}-cosmos"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = var.location
    failover_priority = 0
  }

  dynamic "capabilities" {
    for_each = var.cosmos_throughput_mode == "serverless" ? [1] : []
    content {
      name = "EnableServerless"
    }
  }

  tags = local.tags
}

resource "azurerm_cosmosdb_sql_database" "main" {
  name                = "ppt-generator"
  resource_group_name = data.azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name

  dynamic "throughput" {
    for_each = var.cosmos_throughput_mode == "provisioned" ? [1] : []
    content {
      throughput = var.cosmos_provisioned_throughput
    }
  }
}

resource "azurerm_cosmosdb_sql_container" "jobs" {
  name                = "jobs"
  resource_group_name = data.azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.main.name
  partition_key_path  = "/jobId"
  default_ttl         = 604800 # 7 days
}

resource "azurerm_cosmosdb_sql_container" "cache" {
  name                = "cache"
  resource_group_name = data.azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.main.name
  partition_key_path  = "/contentHash"
  default_ttl         = 86400 # 24 hours
}

resource "azurerm_cosmosdb_sql_container" "errors" {
  name                = "errors"
  resource_group_name = data.azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.main.name
  partition_key_path  = "/jobId"
  default_ttl         = 2592000 # 30 days
}

resource "azurerm_cosmosdb_sql_container" "templates" {
  name                = "templates"
  resource_group_name = data.azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.main.name
  partition_key_path  = "/templateId"
}

# ============================================
# Azure SQL Database
# ============================================

# Managed identity for SQL Server (used for Entra-only auth)
resource "azurerm_user_assigned_identity" "sql" {
  name                = "${local.resource_prefix}-sql-identity"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = var.location

  tags = local.tags
}

# SQL Server with conditional authentication mode
resource "azurerm_mssql_server" "main" {
  name                          = "${local.resource_prefix}-sql"
  resource_group_name           = data.azurerm_resource_group.main.name
  location                      = var.location
  version                       = "12.0"
  minimum_tls_version           = "1.2"
  public_network_access_enabled = true

  # SQL admin credentials only used when Entra-only auth is disabled
  administrator_login          = var.sql_entra_only_auth ? null : var.sql_admin_username
  administrator_login_password = var.sql_entra_only_auth ? null : var.sql_admin_password

  # User-assigned managed identity
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.sql.id]
  }

  primary_user_assigned_identity_id = azurerm_user_assigned_identity.sql.id

  # Entra ID (Azure AD) administrator configuration
  azuread_administrator {
    login_username              = azurerm_user_assigned_identity.sql.name
    object_id                   = azurerm_user_assigned_identity.sql.principal_id
    tenant_id                   = data.azurerm_client_config.current.tenant_id
    azuread_authentication_only = var.sql_entra_only_auth
  }

  tags = local.tags
}

resource "azurerm_mssql_database" "telemetry" {
  name           = "ppt-telemetry"
  server_id      = azurerm_mssql_server.main.id
  collation      = "SQL_Latin1_General_CP1_CI_AS"
  max_size_gb    = 2
  sku_name       = var.sql_sku

  tags = local.tags
}

resource "azurerm_mssql_firewall_rule" "allow_azure" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# ============================================
# Azure OpenAI
# ============================================

# Create new Azure OpenAI resource if no existing one provided
resource "azurerm_cognitive_account" "openai" {
  count                 = var.openai_resource_name == "" ? 1 : 0
  name                  = "${local.resource_prefix}-openai"
  location              = var.location
  resource_group_name   = data.azurerm_resource_group.main.name
  kind                  = "OpenAI"
  sku_name              = "S0"
  custom_subdomain_name = "${local.resource_prefix}-openai"

  tags = local.tags
}

# Reference existing Azure OpenAI resource if provided
data "azurerm_cognitive_account" "existing_openai" {
  count               = var.openai_resource_name != "" ? 1 : 0
  name                = var.openai_resource_name
  resource_group_name = data.azurerm_resource_group.main.name
}

# GPT model deployment
resource "azurerm_cognitive_deployment" "gpt" {
  count                = var.openai_resource_name == "" ? 1 : 0
  name                 = var.openai_gpt_deployment_name
  cognitive_account_id = azurerm_cognitive_account.openai[0].id

  model {
    format  = "OpenAI"
    name    = var.openai_gpt_model_name
    version = var.openai_gpt_model_version
  }

  sku {
    name     = "Standard"
    capacity = 30
  }
}

# Embedding model deployment
resource "azurerm_cognitive_deployment" "embedding" {
  count                = var.openai_resource_name == "" ? 1 : 0
  name                 = var.openai_embedding_deployment_name
  cognitive_account_id = azurerm_cognitive_account.openai[0].id

  model {
    format  = "OpenAI"
    name    = var.openai_embedding_model_name
    version = "1"
  }

  sku {
    name     = "Standard"
    capacity = 30
  }

  depends_on = [azurerm_cognitive_deployment.gpt]
}

# Local values for OpenAI configuration (works with both new and existing)
locals {
  openai_endpoint = var.openai_resource_name == "" ? azurerm_cognitive_account.openai[0].endpoint : data.azurerm_cognitive_account.existing_openai[0].endpoint
  openai_key      = var.openai_resource_name == "" ? azurerm_cognitive_account.openai[0].primary_access_key : data.azurerm_cognitive_account.existing_openai[0].primary_access_key
}

# ============================================
# Log Analytics & Application Insights
# ============================================

resource "azurerm_log_analytics_workspace" "main" {
  name                = "${local.resource_prefix}-logs"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days

  tags = local.tags
}

resource "azurerm_application_insights" "main" {
  name                = "${local.resource_prefix}-appinsights"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"

  tags = local.tags
}

# ============================================
# Container Apps Environment
# ============================================

resource "azurerm_container_app_environment" "main" {
  name                       = "${local.resource_prefix}-cae"
  location                   = var.location
  resource_group_name        = data.azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  tags = local.tags
}

# ============================================
# Managed Identity for Container App (for SQL Entra auth)
# ============================================

resource "azurerm_user_assigned_identity" "container_app" {
  name                = "${local.resource_prefix}-containerapp-identity"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = var.location

  tags = local.tags
}

# ============================================
# Container App (Orchestrator)
# ============================================

# SQL connection string varies based on authentication mode
locals {
  sql_connection_entra = "Driver={ODBC Driver 18 for SQL Server};Server=${azurerm_mssql_server.main.fully_qualified_domain_name};Database=${azurerm_mssql_database.telemetry.name};Authentication=ActiveDirectoryMsi;Encrypt=yes;TrustServerCertificate=no;"
  sql_connection_sql   = "Driver={ODBC Driver 18 for SQL Server};Server=${azurerm_mssql_server.main.fully_qualified_domain_name};Database=${azurerm_mssql_database.telemetry.name};Uid=${var.sql_admin_username};Pwd=${var.sql_admin_password};Encrypt=yes;TrustServerCertificate=no;"
}

resource "azurerm_container_app" "orchestrator" {
  name                         = "${local.resource_prefix}-orchestrator"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = data.azurerm_resource_group.main.name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.container_app.id]
  }

  template {
    container {
      name   = "orchestrator"
      image  = var.container_image
      cpu    = 1.0
      memory = "2Gi"

      env {
        name        = "SERVICEBUS_CONNECTION_STRING"
        secret_name = "servicebus-connection"
      }
      env {
        name  = "SERVICEBUS_QUEUE_NAME"
        value = "ppt-generation-jobs"
      }
      env {
        name  = "COSMOS_ENDPOINT"
        value = azurerm_cosmosdb_account.main.endpoint
      }
      env {
        name        = "COSMOS_KEY"
        secret_name = "cosmos-key"
      }
      env {
        name  = "COSMOS_DATABASE"
        value = "ppt-generator"
      }
      env {
        name        = "BLOB_CONNECTION_STRING"
        secret_name = "storage-connection"
      }
      env {
        name        = "SQL_CONNECTION_STRING"
        secret_name = "sql-connection"
      }
      env {
        name  = "SQL_USE_MANAGED_IDENTITY"
        value = tostring(var.sql_entra_only_auth)
      }
      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.container_app.client_id
      }
      env {
        name  = "AZURE_OPENAI_ENDPOINT"
        value = local.openai_endpoint
      }
      env {
        name        = "AZURE_OPENAI_API_KEY"
        secret_name = "openai-key"
      }
      env {
        name  = "AZURE_OPENAI_GPT_DEPLOYMENT"
        value = var.openai_gpt_deployment_name
      }
      env {
        name  = "AZURE_OPENAI_EMBEDDING_DEPLOYMENT"
        value = var.openai_embedding_deployment_name
      }
      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = azurerm_application_insights.main.connection_string
      }
      env {
        name  = "CACHE_ENABLED"
        value = "true"
      }
      env {
        name  = "CACHE_TTL_SECONDS"
        value = "86400"
      }
    }

    min_replicas = var.container_app_min_replicas
    max_replicas = var.container_app_max_replicas

    custom_scale_rule {
      name             = "queue-scaling"
      custom_rule_type = "azure-servicebus"
      metadata = {
        queueName    = "ppt-generation-jobs"
        messageCount = "25"
      }
      authentication {
        secret_name       = "servicebus-connection"
        trigger_parameter = "connection"
      }
    }
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

  secret {
    name  = "servicebus-connection"
    value = azurerm_servicebus_namespace.main.default_primary_connection_string
  }

  secret {
    name  = "cosmos-key"
    value = azurerm_cosmosdb_account.main.primary_key
  }

  secret {
    name  = "storage-connection"
    value = azurerm_storage_account.main.primary_connection_string
  }

  secret {
    name  = "sql-connection"
    value = var.sql_entra_only_auth ? local.sql_connection_entra : local.sql_connection_sql
  }

  secret {
    name  = "openai-key"
    value = local.openai_key
  }

  tags = local.tags
}

# ============================================
# Key Vault (for secure credential storage)
# ============================================

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "main" {
  name                       = "kv${var.base_name}${var.environment}${substr(random_string.suffix.result, 0, 6)}"
  location                   = var.location
  resource_group_name        = data.azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  enable_rbac_authorization  = true

  tags = local.tags
}

# Key Vault Secrets Officer role for the deploying user
# This MUST be created before any secrets are added to the vault
resource "azurerm_role_assignment" "keyvault_secrets_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Add a time delay to allow RBAC propagation
resource "time_sleep" "wait_for_rbac" {
  depends_on = [azurerm_role_assignment.keyvault_secrets_officer]

  create_duration = "30s"
}

# Only create SQL password secret when NOT using Entra-only auth
resource "azurerm_key_vault_secret" "sql_password" {
  count        = var.sql_entra_only_auth ? 0 : 1
  name         = "sql-admin-password"
  value        = var.sql_admin_password
  key_vault_id = azurerm_key_vault.main.id

  # Ensure role assignment is complete before creating secret
  depends_on = [time_sleep.wait_for_rbac]
}

# ============================================
# Container Registry
# ============================================

resource "azurerm_container_registry" "main" {
  name                = "acr${var.base_name}${var.environment}${random_string.suffix.result}"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = var.location
  sku                 = var.environment == "prod" ? "Standard" : "Basic"
  admin_enabled       = true

  tags = local.tags
}

# ============================================
# Azure Functions (API Layer)
# ============================================

resource "azurerm_storage_account" "functions" {
  name                     = "func${var.base_name}${random_string.suffix.result}"
  resource_group_name      = data.azurerm_resource_group.main.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  tags = local.tags
}

resource "azurerm_service_plan" "functions" {
  name                = "${local.resource_prefix}-func-plan"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = var.location
  os_type             = "Linux"
  sku_name            = "P1v4" # Premium v4 plan

  tags = local.tags
}

resource "azurerm_linux_function_app" "main" {
  name                = "${local.resource_prefix}-func"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = var.location

  storage_account_name       = azurerm_storage_account.functions.name
  storage_account_access_key = azurerm_storage_account.functions.primary_access_key
  service_plan_id            = azurerm_service_plan.functions.id

  site_config {
    application_stack {
      python_version = "3.11"
    }
  }

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"              = "python"
    "SERVICEBUS_CONNECTION_STRING"          = azurerm_servicebus_namespace.main.default_primary_connection_string
    "COSMOS_ENDPOINT"                       = azurerm_cosmosdb_account.main.endpoint
    "COSMOS_KEY"                            = azurerm_cosmosdb_account.main.primary_key
    "COSMOS_DATABASE"                       = "ppt-generator"
    "AZURE_OPENAI_ENDPOINT"                 = local.openai_endpoint
    "AZURE_OPENAI_API_KEY"                  = local.openai_key
    "AZURE_OPENAI_GPT_DEPLOYMENT"           = var.openai_gpt_deployment_name
    "AZURE_OPENAI_EMBEDDING_DEPLOYMENT"     = var.openai_embedding_deployment_name
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
    "ORCHESTRATOR_URL"                      = "https://${azurerm_container_app.orchestrator.ingress[0].fqdn}"
  }

  tags = local.tags
}

# ============================================
# API Management (optional - takes 30+ minutes to deploy)
# ============================================

resource "azurerm_api_management" "main" {
  count               = var.deploy_apim ? 1 : 0
  name                = "${local.resource_prefix}-apim"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  publisher_name      = "PPT Generator"
  publisher_email     = var.apim_publisher_email
  sku_name            = var.environment == "prod" ? "Standard_1" : "Developer_1"

  tags = local.tags
}
