// ============================================
// PPT Generator Service - Azure Infrastructure
// Main Bicep Template
// ============================================

targetScope = 'resourceGroup'

// Parameters
@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Azure region for resources')
param location string = resourceGroup().location

@description('Base name for resources')
param baseName string = 'pptgen'

@description('Existing Azure OpenAI resource name (leave empty to create new)')
param openAiResourceName string = ''

@description('Resource group name for Azure OpenAI (separate from main resources)')
param openAiResourceGroupName string = ''

@description('Azure region for OpenAI resources (may differ from main location)')
param openAiLocation string = ''

@description('Resource group name for Azure Functions (separate to avoid Linux/Windows conflicts)')
param functionsResourceGroupName string = ''

@description('Azure OpenAI GPT model deployment name')
param openAiGptDeploymentName string = 'gpt-4o'

@description('Azure OpenAI GPT model name')
param openAiGptModelName string = 'gpt-4o'

@description('Azure OpenAI GPT model version')
param openAiGptModelVersion string = '2024-08-06'

@description('Azure OpenAI embedding model deployment name')
param openAiEmbeddingDeploymentName string = 'text-embedding-3-small'

@description('Azure OpenAI embedding model name')
param openAiEmbeddingModelName string = 'text-embedding-3-small'

@description('Enable Microsoft Entra-only authentication for SQL Server (recommended for security)')
param sqlEntraOnlyAuth bool = true

@description('SQL Admin username (only used when sqlEntraOnlyAuth is false)')
@secure()
param sqlAdminUsername string = ''

@description('SQL Admin password (only used when sqlEntraOnlyAuth is false)')
@secure()
param sqlAdminPassword string = ''

@description('Principal ID of the deploying user (for Key Vault RBAC)')
param deployerPrincipalId string = ''

// Variables
var uniqueSuffix = uniqueString(resourceGroup().id)
var resourcePrefix = '${baseName}-${environment}'
var aiResourceGroup = empty(openAiResourceGroupName) ? resourceGroup().name : openAiResourceGroupName
var aiLocation = empty(openAiLocation) ? location : openAiLocation
var funcResourceGroup = empty(functionsResourceGroupName) ? resourceGroup().name : functionsResourceGroupName

// Tags
var tags = {
  Environment: environment
  Application: 'PPT-Generator'
  ManagedBy: 'Bicep'
}

// ============================================
// Storage Account
// ============================================
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: '${baseName}${environment}${uniqueSuffix}'
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }
}

resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource templatesContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'ppt-templates'
  properties: {
    publicAccess: 'None'
  }
}

resource outputContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'ppt-outputs'
  properties: {
    publicAccess: 'None'
  }
}

resource tempContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'ppt-temp'
  properties: {
    publicAccess: 'None'
  }
}

// ============================================
// Service Bus Namespace
// ============================================
resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: '${resourcePrefix}-servicebus'
  location: location
  tags: tags
  sku: {
    name: 'Premium'
    tier: 'Premium'
    capacity: 1
  }
  properties: {
    minimumTlsVersion: '1.2'
  }
}

resource serviceBusQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: 'ppt-generation-jobs'
  properties: {
    lockDuration: 'PT5M'
    maxSizeInMegabytes: 5120
    requiresDuplicateDetection: false
    requiresSession: false
    defaultMessageTimeToLive: 'PT1H'
    deadLetteringOnMessageExpiration: true
    maxDeliveryCount: 3
    enablePartitioning: false
  }
}

// ============================================
// Cosmos DB Account
// ============================================
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' = {
  name: '${resourcePrefix}-cosmos'
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
  }
}

resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-04-15' = {
  parent: cosmosAccount
  name: 'ppt-generator'
  properties: {
    resource: {
      id: 'ppt-generator'
    }
  }
}

resource jobsContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = {
  parent: cosmosDatabase
  name: 'jobs'
  properties: {
    resource: {
      id: 'jobs'
      partitionKey: {
        paths: ['/jobId']
        kind: 'Hash'
      }
      defaultTtl: 604800 // 7 days
    }
  }
}

resource cacheContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = {
  parent: cosmosDatabase
  name: 'cache'
  properties: {
    resource: {
      id: 'cache'
      partitionKey: {
        paths: ['/contentHash']
        kind: 'Hash'
      }
      defaultTtl: 86400 // 24 hours
    }
  }
}

resource errorsContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = {
  parent: cosmosDatabase
  name: 'errors'
  properties: {
    resource: {
      id: 'errors'
      partitionKey: {
        paths: ['/jobId']
        kind: 'Hash'
      }
      defaultTtl: 2592000 // 30 days
    }
  }
}

resource cosmosTemplatesContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = {
  parent: cosmosDatabase
  name: 'templates'
  properties: {
    resource: {
      id: 'templates'
      partitionKey: {
        paths: ['/templateId']
        kind: 'Hash'
      }
    }
  }
}

// ============================================
// Azure SQL Database
// ============================================

// Managed identity for SQL Server (used for Entra-only auth)
resource sqlManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${resourcePrefix}-sql-identity'
  location: location
  tags: tags
}

// SQL Server with conditional authentication mode
resource sqlServer 'Microsoft.Sql/servers@2023-02-01-preview' = {
  name: '${resourcePrefix}-sql'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${sqlManagedIdentity.id}': {}
    }
  }
  properties: {
    // SQL admin credentials only used when Entra-only auth is disabled
    administratorLogin: sqlEntraOnlyAuth ? null : sqlAdminUsername
    administratorLoginPassword: sqlEntraOnlyAuth ? null : sqlAdminPassword
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    primaryUserAssignedIdentityId: sqlManagedIdentity.id
    administrators: {
      administratorType: 'ActiveDirectory'
      principalType: 'Application'
      login: sqlManagedIdentity.name
      sid: sqlManagedIdentity.properties.principalId
      tenantId: subscription().tenantId
      azureADOnlyAuthentication: sqlEntraOnlyAuth
    }
  }
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-02-01-preview' = {
  parent: sqlServer
  name: 'ppt-telemetry'
  location: location
  tags: tags
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 2147483648 // 2GB
  }
}

resource sqlFirewallAllowAzure 'Microsoft.Sql/servers/firewallRules@2023-02-01-preview' = {
  parent: sqlServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// ============================================
// Azure OpenAI (deployed to separate resource group)
// ============================================

// Deploy OpenAI module to the AI resource group
module openAiModule 'modules/openai.bicep' = if (empty(openAiResourceName)) {
  name: 'openai-deployment'
  scope: resourceGroup(aiResourceGroup)
  params: {
    resourcePrefix: resourcePrefix
    location: aiLocation
    tags: tags
    gptDeploymentName: openAiGptDeploymentName
    gptModelName: openAiGptModelName
    gptModelVersion: openAiGptModelVersion
    embeddingDeploymentName: openAiEmbeddingDeploymentName
    embeddingModelName: openAiEmbeddingModelName
  }
}

// Reference existing Azure OpenAI resource if provided
resource existingOpenAiAccount 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' existing = if (!empty(openAiResourceName)) {
  name: openAiResourceName
}

// Variables for OpenAI configuration (works with both new and existing)
var openAiEndpoint = empty(openAiResourceName) ? openAiModule.outputs.endpoint : existingOpenAiAccount.properties.endpoint
var openAiKey = empty(openAiResourceName) ? openAiModule.outputs.key : existingOpenAiAccount.listKeys().key1
var openAiAccountName = empty(openAiResourceName) ? openAiModule.outputs.accountName : openAiResourceName

// ============================================
// Container Apps Environment
// ============================================
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${resourcePrefix}-logs'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${resourcePrefix}-appinsights'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: '${resourcePrefix}-cae'
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

// ============================================
// Managed Identity for Container App (for SQL Entra auth)
// ============================================
resource containerAppIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${resourcePrefix}-containerapp-identity'
  location: location
  tags: tags
}

// ============================================
// Container App (Orchestrator)
// ============================================
// SQL connection string varies based on authentication mode
var sqlConnectionStringEntra = 'Driver={ODBC Driver 18 for SQL Server};Server=${sqlServer.properties.fullyQualifiedDomainName};Database=${sqlDatabase.name};Authentication=ActiveDirectoryMsi;Encrypt=yes;TrustServerCertificate=no;'
var sqlConnectionStringSql = 'Driver={ODBC Driver 18 for SQL Server};Server=${sqlServer.properties.fullyQualifiedDomainName};Database=${sqlDatabase.name};Uid=${sqlAdminUsername};Pwd=${sqlAdminPassword};Encrypt=yes;TrustServerCertificate=no;'

resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: '${resourcePrefix}-orchestrator'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${containerAppIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8080
        transport: 'http'
      }
      secrets: [
        {
          name: 'servicebus-connection'
          value: serviceBusNamespace.listKeys().primaryConnectionString
        }
        {
          name: 'cosmos-key'
          value: cosmosAccount.listKeys().primaryMasterKey
        }
        {
          name: 'storage-connection'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'sql-connection'
          value: sqlEntraOnlyAuth ? sqlConnectionStringEntra : sqlConnectionStringSql
        }
        {
          name: 'openai-key'
          value: openAiKey
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'orchestrator'
          image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest' // Replace with actual image
          resources: {
            cpu: json('1.0')
            memory: '2Gi'
          }
          env: [
            {
              name: 'SERVICEBUS_CONNECTION_STRING'
              secretRef: 'servicebus-connection'
            }
            {
              name: 'SERVICEBUS_QUEUE_NAME'
              value: 'ppt-generation-jobs'
            }
            {
              name: 'COSMOS_ENDPOINT'
              value: cosmosAccount.properties.documentEndpoint
            }
            {
              name: 'COSMOS_KEY'
              secretRef: 'cosmos-key'
            }
            {
              name: 'COSMOS_DATABASE'
              value: 'ppt-generator'
            }
            {
              name: 'BLOB_CONNECTION_STRING'
              secretRef: 'storage-connection'
            }
            {
              name: 'SQL_CONNECTION_STRING'
              secretRef: 'sql-connection'
            }
            {
              name: 'SQL_USE_MANAGED_IDENTITY'
              value: string(sqlEntraOnlyAuth)
            }
            {
              name: 'AZURE_CLIENT_ID'
              value: containerAppIdentity.properties.clientId
            }
            {
              name: 'AZURE_OPENAI_ENDPOINT'
              value: openAiEndpoint
            }
            {
              name: 'AZURE_OPENAI_API_KEY'
              secretRef: 'openai-key'
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
              value: appInsights.properties.ConnectionString
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 100
        rules: [
          {
            name: 'queue-scaling'
            custom: {
              type: 'azure-servicebus'
              metadata: {
                queueName: 'ppt-generation-jobs'
                messageCount: '25'
              }
              auth: [
                {
                  secretRef: 'servicebus-connection'
                  triggerParameter: 'connection'
                }
              ]
            }
          }
        ]
      }
    }
  }
}

// ============================================
// Key Vault
// ============================================
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: 'kv${baseName}${environment}${take(uniqueSuffix, 6)}'
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    accessPolicies: []
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enableRbacAuthorization: true
  }
}

// Key Vault Secrets Officer role for the deploying user
// Role ID: b86a8fe4-44ce-4948-aee5-eccb2c155cd7
resource keyVaultSecretsOfficerRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(deployerPrincipalId)) {
  name: guid(keyVault.id, deployerPrincipalId, 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
    principalId: deployerPrincipalId
    principalType: 'User'
  }
}

// Managed identity for deployment scripts
resource deploymentScriptIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${resourcePrefix}-deploy-script-id'
  location: location
  tags: tags
}

// Key Vault Secrets Officer role for the deployment script identity
resource deploymentScriptKvRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, deploymentScriptIdentity.id, 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
    principalId: deploymentScriptIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Deployment script to store SQL password in Key Vault
// Only runs when NOT using Entra-only auth (i.e., when SQL auth is enabled)
resource storeSqlPasswordScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = if (!sqlEntraOnlyAuth) {
  name: '${resourcePrefix}-store-sql-password'
  location: location
  tags: tags
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${deploymentScriptIdentity.id}': {}
    }
  }
  properties: {
    azCliVersion: '2.50.0'
    timeout: 'PT10M'
    retentionInterval: 'PT1H'
    cleanupPreference: 'OnSuccess'
    environmentVariables: [
      {
        name: 'KEY_VAULT_NAME'
        value: keyVault.name
      }
      {
        name: 'SQL_PASSWORD'
        secureValue: sqlAdminPassword
      }
    ]
    scriptContent: '''
      #!/bin/bash
      set -e

      echo "Waiting 30 seconds for RBAC propagation..."
      sleep 30

      echo "Storing SQL password in Key Vault: $KEY_VAULT_NAME"
      az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "sql-admin-password" \
        --value "$SQL_PASSWORD" \
        --output none

      echo "SQL password stored successfully"
    '''
  }
  dependsOn: [
    deploymentScriptKvRole
    keyVaultSecretsOfficerRole
  ]
}

// ============================================
// Container Registry
// ============================================
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: 'acr${baseName}${environment}${uniqueSuffix}'
  location: location
  tags: tags
  sku: {
    name: environment == 'prod' ? 'Standard' : 'Basic'
  }
  properties: {
    adminUserEnabled: true
    publicNetworkAccess: 'Enabled'
  }
}

// ============================================
// Azure Functions (API Layer) - deployed to separate resource group
// ============================================
module functionsModule 'modules/functions.bicep' = {
  name: 'functions-deployment'
  scope: resourceGroup(funcResourceGroup)
  params: {
    resourcePrefix: resourcePrefix
    location: location
    tags: tags
    serviceBusConnectionString: serviceBusNamespace.listKeys().primaryConnectionString
    cosmosEndpoint: cosmosAccount.properties.documentEndpoint
    cosmosKey: cosmosAccount.listKeys().primaryMasterKey
    openAiEndpoint: openAiEndpoint
    openAiKey: openAiKey
    openAiGptDeploymentName: openAiGptDeploymentName
    openAiEmbeddingDeploymentName: openAiEmbeddingDeploymentName
    appInsightsConnectionString: appInsights.properties.ConnectionString
    orchestratorUrl: 'https://${containerApp.properties.configuration.ingress.fqdn}'
    storageAccountName: storageAccount.name
    storageAccountId: storageAccount.id
  }
}

// Role assignments for Function App to access main storage account
// (deployed after functions module creates the managed identity)
module funcStorageRoleAssignments 'modules/storageRoleAssignments.bicep' = {
  name: 'func-storage-role-assignments'
  scope: resourceGroup()
  params: {
    storageAccountName: storageAccount.name
    functionAppPrincipalId: functionsModule.outputs.functionAppPrincipalId
  }
}

// ============================================
// API Management (optional - takes 30+ minutes to deploy)
// ============================================
@description('Deploy API Management (takes 30+ minutes)')
param deployApim bool = false

resource apiManagement 'Microsoft.ApiManagement/service@2023-03-01-preview' = if (deployApim) {
  name: '${resourcePrefix}-apim'
  location: location
  tags: tags
  sku: {
    name: environment == 'prod' ? 'Standard' : 'Developer'
    capacity: 1
  }
  properties: {
    publisherEmail: 'admin@example.com'
    publisherName: 'PPT Generator'
  }
}

// ============================================
// Outputs
// ============================================
output storageAccountName string = storageAccount.name
output serviceBusNamespace string = serviceBusNamespace.name
output cosmosAccountName string = cosmosAccount.name
output openAiAccountName string = openAiAccountName
output openAiResourceGroup string = aiResourceGroup
output openAiLocation string = aiLocation
output openAiEndpoint string = openAiEndpoint
output openAiGptDeployment string = openAiGptDeploymentName
output openAiEmbeddingDeployment string = openAiEmbeddingDeploymentName
output sqlServerName string = sqlServer.name
output sqlEntraOnlyAuthentication bool = sqlEntraOnlyAuth
output sqlManagedIdentityName string = sqlManagedIdentity.name
output sqlManagedIdentityClientId string = sqlManagedIdentity.properties.clientId
output sqlManagedIdentityPrincipalId string = sqlManagedIdentity.properties.principalId
output containerAppUrl string = containerApp.properties.configuration.ingress.fqdn
output containerAppIdentityName string = containerAppIdentity.name
output containerAppIdentityClientId string = containerAppIdentity.properties.clientId
output containerAppIdentityPrincipalId string = containerAppIdentity.properties.principalId
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output containerRegistryName string = containerRegistry.name
output containerRegistryLoginServer string = containerRegistry.properties.loginServer
output functionAppName string = functionsModule.outputs.functionAppName
output functionAppUrl string = functionsModule.outputs.functionAppUrl
output functionsResourceGroup string = funcResourceGroup
output apimGatewayUrl string = deployApim ? apiManagement.properties.gatewayUrl : ''

