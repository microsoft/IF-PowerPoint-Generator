// ============================================
// Azure Functions Module
// Deploys Azure Functions to a separate resource group
// ============================================

@description('Resource prefix for naming')
param resourcePrefix string

@description('Azure region for resources')
param location string

@description('Tags to apply to resources')
param tags object

@description('Service Bus connection string')
@secure()
param serviceBusConnectionString string

@description('Cosmos DB endpoint')
param cosmosEndpoint string

@description('Cosmos DB key')
@secure()
param cosmosKey string

@description('Azure OpenAI endpoint')
param openAiEndpoint string

@description('Azure OpenAI API key')
@secure()
param openAiKey string

@description('Azure OpenAI GPT deployment name')
param openAiGptDeploymentName string

@description('Azure OpenAI embedding deployment name')
param openAiEmbeddingDeploymentName string

@description('Application Insights connection string')
@secure()
param appInsightsConnectionString string

@description('Container App URL for orchestrator')
param orchestratorUrl string

@description('Storage Account Name from stage 2 (for blob triggers)')
param storageAccountName string = ''

@description('Storage Account Resource ID from stage 2 (for role assignments)')
param storageAccountId string = ''

// Storage account for Function App
resource functionAppStorageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: '${replace(resourcePrefix, '-', '')}func'
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    // Required for managed identity access when key access is disabled
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    // IMPORTANT: Must be Enabled for Function App to access storage with managed identity
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// App Service Plan for Function App (Linux P1v4)
resource functionAppServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: '${resourcePrefix}-func-plan'
  location: location
  tags: tags
  kind: 'linux'
  sku: {
    name: 'P1v4'
    tier: 'PremiumV4'
  }
  properties: {
    reserved: true // Linux
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: '${resourcePrefix}-func'
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: functionAppServicePlan.id
    httpsOnly: true
    siteConfig: {
      pythonVersion: '3.11'
      linuxFxVersion: 'PYTHON|3.11'
      appSettings: [
        // Identity-based connection for function runtime storage (internal)
        // Must use explicit service URIs + credential for managed identity to work correctly
        {
          name: 'AzureWebJobsStorage__blobServiceUri'
          value: 'https://${functionAppStorageAccount.name}.blob.core.windows.net'
        }
        {
          name: 'AzureWebJobsStorage__queueServiceUri'
          value: 'https://${functionAppStorageAccount.name}.queue.core.windows.net'
        }
        {
          name: 'AzureWebJobsStorage__tableServiceUri'
          value: 'https://${functionAppStorageAccount.name}.table.core.windows.net'
        }
        {
          name: 'AzureWebJobsStorage__credential'
          value: 'managedidentity'
        }
        // Use file-based secrets storage (avoids blob storage dependency for secrets)
        {
          name: 'AzureWebJobsSecretStorageType'
          value: 'files'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          name: 'SERVICEBUS_CONNECTION_STRING'
          value: serviceBusConnectionString
        }
        {
          name: 'COSMOS_ENDPOINT'
          value: cosmosEndpoint
        }
        {
          name: 'COSMOS_KEY'
          value: cosmosKey
        }
        {
          name: 'COSMOS_DATABASE'
          value: 'ppt-generator'
        }
        // Blob storage settings for templates/outputs (Stage 2)
        {
          name: 'STORAGE_ACCOUNT_NAME'
          value: storageAccountName
        }
        {
          name: 'TEMPLATES_CONTAINER'
          value: 'ppt-templates'
        }
        {
          name: 'OUTPUT_CONTAINER'
          value: 'ppt-outputs'
        }
        // Identity-based connection for BlobStorage (Stage 2 storage)
        {
          name: 'BlobStorage__blobServiceUri'
          value: 'https://${storageAccountName}.blob.core.windows.net'
        }
        {
          name: 'BlobStorage__queueServiceUri'
          value: 'https://${storageAccountName}.queue.core.windows.net'
        }
        {
          name: 'BlobStorage__credential'
          value: 'managedidentity'
        }
        {
          name: 'AZURE_OPENAI_ENDPOINT'
          value: openAiEndpoint
        }
        {
          name: 'AZURE_OPENAI_API_KEY'
          value: openAiKey
        }
        {
          name: 'AZURE_OPENAI_GPT_DEPLOYMENT'
          value: openAiGptDeploymentName
        }
        {
          name: 'AZURE_OPENAI_EMBEDDING_DEPLOYMENT'
          value: openAiEmbeddingDeploymentName
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        {
          name: 'ORCHESTRATOR_URL'
          value: orchestratorUrl
        }
      ]
    }
  }
}

// ============================================
// Role Assignments for Function App's Internal Storage
// (Required for managed identity access to function runtime storage)
// ============================================

// Storage Blob Data Owner - full blob access for function runtime
resource funcInternalStorageBlobOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionAppStorageAccount.id, functionApp.id, 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
  scope: functionAppStorageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Storage Queue Data Contributor - Azure Functions uses queues internally
resource funcInternalStorageQueueContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionAppStorageAccount.id, functionApp.id, '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
  scope: functionAppStorageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Storage Table Data Contributor - Azure Functions may use tables for state
resource funcInternalStorageTableContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionAppStorageAccount.id, functionApp.id, '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
  scope: functionAppStorageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Storage Account Contributor - needed for some function runtime operations
resource funcInternalStorageAccountContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionAppStorageAccount.id, functionApp.id, '17d1049b-9a84-46fb-8f53-869881c3d3ab')
  scope: functionAppStorageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '17d1049b-9a84-46fb-8f53-869881c3d3ab')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Note: Role assignments for templates/outputs storage access should be handled
// by the caller (e.g., main.bicep) using the storageRoleAssignments module, as
// that storage account may be in a different resource group.

// Outputs
output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output functionAppPlanName string = functionAppServicePlan.name
output functionAppPrincipalId string = functionApp.identity.principalId
