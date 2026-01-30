# ============================================
# Stage 3: Compute - Outputs
# ============================================

output "resource_group_name" {
  description = "The name of the resource group"
  value       = azurerm_resource_group.main.name
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

output "container_apps_environment_id" {
  description = "The ID of the Container Apps Environment"
  value       = azurerm_container_app_environment.main.id
}

output "container_apps_environment_name" {
  description = "The name of the Container Apps Environment"
  value       = azurerm_container_app_environment.main.name
}

output "container_app_name" {
  description = "The name of the Container App"
  value       = azurerm_container_app.orchestrator.name
}

output "container_app_url" {
  description = "The URL of the Container App"
  value       = "https://${azurerm_container_app.orchestrator.ingress[0].fqdn}"
}

output "container_app_fqdn" {
  description = "The FQDN of the Container App"
  value       = azurerm_container_app.orchestrator.ingress[0].fqdn
}
