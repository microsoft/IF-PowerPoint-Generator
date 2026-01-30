// ============================================
// Stage 4: Azure Functions
// Function App with Python runtime (Linux)
// Deploy to separate resource group to avoid Linux/Windows conflicts
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

@description('Unique suffix')
param uniqueSuffix string

@description('App Insights Connection String from stage 1')
param appInsightsConnectionString string

@description('Service Bus Namespace name from stage 2 (required for managed identity)')
param serviceBusNamespace string

@description('Service Bus Resource ID from stage 2 (for role assignments)')
param serviceBusId string = ''

@description('Cosmos Endpoint from stage 2')
param cosmosEndpoint string

@description('Cosmos Key from stage 2')
@secure()
param cosmosKey string

@description('Cosmos Account Name from stage 2 (for role assignments)')
param cosmosAccountName string = ''

@description('Resource group containing Cosmos DB from stage 2')
param cosmosResourceGroupName string = ''

@description('Orchestrator URL from stage 3')
param orchestratorUrl string

@description('OpenAI Endpoint from stage 5 (optional)')
param openAiEndpoint string = ''

@description('OpenAI API Key from stage 5 (optional)')
@secure()
param openAiKey string = ''

@description('OpenAI GPT Deployment Name')
param openAiGptDeploymentName string = 'gpt-4o'

@description('OpenAI Embedding Deployment Name')
param openAiEmbeddingDeploymentName string = 'text-embedding-3-small'

@description('Storage Account Name from stage 2 (for blob triggers)')
param storageAccountName string = ''

@description('Storage Account Resource ID from stage 2 (for role assignments)')
param storageAccountId string = ''

@description('Resource group containing the storage account from stage 2')
param storageResourceGroupName string = ''

@description('Resource group containing the Service Bus from stage 2')
param serviceBusResourceGroupName string = ''

@description('Skip role assignments if they already exist')
param skipRoleAssignments bool = false

// Tags
var tags = {
  Environment: environment
  Application: 'PPT-Generator'
  ManagedBy: 'Bicep'
  Stage: '4-Functions'
}

// ============================================
// Storage Account for Function App
// ============================================
resource functionAppStorageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: '${baseName}${environment}func${take(uniqueSuffix, 4)}'
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

// ============================================
// App Service Plan (Linux P1v4)
// ============================================
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

// ============================================
// Function App
// ============================================
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
        // Service Bus settings - managed identity only (no keys allowed)
        // SERVICEBUS_CONNECTION_STRING must be empty for managed identity to be used
        {
          name: 'SERVICEBUS_CONNECTION_STRING'
          value: ''
        }
        {
          name: 'SERVICEBUS_NAMESPACE'
          value: '${serviceBusNamespace}.servicebus.windows.net'
        }
        {
          name: 'SERVICEBUS_QUEUE_NAME'
          value: 'ppt-generation-jobs'
        }
        // Identity-based connection for ServiceBus trigger (uses managed identity)
        {
          name: 'ServiceBusConnection__fullyQualifiedNamespace'
          value: '${serviceBusNamespace}.servicebus.windows.net'
        }
        {
          name: 'COSMOS_ENDPOINT'
          value: cosmosEndpoint
        }
        // COSMOS_KEY must be empty for managed identity to be used
        {
          name: 'COSMOS_KEY'
          value: ''
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
resource funcInternalStorageBlobOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!skipRoleAssignments) {
  name: guid(functionAppStorageAccount.id, functionApp.id, 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
  scope: functionAppStorageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Storage Queue Data Contributor - Azure Functions uses queues internally
resource funcInternalStorageQueueContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!skipRoleAssignments) {
  name: guid(functionAppStorageAccount.id, functionApp.id, '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
  scope: functionAppStorageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Storage Table Data Contributor - Azure Functions may use tables for state
resource funcInternalStorageTableContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!skipRoleAssignments) {
  name: guid(functionAppStorageAccount.id, functionApp.id, '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
  scope: functionAppStorageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Storage Account Contributor - needed for some function runtime operations
resource funcInternalStorageAccountContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!skipRoleAssignments) {
  name: guid(functionAppStorageAccount.id, functionApp.id, '17d1049b-9a84-46fb-8f53-869881c3d3ab')
  scope: functionAppStorageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '17d1049b-9a84-46fb-8f53-869881c3d3ab')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================
// Role Assignments for Templates/Outputs Storage (Stage 2)
// (Deployed via separate module to target storage resource group)
// ============================================

// Deploy role assignments to the storage account's resource group
module storageRoleAssignments 'storageRoleAssignments.bicep' = if (!skipRoleAssignments && !empty(storageAccountName) && !empty(storageResourceGroupName)) {
  name: 'funcStorageRoleAssignments'
  scope: resourceGroup(storageResourceGroupName)
  params: {
    storageAccountName: storageAccountName
    functionAppPrincipalId: functionApp.identity.principalId
  }
}

// ============================================
// Role Assignments for Service Bus (Managed Identity)
// (Deployed via separate module to target Service Bus resource group)
// ============================================

// Deploy role assignments to the Service Bus namespace's resource group
module serviceBusRoleAssignments 'serviceBusRoleAssignments.bicep' = if (!skipRoleAssignments && !empty(serviceBusNamespace) && !empty(serviceBusResourceGroupName)) {
  name: 'funcServiceBusRoleAssignments'
  scope: resourceGroup(serviceBusResourceGroupName)
  params: {
    serviceBusNamespaceName: serviceBusNamespace
    functionAppPrincipalId: functionApp.identity.principalId
  }
}

// ============================================
// Role Assignments for Cosmos DB (Managed Identity)
// (Deployed via separate module to target Cosmos DB resource group)
// ============================================

// Deploy role assignments to the Cosmos DB account's resource group
module cosmosRoleAssignments 'cosmosRoleAssignments.bicep' = if (!skipRoleAssignments && !empty(cosmosAccountName) && !empty(cosmosResourceGroupName)) {
  name: 'funcCosmosRoleAssignments'
  scope: resourceGroup(cosmosResourceGroupName)
  params: {
    cosmosAccountName: cosmosAccountName
    functionAppPrincipalId: functionApp.identity.principalId
  }
}

// ============================================
// Outputs
// ============================================
output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output functionAppPlanName string = functionAppServicePlan.name
output functionAppStorageAccountName string = functionAppStorageAccount.name
output functionAppPrincipalId string = functionApp.identity.principalId
