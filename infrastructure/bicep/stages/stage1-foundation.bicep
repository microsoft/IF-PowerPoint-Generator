// ============================================
// Stage 1: Foundation
// Log Analytics, Application Insights, Key Vault, Managed Identities
// ============================================

targetScope = 'resourceGroup'

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Azure region for resources')
param location string = resourceGroup().location

@description('Base name for resources')
param baseName string = 'pptgen'

@description('Principal ID of the deploying user (for Key Vault RBAC)')
param deployerPrincipalId string = ''

@description('Deployment timestamp for unique naming')
param deploymentTimestamp string = utcNow('yyyyMMddHHmm')

// Variables
var uniqueSuffix = uniqueString(resourceGroup().id)
var kvUniqueSuffix = uniqueString(resourceGroup().id, deploymentTimestamp)
var resourcePrefix = '${baseName}-${environment}'

// Tags
var tags = {
  Environment: environment
  Application: 'PPT-Generator'
  ManagedBy: 'Bicep'
  Stage: '1-Foundation'
}

// ============================================
// Log Analytics Workspace
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

// ============================================
// Application Insights
// ============================================
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${resourcePrefix}-insights'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ============================================
// Key Vault
// ============================================
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv${baseName}${environment}${take(kvUniqueSuffix, 6)}'
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    // Note: enablePurgeProtection not set - defaults to false for new vaults
    // Cannot be set to false if vault already exists with it enabled
  }
}

// Key Vault Administrator role for deployer
resource kvAdminRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(deployerPrincipalId)) {
  name: guid(keyVault.id, deployerPrincipalId, '00482a5a-887f-4fb3-b363-3b7fe8e74483')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00482a5a-887f-4fb3-b363-3b7fe8e74483')
    principalId: deployerPrincipalId
    principalType: 'User'
  }
}

// ============================================
// Managed Identities
// ============================================
resource containerAppIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${resourcePrefix}-container-app-id'
  location: location
  tags: tags
}

resource sqlIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${resourcePrefix}-sql-id'
  location: location
  tags: tags
}

resource functionAppIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${resourcePrefix}-func-id'
  location: location
  tags: tags
}

// ============================================
// Outputs
// ============================================
output logAnalyticsWorkspaceId string = logAnalytics.id
output logAnalyticsWorkspaceName string = logAnalytics.name
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output containerAppIdentityId string = containerAppIdentity.id
output containerAppIdentityClientId string = containerAppIdentity.properties.clientId
output containerAppIdentityPrincipalId string = containerAppIdentity.properties.principalId
output containerAppIdentityName string = containerAppIdentity.name
output sqlIdentityId string = sqlIdentity.id
output sqlIdentityClientId string = sqlIdentity.properties.clientId
output sqlIdentityPrincipalId string = sqlIdentity.properties.principalId
output sqlIdentityName string = sqlIdentity.name
output functionAppIdentityId string = functionAppIdentity.id
output functionAppIdentityClientId string = functionAppIdentity.properties.clientId
output functionAppIdentityPrincipalId string = functionAppIdentity.properties.principalId
output functionAppIdentityName string = functionAppIdentity.name
output resourcePrefix string = resourcePrefix
output uniqueSuffix string = uniqueSuffix
