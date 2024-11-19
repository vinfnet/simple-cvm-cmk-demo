# Script to build a windows CVM and then make it do attestation by automating an attestation process /inside/ the VM
# Nov 2024
# Quick & dirty demo PowerShell script that makes Azure PowerShell module calls to do most of the heavy-lifting for creating a CVM with a CMK
# Simon Gallagher, ACC Product Group
# Use at your own risk, no warranties implied, test in a non-production environment first
# based on https://learn.microsoft.com/en-us/azure/confidential-computing/quick-create-confidential-vm-azure-cli
# Clone this script & adjust the values in <BRACKETS> to suit your environment
# You'll need to have the latest Azure PowerShell module installed as older versions don't have the parameters for AKV & ACC (update-module -force)

# TODO
# - add error handling 
# - convert from mix of azc cli and PowerShell to all PowerShell (90% done, copilot gets 65% of the credit for this), can't create disk encryption set /or/ VM nativeliy in PowerShell yet as they don't support some of the parameters yet, az cli does however
# - add command line parameters (vmname) & check for name >15 chars + abort
# - put vm creds into AKV rather than plaintext in script

# Set PowerShell variables to use in the script
$subsid = "<YOUR SUBSCRIPTION ID>"
$basename = "<YOUR ID>" # keep this unique and short < 15 chars as it will determine the length of the VM name, various objects will be created based on this e.g. if you use MyCMV1 you'll get MyCVM1akv, MyCVM1des, MyCVM1-cmk-key, MyCVM1vnet, MyCVM1vnet-ip, MyCVM1vnet-bastion named objects
$vmusername = "<YOUR USER NAME>" # username for the VM, must be _local for CVM
$vmadminpassword = "<YOUR PASSWORD>" # password for the VM, must be 12 chars or more, complex, and meet Azure password requirements
$ownername = "<YOUR ALIAS>" #used to set the owner tag value on the resouce group
$resgrp =  $basename # nmame of the resource group where all resources will be created, copied from $basename
$akvname = $basename + "akv"
$desname = $basename + "des"
$keyname = $basename + "-cmk-key"
$vmname = $basename # name of the VM, copied from $basename, or customise it here
$vnetname = $vmname + "vnet"
$bastionname = $vnetname + "-bastion"
$vnetipname = $vnetname + "-ip"
$bastionsubnetName = "AzureBastionSubnet" # don't change this
$vmsubnetname = $basename + "vmsubnet" # don't change this
$region = "northeurope" #oops - missed this

# Powershell login
Connect-AzAccount -SubscriptionId $subsid -Tenant microsoft.onmicrosoft.com

# AZCLI login Set your Azure subscription
Set-AzContext -SubscriptionId $subsid

# Create a resource group and tag it with the owner (so all resources inherit tag)
New-AzResourceGroup -Name $resgrp -Location $region -Tag @{owner=$ownername}

# Create AKV premium instance, note it has purge protection enabled, but will only retain for _10_ days - adjust this for production usage! -enablesoftdelete is default now (-disablerbacauthorization _required_)
New-AzKeyVault -VaultName $akvname -ResourceGroupName $resgrp -Location $region -Sku "premium" -EnablePurgeProtection -SoftDeleteRetentionInDays 10 -DisableRbacAuthorization

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

#have to cheat and use az cli for this bit as it's not supported in PowerShell yet as far as I could figure
#Create disk encryption set with the key - note --encryption-type ConfidentialVmEncryptedWithCustomerKey
az disk-encryption-set create --resource-group $resgrp --name $desname --key-url $keyVaultKeyUrl --encryption-type ConfidentialVmEncryptedWithCustomerKey

# Get MI of the disk encryption set
$desIdentity = Get-AzDiskEncryptionSet -ResourceGroupName $resgrp -Name $desname | Select-Object -ExpandProperty Identity

start-sleep -seconds 30 # wait for the MI to be created, it's async and takes a few seconds, otherwise following command can fail intermittently

# Grant MI ability to get keys from the AKV
Set-AzKeyVaultAccessPolicy -VaultName $akvname -ResourceGroupName $resgrp -ObjectId $desIdentity.PrincipalId -PermissionsToKeys "wrapKey", "unwrapKey", "get"

# Get id of the disk encryption set
$diskEncryptionSetID = (Get-AzDiskEncryptionSet -ResourceGroupName $resgrp -Name $desname).Id

#create network 
$vmsubnet = New-AzVirtualNetworkSubnetConfig -Name $vmsubnetname -AddressPrefix "10.0.1.0/24"
$bastionsubnet  = New-AzVirtualNetworkSubnetConfig -Name $bastionsubnetName  -AddressPrefix "10.0.2.0/24"
New-AzVirtualNetwork -Name $vnetname -ResourceGroupName $resgrp -Location $region -AddressPrefix "10.0.0.0/16" -Subnet $vmsubnet, $bastionsubnet

#Create CVM
az vm create --resource-group $resgrp --name ($vmname) --size Standard_DC4as_v5 --admin-username $vmusername --admin-password $vmadminpassword --enable-vtpm true --enable-secure-boot true --image "microsoftwindowsserver:windowsserver:2022-datacenter-smalldisk-g2:latest" --vnet-name $vnetname --subnet $vmsubnetName --public-ip-address "" --security-type ConfidentialVM --os-disk-security-encryption-type DiskWithVMGuestState --os-disk-secure-vm-disk-encryption-set $diskEncryptionSetID

# Enable Bastion for the VM you created

# Get the virtual network - we only enable bastion for the server - can RDP to the client from it if required
$vnet = Get-AzVirtualNetwork -ResourceGroupName $resgrp -Name ($vnetname)

# Create a public IP for the bastion host
$publicIp = New-AzPublicIpAddress -ResourceGroupName $resgrp -Location $vnet.Location -Name $vnetipname -AllocationMethod Static -Sku Standard

# Create the bastion host
New-AzBastion -ResourceGroupName $resgrp -Name $bastionname -PublicIpAddressRgName $resgrp -PublicIpAddressName $vnetipname -VirtualNetworkRgName $resgrp -VirtualNetworkName $vnetname #-Sku "Basic"

#---------Do attestation check, kick off a script inside the VM to do the attestation check---------

# Invoke the command on the VM, using the local file
$output = Invoke-AzVMRunCommand -Name $vmname -ResourceGroupName $resgrp -CommandId 'RunPowerShellScript' -ScriptPath .\WindowsAttest.ps1
write-host "Output from the script that ran inside the VM:"
write-host $output.Value.message # repeat the output from the script that ran inside the VM
write-host "Build and validation complete, check the output above for the attestation status."