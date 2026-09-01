targetScope = 'resourceGroup'

@description('Name of the Container Apps managed environment.')
@minLength(2)
@maxLength(60)
param environmentName string

@description('Name of the container app.')
@minLength(2)
@maxLength(32)
param containerAppName string

@description('Azure region for the Container Apps resources.')
param location string

@description('Name of the container registry the container app pulls images from.')
param registryName string

@description('Container image deployed to the container app. Defaults to the platform quickstart image.')
param containerImage string = 'mcr.microsoft.com/k8se/quickstart:latest'

@description('Container port exposed through external ingress.')
param targetPort int = 80

@description('Name of the shared Log Analytics workspace.')
@minLength(4)
@maxLength(63)
param logAnalyticsWorkspaceName string

// Built-in role definition IDs for ABAC repository permissions on the registry.
var repositoryReaderRoleId = 'b93aa761-3e63-49ed-ac28-beffa264f7ac'
var repositoryCatalogListerRoleId = 'bfdb9389-c9a5-478a-bb2f-ba9ca092c3c7'
var containerAppRoleIds = [
  repositoryReaderRoleId
  repositoryCatalogListerRoleId
]

resource registry 'Microsoft.ContainerRegistry/registries@2025-05-01-preview' existing = {
  name: registryName
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource managedEnvironment 'Microsoft.App/managedEnvironments@2025-01-01' = {
  name: environmentName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
  }
}

resource containerApp 'Microsoft.App/containerApps@2025-01-01' = {
  name: containerAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    environmentId: managedEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: targetPort
        transport: 'auto'
      }
      registries: [
        {
          server: registry.properties.loginServer
          // Pull images with the system-assigned identity instead of registry credentials.
          identity: 'system'
        }
      ]
    }
    template: {
      containers: [
        {
          name: containerAppName
          image: containerImage
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 10
      }
    }
  }
}

resource containerAppRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for roleId in containerAppRoleIds: {
  scope: registry
  name: guid(registry.id, containerApp.id, roleId)
  properties: {
    principalId: containerApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleId)
  }
}]

resource environmentDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: managedEnvironment
  name: 'send-to-log-analytics'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

output environmentName string = managedEnvironment.name
output environmentId string = managedEnvironment.id
output containerAppName string = containerApp.name
output containerAppFqdn string = containerApp.properties.configuration.ingress.fqdn
output containerAppUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output containerAppPrincipalId string = containerApp.identity.principalId
