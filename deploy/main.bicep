targetScope = 'subscription'

@description('Unique user hash used to derive the resource group, container registry, app service plan and web app names.')
@minLength(2)
@maxLength(42)
param userHash string

@description('Azure region for the resource group and container registry.')
param location string = 'francecentral'

@description('Principal ID that receives repository permissions on the container registry. Leave empty to skip role assignments.')
param principalId string = ''

@description('User principal name of the signed-in user that becomes the PostgreSQL Microsoft Entra administrator.')
param userPrincipalName string

@description('SKU name of the App Service plan hosting the container web app.')
param appServicePlanSku string = 'P0v3'

@description('Placeholder container image used until the ACR image is built and pushed from the CLI script.')
param placeholderContainerImage string = 'DOCKER|mcr.microsoft.com/appsvc/staticsite:latest'

@description('Placeholder container image used until the MCP Function App image is built and pushed from the CLI script.')
param placeholderFunctionContainerImage string = 'DOCKER|mcr.microsoft.com/azure-functions/python:4-python3.11'

@description('Embeddings API key stored as a secret on the manage demo container app.')
@secure()
param embeddingsApiKey string

@description('Sample OpenAI API key stored in Key Vault.')
@secure()
param openaiApiKey string

@description('Sample Cosmos DB connection string stored in Key Vault.')
@secure()
param cosmosDbConnectionString string

type containerRegistryOutputType = {
  name: string
  resourceId: string
  loginServer: string
}

type appServiceOutputType = {
  plan: string
  webApp: string
  webAppUrl: string
  webAppPrincipalId: string
}

type privateNetworkingOutputType = {
  virtualNetwork: string
  frontDoorProfile: string
  frontDoorEndpoint: string
  frontDoorHostname: string
  frontDoorUrl: string
}

type containerAppsOutputType = {
  environment: string
  app: string
  appUrl: string
  appPrincipalId: string
  manageApp: string
  manageAppUrl: string
  manageAppPrincipalId: string
  scaleApp: string
  scaleAppUrl: string
  scaleAppPrincipalId: string
}

type logAnalyticsOutputType = {
  workspace: string
}

type applicationInsightsOutputType = {
  name: string
  resourceId: string
  connectionString: string
}

type foundryOutputType = {
  account: string
  endpoint: string
  project: string
  modelDeployment: string
}

type aksOutputType = {
  cluster: string
  kubeletObjectId: string
}

type cosmosOutputType = {
  account: string
  endpoint: string
  database: string
  container: string
  vectorDatabase: string
  vectorContainer: string
  indexOptimizationDatabase: string
  indexOptimizationContainers: string[]
  clientIdentityName: string
  clientIdentityClientId: string
}

type postgresOutputType = {
  server: string
  host: string
  database: string
  admin: string
}

type redisOutputType = {
  cluster: string
  host: string
  database: string
  port: int
  accessAssignment: string
}

type serviceBusOutputType = {
  namespace: string
  resourceId: string
  fqdn: string
  queue: string
  topic: string
  notificationsSubscription: string
  highPrioritySubscription: string
  highPriorityRule: string
}

type eventGridOutputType = {
  namespace: string
  resourceId: string
  topic: string
  flaggedSubscription: string
  approvedSubscription: string
  allEventsSubscription: string
  hostname: string
  endpoint: string
}

type keyVaultOutputType = {
  name: string
  uri: string
  clientIdentity: string
  clientIdentityClientId: string
}

type appConfigurationOutputType = {
  name: string
  endpoint: string
}

var resourceGroupName = 'rg-AI200-${userHash}'
var registryName = 'acr${userHash}'
var appServicePlanName = 'plan-docprocessor-${userHash}'
var webAppName = 'app-docprocessor-${userHash}'
var containerAppsEnvironmentName = 'aca-env-demo'
var containerAppName = 'ai-api'
var manageContainerAppName = 'ai-api-manage'
var scaleContainerAppName = 'agent-api-scale'
var foundryName = 'foundry-resource-${userHash}'
var foundryProjectName = 'foundry-project-${userHash}'
var aksName = 'aks-${userHash}'
var logAnalyticsWorkspaceName = 'log-ai200-${userHash}'
var applicationInsightsName = 'appi-exercise-${userHash}'
var functionAppName = take('func-document-tools-${userHash}', 60)
var functionStorageAccountName = take('stdoctools${userHash}', 24)
var cosmosName = take('cosmos-rag-${userHash}', 44)
var cosmosClientIdentityName = 'id-cosmos-client-${userHash}'
var keyVaultClientIdentityName = 'id-keyvault-client-${userHash}'
var postgresName = 'psql-ai200-${userHash}'
var postgresDatabaseName = 'postgres'
var redisName = 'amr-exercise-${userHash}'
var serviceBusName = take('sbns-exercise-${userHash}', 50)
var eventGridName = take('egns-exercise-${userHash}', 50)
var appConfigurationName = take('appconfig-${userHash}', 50)
var keyVaultName = 'kv-${uniqueString(subscription().id, resourceGroup.name, principalId)}'

resource resourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: resourceGroupName
  location: location
}

module logAnalytics './log-analytics.bicep' = {
  scope: az.resourceGroup(resourceGroup.name)
  params: {
    name: logAnalyticsWorkspaceName
    location: location
  }
}

module applicationInsights './application-insights.bicep' = {
  scope: az.resourceGroup(resourceGroup.name)
  params: {
    name: applicationInsightsName
    location: location
    logAnalyticsWorkspaceName: logAnalytics.outputs.name
    userPrincipalId: principalId
  }
}

module appServicePlan './app-service-plan.bicep' = {
  scope: az.resourceGroup(resourceGroup.name)
  params: {
    name: appServicePlanName
    location: location
    skuName: appServicePlanSku
    skuCapacity: 1
  }
}

module webApp './web-app.bicep' = {
  scope: az.resourceGroup(resourceGroup.name)
  params: {
    name: webAppName
    location: location
    serverFarmResourceId: appServicePlan.outputs.resourceId
    linuxFxVersion: placeholderContainerImage
    logAnalyticsWorkspaceName: logAnalytics.outputs.name
  }
}

module functionStorage './function-storage.bicep' = {
  scope: az.resourceGroup(resourceGroup.name)
  params: {
    name: functionStorageAccountName
    location: location
  }
}

module functionApp './function-app.bicep' = {
  scope: az.resourceGroup(resourceGroup.name)
  params: {
    name: functionAppName
    location: location
    serverFarmResourceId: appServicePlan.outputs.resourceId
    linuxFxVersion: placeholderFunctionContainerImage
    storageAccountName: functionStorage.outputs.name
    logAnalyticsWorkspaceName: logAnalytics.outputs.name
  }
}

module privateNetworking './private-network.bicep' = {
  scope: resourceGroup
  params: {
    location: location
    userHash: userHash
    webAppResourceId: webApp.outputs.resourceId
    webAppDefaultHostname: webApp.outputs.defaultHostname
    functionAppName: functionApp.outputs.name
    functionAppResourceId: functionApp.outputs.resourceId
    functionAppDefaultHostname: functionApp.outputs.defaultHostname
    functionStorageAccountName: functionStorage.outputs.name
    functionStorageAccountResourceId: functionStorage.outputs.resourceId
    logAnalyticsWorkspaceName: logAnalytics.outputs.name
  }
}

// Deployed after the web app so its system-assigned identity can be granted repository access here.
module registry './container-registry.bicep' = {
  scope: az.resourceGroup(resourceGroup.name)
  params: {
    name: registryName
    location: location
    acrSku: 'Basic'
    userPrincipalId: principalId
    webAppPrincipalId: webApp.outputs.systemAssignedMIPrincipalId
    functionAppPrincipalId: functionApp.outputs.systemAssignedMIPrincipalId
    logAnalyticsWorkspaceName: logAnalytics.outputs.name
  }
}

// Deployed after the registry so the container app identity can be granted repository access here.
module containerApps './container-apps.bicep' = {
  scope: az.resourceGroup(resourceGroup.name)
  params: {
    environmentName: containerAppsEnvironmentName
    containerAppName: containerAppName
    manageContainerAppName: manageContainerAppName
    scaleContainerAppName: scaleContainerAppName
    embeddingsApiKey: embeddingsApiKey
    location: location
    registryName: registry.outputs.name
    logAnalyticsWorkspaceName: logAnalytics.outputs.name
  }
}

// Shared by all three PostgreSQL exercises; the vector extension is allow-listed up front.
module postgres './postgresql.bicep' = {
  scope: az.resourceGroup(resourceGroup.name)
  params: {
    name: postgresName
    location: location
    administratorObjectId: principalId
    administratorPrincipalName: userPrincipalName
    logAnalyticsWorkspaceName: logAnalytics.outputs.name
  }
}

module redis './redis.bicep' = {
  scope: az.resourceGroup(resourceGroup.name)
  params: {
    name: redisName
    location: location
    userPrincipalId: principalId
  }
}

module serviceBus './service-bus.bicep' = {
  scope: az.resourceGroup(resourceGroup.name)
  params: {
    name: serviceBusName
    location: location
    userPrincipalId: principalId
  }
}

module eventGrid './event-grid.bicep' = {
  scope: az.resourceGroup(resourceGroup.name)
  params: {
    name: eventGridName
    location: location
    userPrincipalId: principalId
  }
}

module keyVault './key-vault.bicep' = {
  scope: az.resourceGroup(resourceGroup.name)
  params: {
    name: keyVaultName
    location: location
    clientIdentityName: keyVaultClientIdentityName
    aksOidcIssuerUrl: aks.outputs.oidcIssuerUrl
    userPrincipalId: principalId
    openaiApiKey: openaiApiKey
    cosmosDbConnectionString: cosmosDbConnectionString
    virtualNetworkName: privateNetworking.outputs.virtualNetwork
    privateEndpointSubnetName: privateNetworking.outputs.privateEndpointSubnetName
  }
}

module appConfiguration './app-configuration.bicep' = {
  scope: az.resourceGroup(resourceGroup.name)
  params: {
    name: appConfigurationName
    location: location
    userPrincipalId: principalId
    clientIdentityName: keyVaultClientIdentityName
    keyVaultUri: keyVault.outputs.uri
  }
}

module foundry './foundry.bicep' = {
  scope: az.resourceGroup(resourceGroup.name)
  params: {
    name: foundryName
    projectName: foundryProjectName
    location: location
  }
}

// Deployed last so the cluster identities can be granted access to the registry, Foundry and subnet.
module aks './aks.bicep' = {
  scope: az.resourceGroup(resourceGroup.name)
  params: {
    name: aksName
    location: location
    dnsPrefix: aksName
    virtualNetworkName: privateNetworking.outputs.virtualNetwork
    subnetName: privateNetworking.outputs.aksSubnetName
    registryName: registry.outputs.name
    foundryName: foundry.outputs.name
    logAnalyticsWorkspaceName: logAnalytics.outputs.name
  }
}

// Deployed after the cluster so the client identity can federate with the cluster OIDC issuer.
module cosmos './cosmos.bicep' = {
  scope: az.resourceGroup(resourceGroup.name)
  params: {
    name: cosmosName
    location: location
    clientIdentityName: cosmosClientIdentityName
    aksOidcIssuerUrl: aks.outputs.oidcIssuerUrl
    virtualNetworkName: privateNetworking.outputs.virtualNetwork
    privateEndpointSubnetName: privateNetworking.outputs.privateEndpointSubnetName
    userPrincipalId: principalId
    logAnalyticsWorkspaceName: logAnalytics.outputs.name
  }
}

output resourceGroup string = resourceGroup.name
output appConfiguration appConfigurationOutputType = {
  name: appConfiguration.outputs.name
  endpoint: appConfiguration.outputs.endpoint
}
output containerRegistry containerRegistryOutputType = {
  name: registry.outputs.name
  resourceId: registry.outputs.resourceId
  loginServer: registry.outputs.loginServer
}
output appService appServiceOutputType = {
  plan: appServicePlan.outputs.name
  webApp: webApp.outputs.name
  webAppUrl: 'https://${webApp.outputs.defaultHostname}'
  webAppPrincipalId: webApp.outputs.systemAssignedMIPrincipalId
}
output privateNetworking privateNetworkingOutputType = {
  virtualNetwork: privateNetworking.outputs.virtualNetwork
  frontDoorProfile: privateNetworking.outputs.frontDoorProfile
  frontDoorEndpoint: privateNetworking.outputs.frontDoorEndpoint
  frontDoorHostname: privateNetworking.outputs.frontDoorHostname
  frontDoorUrl: privateNetworking.outputs.frontDoorUrl
}
output containerApps containerAppsOutputType = {
  environment: containerApps.outputs.environmentName
  app: containerApps.outputs.containerAppName
  appUrl: containerApps.outputs.containerAppUrl
  appPrincipalId: containerApps.outputs.containerAppPrincipalId
  manageApp: containerApps.outputs.manageContainerAppName
  manageAppUrl: containerApps.outputs.manageContainerAppUrl
  manageAppPrincipalId: containerApps.outputs.manageContainerAppPrincipalId
  scaleApp: containerApps.outputs.scaleContainerAppName
  scaleAppUrl: containerApps.outputs.scaleContainerAppUrl
  scaleAppPrincipalId: containerApps.outputs.scaleContainerAppPrincipalId
}
output logAnalytics logAnalyticsOutputType = {
  workspace: logAnalytics.outputs.name
}
output applicationInsights applicationInsightsOutputType = {
  name: applicationInsights.outputs.name
  resourceId: applicationInsights.outputs.resourceId
  connectionString: applicationInsights.outputs.connectionString
}
output foundry foundryOutputType = {
  account: foundry.outputs.name
  endpoint: foundry.outputs.endpoint
  project: foundry.outputs.projectName
  modelDeployment: foundry.outputs.modelDeploymentName
}
output aks aksOutputType = {
  cluster: aks.outputs.name
  kubeletObjectId: aks.outputs.kubeletIdentityObjectId
}
output cosmos cosmosOutputType = {
  account: cosmos.outputs.name
  endpoint: cosmos.outputs.endpoint
  database: cosmos.outputs.databaseName
  container: cosmos.outputs.containerName
  vectorDatabase: cosmos.outputs.vectorDatabaseName
  vectorContainer: cosmos.outputs.vectorContainerName
  indexOptimizationDatabase: cosmos.outputs.indexOptimizationDatabaseName
  indexOptimizationContainers: cosmos.outputs.indexOptimizationContainerNames
  clientIdentityName: cosmos.outputs.clientIdentityName
  clientIdentityClientId: cosmos.outputs.clientIdentityClientId
}
output postgres postgresOutputType = {
  server: postgres.outputs.name
  host: postgres.outputs.fullyQualifiedDomainName
  database: postgresDatabaseName
  admin: postgres.outputs.administratorPrincipalName
}
output redis redisOutputType = {
  cluster: redis.outputs.name
  host: redis.outputs.hostName
  database: redis.outputs.databaseName
  port: redis.outputs.databasePort
  accessAssignment: redis.outputs.accessAssignmentName
}
output serviceBus serviceBusOutputType = {
  namespace: serviceBus.outputs.name
  resourceId: serviceBus.outputs.resourceId
  fqdn: serviceBus.outputs.fullyQualifiedDomainName
  queue: serviceBus.outputs.queueName
  topic: serviceBus.outputs.topicName
  notificationsSubscription: serviceBus.outputs.notificationsSubscriptionName
  highPrioritySubscription: serviceBus.outputs.highPrioritySubscriptionName
  highPriorityRule: serviceBus.outputs.highPriorityRuleName
}
output eventGrid eventGridOutputType = {
  namespace: eventGrid.outputs.name
  resourceId: eventGrid.outputs.resourceId
  topic: eventGrid.outputs.topicName
  flaggedSubscription: eventGrid.outputs.flaggedSubscriptionName
  approvedSubscription: eventGrid.outputs.approvedSubscriptionName
  allEventsSubscription: eventGrid.outputs.allEventsSubscriptionName
  hostname: eventGrid.outputs.hostname
  endpoint: eventGrid.outputs.endpoint
}
output keyVault keyVaultOutputType = {
  name: keyVault.outputs.name
  uri: keyVault.outputs.uri
  clientIdentity: keyVault.outputs.clientIdentityName
  clientIdentityClientId: keyVault.outputs.clientIdentityClientId
}
