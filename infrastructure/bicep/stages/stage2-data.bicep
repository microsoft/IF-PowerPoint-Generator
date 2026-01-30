// ============================================
// Stage 2: Data Services
// Storage, Cosmos DB, SQL Server, Service Bus
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

@description('SQL Managed Identity ID from stage 1')
param sqlIdentityId string

@description('SQL Managed Identity Principal ID from stage 1')
param sqlIdentityPrincipalId string

@description('Enable Microsoft Entra-only authentication for SQL Server')
param sqlEntraOnlyAuth bool = true

@description('SQL Admin username (only used when sqlEntraOnlyAuth is false)')
@secure()
param sqlAdminUsername string = ''

@description('SQL Admin password (only used when sqlEntraOnlyAuth is false)')
@secure()
param sqlAdminPassword string = ''

// Tags
var tags = {
  Environment: environment
  Application: 'PPT-Generator'
  ManagedBy: 'Bicep'
  Stage: '2-Data'
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

// Blob containers
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource templatesContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'ppt-templates'
  properties: {
    publicAccess: 'None'
  }
}

resource outputsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'ppt-outputs'
  properties: {
    publicAccess: 'None'
  }
}

resource tempContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'ppt-temp'
  properties: {
    publicAccess: 'None'
  }
}

// ============================================
// Service Bus
// ============================================
resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: '${resourcePrefix}-servicebus'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
}

resource serviceBusQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: 'ppt-generation-jobs'
  properties: {
    maxDeliveryCount: 10
    defaultMessageTimeToLive: 'P1D'
    lockDuration: 'PT5M'
    deadLetteringOnMessageExpiration: true
  }
}

// ============================================
// Cosmos DB
// ============================================
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-11-15' = {
  name: '${resourcePrefix}-cosmos'
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
  }
}

resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-11-15' = {
  parent: cosmosAccount
  name: 'ppt-generator'
  properties: {
    resource: {
      id: 'ppt-generator'
    }
  }
}

resource jobsContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-11-15' = {
  parent: cosmosDatabase
  name: 'jobs'
  properties: {
    resource: {
      id: 'jobs'
      partitionKey: {
        paths: ['/partitionKey']
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
      }
    }
  }
}

resource templatesCosmosContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-11-15' = {
  parent: cosmosDatabase
  name: 'templates'
  properties: {
    resource: {
      id: 'templates'
      partitionKey: {
        paths: ['/partitionKey']
        kind: 'Hash'
      }
    }
  }
}

// ============================================
// SQL Server
// ============================================
resource sqlServer 'Microsoft.Sql/servers@2023-05-01-preview' = {
  name: '${resourcePrefix}-sql'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${sqlIdentityId}': {}
    }
  }
  properties: {
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    primaryUserAssignedIdentityId: sqlIdentityId
    administrators: sqlEntraOnlyAuth ? {
      administratorType: 'ActiveDirectory'
      azureADOnlyAuthentication: true
      login: 'SQL Admin'
      principalType: 'Application'
      sid: sqlIdentityPrincipalId
      tenantId: subscription().tenantId
    } : null
    administratorLogin: sqlEntraOnlyAuth ? null : sqlAdminUsername
    administratorLoginPassword: sqlEntraOnlyAuth ? null : sqlAdminPassword
  }
}

resource sqlFirewallAllowAzure 'Microsoft.Sql/servers/firewallRules@2023-05-01-preview' = {
  parent: sqlServer
  name: 'AllowAllAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-05-01-preview' = {
  parent: sqlServer
  name: 'telemetry'
  location: location
  tags: tags
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 2147483648
  }
}

// ============================================
// Outputs
// ============================================
output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output storageAccountConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
output serviceBusNamespace string = serviceBusNamespace.name
output serviceBusId string = serviceBusNamespace.id
output serviceBusConnectionString string = listKeys('${serviceBusNamespace.id}/AuthorizationRules/RootManageSharedAccessKey', serviceBusNamespace.apiVersion).primaryConnectionString
output cosmosAccountName string = cosmosAccount.name
output cosmosEndpoint string = cosmosAccount.properties.documentEndpoint
output cosmosKey string = cosmosAccount.listKeys().primaryMasterKey
output sqlServerName string = sqlServer.name
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName
output sqlDatabaseName string = sqlDatabase.name
output sqlEntraOnlyAuthentication bool = sqlEntraOnlyAuth
