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

@description('Name of the container app used for the manage and troubleshoot demo.')
@minLength(2)
@maxLength(32)
param manageContainerAppName string

@description('Container port the manage demo image listens on once it is deployed.')
param manageTargetPort int = 8000

@description('Model name exposed to the manage demo container.')
param modelName string = 'gpt-4o-mini'

@description('Embeddings API key stored as a container app secret.')
@secure()
param embeddingsApiKey string

@description('Name of the container app used for the scaling demo.')
@minLength(2)
@maxLength(32)
param scaleContainerAppName string

@description('Container port the scaling demo image listens on once it is deployed.')
param scaleTargetPort int = 8080

@description('Simulated agent processing delay in milliseconds for the scaling demo.')
param agentDefaultDelayMs int = 500

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

// Ingress already targets the port of the image the demo script pushes later, not the quickstart image.
resource manageContainerApp 'Microsoft.App/containerApps@2025-01-01' = {
  name: manageContainerAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    environmentId: managedEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: manageTargetPort
        transport: 'auto'
      }
      secrets: [
        {
          name: 'embeddings-api-key'
          value: embeddingsApiKey
        }
      ]
      registries: [
        {
          server: registry.properties.loginServer
          identity: 'system'
        }
      ]
    }
    template: {
      containers: [
        {
          name: manageContainerAppName
          image: containerImage
          env: [
            {
              name: 'MODEL_NAME'
              value: modelName
            }
            {
              name: 'EMBEDDINGS_API_KEY'
              secretRef: 'embeddings-api-key'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 10
      }
    }
  }
}

resource manageContainerAppRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for roleId in containerAppRoleIds: {
  scope: registry
  name: guid(registry.id, manageContainerApp.id, roleId)
  properties: {
    principalId: manageContainerApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleId)
  }
}]

// Scale rules are configured from the demo script, so only the default scale bounds are set here.
resource scaleContainerApp 'Microsoft.App/containerApps@2025-01-01' = {
  name: scaleContainerAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    environmentId: managedEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: scaleTargetPort
        transport: 'auto'
      }
      registries: [
        {
          server: registry.properties.loginServer
          identity: 'system'
        }
      ]
    }
    template: {
      containers: [
        {
          name: scaleContainerAppName
          image: containerImage
          env: [
            {
              name: 'AGENT_DEFAULT_DELAY_MS'
              value: string(agentDefaultDelayMs)
            }
          ]
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 10
      }
    }
  }
}

resource scaleContainerAppRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for roleId in containerAppRoleIds: {
  scope: registry
  name: guid(registry.id, scaleContainerApp.id, roleId)
  properties: {
    principalId: scaleContainerApp.identity.principalId
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
output manageContainerAppName string = manageContainerApp.name
output manageContainerAppFqdn string = manageContainerApp.properties.configuration.ingress.fqdn
output manageContainerAppUrl string = 'https://${manageContainerApp.properties.configuration.ingress.fqdn}'
output manageContainerAppPrincipalId string = manageContainerApp.identity.principalId
output scaleContainerAppName string = scaleContainerApp.name
output scaleContainerAppFqdn string = scaleContainerApp.properties.configuration.ingress.fqdn
output scaleContainerAppUrl string = 'https://${scaleContainerApp.properties.configuration.ingress.fqdn}'
output scaleContainerAppPrincipalId string = scaleContainerApp.identity.principalId
