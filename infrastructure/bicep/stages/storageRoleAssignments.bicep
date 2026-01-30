// ============================================
// Storage Role Assignments Module
// Assigns blob storage roles to a service principal
// ============================================

targetScope = 'resourceGroup'

@description('Name of the storage account to assign roles on')
param storageAccountName string

@description('Principal ID of the Function App managed identity')
param functionAppPrincipalId string

// Reference existing storage account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

// Storage Blob Data Contributor - allows read/write to blobs
resource funcStorageBlobContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionAppPrincipalId, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Storage Blob Delegator - required for generating user delegation SAS tokens
resource funcStorageBlobDelegator 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionAppPrincipalId, 'db58b8e5-c6ad-4a2a-8342-4190687cbf4a')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'db58b8e5-c6ad-4a2a-8342-4190687cbf4a')
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Storage Queue Data Contributor - required for identity-based queue access
resource funcStorageQueueContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionAppPrincipalId, '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}
