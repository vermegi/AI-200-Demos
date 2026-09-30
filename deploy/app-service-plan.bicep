targetScope = 'resourceGroup'

@description('Name of the App Service plan.')
@minLength(1)
@maxLength(60)
param name string

@description('Azure region for the App Service plan.')
param location string

@description('SKU name of the App Service plan.')
param skuName string

@description('Number of workers assigned to the App Service plan.')
param skuCapacity int = 1

resource appServicePlan 'Microsoft.Web/serverfarms@2024-11-01' = {
  name: name
  location: location
  kind: 'linux'
  sku: {
    name: skuName
    capacity: skuCapacity
  }
  properties: {
    // Required for Linux plans so the platform provisions Linux workers.
    reserved: true
    zoneRedundant: false
  }
}

output resourceId string = appServicePlan.id
output name string = appServicePlan.name
