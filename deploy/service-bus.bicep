targetScope = 'resourceGroup'

@description('Name of the Azure Service Bus namespace.')
@minLength(6)
@maxLength(50)
param name string

@description('Azure region for the Service Bus namespace.')
param location string

@description('Object ID of the signed-in user that receives the Service Bus Data Owner role.')
param userPrincipalId string

var queueName = 'inference-requests'
var topicName = 'inference-results'
var notificationsSubscriptionName = 'notifications'
var highPrioritySubscriptionName = 'high-priority'
var highPriorityRuleName = 'high-priority-filter'
var serviceBusDataOwnerRoleId = '090c5cfd-751d-490a-894a-3ce6f1109419'

resource namespace 'Microsoft.ServiceBus/namespaces@2024-01-01' = {
  name: name
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

resource queue 'Microsoft.ServiceBus/namespaces/queues@2024-01-01' = {
  parent: namespace
  name: queueName
  properties: {
    maxDeliveryCount: 5
    deadLetteringOnMessageExpiration: true
  }
}

resource topic 'Microsoft.ServiceBus/namespaces/topics@2024-01-01' = {
  parent: namespace
  name: topicName
}

resource notificationsSubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2024-01-01' = {
  parent: topic
  name: notificationsSubscriptionName
}

resource highPrioritySubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2024-01-01' = {
  parent: topic
  name: highPrioritySubscriptionName
}

resource highPriorityRule 'Microsoft.ServiceBus/namespaces/topics/subscriptions/rules@2024-01-01' = {
  parent: highPrioritySubscription
  name: highPriorityRuleName
  properties: {
    filterType: 'SqlFilter'
    sqlFilter: {
      sqlExpression: 'priority = \'high\''
    }
  }
}

resource dataOwnerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: namespace
  name: guid(namespace.id, userPrincipalId, serviceBusDataOwnerRoleId)
  properties: {
    principalId: userPrincipalId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', serviceBusDataOwnerRoleId)
  }
}

output name string = namespace.name
output resourceId string = namespace.id
output fullyQualifiedDomainName string = '${namespace.name}.servicebus.windows.net'
output queueName string = queue.name
output topicName string = topic.name
output notificationsSubscriptionName string = notificationsSubscription.name
output highPrioritySubscriptionName string = highPrioritySubscription.name
output highPriorityRuleName string = highPriorityRule.name
