targetScope = 'resourceGroup'

@description('Name of the Log Analytics workspace shared by all resources in the deployment.')
@minLength(4)
@maxLength(63)
param name string

@description('Azure region for the Log Analytics workspace.')
param location string

@description('Number of days log data is retained.')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' = {
  name: name
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
  }
}

output name string = logAnalyticsWorkspace.name
output resourceId string = logAnalyticsWorkspace.id
output customerId string = logAnalyticsWorkspace.properties.customerId
