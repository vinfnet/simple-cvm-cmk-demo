# Quick & dirty demo PowerShell script that makes Azure PowerShell module calls to do most of the heavy-lifting for creating a CVM with a CMK
# Simon Gallagher, ACC Product Group
# Use at your own risk, no warranties implied
# based on https://learn.microsoft.com/en-us/azure/confidential-computing/quick-create-confidential-vm-azure-cli
# Clone this script & adjust the values in <BRACKETS> to suit your environment
# You'll need to have the latest Azure PowerShell module installed as older versions don't have the parameters for AKV & ACC (update-module -force)

# TODO
# - add error handling 
# - convert from mix of azc cli and PowerShell to all PowerShell (90% done, copilot gets 65% of the credit for this), can't create disk encryption set /or/ VM nativeliy in PowerShell yet as they don't support some of the parameters yet, az cli does however
# - add command line parameters (vmname) & check for name >15 chars + abort
# - confirm at script start the name of the subscription you're targeting
# - investigate vm creds into AKV rather than plaintext in script

# Set PowerShell variables to use in the script
$subsid = "<YOUR SUBSCRIPTION ID>"
$basename = "<YOUR VALUE>" # keep this unique and short < 15 chars as it will determine the length of the VM name, various objects will be created based on this e.g. if you use MyCMV1 you'll get MyCVM1akv, MyCVM1des, MyCVM1-cmk-key, MyCVM1vnet, MyCVM1vnet-ip, MyCVM1vnet-bastion named objects
$vmusername = "<YOUR USERNAME>" # username for the VM, must be _local for CVM
$vmadminpassword = "<YOUR ADMIN PASSWORD>" # password for the VM, must be 12 chars or more, complex, and meet Azure password requirements
$ownername = "<YOUR ALIAS>" #used to set the owner tag value on the resouce group
$resgrp =  $basename ; # nmame of the resource group where all resources will be created, copied from $basename
$akvname = $basename + "akv"
$desname = $basename + "des"
$keyname = $basename + "-cmk-key"
$vmname = $basename # name of the VM, copied from $basename
$vnetname = $vmname + "vnet"
$bastionname = $vnetname + "-bastion"
$vnetipname = $vnetname + "-ip"
$subnetName = "AzureBastionSubnet" # don't change this


#if not already logged in, use Connect-AzAccount -SubscriptionId $subsid -Tenant <YOUR ENTRA TENANT ID>
# Set your Azure subscription
Set-AzContext -SubscriptionId $subsid

# Create a resource group and tag it with the owner (so all resources inherit tag)
New-AzResourceGroup -Name $resgrp -Location "eastus" -Tag @{owner=$ownername}

# Create AKV premium instance, note it has purge protection enabled, but will only retain for _10_ days - adjust this for production usage! -enablesoftdelete is default now (-disablerbacauthorization _required_)
New-AzKeyVault -VaultName $akvname -ResourceGroupName $resgrp -Location "eastus" -Sku "premium" -EnablePurgeProtection -SoftDeleteRetentionInDays 10 -DisableRbacAuthorization

# Grab the CVM agent ID for your tenant
$cvmAgent = Get-AzADServicePrincipal -ApplicationId bf7b6499-ff71-4aa2-97a4-f372087be7f0

# Grant it ability to get keys from the AKV
Set-AzKeyVaultAccessPolicy -VaultName $akvname -ObjectId $cvmAgent.Id -PermissionsToKeys "get", "release"

start-sleep 10 # wait for the AKV policy to be created, it's async and takes a few seconds, otherwise following command can fail intermittently

# Create a CMK key in the AKV, note RSA-HSM
#translated $key = Add-AzKeyVaultKey -VaultName $akvname -Name $keyname -Destination "Software" -KeyType "RSA-HSM" -KeyOps @{'wrapKey','unwrapKey','get'}
#hacked up version of the above command to work in POSH
$key = Add-AzKeyVaultKey -VaultName $akvName -Name $keyname -Size 2048 -KeyOps wrapKey,unwrapKey -KeyType RSA -Destination HSM -Exportable -UseDefaultCVMPolicy;

# Find the key URL (https://<akvname>.vault.azure.net/keys/<keyname>/<keyversion>)
$keyVaultKeyUrl = $key.Key.Kid

# Create disk encryption set with the key - note --encryption-type ConfidentialVmEncryptedWithCustomerKey
#####dup? $des = New-AzDiskEncryptionSet -ResourceGroupName $resgrp -Name $desname -KeyUrl $keyVaultKeyUrl -DiskEncryptionSetType "ConfidentialVmEncryptedWithCustomerKey"

#this bit doesn't work as I don't think the -encryptionType parameter supports confVMencryptedwithCMK yet
#stolen from https://learn.microsoft.com/en-us/powershell/module/az.keyvault/get-azkeyvault?view=azps-12.0.0
##Get the resource ID of the AKV, then create the disk encryption set
#$akvresourceid = (Get-AzKeyVault -VaultName $akvname).ResourceId
#$config = New-AzDiskEncryptionSetConfig -Location 'eastus' -KeyUrl $keyVaultKeyUrl -SourceVaultId $akvresourceid -IdentityType 'SystemAssigned' -DiskEncryptionSetType "ConfidentialVmEncryptedWithCustomerKey"
#$config | New-AzDiskEncryptionSet -ResourceGroupName $resgrp 

#have to cheat and use az cli for this bit as it's not supported in PowerShell yet as far as I could figure
#Create disk encryption set with the key - note --encryption-type ConfidentialVmEncryptedWithCustomerKey
az disk-encryption-set create --resource-group $resgrp --name $desname --key-url $keyVaultKeyUrl --encryption-type ConfidentialVmEncryptedWithCustomerKey

# Get MI of the disk encryption set
$desIdentity = Get-AzDiskEncryptionSet -ResourceGroupName $resgrp -Name $desname | Select-Object -ExpandProperty Identity

start-sleep -seconds 10 # wait for the MI to be created, it's async and takes a few seconds, otherwise following command can fail intermittently

# Grant MI ability to get keys from the AKV
Set-AzKeyVaultAccessPolicy -VaultName $akvname -ResourceGroupName $resgrp -ObjectId $desIdentity.PrincipalId -PermissionsToKeys "wrapKey", "unwrapKey", "get"

# Get id of the disk encryption set
$diskEncryptionSetID = (Get-AzDiskEncryptionSet -ResourceGroupName $resgrp -Name $desname).Id
#tested to this point, works ok

#create the VM, finally! note this creates a Windows VM, without a public IP address (you'll access it using Bastion, configured in the next step)
#need to do this bit in az cli as I'm testing from a Mac, where PowerShell doesn't support the -enablevtpm and secureboot parameters yet
az vm create --resource-group $resgrp --name $vmname --size Standard_DC4as_v5 --admin-username $vmusername --admin-password $vmadminpassword --enable-vtpm true --enable-secure-boot true --image "microsoftwindowsserver:windowsserver:2022-datacenter-smalldisk-g2:latest" --public-ip-address "" --security-type ConfidentialVM --os-disk-security-encryption-type DiskWithVMGuestState --os-disk-secure-vm-disk-encryption-set $diskEncryptionSetID 

<# 
this doesn't work on Mac Powershell yet - no support for -enablevtpm and secureboot parameters
# Create the VM, finally! note this creates a Windows VM, without a public IP address (you'll access it using Bastion, configured in the next step)
$vmconfig= New-AzVMConfig -VMName $vmname -VMSize "Standard_DC4as_v5" -EnableVtpm $true -EnableSecureBoot $true
$vmconfig= Set-AzVMOperatingSystem -VM $vmconfig-Windows -ComputerName $vmname -ProvisionVMAgent -EnableAutoUpdate -Credential (Get-Credential -UserName "_local" -Message "Enter the password for the VM")
$vmconfig= Set-AzVMSourceImage -VM $vmconfig-PublisherName "microsoftwindowsserver" -Offer "windowsserver" -Skus "2022-datacenter-smalldisk-g2" -Version "latest"
$vmconfig= Add-AzVMNetworkInterface -VM $vmconfig-Id (New-AzVirtualNetwork -ResourceGroupName $resgrp -Name $vnetname -Location "eastus" -AddressPrefix "10.0.0.0/16" | Add-AzVirtualNetworkSubnetConfig -Name "default" -AddressPrefix "10.0.0.0/24" | Add-AzVirtualNetworkSubnetConfig -Name "bastion" -AddressPrefix "10.0.1.0/26" | Set-AzVirtualNetwork).Subnets[0].Id
$vmconfig= Set-AzVMDiskEncryptionExtension -VM $vmconfig-DiskEncryptionKeyVaultUrl $keyVaultKeyUrl -DiskEncryptionKeyVaultId (Get-AzKeyVault -VaultName $akvname).ResourceId -VolumeType "All"
$vmconfig= Set-AzVMBootDiagnostic -VM $vmconfig-Enable -StorageAccountName "bootdiagstorage" -StorageAccountResourceGroupName $resgrp
$vmconfig= Set-AzVMOSDisk -VM $vmconfig-CreateOption "FromImage" -DiskSizeInGB 128 -ManagedDiskType "Standard_LRS" -DiskEncryptionSetId $diskEncryptionSetID
New-AzVM -ResourceGroupName $resgrp -Location "eastus" -VM $vmconfig
 #>

# Enable Bastion for the VM you created

# Get the virtual network
$vnet = Get-AzVirtualNetwork -ResourceGroupName $resgrp -Name $vnetname

# Create a subnet for the bastion host
$subnetConfig = New-AzVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix "10.0.1.0/27"
$vnet = Add-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $subnetName -AddressPrefix "10.0.1.0/27"
Set-AzVirtualNetwork -VirtualNetwork $vnet

# Create a public IP for the bastion host
$publicIp = New-AzPublicIpAddress -ResourceGroupName $resgrp -Location $vnet.Location -Name $vnetipname -AllocationMethod Static -Sku Standard

# Create the bastion host
New-AzBastion -ResourceGroupName $resgrp -Name $bastionname -PublicIpAddressRgName $resgrp -PublicIpAddressName $vnetipname -VirtualNetworkRgName $resgrp -VirtualNetworkName $vnetname #-Sku "Basic"

Write-Host "all done! - you can access the VM via the Azure portal - instructions: https://learn.microsoft.com/en-us/azure/bastion/bastion-connect-vm-rdp-windows"
