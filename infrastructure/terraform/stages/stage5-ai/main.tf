# ============================================
# Stage 5: Azure OpenAI
# OpenAI Account and Model Deployments
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
    cognitive_account {
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
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus2"
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

variable "gpt_deployment_name" {
  description = "Azure OpenAI GPT model deployment name"
  type        = string
  default     = "gpt-4o"
}

variable "gpt_model_name" {
  description = "Azure OpenAI GPT model name"
  type        = string
  default     = "gpt-4o"
}

variable "gpt_model_version" {
  description = "Azure OpenAI GPT model version"
  type        = string
  default     = "2024-08-06"
}

variable "embedding_deployment_name" {
  description = "Azure OpenAI embedding model deployment name"
  type        = string
  default     = "text-embedding-3-small"
}

variable "embedding_model_name" {
  description = "Azure OpenAI embedding model name"
  type        = string
  default     = "text-embedding-3-small"
}

# ============================================
# Random suffix for unique naming
# ============================================

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ============================================
# Locals
# ============================================

locals {
  tags = {
    Environment = var.environment
    Application = "PPT-Generator"
    ManagedBy   = "Terraform"
    Stage       = "5-AI"
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
# Azure OpenAI Account
# ============================================

resource "azurerm_cognitive_account" "openai" {
  name                  = "${var.resource_prefix}-openai-${random_string.suffix.result}"
  location              = azurerm_resource_group.main.location
  resource_group_name   = azurerm_resource_group.main.name
  kind                  = "OpenAI"
  sku_name              = "S0"
  custom_subdomain_name = "${var.resource_prefix}-openai-${random_string.suffix.result}"

  tags = local.tags
}

# ============================================
# GPT Model Deployment
# ============================================

resource "azurerm_cognitive_deployment" "gpt" {
  name                 = var.gpt_deployment_name
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = var.gpt_model_name
    version = var.gpt_model_version
  }

  scale {
    type     = "Standard"
    capacity = 30
  }
}

# ============================================
# Embedding Model Deployment
# ============================================

resource "azurerm_cognitive_deployment" "embedding" {
  name                 = var.embedding_deployment_name
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = var.embedding_model_name
    version = "1"
  }

  scale {
    type     = "Standard"
    capacity = 30
  }

  depends_on = [azurerm_cognitive_deployment.gpt]
}
