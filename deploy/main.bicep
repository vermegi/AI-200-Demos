targetScope = 'subscription'

@description('Unique user hash used to derive the resource group, container registry, app service plan and web app names.')
@minLength(2)
@maxLength(42)
param userHash string

@description('Azure region for the resource group and container registry.')
param location string = 'francecentral'

@description('Principal ID that receives repository permissions on the container registry. Leave empty to skip role assignments.')
param principalId string = ''

@description('SKU name of the App Service plan hosting the container web app.')
param appServicePlanSku string = 'P0v3'

@description('Placeholder container image used until the ACR image is built and pushed from the CLI script.')
param placeholderContainerImage string = 'DOCKER|mcr.microsoft.com/appsvc/staticsite:latest'

@description('Embeddings API key stored as a secret on the manage demo container app.')
@secure()
param embeddingsApiKey string

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
var cosmosName = take('cosmos-rag-${userHash}', 44)
var cosmosClientIdentityName = 'id-cosmos-client-${userHash}'

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

module privateNetworking './private-network.bicep' = {
  scope: resourceGroup
  params: {
    location: location
    userHash: userHash
    webAppResourceId: webApp.outputs.resourceId
    webAppDefaultHostname: webApp.outputs.defaultHostname
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
output registry string = registry.outputs.name
output registryId string = registry.outputs.resourceId
output loginServer string = registry.outputs.loginServer
output appServicePlan string = appServicePlan.outputs.name
output webApp string = webApp.outputs.name
output webAppUrl string = 'https://${webApp.outputs.defaultHostname}'
output webAppPrincipalId string = webApp.outputs.systemAssignedMIPrincipalId
output virtualNetwork string = privateNetworking.outputs.virtualNetwork
output frontDoorProfile string = privateNetworking.outputs.frontDoorProfile
output frontDoorEndpoint string = privateNetworking.outputs.frontDoorEndpoint
output frontDoorHostname string = privateNetworking.outputs.frontDoorHostname
output frontDoorUrl string = privateNetworking.outputs.frontDoorUrl
output containerAppsEnvironment string = containerApps.outputs.environmentName
output containerApp string = containerApps.outputs.containerAppName
output containerAppUrl string = containerApps.outputs.containerAppUrl
output containerAppPrincipalId string = containerApps.outputs.containerAppPrincipalId
output manageContainerApp string = containerApps.outputs.manageContainerAppName
output manageContainerAppUrl string = containerApps.outputs.manageContainerAppUrl
output manageContainerAppPrincipalId string = containerApps.outputs.manageContainerAppPrincipalId
output scaleContainerApp string = containerApps.outputs.scaleContainerAppName
output scaleContainerAppUrl string = containerApps.outputs.scaleContainerAppUrl
output scaleContainerAppPrincipalId string = containerApps.outputs.scaleContainerAppPrincipalId
output logAnalyticsWorkspace string = logAnalytics.outputs.name
output foundryAccount string = foundry.outputs.name
output foundryEndpoint string = foundry.outputs.endpoint
output foundryProject string = foundry.outputs.projectName
output foundryModelDeployment string = foundry.outputs.modelDeploymentName
output aksCluster string = aks.outputs.name
output aksKubeletObjectId string = aks.outputs.kubeletIdentityObjectId
output cosmosAccount string = cosmos.outputs.name
output cosmosEndpoint string = cosmos.outputs.endpoint
output cosmosDatabase string = cosmos.outputs.databaseName
output cosmosContainer string = cosmos.outputs.containerName
output cosmosVectorDatabase string = cosmos.outputs.vectorDatabaseName
output cosmosVectorContainer string = cosmos.outputs.vectorContainerName
output cosmosClientIdentityClientId string = cosmos.outputs.clientIdentityClientId
