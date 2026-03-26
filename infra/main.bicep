targetScope = 'resourceGroup'

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Virtual network name.')
param vnetName string = 'vnet-dns-lab'

@description('VNet address space.')
param vnetAddressSpace string = '10.0.0.0/16'

@description('Subnet name.')
param subnetName string = 'subnet-vm'

@description('Subnet address prefix.')
param subnetAddressPrefix string = '10.0.1.0/24'

@description('VM name.')
param vmName string = 'vm-ubuntu-lab'

@description('VM SKU size.')
param vmSize string = 'Standard_B1s'

@description('VM administrator username.')
param vmAdminUsername string = 'azureuser'

@description('VM administrator password. Must be 12-123 characters with uppercase, lowercase, number, and special character.')
@secure()
@minLength(12)
@maxLength(123)
param vmAdminPassword string

@description('Network Security Group name.')
param nsgName string = 'nsg-vm-lab'

@description('Log Analytics workspace name.')
param logAnalyticsWorkspaceName string = 'law-dns-security-lab'

@description('DNS security policy name.')
param dnsSecurityPolicyName string = 'dns-security-policy-lab'

@description('DNS domain list name.')
param domainListName string = 'malicious-domains-list'

@description('DNS security rule name.')
param securityRuleName string = 'block-malicious-rule'

@description('VNet link name for DNS policy.')
param vnetLinkName string = 'vnet-link-lab'

var tags = {
  Purpose: 'DNS-Security-Lab'
  Environment: 'Lab'
}

// Storage account name: 'sadiag' (6) + uniqueString (13) = 19 chars, all lowercase alphanumeric
var storageAccountName = 'sadiag${uniqueString(resourceGroup().id)}'

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Network Security Group (no inbound rules - internal access only via serial console)
resource nsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {}
}

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressSpace]
    }
  }
}

// Subnet with NSG association
resource subnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' = {
  parent: vnet
  name: subnetName
  properties: {
    addressPrefix: subnetAddressPrefix
    networkSecurityGroup: {
      id: nsg.id
    }
  }
}

// Storage Account for VM boot diagnostics
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

// Network Interface without public IP
resource nic 'Microsoft.Network/networkInterfaces@2024-01-01' = {
  name: '${vmName}-nic'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnet.id
          }
        }
      }
    ]
  }
}

// Ubuntu 22.04 LTS VM (no public IP — access via Azure Portal serial console)
resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: vmName
  location: location
  tags: tags
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: vmAdminUsername
      adminPassword: vmAdminPassword
      linuxConfiguration: {
        disablePasswordAuthentication: false
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        storageUri: storageAccount.properties.primaryEndpoints.blob
      }
    }
  }
}

// DNS Resolver Domain List with malicious domains to block
resource domainList 'Microsoft.Network/dnsResolverDomainLists@2023-07-01-preview' = {
  name: domainListName
  location: location
  tags: tags
  properties: {
    domains: [
      'malicious.contoso.com.'
      'exploit.adatum.com.'
    ]
  }
}

// DNS Resolver Policy
resource dnsSecurityPolicy 'Microsoft.Network/dnsResolverPolicies@2023-07-01-preview' = {
  name: dnsSecurityPolicyName
  location: location
  tags: tags
}

// DNS Security Rule — Block action at priority 100
resource securityRule 'Microsoft.Network/dnsResolverPolicies/dnsSecurityRules@2023-07-01-preview' = {
  parent: dnsSecurityPolicy
  name: securityRuleName
  location: location
  properties: {
    priority: 100
    action: {
      actionType: 'Block'
    }
    dnsResolverDomainLists: [
      {
        id: domainList.id
      }
    ]
    dnsSecurityRuleState: 'Enabled'
  }
}

// Virtual Network Link — associates VNet with the DNS security policy
resource vnetLink 'Microsoft.Network/dnsResolverPolicies/virtualNetworkLinks@2023-07-01-preview' = {
  parent: dnsSecurityPolicy
  name: vnetLinkName
  location: location
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
  }
}

// Diagnostic Settings — send DNS response logs to Log Analytics
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'dns-policy-diagnostics'
  scope: dnsSecurityPolicy
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'DnsResponse'
        enabled: true
      }
    ]
  }
}

output resourceGroupName string = resourceGroup().name
output vmName string = vm.name
output vmAdminUsername string = vmAdminUsername
output vnetName string = vnet.name
output dnsSecurityPolicyName string = dnsSecurityPolicy.name
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
output blockedDomains string[] = domainList.properties.domains
