using './main.bicep'

param location = 'eastus2'
param vnetName = 'vnet-dns-lab'
param vnetAddressSpace = '10.0.0.0/16'
param subnetName = 'subnet-vm'
param subnetAddressPrefix = '10.0.1.0/24'
param vmName = 'vm-ubuntu-lab'
param vmSize = 'Standard_B1s'
param vmAdminUsername = 'azureuser'
param nsgName = 'nsg-vm-lab'
param logAnalyticsWorkspaceName = 'law-dns-security-lab'
param dnsSecurityPolicyName = 'dns-security-policy-lab'
param domainListName = 'malicious-domains-list'
param securityRuleName = 'block-malicious-rule'
param vnetLinkName = 'vnet-link-lab'
param bastionName = 'bastion-dns-lab'
// keyVaultAdminObjectId has no default in main.bicep (required param).
// The placeholder below satisfies BCP258 file validation.
// It is always overridden at deploy time by the --parameters argument in the deployment scripts.
param keyVaultAdminObjectId = 'override-at-deploy-time'
