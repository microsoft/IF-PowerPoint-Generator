// ============================================
// Container App Role Assignments Module
// Assigns all required roles to the Container App managed identity
// for Service Bus, Storage, Cosmos DB, and Azure OpenAI
// ============================================

targetScope = 'resourceGroup'

@description('Principal ID of the Container App managed identity')
param containerAppPrincipalId string

@description('Storage Account name')
param storageAccountName string

@description('Service Bus Namespace name')
param serviceBusNamespaceName string

@description('Cosmos DB Account name')
param cosmosAccountName string

// ============================================
// Role Definition IDs
// ============================================
// Storage Blob Data Contributor
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
// Storage Blob Delegator (for SAS token generation)
var storageBlobDelegatorRoleId = 'db58b8e5-c6ad-4a2a-8342-4190687cbf4a'
// Azure Service Bus Data Receiver
var serviceBusDataReceiverRoleId = '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0'
// Cosmos DB Built-in Data Contributor
var cosmosDbDataContributorRoleId = '00000000-0000-0000-0000-000000000002'

// ============================================
// Reference Existing Resources
// ============================================
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' existing = {
  name: serviceBusNamespaceName
}

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-11-15' existing = {
  name: cosmosAccountName
}

// ============================================
// Storage Role Assignments
// ============================================

// Storage Blob Data Contributor - read/write blobs
resource storageContainerAppBlobContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, containerAppPrincipalId, storageBlobDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: containerAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Storage Blob Delegator - generate SAS tokens with managed identity
resource storageContainerAppBlobDelegator 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, containerAppPrincipalId, storageBlobDelegatorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDelegatorRoleId)
    principalId: containerAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================
// Service Bus Role Assignment
// ============================================

// Azure Service Bus Data Receiver - receive messages from queue
resource serviceBusContainerAppReceiver 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBusNamespace.id, containerAppPrincipalId, serviceBusDataReceiverRoleId)
  scope: serviceBusNamespace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', serviceBusDataReceiverRoleId)
    principalId: containerAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================
// Cosmos DB Role Assignment
// ============================================

// Cosmos DB Built-in Data Contributor - read/write data
resource cosmosContainerAppDataContributor 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2023-11-15' = {
  name: guid(cosmosAccount.id, containerAppPrincipalId, cosmosDbDataContributorRoleId)
  parent: cosmosAccount
  properties: {
    roleDefinitionId: '${cosmosAccount.id}/sqlRoleDefinitions/${cosmosDbDataContributorRoleId}'
    principalId: containerAppPrincipalId
    scope: cosmosAccount.id
  }
}

// ============================================
// Outputs
// ============================================
output storageBlobContributorAssignmentId string = storageContainerAppBlobContributor.id
output storageBlobDelegatorAssignmentId string = storageContainerAppBlobDelegator.id
output serviceBusReceiverAssignmentId string = serviceBusContainerAppReceiver.id
output cosmosDataContributorAssignmentId string = cosmosContainerAppDataContributor.id
