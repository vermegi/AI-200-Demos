targetScope = 'resourceGroup'

@description('Globally unique name of the Key Vault.')
@minLength(3)
@maxLength(24)
param name string

@description('Azure region for the Key Vault.')
param location string
@description('Name of the user-assigned managed identity used by the AKS Key Vault client pod.')
param clientIdentityName string

@description('OIDC issuer URL of the AKS cluster the workload identity federates with.')
param aksOidcIssuerUrl string

@description('Object ID of the signed-in user that receives the Key Vault Secrets Officer role.')
param userPrincipalId string

@description('Name of the virtual network hosting the private endpoint subnet.')
param virtualNetworkName string

@description('Name of the subnet that receives the Key Vault private endpoint.')
param privateEndpointSubnetName string

@description('Sample OpenAI API key stored in the vault.')
@secure()
param openaiApiKey string

@description('Sample Cosmos DB connection string stored in the vault.')
@secure()
param cosmosDbConnectionString string

var keyVaultSecretsOfficerRoleId = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
var kubernetesNamespace = 'default'
var kubernetesServiceAccountName = 'keyvault-client-sa'
var privateDnsZoneName = 'privatelink.vaultcore.azure.net'

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2025-01-01' existing = {
  name: virtualNetworkName

  resource privateEndpointSubnet 'subnets' existing = {
    name: privateEndpointSubnetName
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2026-02-01' = {
  name: name
  location: location
  properties: {
    enableRbacAuthorization: true
    enableSoftDelete: true
    // Only reachable over the private endpoint, e.g. from the AKS subnet.
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
  }
}

resource clientIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2025-01-31-preview' = {
  name: clientIdentityName
  location: location
}

resource federatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2025-01-31-preview' = {
  parent: clientIdentity
  name: 'fc-keyvault-client'
  properties: {
    issuer: aksOidcIssuerUrl
    subject: 'system:serviceaccount:${kubernetesNamespace}:${kubernetesServiceAccountName}'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
}

resource clientSecretsOfficerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, clientIdentity.id, keyVaultSecretsOfficerRoleId)
  properties: {
    principalId: clientIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsOfficerRoleId)
  }
}

resource secretsOfficerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, userPrincipalId, keyVaultSecretsOfficerRoleId)
  properties: {
    principalId: userPrincipalId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsOfficerRoleId)
  }
}

resource openaiApiKeySecret 'Microsoft.KeyVault/vaults/secrets@2026-02-01' = {
  parent: keyVault
  name: 'openai-api-key'
  properties: {
    contentType: 'application/x-api-key'
    value: openaiApiKey
  }
  tags: {
    environment: 'development'
    service: 'openai'
  }
  dependsOn: [
    secretsOfficerRoleAssignment
  ]
}

resource cosmosDbConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2026-02-01' = {
  parent: keyVault
  name: 'cosmosdb-connection-string'
  properties: {
    contentType: 'application/x-connection-string'
    value: cosmosDbConnectionString
  }
  tags: {
    environment: 'development'
    service: 'cosmosdb'
  }
  dependsOn: [
    secretsOfficerRoleAssignment
  ]
}

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: privateDnsZoneName
  location: 'global'
}

resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: privateDnsZone
  name: '${virtualNetworkName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2025-01-01' = {
  name: 'pe-${name}'
  location: location
  properties: {
    subnet: {
      id: virtualNetwork::privateEndpointSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'keyvault-connection'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
}

resource privateEndpointDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2025-01-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'vaultcore'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

output name string = keyVault.name
output uri string = keyVault.properties.vaultUri
output clientIdentityName string = clientIdentity.name
output clientIdentityClientId string = clientIdentity.properties.clientId
output clientIdentityPrincipalId string = clientIdentity.properties.principalId
