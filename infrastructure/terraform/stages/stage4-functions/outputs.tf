# ============================================
# Stage 4: Functions - Outputs
# ============================================

output "resource_group_name" {
  description = "The name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "function_app_name" {
  description = "The name of the Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_url" {
  description = "The URL of the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_plan_name" {
  description = "The name of the Function App Service Plan"
  value       = azurerm_service_plan.functions.name
}

output "function_app_storage_account_name" {
  description = "The name of the Function App storage account"
  value       = azurerm_storage_account.functions.name
}

output "function_app_principal_id" {
  description = "The principal ID of the Function App managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}
