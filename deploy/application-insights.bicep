targetScope = 'resourceGroup'

@description('Name of the Application Insights component.')
@minLength(1)
@maxLength(255)
param name string

@description('Azure region for the Application Insights component.')
param location string

@description('Name of the Log Analytics workspace used by the component.')
param logAnalyticsWorkspaceName string

@description('Object ID of the signed-in user that receives the Monitoring Metrics Publisher role.')
param userPrincipalId string

var monitoringMetricsPublisherRoleId = '3913510d-42f4-4e42-8a64-420c390055eb'

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: name
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

resource metricsPublisherRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: applicationInsights
  name: guid(applicationInsights.id, userPrincipalId, monitoringMetricsPublisherRoleId)
  properties: {
    principalId: userPrincipalId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringMetricsPublisherRoleId)
  }
}

output name string = applicationInsights.name
output resourceId string = applicationInsights.id
output connectionString string = applicationInsights.properties.ConnectionString
