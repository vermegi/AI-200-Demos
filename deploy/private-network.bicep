targetScope = 'resourceGroup'

@description('Azure region for the virtual network and private endpoint.')
param location string

@description('Unique user hash used to derive resource names.')
param userHash string

@description('Resource ID of the web app to connect privately.')
param webAppResourceId string

@description('Default host name of the web app used by Azure Front Door.')
param webAppDefaultHostname string

@description('Name of the shared Log Analytics workspace collecting network diagnostics.')
@minLength(4)
@maxLength(63)
param logAnalyticsWorkspaceName string

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' existing = {
  name: logAnalyticsWorkspaceName
}

var virtualNetworkName = 'vnet-ai200-${userHash}'
var frontDoorProfileName = 'afd-docprocessor-${userHash}'
var frontDoorEndpointName = 'afd-docprocessor-${userHash}-${uniqueString(subscription().id, userHash)}'

// Owning this NSG keeps the subnet compliant, so the platform policy does not attach one that blocks load balancer ingress.
resource aksNetworkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2025-01-01' = {
  name: 'nsg-aks-${userHash}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowHttpInbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
        }
      }
    ]
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2025-01-01' = {
  name: virtualNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/8'
      ]
    }
    subnets: [
      {
        name: 'private-endpoints'
        properties: {
          addressPrefix: '10.0.0.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'aks'
        properties: {
          addressPrefix: '10.16.0.0/12'
          networkSecurityGroup: {
            id: aksNetworkSecurityGroup.id
          }
        }
      }
    ]
  }
}

resource frontDoorProfile 'Microsoft.Cdn/profiles@2025-06-01' = {
  name: frontDoorProfileName
  location: 'global'
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
}

resource frontDoorEndpoint 'Microsoft.Cdn/profiles/afdEndpoints@2025-06-01' = {
  parent: frontDoorProfile
  name: frontDoorEndpointName
  location: 'global'
  properties: {
    enabledState: 'Enabled'
  }
}

resource frontDoorOriginGroup 'Microsoft.Cdn/profiles/originGroups@2025-06-01' = {
  parent: frontDoorProfile
  name: 'webapp-origin-group'
  properties: {
    healthProbeSettings: {
      probePath: '/'
      probeRequestType: 'GET'
      probeProtocol: 'Https'
      probeIntervalInSeconds: 30
    }
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
  }
}

// Azure Front Door Premium creates a managed private endpoint request to this web app.
resource frontDoorOrigin 'Microsoft.Cdn/profiles/originGroups/origins@2025-06-01' = {
  parent: frontDoorOriginGroup
  name: 'webapp-private-origin'
  properties: {
    hostName: webAppDefaultHostname
    originHostHeader: webAppDefaultHostname
    httpPort: 80
    httpsPort: 443
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
    enforceCertificateNameCheck: true
    sharedPrivateLinkResource: {
      groupId: 'sites'
      privateLink: {
        id: webAppResourceId
      }
      privateLinkLocation: location
      requestMessage: 'Azure Front Door Premium access to the web app'
    }
  }
}

resource frontDoorRoute 'Microsoft.Cdn/profiles/afdEndpoints/routes@2025-06-01' = {
  parent: frontDoorEndpoint
  name: 'webapp-route'
  dependsOn: [
    frontDoorOrigin
  ]
  properties: {
    enabledState: 'Enabled'
    originGroup: {
      id: frontDoorOriginGroup.id
    }
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    forwardingProtocol: 'HttpsOnly'
    httpsRedirect: 'Enabled'
    linkToDefaultDomain: 'Enabled'
  }
}

resource virtualNetworkDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: virtualNetwork
  name: 'send-to-log-analytics'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

resource frontDoorDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: frontDoorProfile
  name: 'send-to-log-analytics'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

output virtualNetwork string = virtualNetwork.name
output aksSubnetName string = virtualNetwork.properties.subnets[1].name
output frontDoorProfile string = frontDoorProfile.name
output frontDoorEndpoint string = frontDoorEndpoint.name
output frontDoorHostname string = frontDoorEndpoint.properties.hostName
output frontDoorUrl string = 'https://${frontDoorEndpoint.properties.hostName}'
