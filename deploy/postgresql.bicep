targetScope = 'resourceGroup'

@description('Name of the Azure Database for PostgreSQL flexible server.')
@minLength(3)
@maxLength(63)
param name string

@description('Azure region for the flexible server.')
param location string

@description('Major PostgreSQL engine version.')
param postgresVersion string = '16'

@description('Compute SKU of the flexible server.')
param skuName string = 'Standard_B1ms'

@description('Compute tier matching the SKU.')
@allowed([
  'Burstable'
  'GeneralPurpose'
  'MemoryOptimized'
])
param skuTier string = 'Burstable'

@description('Provisioned storage in GB.')
param storageSizeGB int = 32

@description('Object ID of the Microsoft Entra user that becomes the server administrator.')
param administratorObjectId string

@description('User principal name of the Microsoft Entra administrator. This is also the PostgreSQL role name the clients sign in with.')
param administratorPrincipalName string

@description('Extensions added to the azure.extensions allow-list so the labs can run CREATE EXTENSION.')
param allowedExtensions string = 'vector'

@description('Name of the shared Log Analytics workspace collecting PostgreSQL diagnostics.')
@minLength(4)
@maxLength(63)
param logAnalyticsWorkspaceName string

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' existing = {
  name: logAnalyticsWorkspaceName
}

// administratorLogin and administratorLoginPassword are intentionally omitted: the server accepts Entra tokens only.
resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: name
  location: location
  sku: {
    name: skuName
    tier: skuTier
  }
  properties: {
    version: postgresVersion
    createMode: 'Default'
    authConfig: {
      activeDirectoryAuth: 'Enabled'
      passwordAuth: 'Disabled'
      tenantId: subscription().tenantId
    }
    storage: {
      storageSizeGB: storageSizeGB
      autoGrow: 'Disabled'
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    network: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

// The labs connect from developer machines and from AKS pods with unpredictable egress addresses.
resource allowAllFirewallRule 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = {
  parent: postgres
  name: 'AllowAll'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '255.255.255.255'
  }
}

// The resource name must be the Entra object ID of the principal.
resource entraAdministrator 'Microsoft.DBforPostgreSQL/flexibleServers/administrators@2024-08-01' = {
  parent: postgres
  name: administratorObjectId
  properties: {
    principalName: administratorPrincipalName
    principalType: 'User'
    tenantId: subscription().tenantId
  }
  // Flexible server rejects concurrent child writes, so the children are chained.
  dependsOn: [
    allowAllFirewallRule
  ]
}

// azure.extensions is a static parameter, so setting it here folds the required restart into provisioning.
resource extensionsAllowList 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2024-08-01' = {
  parent: postgres
  name: 'azure.extensions'
  properties: {
    value: allowedExtensions
    source: 'user-override'
  }
  dependsOn: [
    entraAdministrator
  ]
}

resource postgresDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: postgres
  name: 'send-to-log-analytics'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'PostgreSQLLogs'
        enabled: true
      }
      {
        category: 'PostgreSQLFlexSessions'
        enabled: true
      }
      {
        category: 'PostgreSQLFlexQueryStoreRuntime'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
  dependsOn: [
    extensionsAllowList
  ]
}

output name string = postgres.name
output resourceId string = postgres.id
output fullyQualifiedDomainName string = postgres.properties.fullyQualifiedDomainName
output administratorPrincipalName string = administratorPrincipalName
output allowedExtensions string = allowedExtensions
