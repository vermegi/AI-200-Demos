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
var logAnalyticsWorkspaceName = 'log-ai200-${userHash}'

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
    embeddingsApiKey: embeddingsApiKey
    location: location
    registryName: registry.outputs.name
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
output logAnalyticsWorkspace string = logAnalytics.outputs.name
