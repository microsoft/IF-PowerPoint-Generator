// ============================================
// OpenAI Role Assignment Module
// Deploys to the OpenAI resource group
// ============================================

targetScope = 'resourceGroup'

@description('Principal ID to assign the role to')
param principalId string

@description('Azure OpenAI Account name')
param openAiAccountName string

// Cognitive Services OpenAI User role
var cognitiveServicesOpenAiUserRoleId = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'

resource openAiAccount 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' existing = {
  name: openAiAccountName
}

resource openAiRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openAiAccount.id, principalId, cognitiveServicesOpenAiUserRoleId)
  scope: openAiAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesOpenAiUserRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

output roleAssignmentId string = openAiRoleAssignment.id
