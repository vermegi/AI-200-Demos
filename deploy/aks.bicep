targetScope = 'resourceGroup'

@description('Name of the AKS cluster.')
@minLength(1)
@maxLength(63)
param name string

@description('Azure region for the AKS cluster.')
param location string

@description('DNS prefix of the managed cluster.')
param dnsPrefix string

@description('Name of the virtual network holding the cluster subnet.')
param virtualNetworkName string

@description('Name of the subnet reserved for the AKS node pool.')
param subnetName string

@description('Name of the container registry the cluster pulls images from.')
param registryName string

@description('Name of the Microsoft Foundry account the workloads call.')
param foundryName string

@description('Name of the shared Log Analytics workspace collecting control plane logs.')
@minLength(4)
@maxLength(63)
param logAnalyticsWorkspaceName string

@description('Number of nodes the system node pool starts with and scales down to.')
@minValue(1)
@maxValue(10)
param minNodeCount int = 1

@description('Maximum number of nodes the cluster autoscaler may add to the system node pool.')
@minValue(1)
@maxValue(20)
param maxNodeCount int = 3

@description('VM size used by the system node pool. Needs a local temp disk so the OS disk can be ephemeral.')
param nodeVmSize string = 'Standard_D2ds_v5'

@description('Availability zones for the system node pool. Leave empty when the region or VM size offers no usable zones.')
param availabilityZones array = []

// Overlay pod and service ranges must stay outside the 10.0.0.0/8 virtual network address space.
var podCidr = '172.16.0.0/16'
var serviceCidr = '172.17.0.0/16'
var dnsServiceIp = '172.17.0.10'

// Built-in role definition IDs.
var repositoryReaderRoleId = 'b93aa761-3e63-49ed-ac28-beffa264f7ac'
var repositoryCatalogListerRoleId = 'bfdb9389-c9a5-478a-bb2f-ba9ca092c3c7'
var networkContributorRoleId = '4d97b98b-1d4f-4787-a291-c67834d212e7'
var cognitiveServicesOpenAiUserRoleId = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
var registryRoleIds = [
  repositoryReaderRoleId
  repositoryCatalogListerRoleId
]

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2025-01-01' existing = {
  name: virtualNetworkName

  resource aksSubnet 'subnets' existing = {
    name: subnetName
  }
}

resource registry 'Microsoft.ContainerRegistry/registries@2025-05-01-preview' existing = {
  name: registryName
}

resource foundry 'Microsoft.CognitiveServices/accounts@2025-09-01' existing = {
  name: foundryName
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource aks 'Microsoft.ContainerService/managedClusters@2026-05-01' = {
  name: name
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Base'
    tier: 'Free'
  }
  properties: {
    dnsPrefix: dnsPrefix
    enableRBAC: true
    disableLocalAccounts: false
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }
    autoUpgradeProfile: {
      upgradeChannel: 'patch'
      nodeOSUpgradeChannel: 'NodeImage'
    }
    autoScalerProfile: {
      'scale-down-delay-after-add': '10m'
      'scale-down-unneeded-time': '10m'
      expander: 'least-waste'
    }
    networkProfile: {
      networkPlugin: 'azure'
      // Overlay keeps pod IPs off the virtual network so the node subnet only needs node addresses.
      networkPluginMode: 'overlay'
      networkDataplane: 'cilium'
      networkPolicy: 'cilium'
      loadBalancerSku: 'standard'
      outboundType: 'loadBalancer'
      podCidr: podCidr
      serviceCidr: serviceCidr
      dnsServiceIP: dnsServiceIp
    }
    agentPoolProfiles: [
      {
        name: 'systempool'
        mode: 'System'
        osType: 'Linux'
        osSKU: 'AzureLinux'
        count: minNodeCount
        minCount: minNodeCount
        maxCount: maxNodeCount
        enableAutoScaling: true
        vmSize: nodeVmSize
        type: 'VirtualMachineScaleSets'
        osDiskType: 'Ephemeral'
        osDiskSizeGB: 64
        maxPods: 110
        vnetSubnetID: virtualNetwork::aksSubnet.id
        availabilityZones: empty(availabilityZones) ? null : availabilityZones
      }
    ]
  }
}

// The cluster identity manages load balancers and node NICs inside the pre-created subnet.
resource subnetRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: virtualNetwork::aksSubnet
  name: guid(virtualNetwork::aksSubnet.id, aks.id, networkContributorRoleId)
  properties: {
    principalId: aks.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', networkContributorRoleId)
  }
}

// The kubelet identity is what actually pulls images and requests tokens for the pods.
resource registryRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for roleId in registryRoleIds: {
  scope: registry
  name: guid(registry.id, aks.id, roleId)
  properties: {
    principalId: aks.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleId)
  }
}]

resource foundryRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: foundry
  name: guid(foundry.id, aks.id, cognitiveServicesOpenAiUserRoleId)
  properties: {
    principalId: aks.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesOpenAiUserRoleId)
  }
}

// Audit categories are left out on purpose because they dominate ingestion cost.
resource aksDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: aks
  name: 'send-to-log-analytics'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'kube-apiserver'
        enabled: true
      }
      {
        category: 'kube-controller-manager'
        enabled: true
      }
      {
        category: 'kube-scheduler'
        enabled: true
      }
      {
        category: 'cluster-autoscaler'
        enabled: true
      }
    ]
  }
}

output name string = aks.name
output resourceId string = aks.id
output oidcIssuerUrl string = aks.properties.oidcIssuerProfile.issuerURL
output kubeletIdentityObjectId string = aks.properties.identityProfile.kubeletidentity.objectId
output nodeResourceGroup string = aks.properties.nodeResourceGroup
