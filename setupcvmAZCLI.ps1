#Quick & dirty demo Powershell script that makes az cli calls to do most of the heavy-lifting for creating a CVM with a CMK
#Simon Gallagher, ACC Product Group
#Use at your own risk, no warranties implied
#based on https://learn.microsoft.com/en-us/azure/confidential-computing/quick-create-confidential-vm-azure-cli
#Clone this script & adjust the values in <BRACKETS> to suit your environment
#this is a mix of az cli and powershell

#TODO
# - add error handling 
# - add command line parameters (vmname) & check for name >15 chars + abort
# - confirm at script start the name of the subscription you're targetting
# - convert az cli calls into powershell proper
# - investigate vm creds into AKV rather than plaintext in script

#set PowerShell variables to use in the script
$subsid="<YOUR SUBSCRIPTION ID>"
$basename ="<YOUR VM NAME>" # keep this unique and short < 15 chars as it will determine the length of the VM name, various objects will be created based on this e.g. if you use MyCMV1 you'll get MyCVM1akv, MyCVM1des, MyCVM1-cmk-key, MyCVM1vnet, MyCVM1vnet-ip, MyCVM1vnet-bastion named objects
$resgrp=  $basename
$akvname= $basename + "akv"
$desname= $basename + "des"
$keyname= $basename + "-cmk-key"
$vmname=  $basename
$vnetname=$vmname + "vnet"
$bastionname= $vnetname + "-bastion"
$vnetipname=  $vnetname + "-ip"

# Set your Azure subscription, assumes you're already logged in (otherwise do az account login)
az account set --subscription $subsid

# Create a resource group and tag it with the owner (so all resources inherit tag)
az group create --name $resgrp --location eastus --tags "owner=<YOUR ALIAS>"

#create AKV premium instance, note it has purge protection enabled, but will only retain for _10_ days - adjust this for production usage!
az keyvault create -n $akvname -g $resgrp --enabled-for-disk-encryption true --sku premium --enable-purge-protection true --enable-rbac-authorization false --retention-days 10 

#grab the CVM agent ID for your tenant
$cvmAgent = az ad sp show --id "bf7b6499-ff71-4aa2-97a4-f372087be7f0" | Out-String | ConvertFrom-Json
#grant it ability to get keys from the AKV
az keyvault set-policy --name $akvname --object-id $cvmAgent.Id --key-permissions get release
#create a CMK key in the AKV, note RSA-HSM
az keyvault key create --name $keyname --vault-name $akvname --default-cvm-policy --exportable --kty RSA-HSM
#find the key URL (https://<akvname>.vault.azure.net/keys/<keyname>/<keyversion>)
$keyVaultKeyUrl=(az keyvault key show --vault-name $akvname --name $keyname --query [key.kid] -o tsv)
#Create disk encryption set with the key - note --encryption-type ConfidentialVmEncryptedWithCustomerKey
az disk-encryption-set create --resource-group $resgrp --name $desname --key-url $keyVaultKeyUrl --encryption-type ConfidentialVmEncryptedWithCustomerKey
#get MI of the disk encryption set
$desIdentity=(az disk-encryption-set show -n $desname -g $resgrp --query [identity.principalId] -o tsv)
#grant MI ability to get keys from the AKV
az keyvault set-policy -n $akvname -g $resgrp --object-id $desIdentity --key-permissions wrapkey unwrapkey get
#get id of the disk encryption set
$diskEncryptionSetID=(az disk-encryption-set show -n $desname -g $resgrp --query [id] -o tsv)

#create the VM, finally! note this creates a Windows VM, without a public IP address (you'll access it using Bastion, configured in the next step)
az vm create --resource-group $resgrp --name $vmname --size Standard_DC4as_v5 --admin-username "<YOUR USERNAME>" --admin-password "<YOUR ADMIN PASSWORD>" --enable-vtpm true --enable-secure-boot true --image "microsoftwindowsserver:windowsserver:2022-datacenter-smalldisk-g2:latest" --public-ip-address "" --security-type ConfidentialVM --os-disk-security-encryption-type DiskWithVMGuestState --os-disk-secure-vm-disk-encryption-set $diskEncryptionSetID 

#enable Bastion for it
#create a subnet for the bastion
az network vnet subnet create --name AzureBastionSubnet --resource-group $resgrp --vnet-name $vnetname --address-prefix 10.0.1.0/26 #adjusted to smaller subnet which fits inside space
#create a public IP for the bastion
az network public-ip create --resource-group $resgrp --name $vnetipname --sku Standard --location eastus
#now create the bastion configuration, this takes up to 10 mins, go get a coffee
az network bastion create --name $bastionname --public-ip-address $vnetipname --resource-group $resgrp --vnet-name $vnetname --location eastus --sku Basic

Write-Host "all done! - you can access the VM via the Azure portal - instructions: https://learn.microsoft.com/en-us/azure/bastion/bastion-connect-vm-rdp-windows"



