targetScope = 'resourceGroup'

@description('Name of the Microsoft Foundry (AI Services) account.')
@minLength(2)
@maxLength(64)
param name string

@description('Name of the Microsoft Foundry project.')
@minLength(2)
@maxLength(64)
param projectName string

@description('Azure region for the Microsoft Foundry account.')
param location string

@description('Name of the model deployed to the Microsoft Foundry account.')
param modelName string = 'gpt-5-mini'

@description('Version of the deployed model.')
param modelVersion string = '2025-08-07'

@description('Provisioned throughput units assigned to the model deployment.')
param modelCapacity int = 1

resource foundry 'Microsoft.CognitiveServices/accounts@2025-09-01' = {
  name: name
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    // Required so the account can be reached on its own endpoint and used with Entra ID tokens.
    customSubDomainName: name
    allowProjectManagement: true
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
  }
}

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-09-01' = {
  parent: foundry
  name: projectName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
}

resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-09-01' = {
  parent: foundry
  name: modelName
  // The account only accepts one write operation at a time, so the project must finish first.
  dependsOn: [
    foundryProject
  ]
  sku: {
    name: 'GlobalStandard'
    capacity: modelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
  }
}

output name string = foundry.name
output resourceId string = foundry.id
output endpoint string = foundry.properties.endpoint
output projectName string = foundryProject.name
output modelDeploymentName string = modelDeployment.name
