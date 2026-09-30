targetScope = 'resourceGroup'

@description('Name of the web app.')
@minLength(2)
@maxLength(60)
param name string

@description('Azure region for the web app.')
param location string

@description('Resource ID of the App Service plan hosting the web app.')
param serverFarmResourceId string

@description('Container image reference used by the Linux web app.')
param linuxFxVersion string

@description('Name of the shared Log Analytics workspace collecting web app diagnostics.')
@minLength(4)
@maxLength(63)
param logAnalyticsWorkspaceName string

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource webApp 'Microsoft.Web/sites@2024-11-01' = {
  name: name
  location: location
  kind: 'app,linux,container'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: serverFarmResourceId
    httpsOnly: true
    siteConfig: {
      alwaysOn: true
      linuxFxVersion: linuxFxVersion
      // Pull images from the container registry with the system-assigned identity instead of admin credentials.
      acrUseManagedIdentityCreds: true
      appSettings: [
        {
          name: 'WEBSITES_PORT'
          value: '80'
        }
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'true'
        }
      ]
    }
  }
}

resource logs 'Microsoft.Web/sites/config@2024-11-01' = {
  parent: webApp
  name: 'logs'
  properties: {
    httpLogs: {
      fileSystem: {
        enabled: true
        retentionInDays: 1
        retentionInMb: 35
      }
    }
  }
}

resource webAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: webApp
  name: 'send-to-log-analytics'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'AppServiceHTTPLogs'
        enabled: true
      }
      {
        category: 'AppServiceConsoleLogs'
        enabled: true
      }
      {
        category: 'AppServiceAppLogs'
        enabled: true
      }
      {
        category: 'AppServicePlatformLogs'
        enabled: true
      }
      {
        category: 'AppServiceAuditLogs'
        enabled: true
      }
      {
        category: 'AppServiceIPSecAuditLogs'
        enabled: true
      }
      {
        category: 'AppServiceAuthenticationLogs'
        enabled: true
      }
    ]
  }
}

output resourceId string = webApp.id
output name string = webApp.name
output defaultHostname string = webApp.properties.defaultHostName
output systemAssignedMIPrincipalId string = webApp.identity.principalId
