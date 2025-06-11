param vmName string = 'syslogvm'  
param adminUsername string = 'azureuser'  
param deploymentTimestamp string = utcNow()  
  
var location = 'uksouth'  
var uniq = uniqueString(resourceGroup().id, vmName)  
  
// Networking  
var vnetName = '${vmName}-vnet'  
var subnetName = 'default'  
var subnetPrefix = '10.10.0.0/24'  
var nsgName = '${vmName}-nsg'  
var publicIpName = '${vmName}-pip'  
var nicName = '${vmName}-nic'  
  
var keyVaultName = toLower('${vmName}kv${uniq}')  
var adminPassword = base64(uniqueString(resourceGroup().id, vmName, deploymentTimestamp, adminUsername))  
  
// Monitoring  
var lawName = 'logws${uniq}'  


// User data: enables rsyslog with TLS, and unattended-upgrades  
var cloudInit = '''  
#cloud-config  
package_update: true  
package_upgrade: true  
packages:  
  - rsyslog-gnutls  
  - unattended-upgrades  
  - apt-listchanges
  - net-tools  
write_files:
  - path: /etc/rsyslog.d/99-tls.conf
    content: |
      module(load="imtcp"
        StreamDriver.Name="gtls"
        StreamDriver.Mode="1"
        StreamDriver.Authmode="x509/certvalid"
      )

      global(
        defaultNetstreamDriver="gtls"
        defaultNetstreamDriverCAFile="/etc/ssl/certs/ca-certificates.crt"
        defaultNetstreamDriverCertFile="/etc/rsyslog.d/syslog-cert.pem"
        defaultNetstreamDriverKeyFile="/etc/rsyslog.d/syslog-key.pem"
      )

      # start up listener at port 6514
      input(type="imtcp" port="6514")

  - path: /etc/apt/apt.conf.d/20auto-upgrades  
    content: |  
      APT::Periodic::Update-Package-Lists "1";  
      APT::Periodic::Unattended-Upgrade "1";  
runcmd:  
  - |  
    openssl req -x509 -nodes -days 1095 -newkey rsa:2048 -keyout /etc/rsyslog.d/syslog-key.pem -out /etc/rsyslog.d/syslog-cert.pem -subj "/CN=$(hostname)"  
    chmod 600 /etc/rsyslog.d/syslog-key.pem /etc/rsyslog.d/syslog-cert.pem  
    chown syslog:adm /etc/rsyslog.d/syslog-key.pem /etc/rsyslog.d/syslog-cert.pem  
    systemctl restart rsyslog  
    systemctl enable unattended-upgrades 
    apt-get install -y certbot 
'''  
  
resource law 'Microsoft.OperationalInsights/workspaces@2025-02-01' = {  
  name: lawName  
  location: location  
  properties: {  
    sku: {  
      name: 'PerGB2018'  
    }  
    retentionInDays: 30  
  }  
}  
  
resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {  
  name: keyVaultName  
  location: location  
  properties: {  
    sku: {  
      family: 'A'  
      name: 'standard'  
    }  
    tenantId: subscription().tenantId  
    accessPolicies: [  
      {  
        tenantId: subscription().tenantId  
        objectId: deployer().objectId
        permissions: {  
          secrets: [  
            'get'  
            'list'  
            'set'  
          ]  
        }  
      }  
    ]  
    enabledForDeployment: true  
    enabledForTemplateDeployment: true  
  }  
}  
  
// Save the VM password in Key Vault  
resource vmSecret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {  
  name: '${keyVault.name}/vmAdminPass'  
  properties: {  
    value: adminPassword  
  }  
  dependsOn: [  
    keyVault  
  ]  
}  
  
resource vnet 'Microsoft.Network/virtualNetworks@2022-07-01' = {  
  name: vnetName  
  location: location  
  properties: {  
    addressSpace: {  
      addressPrefixes: [ '10.10.0.0/16' ]  
    }  
    subnets: [  
      {  
        name: subnetName  
        properties: {  
          addressPrefix: subnetPrefix  
          networkSecurityGroup: {  
            id: nsg.id  
          }  
        }  
      }  
    ]  
  }  
}  
  
resource nsg 'Microsoft.Network/networkSecurityGroups@2022-07-01' = {  
  name: nsgName  
  location: location  
  properties: {  
    securityRules: [  
      {  
        name: 'Allow-SSH'  
        properties: {  
          priority: 1000  
          protocol: 'Tcp'  
          access: 'Allow'  
          direction: 'Inbound'  
          sourceAddressPrefix: '*'  
          sourcePortRange: '*'  
          destinationAddressPrefix: '*'  
          destinationPortRange: '22'  
        }  
      }  
      {  
        name: 'Allow-SyslogTLS'  
        properties: {  
          priority: 1010  
          protocol: 'Tcp'  
          access: 'Allow'  
          direction: 'Inbound'  
          sourceAddressPrefix: '*'  
          sourcePortRange: '*'  
          destinationAddressPrefix: '*'  
          destinationPortRange: '6514'  
        }  
      }  
      {  
        name: 'Deny-All-In'  
        properties: {  
          priority: 4096  
          protocol: '*'  
          access: 'Deny'  
          direction: 'Inbound'  
          sourceAddressPrefix: '*'  
          sourcePortRange: '*'  
          destinationAddressPrefix: '*'  
          destinationPortRange: '*'  
        }  
      }  
    ]  
  }  
}  
  
resource pip 'Microsoft.Network/publicIPAddresses@2024-07-01' = {  
  name: publicIpName  
  location: location  
  sku: {  
    name: 'Basic'  
  }  
  properties: {  
    publicIPAllocationMethod: 'Static'  
  }  
}  
  
resource nic 'Microsoft.Network/networkInterfaces@2022-07-01' = {  
  name: nicName  
  location: location  
  properties: {  
    ipConfigurations: [  
      {  
        name: 'ipconfig1'  
        properties: {  
          privateIPAllocationMethod: 'Static'  
          publicIPAddress: {  
            id: pip.id  
          }  
          subnet: {  
            id: vnet.properties.subnets[0].id  
          }  
        }  
      }  
    ]  
  }  
}  
  
resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {  
  name: vmName  
  location: location  
  properties: {  
    hardwareProfile: {  
      vmSize: 'Standard_B1s'  
    }  
    osProfile: {  
      computerName: vmName  
      adminUsername: adminUsername  
      adminPassword: adminPassword  
      linuxConfiguration: {  
        disablePasswordAuthentication: false  
      }  
      customData: base64(cloudInit)  
    }  
    storageProfile: {  
      imageReference: {  
        publisher: 'Canonical'  
        offer: 'ubuntu-24_04-lts'  
        sku: 'server'  
        version: 'latest'  
      }  
      osDisk: {  
        createOption: 'FromImage'  
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
      }  
    }  
  }  
  dependsOn: [  
    nic  
    keyVault  
  ]  
}  
  
// Enable VM Insights (via Azure Monitor agent) for disk/CPU/service monitoring  
resource vmExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {  
  parent: vm  
  name: 'AzureMonitorLinuxAgent'  
  location: location  
  properties: {  
    publisher: 'Microsoft.Azure.Monitor'  
    type: 'AzureMonitorLinuxAgent'  
    typeHandlerVersion: '1.0'  
    autoUpgradeMinorVersion: true  
    protectedSettings: {}  
    settings: {  
      workspaceId: law.properties.customerId  
    }  
  }  
  dependsOn: [ law ]  
}  
  
output vmLoginUsername string = adminUsername  
output vaultUri string = keyVault.properties.vaultUri  
output lawId string = law.id
output publicIpAddress string = pip.properties.ipAddress
