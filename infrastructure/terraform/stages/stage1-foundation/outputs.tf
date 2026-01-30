# ============================================
# Stage 1: Foundation - Outputs
# ============================================

output "resource_group_name" {
  description = "The name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "The ID of the resource group"
  value       = azurerm_resource_group.main.id
}

output "location" {
  description = "The Azure region"
  value       = azurerm_resource_group.main.location
}

output "resource_prefix" {
  description = "The resource naming prefix"
  value       = local.resource_prefix
}

output "unique_suffix" {
  description = "The unique suffix for naming"
  value       = local.unique_suffix
}

output "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_name" {
  description = "The name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_customer_id" {
  description = "The customer ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_primary_shared_key" {
  description = "The primary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
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

output "key_vault_id" {
  description = "The ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

output "container_app_identity_id" {
  description = "The ID of the Container App managed identity"
  value       = azurerm_user_assigned_identity.container_app.id
}

output "container_app_identity_client_id" {
  description = "The client ID of the Container App managed identity"
  value       = azurerm_user_assigned_identity.container_app.client_id
}

output "container_app_identity_principal_id" {
  description = "The principal ID of the Container App managed identity"
  value       = azurerm_user_assigned_identity.container_app.principal_id
}

output "container_app_identity_name" {
  description = "The name of the Container App managed identity"
  value       = azurerm_user_assigned_identity.container_app.name
}

output "sql_identity_id" {
  description = "The ID of the SQL managed identity"
  value       = azurerm_user_assigned_identity.sql.id
}

output "sql_identity_client_id" {
  description = "The client ID of the SQL managed identity"
  value       = azurerm_user_assigned_identity.sql.client_id
}

output "sql_identity_principal_id" {
  description = "The principal ID of the SQL managed identity"
  value       = azurerm_user_assigned_identity.sql.principal_id
}

output "sql_identity_name" {
  description = "The name of the SQL managed identity"
  value       = azurerm_user_assigned_identity.sql.name
}

output "function_app_identity_id" {
  description = "The ID of the Function App managed identity"
  value       = azurerm_user_assigned_identity.function_app.id
}

output "function_app_identity_client_id" {
  description = "The client ID of the Function App managed identity"
  value       = azurerm_user_assigned_identity.function_app.client_id
}

output "function_app_identity_principal_id" {
  description = "The principal ID of the Function App managed identity"
  value       = azurerm_user_assigned_identity.function_app.principal_id
}

output "function_app_identity_name" {
  description = "The name of the Function App managed identity"
  value       = azurerm_user_assigned_identity.function_app.name
}
