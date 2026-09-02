targetScope = 'resourceGroup'

@description('Name of the Azure Cosmos DB for NoSQL account.')
@minLength(3)
@maxLength(44)
param name string

@description('Azure region for the Cosmos DB account.')
param location string

@description('Name of the SQL database holding the RAG chunks.')
param databaseName string = 'ragstore'

@description('Name of the container holding the RAG chunks.')
param containerName string = 'chunks'

@description('Name of the SQL database holding the vector search documents.')
param vectorDatabaseName string = 'vectorstore'

@description('Name of the container holding the vector search documents.')
param vectorContainerName string = 'vectors'

@description('Number of dimensions of the embeddings stored in the vector container.')
@minValue(2)
@maxValue(4096)
param vectorDimensions int = 256

@description('Partition key path of the containers.')
param partitionKeyPath string = '/documentId'

@description('Name of the user-assigned managed identity used by the AKS client pod.')
param clientIdentityName string

@description('OIDC issuer URL of the AKS cluster the workload identity federates with.')
param aksOidcIssuerUrl string

@description('Kubernetes namespace of the service account used by the client pod.')
param kubernetesNamespace string = 'default'

@description('Kubernetes service account used by the RAG client pod.')
param kubernetesServiceAccountName string = 'cosmos-client-sa'

@description('Kubernetes service account used by the vector search client pod.')
param vectorKubernetesServiceAccountName string = 'vector-client-sa'

@description('Name of the virtual network hosting the private endpoint subnet.')
param virtualNetworkName string

@description('Name of the subnet that receives the Cosmos DB private endpoint.')
param privateEndpointSubnetName string

@description('Principal ID of the developer that manages and queries the account. Leave empty to skip the role assignments.')
param userPrincipalId string = ''

@description('Name of the shared Log Analytics workspace collecting Cosmos DB diagnostics.')
@minLength(4)
@maxLength(63)
param logAnalyticsWorkspaceName string

// Built-in role definition IDs.
var contributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
var privateDnsZoneName = 'privatelink.documents.azure.com'

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2025-01-01' existing = {
  name: virtualNetworkName

  resource privateEndpointSubnet 'subnets' existing = {
    name: privateEndpointSubnetName
  }
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2025-05-01-preview' = {
  name: name
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    // Recent API versions expect capacityMode instead of the EnableServerless capability.
    capacityMode: 'Serverless'
    capabilities: [
      {
        name: 'EnableNoSQLVectorSearch'
      }
    ]
    // The clients authenticate with Entra ID through DefaultAzureCredential, so account keys stay unusable.
    disableLocalAuth: true
    // Kept enabled so the demo client can also run from a developer machine next to the private endpoint.
    publicNetworkAccess: 'Enabled'
    networkAclBypass: 'AzureServices'
  }
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2025-05-01-preview' = {
  parent: cosmos
  name: databaseName
  properties: {
    resource: {
      id: databaseName
    }
  }
}

resource container 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2025-05-01-preview' = {
  parent: database
  name: containerName
  properties: {
    resource: {
      id: containerName
      partitionKey: {
        paths: [
          partitionKeyPath
        ]
        kind: 'Hash'
      }
    }
  }
}

resource vectorDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2025-05-01-preview' = {
  parent: cosmos
  name: vectorDatabaseName
  properties: {
    resource: {
      id: vectorDatabaseName
    }
  }
}

resource vectorContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2025-05-01-preview' = {
  parent: vectorDatabase
  name: vectorContainerName
  properties: {
    resource: {
      id: vectorContainerName
      partitionKey: {
        paths: [
          partitionKeyPath
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
        includedPaths: [
          {
            path: '/*'
          }
        ]
        // The embeddings are served by the diskANN index, so they stay out of the standard index.
        excludedPaths: [
          {
            path: '/embedding/*'
          }
        ]
        vectorIndexes: [
          {
            path: '/embedding'
            type: 'diskANN'
          }
        ]
      }
      vectorEmbeddingPolicy: {
        vectorEmbeddings: [
          {
            path: '/embedding'
            dataType: 'float32'
            distanceFunction: 'cosine'
            dimensions: vectorDimensions
          }
        ]
      }
    }
  }
}

// Identity the AKS client pod exchanges its service account token for.
resource clientIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2025-01-31-preview' = {
  name: clientIdentityName
  location: location
}

resource federatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2025-01-31-preview' = {
  parent: clientIdentity
  name: 'fc-cosmos-client'
  properties: {
    issuer: aksOidcIssuerUrl
    subject: 'system:serviceaccount:${kubernetesNamespace}:${kubernetesServiceAccountName}'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
}

// The vector search client reuses the same identity, so it needs its own subject mapping.
resource vectorFederatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2025-01-31-preview' = {
  parent: clientIdentity
  name: 'fc-vector-client'
  properties: {
    issuer: aksOidcIssuerUrl
    subject: 'system:serviceaccount:${kubernetesNamespace}:${vectorKubernetesServiceAccountName}'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
  dependsOn: [
    federatedCredential
  ]
}

resource clientDataContributor 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2025-05-01-preview' = {
  parent: cosmos
  name: guid(cosmos.id, clientIdentity.id, 'data-contributor')
  properties: {
    principalId: clientIdentity.properties.principalId
    roleDefinitionId: '${cosmos.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'
    scope: cosmos.id
  }
}

resource userDataContributor 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2025-05-01-preview' = if (!empty(userPrincipalId)) {
  parent: cosmos
  name: guid(cosmos.id, userPrincipalId, 'data-contributor')
  properties: {
    principalId: userPrincipalId
    roleDefinitionId: '${cosmos.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'
    scope: cosmos.id
  }
}

// Control plane access so the developer can manage databases and containers from the CLI.
resource userContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(userPrincipalId)) {
  scope: cosmos
  name: guid(cosmos.id, userPrincipalId, contributorRoleId)
  properties: {
    principalId: userPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleId)
  }
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
        name: 'cosmos-sql-connection'
        properties: {
          privateLinkServiceId: cosmos.id
          groupIds: [
            'Sql'
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
        name: 'documents'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

resource cosmosDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: cosmos
  name: 'send-to-log-analytics'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'DataPlaneRequests'
        enabled: true
      }
      {
        category: 'ControlPlaneRequests'
        enabled: true
      }
    ]
  }
}

output name string = cosmos.name
output resourceId string = cosmos.id
output endpoint string = cosmos.properties.documentEndpoint
output databaseName string = database.name
output containerName string = container.name
output vectorDatabaseName string = vectorDatabase.name
output vectorContainerName string = vectorContainer.name
output clientIdentityName string = clientIdentity.name
output clientIdentityClientId string = clientIdentity.properties.clientId
output clientIdentityPrincipalId string = clientIdentity.properties.principalId
output privateEndpointName string = privateEndpoint.name
