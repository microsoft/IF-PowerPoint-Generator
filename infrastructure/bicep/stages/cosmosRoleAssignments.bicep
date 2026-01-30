// ============================================
// Cosmos DB Role Assignments Module
// Assigns Cosmos DB Data Contributor role to the Function App managed identity
// ============================================

targetScope = 'resourceGroup'

@description('Principal ID of the Function App managed identity')
param functionAppPrincipalId string

@description('Cosmos DB Account name')
param cosmosAccountName string

// ============================================
// Role Definition IDs
// ============================================
// Cosmos DB Built-in Data Contributor (read/write data)
var cosmosDbDataContributorRoleId = '00000000-0000-0000-0000-000000000002'

// ============================================
// Reference Existing Resources
// ============================================
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-11-15' existing = {
  name: cosmosAccountName
}

// ============================================
// Cosmos DB Role Assignment
// ============================================

// Cosmos DB Built-in Data Contributor - read/write data
resource cosmosFunctionAppDataContributor 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2023-11-15' = {
  name: guid(cosmosAccount.id, functionAppPrincipalId, cosmosDbDataContributorRoleId)
  parent: cosmosAccount
  properties: {
    roleDefinitionId: '${cosmosAccount.id}/sqlRoleDefinitions/${cosmosDbDataContributorRoleId}'
    principalId: functionAppPrincipalId
    scope: cosmosAccount.id
  }
}

// ============================================
// Outputs
// ============================================
output cosmosDataContributorAssignmentId string = cosmosFunctionAppDataContributor.id
