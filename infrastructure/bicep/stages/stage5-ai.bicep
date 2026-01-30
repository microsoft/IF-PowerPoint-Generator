// ============================================
// Stage 5: Azure OpenAI
// OpenAI Account and Model Deployments
// Deploy to separate resource group for regional flexibility
// ============================================

targetScope = 'resourceGroup'

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Azure region for resources')
param location string = resourceGroup().location

@description('Base name for resources')
param baseName string = 'pptgen'

@description('Resource prefix')
param resourcePrefix string

@description('Deployment timestamp for unique naming')
param deploymentTimestamp string = utcNow('yyyyMMddHHmm')

// Unique suffix for globally unique names
var uniqueSuffix = uniqueString(resourceGroup().id, deploymentTimestamp)

@description('Azure OpenAI GPT model deployment name')
param gptDeploymentName string = 'gpt-4o'

@description('Azure OpenAI GPT model name')
param gptModelName string = 'gpt-4o'

@description('Azure OpenAI GPT model version')
param gptModelVersion string = '2024-08-06'

@description('Azure OpenAI embedding model deployment name')
param embeddingDeploymentName string = 'text-embedding-3-small'

@description('Azure OpenAI embedding model name')
param embeddingModelName string = 'text-embedding-3-small'

// Tags
var tags = {
  Environment: environment
  Application: 'PPT-Generator'
  ManagedBy: 'Bicep'
  Stage: '5-AI'
}

// ============================================
// Azure OpenAI Account
// ============================================
resource openAiAccount 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' = {
  name: '${resourcePrefix}-openai-${take(uniqueSuffix, 6)}'
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: '${resourcePrefix}-openai-${take(uniqueSuffix, 6)}'
    publicNetworkAccess: 'Enabled'
  }
}

// ============================================
// GPT Model Deployment
// ============================================
resource gptDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-10-01-preview' = {
  parent: openAiAccount
  name: gptDeploymentName
  sku: {
    name: 'Standard'
    capacity: 30
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: gptModelName
      version: gptModelVersion
    }
  }
}

// ============================================
// Embedding Model Deployment
// ============================================
resource embeddingDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-10-01-preview' = {
  parent: openAiAccount
  name: embeddingDeploymentName
  sku: {
    name: 'Standard'
    capacity: 30
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: embeddingModelName
      version: '1'
    }
  }
  dependsOn: [
    gptDeployment
  ]
}

// ============================================
// Outputs
// ============================================
output openAiAccountName string = openAiAccount.name
output openAiEndpoint string = openAiAccount.properties.endpoint
output openAiKey string = openAiAccount.listKeys().key1
output gptDeploymentName string = gptDeployment.name
output embeddingDeploymentName string = embeddingDeployment.name
