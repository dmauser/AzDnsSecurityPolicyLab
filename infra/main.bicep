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

@description('Azure Bastion host name.')
param bastionName string = 'bastion-dns-lab'

@description('Object ID of the deploying user/principal, used to grant Key Vault secret read access.')
param keyVaultAdminObjectId string

var tags = {
  Purpose: 'DNS-Security-Lab'
  Environment: 'Lab'
}

// Unique suffixes derived from the resource group to avoid naming collisions on redeploy
var storageAccountName = 'sadiag${uniqueString(resourceGroup().id)}'
var keyVaultName = 'kv-lab-${uniqueString(resourceGroup().id)}'

// VM password is randomly generated each deployment and stored in Key Vault.
// Format: 'Lab1!' prefix (satisfies all 4 complexity categories) + a GUID (36 chars of hex/hyphens)
// Total length: 41 chars — well within the 12-123 char Azure VM password requirement.
// @secure() ensures the value never appears in deployment outputs or logs.
@secure()
@description('Auto-generated VM admin password. Leave as default to be randomly generated on each deployment.')
param generatedVmPassword string = 'Lab1!${newGuid()}'

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

// Key Vault — stores the auto-generated VM password
// Soft delete is enabled (Azure default); purge protection is OFF so the lab can be cleanly removed.
// Soft delete retention set to 7 days (minimum) for lab convenience.
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enabledForTemplateDeployment: true
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: keyVaultAdminObjectId
        permissions: {
          secrets: ['get', 'list', 'set', 'delete']
        }
      }
    ]
  }
}

// Store the generated VM password as a Key Vault secret
resource kvSecretVmPassword 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'vm-admin-password'
  properties: {
    value: generatedVmPassword
  }
}

// Network Security Group (no inbound rules — VM access is via Bastion only)
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

// VM subnet with NSG association
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

// Network Interface — no public IP (access is via Bastion)
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

// Cloud-init config that ensures SSH password authentication is enabled and installs dnsutils (dig).
// Ubuntu 22.04 cloud-init disables password auth by default, which blocks Bastion login.
var cloudInitScript = '''
#cloud-config
ssh_pwauth: true
chpasswd:
  expire: false
packages:
  - dnsutils
'''

// Ubuntu 22.04 LTS VM — password from Key Vault, access via Azure Bastion
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
      adminPassword: generatedVmPassword
      customData: base64(cloudInitScript)
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

// Azure Bastion Developer SKU — free tier, browser-based SSH, no dedicated subnet or public IP required.
// The Developer SKU uses shared Azure infrastructure and only needs a reference to the VNet.
// NOTE: Developer SKU is available in most Azure regions. If deployment fails with a region error,
// set 'location' in main.bicepparam to one of: eastus, westus, eastus2, westeurope, northeurope,
// southeastasia, australiaeast, westus2, or check https://aka.ms/bastionsku for the latest list.
resource bastion 'Microsoft.Network/bastionHosts@2024-01-01' = {
  name: bastionName
  location: location
  tags: tags
  sku: {
    name: 'Developer'
  }
  properties: {
    virtualNetwork: {
      id: vnet.id
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

// Microsoft Sentinel — enabled on the Log Analytics workspace.
// Sentinel uses the SecurityInsights solution on top of the existing workspace.
// Cost: pay-per-GB ingested; first 31 days of a new workspace are free (10 GB/day).
resource sentinel 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'SecurityInsights(${logAnalyticsWorkspaceName})'
  location: location
  tags: tags
  plan: {
    name: 'SecurityInsights(${logAnalyticsWorkspaceName})'
    product: 'OMSGallery/SecurityInsights'
    promotionCode: ''
    publisher: 'Microsoft'
  }
  properties: {
    workspaceResourceId: logAnalyticsWorkspace.id
  }
}

output resourceGroupName string = resourceGroup().name
output vmName string = vm.name
output vmAdminUsername string = vmAdminUsername
output vnetName string = vnet.name
output bastionName string = bastion.name
output dnsSecurityPolicyName string = dnsSecurityPolicy.name
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
output blockedDomains string[] = domainList.properties.domains
output keyVaultName string = keyVault.name
// This output contains the KEY VAULT ITEM NAME (e.g. 'vm-admin-password'), not the secret value itself.
// The suppression below is intentional: the linter matches on the output name, not the value type.
#disable-next-line outputs-should-not-contain-secrets
output vmPasswordSecretName string = kvSecretVmPassword.name
output keyVaultUri string = keyVault.properties.vaultUri

