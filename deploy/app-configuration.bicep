targetScope = 'resourceGroup'

@description('Globally unique name of the App Configuration store.')
@minLength(5)
@maxLength(50)
param name string

@description('Azure region for the App Configuration store.')
param location string

@description('Object ID of the signed-in user that receives the App Configuration Data Owner role.')
param userPrincipalId string

@description('Name of the user-assigned managed identity federated with the AKS workload service account.')
param clientIdentityName string

@description('Vault URI used to construct the App Configuration Key Vault reference.')
param keyVaultUri string

var appConfigurationDataOwnerRoleId = '5ae67dd6-50cb-40e7-96ff-dc2bfa4b606b'
var keyVaultReferenceContentType = 'application/vnd.microsoft.appconfig.keyvaultref+json;charset=utf-8'

resource clientIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2025-01-31-preview' existing = {
  name: clientIdentityName
}

resource appConfiguration 'Microsoft.AppConfiguration/configurationStores@2024-06-01' = {
  name: name
  location: location
  sku: {
    name: 'Standard'
  }
}

resource dataOwnerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: appConfiguration
  name: guid(appConfiguration.id, userPrincipalId, appConfigurationDataOwnerRoleId)
  properties: {
    principalId: userPrincipalId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', appConfigurationDataOwnerRoleId)
  }
}

resource clientDataOwnerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: appConfiguration
  name: guid(appConfiguration.id, clientIdentity.id, appConfigurationDataOwnerRoleId)
  properties: {
    principalId: clientIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', appConfigurationDataOwnerRoleId)
  }
}

resource openAiEndpoint 'Microsoft.AppConfiguration/configurationStores/keyValues@2024-06-01' = {
  parent: appConfiguration
  name: 'OpenAI:Endpoint'
  properties: {
    value: 'https://my-openai.openai.azure.com/'
  }
}

resource openAiDeploymentName 'Microsoft.AppConfiguration/configurationStores/keyValues@2024-06-01' = {
  parent: appConfiguration
  name: 'OpenAI:DeploymentName'
  properties: {
    value: 'gpt-4o'
  }
}

resource pipelineBatchSize 'Microsoft.AppConfiguration/configurationStores/keyValues@2024-06-01' = {
  parent: appConfiguration
  name: 'Pipeline:BatchSize'
  properties: {
    value: '10'
  }
}

resource pipelineRetryCount 'Microsoft.AppConfiguration/configurationStores/keyValues@2024-06-01' = {
  parent: appConfiguration
  name: 'Pipeline:RetryCount'
  properties: {
    value: '3'
  }
}

resource productionPipelineBatchSize 'Microsoft.AppConfiguration/configurationStores/keyValues@2024-06-01' = {
  parent: appConfiguration
  name: 'Pipeline:BatchSize$Production'
  properties: {
    value: '200'
  }
}

resource productionPipelineRetryCount 'Microsoft.AppConfiguration/configurationStores/keyValues@2024-06-01' = {
  parent: appConfiguration
  name: 'Pipeline:RetryCount$Production'
  properties: {
    value: '5'
  }
}

resource sentinel 'Microsoft.AppConfiguration/configurationStores/keyValues@2024-06-01' = {
  parent: appConfiguration
  name: 'Sentinel'
  properties: {
    value: '1'
  }
}

resource openAiApiKeyReference 'Microsoft.AppConfiguration/configurationStores/keyValues@2024-06-01' = {
  parent: appConfiguration
  name: 'OpenAI:ApiKey'
  properties: {
    contentType: keyVaultReferenceContentType
    value: format('{{"uri":"{0}secrets/openai-api-key"}}', keyVaultUri)
  }
}

output name string = appConfiguration.name
output endpoint string = appConfiguration.properties.endpoint
