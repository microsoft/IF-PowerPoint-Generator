// ============================================
// Service Bus Role Assignments Module
// Assigns Service Bus roles to the Function App
// ============================================

@description('Service Bus Namespace name')
param serviceBusNamespaceName string

@description('Function App Principal ID')
param functionAppPrincipalId string

// Reference existing Service Bus namespace
resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' existing = {
  name: serviceBusNamespaceName
}

// Azure Service Bus Data Receiver - required for receiving messages from queues
// Role ID: 4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0
resource serviceBusDataReceiver 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBusNamespace.id, functionAppPrincipalId, '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0')
  scope: serviceBusNamespace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0')
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Azure Service Bus Data Sender - required for sending messages to queues
// Role ID: 69a216fc-b8fb-44d8-bc22-1f3c2cd27a39
resource serviceBusDataSender 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBusNamespace.id, functionAppPrincipalId, '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39')
  scope: serviceBusNamespace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39')
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}
