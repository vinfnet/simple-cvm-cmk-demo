Quick & dirty demo Powershell script that makes az cli calls to do most of the heavy-lifting for creating a CVM with a CMK

Use at your own risk, no warranties implied

Based on https://learn.microsoft.com/en-us/azure/confidential-computing/quick-create-confidential-vm-azure-cli 

Clone this script & adjust the values in < BRACKETS > to suit your environment

Note this will deploy an Azure Keyvault *Premium* SKU [pricing](https://azure.microsoft.com/en-gb/pricing/details/key-vault/#pricing) & enables purge protection for 10 days

Once you've deployed you can install the [simple attestation client](https://github.com/Azure/confidential-computing-cvm-guest-attestation/blob/main/cvm-platform-checker-exe/README.md) install the VC runtime 1st! to see true/false if your VM is protected by Azure Confidential Computing

The WindowsAttest.ps1 script can be invoked inside a CVM to do an attestation check against the West Europe shared attestation endpoint

Expected output:

Running on a CVM (DCa / ECa Series SKU using AMD SEV-SNP hardware)
>    This  Windows  OS is running on  sevsnpvm VM hardware
>    This VM is an Azure compliant CVM attested by  https://sharedweu.weu.attest.azure.net

NOT running on a CVM (any other Azure SKU)
>    This VM is NOT an Azure compliant CVM


You can download the script to a CVM or execute directly from GitHub from your CVM by pasting the following single line Command in a PowerShell session

```
$ScriptFromGitHub = Invoke-WebRequest -uri https://raw.githubusercontent.com/vinfnet/simple-cvm-cmk-demo/refs/heads/main/WindowsAttest.ps1 ; Invoke-Expression $($ScriptFromGitHub.Content)
```

For more information on Azure confidential Computing see the [public docs](https//aka.ms/accdocs)
