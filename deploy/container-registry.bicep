targetScope = 'resourceGroup'

@description('Name of the container registry.')
@minLength(5)
@maxLength(50)
param name string

@description('Azure region for the container registry.')
param location string

@description('SKU of the container registry.')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param acrSku string = 'Basic'

@description('Object ID of the signed-in user that receives repository permissions. Leave empty to skip the user role assignments.')
param userPrincipalId string = ''

@description('Principal ID of the web app system-assigned identity that pulls images from the registry.')
param webAppPrincipalId string

// Built-in role definition IDs for ABAC repository permissions.
var repositoryReaderRoleId = 'b93aa761-3e63-49ed-ac28-beffa264f7ac'
var repositoryCatalogListerRoleId = 'bfdb9389-c9a5-478a-bb2f-ba9ca092c3c7'
var repositoryWriterRoleId = '2a1e307c-b015-4ebd-883e-5b7698a07328'

var userRoleIds = empty(userPrincipalId) ? [] : [
  repositoryReaderRoleId
  repositoryCatalogListerRoleId
  repositoryWriterRoleId
]
var webAppRoleIds = [
  repositoryReaderRoleId
  repositoryCatalogListerRoleId
]

resource registry 'Microsoft.ContainerRegistry/registries@2025-05-01-preview' = {
  name: name
  location: location
  sku: {
    name: acrSku
  }
  properties: {
    adminUserEnabled: false
    // Scope permissions per repository instead of using the legacy registry-wide roles.
    roleAssignmentMode: 'AbacRepositoryPermissions'
  }
}

resource userRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for roleId in userRoleIds: {
  scope: registry
  name: guid(registry.id, userPrincipalId, roleId)
  properties: {
    principalId: userPrincipalId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleId)
  }
}]

resource webAppRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for roleId in webAppRoleIds: {
  scope: registry
  name: guid(registry.id, webAppPrincipalId, roleId)
  properties: {
    principalId: webAppPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleId)
  }
}]

output name string = registry.name
output resourceId string = registry.id
output loginServer string = registry.properties.loginServer
