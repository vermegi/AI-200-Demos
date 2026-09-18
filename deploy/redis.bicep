targetScope = 'resourceGroup'

@description('Name of the Azure Managed Redis cluster.')
@minLength(1)
@maxLength(60)
param name string

@description('Azure region for the Azure Managed Redis cluster.')
param location string

@description('Object ID of the signed-in Microsoft Entra user that receives access to the Redis database.')
param userPrincipalId string

resource redis 'Microsoft.Cache/redisEnterprise@2025-07-01' = {
  name: name
  location: location
  sku: {
    name: 'Balanced_B0'
  }
  properties: {
    encryption: {}
    highAvailability: 'Enabled'
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

// RediSearch is enabled so the same database supports the vector-query exercise.
resource database 'Microsoft.Cache/redisEnterprise/databases@2025-07-01' = {
  parent: redis
  name: 'default'
  properties: {
    accessKeysAuthentication: 'Disabled'
    clientProtocol: 'Encrypted'
    clusteringPolicy: 'EnterpriseCluster'
    evictionPolicy: 'NoEviction'
    modules: [
      {
        name: 'RediSearch'
      }
    ]
    port: 10000
  }
}

resource accessAssignment 'Microsoft.Cache/redisEnterprise/databases/accessPolicyAssignments@2025-07-01' = {
  parent: database
  name: 'useraccess'
  properties: {
    accessPolicyName: 'default'
    user: {
      objectId: userPrincipalId
    }
  }
}

output name string = redis.name
output resourceId string = redis.id
output hostName string = redis.properties.hostName
output databaseName string = database.name
output databasePort int = database.properties.port
output accessAssignmentName string = accessAssignment.name
