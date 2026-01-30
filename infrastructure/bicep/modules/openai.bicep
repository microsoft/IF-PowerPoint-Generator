// ============================================
// Azure OpenAI Module
// Deploys Azure OpenAI resources to a separate resource group
// ============================================

@description('Resource prefix for naming')
param resourcePrefix string

@description('Azure region for resources')
param location string

@description('Tags to apply to resources')
param tags object

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

// Azure OpenAI Account
resource openAiAccount 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' = {
  name: '${resourcePrefix}-openai'
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: '${resourcePrefix}-openai'
    publicNetworkAccess: 'Enabled'
  }
}

// GPT model deployment
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

// Embedding model deployment
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

// Outputs
output accountName string = openAiAccount.name
output endpoint string = openAiAccount.properties.endpoint
output key string = openAiAccount.listKeys().key1
