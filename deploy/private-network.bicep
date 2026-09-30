targetScope = 'resourceGroup'

@description('Azure region for the virtual network and private endpoint.')
param location string

@description('Unique user hash used to derive resource names.')
param userHash string

@description('Resource ID of the web app to connect privately.')
param webAppResourceId string

@description('Default host name of the web app used by Azure Front Door.')
param webAppDefaultHostname string

@description('Name of the MCP Function App to integrate with the virtual network.')
@minLength(2)
@maxLength(60)
param functionAppName string

@description('Resource ID of the MCP Function App to connect privately.')
param functionAppResourceId string

@description('Default host name of the MCP Function App used by Azure Front Door.')
param functionAppDefaultHostname string

@description('Name of the storage account used by the MCP Function App.')
@minLength(3)
@maxLength(24)
param functionStorageAccountName string

@description('Resource ID of the storage account used by the MCP Function App.')
param functionStorageAccountResourceId string

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
var functionIntegrationSubnetName = 'function-integration'
var storagePrivateEndpointServices = [
  {
    groupId: 'blob'
    zoneName: 'privatelink.blob.${environment().suffixes.storage}'
  }
  {
    groupId: 'queue'
    zoneName: 'privatelink.queue.${environment().suffixes.storage}'
  }
  {
    groupId: 'table'
    zoneName: 'privatelink.table.${environment().suffixes.storage}'
  }
  {
    groupId: 'file'
    zoneName: 'privatelink.file.${environment().suffixes.storage}'
  }
]

resource functionApp 'Microsoft.Web/sites@2024-11-01' existing = {
  name: functionAppName
}

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
        name: functionIntegrationSubnetName
        properties: {
          addressPrefix: '10.1.0.0/24'
          delegations: [
            {
              name: 'web-serverfarms-delegation'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
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

resource functionAppVirtualNetworkIntegration 'Microsoft.Web/sites/networkConfig@2024-11-01' = {
  parent: functionApp
  name: 'virtualNetwork'
  properties: {
    subnetResourceId: virtualNetwork.properties.subnets[1].id
    swiftSupported: true
  }
}

resource storagePrivateDnsZones 'Microsoft.Network/privateDnsZones@2024-06-01' = [for service in storagePrivateEndpointServices: {
  name: service.zoneName
  location: 'global'
}]

resource storagePrivateDnsZoneLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (service, index) in storagePrivateEndpointServices: {
  parent: storagePrivateDnsZones[index]
  name: '${virtualNetwork.name}-${service.groupId}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}]

resource storagePrivateEndpoints 'Microsoft.Network/privateEndpoints@2025-01-01' = [for service in storagePrivateEndpointServices: {
  name: 'pe-${functionStorageAccountName}-${service.groupId}'
  location: location
  properties: {
    subnet: {
      id: virtualNetwork.properties.subnets[0].id
    }
    privateLinkServiceConnections: [
      {
        name: '${service.groupId}-storage-connection'
        properties: {
          privateLinkServiceId: functionStorageAccountResourceId
          groupIds: [
            service.groupId
          ]
        }
      }
    ]
  }
}]

resource storagePrivateEndpointDnsZoneGroups 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2025-01-01' = [for (service, index) in storagePrivateEndpointServices: {
  parent: storagePrivateEndpoints[index]
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: service.groupId
        properties: {
          privateDnsZoneId: storagePrivateDnsZones[index].id
        }
      }
    ]
  }
}]

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

resource functionFrontDoorOriginGroup 'Microsoft.Cdn/profiles/originGroups@2025-06-01' = {
  parent: frontDoorProfile
  name: 'functionapp-origin-group'
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

// Azure Front Door Premium creates a managed private endpoint request to this Function App.
resource functionFrontDoorOrigin 'Microsoft.Cdn/profiles/originGroups/origins@2025-06-01' = {
  parent: functionFrontDoorOriginGroup
  name: 'functionapp-private-origin'
  properties: {
    hostName: functionAppDefaultHostname
    originHostHeader: functionAppDefaultHostname
    httpPort: 80
    httpsPort: 443
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
    enforceCertificateNameCheck: true
    sharedPrivateLinkResource: {
      groupId: 'sites'
      privateLink: {
        id: functionAppResourceId
      }
      privateLinkLocation: location
      requestMessage: 'Azure Front Door Premium access to the MCP Function App'
    }
  }
}

resource functionFrontDoorRoute 'Microsoft.Cdn/profiles/afdEndpoints/routes@2025-06-01' = {
  parent: frontDoorEndpoint
  name: 'mcp-function-route'
  dependsOn: [
    functionFrontDoorOrigin
  ]
  properties: {
    enabledState: 'Enabled'
    originGroup: {
      id: functionFrontDoorOriginGroup.id
    }
    supportedProtocols: [
      'Https'
    ]
    patternsToMatch: [
      '/runtime/webhooks/mcp/*'
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
output privateEndpointSubnetName string = virtualNetwork.properties.subnets[0].name
output functionIntegrationSubnetName string = virtualNetwork.properties.subnets[1].name
output functionIntegrationSubnetResourceId string = virtualNetwork.properties.subnets[1].id
output aksSubnetName string = virtualNetwork.properties.subnets[2].name
output frontDoorProfile string = frontDoorProfile.name
output frontDoorEndpoint string = frontDoorEndpoint.name
output frontDoorHostname string = frontDoorEndpoint.properties.hostName
output frontDoorUrl string = 'https://${frontDoorEndpoint.properties.hostName}'
output mcpFrontDoorUrl string = 'https://${frontDoorEndpoint.properties.hostName}/runtime/webhooks/mcp'
