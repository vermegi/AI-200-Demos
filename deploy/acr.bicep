targetScope = 'subscription'

@description('Unique user hash used to derive the resource group and container registry names.')
@minLength(2)
@maxLength(47)
param userHash string

@description('Azure region for the resource group and container registry.')
param location string = 'francecentral'

@description('Principal ID that receives repository permissions on the container registry. Leave empty to skip role assignments.')
param principalId string = ''

@description('Principal type for the repository role assignments.')
@allowed([
  'Device'
  'ForeignGroup'
  'Group'
  'ServicePrincipal'
  'User'
])
param principalType string = 'User'

var resourceGroupName = 'rg-AI200-${userHash}'
var registryName = 'acr${userHash}'
var repositoryRoles = [
  'Container Registry Repository Reader'
  'Container Registry Repository Catalog Lister'
  'Container Registry Repository Writer'
]
var repositoryRoleAssignments = [for role in repositoryRoles: {
  principalId: principalId
  principalType: principalType
  roleDefinitionIdOrName: role
}]
var roleAssignments = empty(principalId) ? [] : repositoryRoleAssignments

resource resourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: resourceGroupName
  location: location
}

module registry 'br/public:avm/res/container-registry/registry:0.13.0' = {
  scope: az.resourceGroup(resourceGroup.name)
  params: {
    name: registryName
    location: location
    acrSku: 'Basic'
    roleAssignmentMode: 'AbacRepositoryPermissions'
    roleAssignments: roleAssignments
  }
}

output resourceGroup string = resourceGroup.name
output registry string = registry.outputs.name
output registryId string = registry.outputs.resourceId
output loginServer string = registry.outputs.loginServer
