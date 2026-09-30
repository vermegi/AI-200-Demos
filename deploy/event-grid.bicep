targetScope = 'resourceGroup'

@description('Name of the Event Grid namespace.')
@minLength(3)
@maxLength(50)
param name string

@description('Azure region for the Event Grid namespace.')
param location string

@description('Object ID of the signed-in user that receives the Event Grid roles.')
param userPrincipalId string

var topicName = 'moderation-events'
var dataSenderRoleDefinitionId = 'd5a91429-5739-47e2-a06b-3470a27159e7'
var dataReceiverRoleDefinitionId = '78cbd9e7-9798-4e2e-9b5a-547d9ebb31fb'

resource namespace 'Microsoft.EventGrid/namespaces@2025-02-15' = {
  name: name
  location: location
  sku: {
    name: 'Standard'
    capacity: 1
  }
}

resource topic 'Microsoft.EventGrid/namespaces/topics@2025-02-15' = {
  parent: namespace
  name: topicName
  properties: {
    inputSchema: 'CloudEventSchemaV1_0'
    publisherType: 'Custom'
    eventRetentionInDays: 1
  }
}

resource flaggedSubscription 'Microsoft.EventGrid/namespaces/topics/eventSubscriptions@2025-02-15' = {
  parent: topic
  name: 'sub-flagged'
  properties: {
    eventDeliverySchema: 'CloudEventSchemaV1_0'
    deliveryConfiguration: {
      deliveryMode: 'Queue'
      queue: {
        maxDeliveryCount: 10
        receiveLockDurationInSeconds: 60
        eventTimeToLive: 'P1D'
      }
    }
    filtersConfiguration: {
      includedEventTypes: [
        'com.contoso.ai.ContentFlagged'
      ]
    }
  }
}

resource approvedSubscription 'Microsoft.EventGrid/namespaces/topics/eventSubscriptions@2025-02-15' = {
  parent: topic
  name: 'sub-approved'
  properties: {
    eventDeliverySchema: 'CloudEventSchemaV1_0'
    deliveryConfiguration: {
      deliveryMode: 'Queue'
      queue: {
        maxDeliveryCount: 10
        receiveLockDurationInSeconds: 60
        eventTimeToLive: 'P1D'
      }
    }
    filtersConfiguration: {
      includedEventTypes: [
        'com.contoso.ai.ContentApproved'
      ]
    }
  }
}

resource allEventsSubscription 'Microsoft.EventGrid/namespaces/topics/eventSubscriptions@2025-02-15' = {
  parent: topic
  name: 'sub-all-events'
  properties: {
    eventDeliverySchema: 'CloudEventSchemaV1_0'
    deliveryConfiguration: {
      deliveryMode: 'Queue'
      queue: {
        maxDeliveryCount: 10
        receiveLockDurationInSeconds: 60
        eventTimeToLive: 'P1D'
      }
    }
  }
}

resource dataSenderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: namespace
  name: guid(namespace.id, userPrincipalId, dataSenderRoleDefinitionId)
  properties: {
    principalId: userPrincipalId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', dataSenderRoleDefinitionId)
  }
}

resource dataReceiverRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: namespace
  name: guid(namespace.id, userPrincipalId, dataReceiverRoleDefinitionId)
  properties: {
    principalId: userPrincipalId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', dataReceiverRoleDefinitionId)
  }
}

output name string = namespace.name
output resourceId string = namespace.id
output topicName string = topic.name
output flaggedSubscriptionName string = flaggedSubscription.name
output approvedSubscriptionName string = approvedSubscription.name
output allEventsSubscriptionName string = allEventsSubscription.name
output hostname string = namespace.properties.topicsConfiguration.hostname
output endpoint string = 'https://${namespace.properties.topicsConfiguration.hostname}'
