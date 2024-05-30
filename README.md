Quick & dirty demo Powershell script that makes az cli calls to do most of the heavy-lifting for creating a CVM with a CMK

Use at your own risk, no warranties implied

Based on https://learn.microsoft.com/en-us/azure/confidential-computing/quick-create-confidential-vm-azure-cli 

Clone this script & adjust the values in <BRACKETS> to suit your environment

Note this will deploy an Azure Keyvault *Premium* SKU [pricing](https://azure.microsoft.com/en-gb/pricing/details/key-vault/#pricing) & enables purge protection for 10 days

For more information on Azure confidential Computing see the [public docs](https//aka.ms/accdocs)
