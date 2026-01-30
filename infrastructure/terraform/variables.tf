# ============================================
# PPT Generator Service - Terraform Variables
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

variable "sql_entra_only_auth" {
  description = "Enable Microsoft Entra-only authentication for SQL Server (recommended for security)"
  type        = bool
  default     = true
}

variable "sql_admin_username" {
  description = "SQL Server admin username (only used when sql_entra_only_auth is false)"
  type        = string
  default     = "pptadmin"
  sensitive   = true
}

variable "sql_admin_password" {
  description = "SQL Server admin password (only used when sql_entra_only_auth is false)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "openai_resource_name" {
  description = "Existing Azure OpenAI resource name (leave empty to create new)"
  type        = string
  default     = ""
}

variable "openai_gpt_deployment_name" {
  description = "Azure OpenAI GPT model deployment name"
  type        = string
  default     = "gpt-4o"
}

variable "openai_gpt_model_name" {
  description = "Azure OpenAI GPT model name"
  type        = string
  default     = "gpt-4o"
}

variable "openai_gpt_model_version" {
  description = "Azure OpenAI GPT model version"
  type        = string
  default     = "2024-08-06"
}

variable "openai_embedding_deployment_name" {
  description = "Azure OpenAI embedding model deployment name"
  type        = string
  default     = "text-embedding-3-small"
}

variable "openai_embedding_model_name" {
  description = "Azure OpenAI embedding model name"
  type        = string
  default     = "text-embedding-3-small"
}

variable "container_image" {
  description = "Container image for the orchestrator"
  type        = string
  default     = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
}

variable "enable_vnet" {
  description = "Enable VNet integration for production"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ============================================
# Environment-specific configurations
# ============================================

variable "service_bus_sku" {
  description = "Service Bus SKU"
  type        = string
  default     = "Premium"
}

variable "service_bus_capacity" {
  description = "Service Bus capacity units (Premium only)"
  type        = number
  default     = 1
}

variable "cosmos_throughput_mode" {
  description = "Cosmos DB throughput mode (serverless or provisioned)"
  type        = string
  default     = "serverless"

  validation {
    condition     = contains(["serverless", "provisioned"], var.cosmos_throughput_mode)
    error_message = "Throughput mode must be serverless or provisioned."
  }
}

variable "cosmos_provisioned_throughput" {
  description = "Cosmos DB provisioned throughput (RU/s) - only used if throughput_mode is provisioned"
  type        = number
  default     = 4000
}

variable "sql_sku" {
  description = "Azure SQL Database SKU"
  type        = string
  default     = "Basic"
}

variable "container_app_min_replicas" {
  description = "Minimum number of container replicas"
  type        = number
  default     = 1
}

variable "container_app_max_replicas" {
  description = "Maximum number of container replicas"
  type        = number
  default     = 100
}

variable "log_retention_days" {
  description = "Log Analytics retention in days"
  type        = number
  default     = 30
}

# ============================================
# API Management Configuration
# ============================================

variable "deploy_apim" {
  description = "Deploy API Management (takes 30+ minutes)"
  type        = bool
  default     = false
}

variable "apim_publisher_email" {
  description = "API Management publisher email"
  type        = string
  default     = "admin@example.com"
}
