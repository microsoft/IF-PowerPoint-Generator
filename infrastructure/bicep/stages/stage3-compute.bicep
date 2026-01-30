// ============================================
// Stage 3: Compute
// Container Registry, Container Apps Environment, Container App
// ============================================

targetScope = 'resourceGroup'

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Azure region for resources')
param location string = resourceGroup().location

@description('Base name for resources')
param baseName string = 'pptgen'

@description('Resource prefix from stage 1')
param resourcePrefix string

@description('Unique suffix from stage 1')
param uniqueSuffix string

@description('Log Analytics Workspace ID from stage 1')
param logAnalyticsWorkspaceId string

@description('App Insights Connection String from stage 1')
param appInsightsConnectionString string

@description('Container App Identity ID from stage 1')
param containerAppIdentityId string

@description('Container App Identity Client ID from stage 1')
param containerAppIdentityClientId string

@description('Container App Identity Principal ID (Object ID) from stage 1')
param containerAppIdentityPrincipalId string

@description('Storage Account Name from stage 2 (for managed identity)')
param storageAccountName string

@description('Service Bus Namespace FQDN from stage 2 (for managed identity)')
param serviceBusNamespace string

@description('Cosmos Endpoint from stage 2')
param cosmosEndpoint string

@description('Cosmos Account Name from stage 2 (for role assignments)')
param cosmosAccountName string

@description('Azure OpenAI Endpoint from stage 5')
param openAiEndpoint string

@description('Azure OpenAI Account Name from stage 5 (for role assignments)')
param openAiAccountName string

@description('Azure OpenAI GPT deployment name')
param openAiGptDeployment string = 'gpt-4o'

@description('Azure OpenAI Mini deployment name')
param openAiMiniDeployment string = 'gpt-4o-mini'

@description('Azure OpenAI resource group')
param openAiResourceGroup string

@description('Data resource group (where storage, cosmos, service bus are)')
param dataResourceGroup string

@description('Container image for the orchestrator')
param containerImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

// Tags
var tags = {
  Environment: environment
  Application: 'PPT-Generator'
  ManagedBy: 'Bicep'
  Stage: '3-Compute'
}

// ============================================
// Container Registry
// ============================================
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: '${baseName}${environment}${uniqueSuffix}acr'
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
  }
}

// ============================================
// Container Apps Environment
// ============================================
resource containerAppsEnv 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: '${resourcePrefix}-cae'
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: reference(logAnalyticsWorkspaceId, '2022-10-01').customerId
        sharedKey: listKeys(logAnalyticsWorkspaceId, '2022-10-01').primarySharedKey
      }
    }
  }
}

// ============================================
// Container App (Orchestrator)
// ============================================
resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: '${resourcePrefix}-orchestrator'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${containerAppIdentityId}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8080
        transport: 'http'
        allowInsecure: false
      }
      registries: [
        {
          server: containerRegistry.properties.loginServer
          username: containerRegistry.listCredentials().username
          passwordSecretRef: 'acr-password'
        }
      ]
      secrets: [
        {
          name: 'acr-password'
          value: containerRegistry.listCredentials().passwords[0].value
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'orchestrator'
          image: containerImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            // Service Bus (managed identity)
            { name: 'SERVICEBUS_NAMESPACE', value: serviceBusNamespace }
            { name: 'SERVICEBUS_QUEUE_NAME', value: 'ppt-generation-jobs' }
            // Cosmos DB (managed identity)
            { name: 'COSMOS_ENDPOINT', value: cosmosEndpoint }
            { name: 'COSMOS_DATABASE', value: 'ppt-generator' }
            // Blob Storage (managed identity)
            { name: 'STORAGE_ACCOUNT_NAME', value: storageAccountName }
            { name: 'TEMPLATES_CONTAINER', value: 'ppt-templates' }
            { name: 'OUTPUT_CONTAINER', value: 'ppt-outputs' }
            // Azure OpenAI (managed identity)
            { name: 'AZURE_OPENAI_ENDPOINT', value: openAiEndpoint }
            { name: 'AZURE_OPENAI_GPT_DEPLOYMENT', value: openAiGptDeployment }
            { name: 'AZURE_OPENAI_MINI_DEPLOYMENT', value: openAiMiniDeployment }
            // Managed identity client ID for DefaultAzureCredential
            { name: 'AZURE_CLIENT_ID', value: containerAppIdentityClientId }
            // Application Insights
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 10
      }
    }
  }
}

// ============================================
// Role Assignments for Container App Managed Identity
// ============================================
module containerAppRoleAssignments 'containerAppRoleAssignments.bicep' = {
  name: 'containerAppRoleAssignments'
  scope: resourceGroup(dataResourceGroup)
  params: {
    containerAppPrincipalId: containerAppIdentityPrincipalId
    storageAccountName: storageAccountName
    serviceBusNamespaceName: split(serviceBusNamespace, '.')[0]  // Extract namespace name from FQDN
    cosmosAccountName: cosmosAccountName
  }
  dependsOn: [
    containerApp
  ]
}

// OpenAI role assignment - deployed to the AI resource group
module openAiRoleAssignment 'openAiRoleAssignment.bicep' = {
  name: 'openAiRoleAssignment'
  scope: resourceGroup(openAiResourceGroup)
  params: {
    principalId: containerAppIdentityPrincipalId
    openAiAccountName: openAiAccountName
  }
  dependsOn: [
    containerApp
  ]
}

// ============================================
// Outputs
// ============================================
output containerRegistryName string = containerRegistry.name
output containerRegistryLoginServer string = containerRegistry.properties.loginServer
output containerAppsEnvironmentId string = containerAppsEnv.id
output containerAppsEnvironmentName string = containerAppsEnv.name
output containerAppName string = containerApp.name
output containerAppUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output containerAppFqdn string = containerApp.properties.configuration.ingress.fqdn
