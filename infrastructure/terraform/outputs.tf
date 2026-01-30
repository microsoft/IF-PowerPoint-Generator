# ============================================
# PPT Generator Service - Terraform Outputs
# ============================================

output "resource_group_name" {
  description = "The name of the resource group"
  value       = data.azurerm_resource_group.main.name
}

output "storage_account_name" {
  description = "The name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_connection_string" {
  description = "The connection string for the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "servicebus_namespace" {
  description = "The name of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.name
}

output "servicebus_connection_string" {
  description = "The connection string for Service Bus"
  value       = azurerm_servicebus_namespace.main.default_primary_connection_string
  sensitive   = true
}

output "cosmos_account_name" {
  description = "The name of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.name
}

output "cosmos_endpoint" {
  description = "The endpoint for Cosmos DB"
  value       = azurerm_cosmosdb_account.main.endpoint
}

output "cosmos_primary_key" {
  description = "The primary key for Cosmos DB"
  value       = azurerm_cosmosdb_account.main.primary_key
  sensitive   = true
}

output "openai_account_name" {
  description = "The name of the Azure OpenAI account"
  value       = var.openai_resource_name == "" ? azurerm_cognitive_account.openai[0].name : var.openai_resource_name
}

output "openai_endpoint" {
  description = "The endpoint for Azure OpenAI"
  value       = local.openai_endpoint
}

output "openai_gpt_deployment" {
  description = "The GPT model deployment name"
  value       = var.openai_gpt_deployment_name
}

output "openai_embedding_deployment" {
  description = "The embedding model deployment name"
  value       = var.openai_embedding_deployment_name
}

output "sql_server_name" {
  description = "The name of the SQL Server"
  value       = azurerm_mssql_server.main.name
}

output "sql_server_fqdn" {
  description = "The fully qualified domain name of the SQL Server"
  value       = azurerm_mssql_server.main.fully_qualified_domain_name
}

output "sql_database_name" {
  description = "The name of the SQL database"
  value       = azurerm_mssql_database.telemetry.name
}

output "sql_entra_only_authentication" {
  description = "Whether SQL Server is using Entra-only authentication"
  value       = var.sql_entra_only_auth
}

output "sql_managed_identity_name" {
  description = "The name of the SQL Server managed identity"
  value       = azurerm_user_assigned_identity.sql.name
}

output "sql_managed_identity_client_id" {
  description = "The client ID of the SQL Server managed identity"
  value       = azurerm_user_assigned_identity.sql.client_id
}

output "sql_managed_identity_principal_id" {
  description = "The principal ID of the SQL Server managed identity"
  value       = azurerm_user_assigned_identity.sql.principal_id
}

output "container_app_url" {
  description = "The URL of the Container App"
  value       = "https://${azurerm_container_app.orchestrator.ingress[0].fqdn}"
}

output "container_app_name" {
  description = "The name of the Container App"
  value       = azurerm_container_app.orchestrator.name
}

output "container_app_identity_name" {
  description = "The name of the Container App managed identity"
  value       = azurerm_user_assigned_identity.container_app.name
}

output "container_app_identity_client_id" {
  description = "The client ID of the Container App managed identity"
  value       = azurerm_user_assigned_identity.container_app.client_id
}

output "container_app_identity_principal_id" {
  description = "The principal ID of the Container App managed identity"
  value       = azurerm_user_assigned_identity.container_app.principal_id
}

output "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "app_insights_connection_string" {
  description = "The connection string for Application Insights"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "app_insights_instrumentation_key" {
  description = "The instrumentation key for Application Insights"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "key_vault_name" {
  description = "The name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "The URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "container_registry_name" {
  description = "The name of the Container Registry"
  value       = azurerm_container_registry.main.name
}

output "container_registry_login_server" {
  description = "The login server URL for Container Registry"
  value       = azurerm_container_registry.main.login_server
}

output "container_registry_admin_username" {
  description = "The admin username for Container Registry"
  value       = azurerm_container_registry.main.admin_username
  sensitive   = true
}

output "container_registry_admin_password" {
  description = "The admin password for Container Registry"
  value       = azurerm_container_registry.main.admin_password
  sensitive   = true
}

output "function_app_name" {
  description = "The name of the Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_url" {
  description = "The URL of the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "apim_gateway_url" {
  description = "The gateway URL of API Management (if deployed)"
  value       = var.deploy_apim ? azurerm_api_management.main[0].gateway_url : ""
}

# ============================================
# Environment Configuration Output
# ============================================

output "env_file_content" {
  description = "Environment file content for local development"
  sensitive   = true
  value       = <<-EOT
    # PPT Generator - Environment Configuration
    # Generated by Terraform

    # Azure Service Bus
    SERVICEBUS_CONNECTION_STRING=${azurerm_servicebus_namespace.main.default_primary_connection_string}
    SERVICEBUS_QUEUE_NAME=ppt-generation-jobs

    # Azure Cosmos DB
    COSMOS_ENDPOINT=${azurerm_cosmosdb_account.main.endpoint}
    COSMOS_KEY=${azurerm_cosmosdb_account.main.primary_key}
    COSMOS_DATABASE=ppt-generator

    # Azure Blob Storage
    BLOB_CONNECTION_STRING=${azurerm_storage_account.main.primary_connection_string}
    TEMPLATES_CONTAINER=ppt-templates
    OUTPUT_CONTAINER=ppt-outputs
    TEMP_CONTAINER=ppt-temp

    # Azure SQL
    SQL_CONNECTION_STRING=${var.sql_entra_only_auth ? "Driver={ODBC Driver 18 for SQL Server};Server=${azurerm_mssql_server.main.fully_qualified_domain_name};Database=${azurerm_mssql_database.telemetry.name};Authentication=ActiveDirectoryMsi;Encrypt=yes;TrustServerCertificate=no;" : "Driver={ODBC Driver 18 for SQL Server};Server=${azurerm_mssql_server.main.fully_qualified_domain_name};Database=${azurerm_mssql_database.telemetry.name};Uid=${var.sql_admin_username};Pwd=${var.sql_admin_password};Encrypt=yes;TrustServerCertificate=no;"}
    SQL_USE_MANAGED_IDENTITY=${var.sql_entra_only_auth}
    AZURE_CLIENT_ID=${azurerm_user_assigned_identity.container_app.client_id}

    # Azure OpenAI
    AZURE_OPENAI_ENDPOINT=${local.openai_endpoint}
    AZURE_OPENAI_API_KEY=${local.openai_key}
    AZURE_OPENAI_GPT_DEPLOYMENT=${var.openai_gpt_deployment_name}
    AZURE_OPENAI_EMBEDDING_DEPLOYMENT=${var.openai_embedding_deployment_name}

    # Application Insights
    APPLICATIONINSIGHTS_CONNECTION_STRING=${azurerm_application_insights.main.connection_string}

    # Caching
    CACHE_ENABLED=true
    CACHE_TTL_SECONDS=86400

    # Application Settings
    PORT=8080
    LOG_LEVEL=INFO
  EOT
}
