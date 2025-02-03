# Script to build a windows CVM and then make it do attestation by automating an attestation process /inside/ the VM
# Feb 2025, now creates a randomly suffixed CVM and sets a random password
# Quick & dirty demo PowerShell script that makes Azure PowerShell module calls to do most of the heavy-lifting for creating a CVM with a CMK
# Simon Gallagher, ACC Product Group
# Use at your own risk, no warranties implied, test in a non-production environment first
# based on https://learn.microsoft.com/en-us/azure/confidential-computing/quick-create-confidential-vm-azure-cli
# Clone this script & adjust the values in <BRACKETS> to suit your environment
# You'll need to have the latest Azure PowerShell module installed as older versions don't have the parameters for AKV & ACC (update-module -force)


write-host "----------------------------------------------------------------------------------------------------------------"
write-host "Building a server in " $basename " in " $region
write-host "IMPORTANT, randomly generated passsword for the VM is " $vmadminpassword " - save this as you CANNOT retrieve it later"
write-host "----------------------------------------------------------------------------------------------------------------"

#Interactive login for PowerShell and AZCLI (both required) - comment out if you're already logged in

# Powershell login
Connect-AzAccount -SubscriptionId $subsid -Tenant $entra_tenant
Set-AzContext -SubscriptionId $subsid -TenantId $entra_tenant

# AZCLI login Set your Azure subscription
az login --tenant $entra_tenant
az account set --subscription $subsid #will ensure the correct subscription is chosen if you have access to multiple

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
az vm create --resource-group $resgrp --name ($vmname) --size Standard_DC4as_v5 --admin-username $vmusername --admin-password $vmadminpassword --enable-vtpm true --enable-secure-boot true --image "microsoftwindowsserver:windowsserver:2022-datacenter-smalldisk-g2:latest" --vnet-name $vnetname --subnet $vmsubnetName --public-ip-address '""' --security-type ConfidentialVM --os-disk-security-encryption-type DiskWithVMGuestState --os-disk-secure-vm-disk-encryption-set $diskEncryptionSetID
# note special escaping on "" to pass a null value for the public IP address to work on Mac & Windows PowerShell

# Enable Bastion for the VM you created

# Get the virtual network - we only enable bastion for the server - can RDP to the client from it if required
$vnet = Get-AzVirtualNetwork -ResourceGroupName $resgrp -Name ($vnetname)

# Create a public IP for the bastion host
$publicIp = New-AzPublicIpAddress -ResourceGroupName $resgrp -Location $vnet.Location -Name $vnetipname -AllocationMethod Static -Sku Standard

# Create the bastion host
New-AzBastion -ResourceGroupName $resgrp -Name $bastionname -PublicIpAddressRgName $resgrp -PublicIpAddressName $vnetipname -VirtualNetworkRgName $resgrp -VirtualNetworkName $vnetname #-Sku "Basic"

#---------Do attestation check, kick off a script inside the VM to do the attestation check---------

# Invoke the command on the VM, using the local file
write-host "Running an attestation check inside the VM, please wait for output..."
$output = Invoke-AzVMRunCommand -Name $vmname -ResourceGroupName $resgrp -CommandId 'RunPowerShellScript' -ScriptPath .\WindowsAttest.ps1
write-host "--------------Output from the script that ran inside the VM--------------"
write-host $output.Value.message # repeat the output from the script that ran inside the VM
write-host "----------------------------------------------------------------------------------------------------------------"
write-host "Build and validation complete, check the output above for the attestation status."