# ============================================
# Stage 5: AI - Outputs
# ============================================

output "resource_group_name" {
  description = "The name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "openai_account_name" {
  description = "The name of the Azure OpenAI account"
  value       = azurerm_cognitive_account.openai.name
}

output "openai_endpoint" {
  description = "The endpoint for Azure OpenAI"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "openai_key" {
  description = "The primary key for Azure OpenAI"
  value       = azurerm_cognitive_account.openai.primary_access_key
  sensitive   = true
}

output "gpt_deployment_name" {
  description = "The GPT model deployment name"
  value       = azurerm_cognitive_deployment.gpt.name
}

output "embedding_deployment_name" {
  description = "The embedding model deployment name"
  value       = azurerm_cognitive_deployment.embedding.name
}
