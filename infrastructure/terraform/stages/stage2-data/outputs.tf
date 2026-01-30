# ============================================
# Stage 2: Data - Outputs
# ============================================

output "resource_group_name" {
  description = "The name of the resource group"
  value       = azurerm_resource_group.main.name
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

output "servicebus_id" {
  description = "The resource ID of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.id
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

output "cosmos_key" {
  description = "The primary key for Cosmos DB"
  value       = azurerm_cosmosdb_account.main.primary_key
  sensitive   = true
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

output "storage_account_id" {
  description = "The resource ID of the storage account"
  value       = azurerm_storage_account.main.id
}
