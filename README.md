BuildRandomCVM.ps1 will build a CVM with Customer Managed Key, Confidential Disk Encryption, a private VNet (no public IP) and deploy Azure Bastion for RDP access over the Internet. It will then kick off an attestation inside the CVM and present back the output (see WindowsAttest.ps1 for details) via Invoke-AzVMRunCommand

Use at your own risk, no warranties implied

Based on https://learn.microsoft.com/en-us/azure/confidential-computing/quick-create-confidential-vm-azure-cli and https://aka.ms/accdocs resources

Usage: 
Git clone this repo locally (subsequent script depends on WindowsAttest.ps1)
Basename is a prefix assigned to all resources created by the script and will be given a 5 char suffix - for example : myCVM-sdfrw
The script will generate a random complex password and output it to the terminal once, make sure you copy it if you want to login to the CVM

```
./BuildRandomCVM.ps1 -subsID <YOUR SUBSCRIPTION ID> -basename <YOUR BASENAME>
```
Note this will deploy an Azure Keyvault *Premium* SKU [pricing](https://azure.microsoft.com/en-gb/pricing/details/key-vault/#pricing) & enables purge protection for 10 days (you can adjust the purge protection period but AKV Premium is required for CVMs with confidential disk encryption

By default the script will create a resource in North Europe - adjust the $region parameter in the parameter block at the start for alternative regions - check availability of CVMs in that region 1st

# ARM Template
Create a simple CVM with CMK enabled (work-in-progress)

You'll need to create a disk encryption set and encryption key (use Azure Keyvault Premium) and replace the relevant values in the parameter file.

To deploy from the command line:

Once you've deployed you can install the [simple attestation client](https://github.com/Azure/confidential-computing-cvm-guest-attestation/blob/main/cvm-platform-checker-exe/README.md) install the VC runtime 1st! to see true/false if your VM is protected by Azure Confidential Computing

The WindowsAttest.ps1 script can manually be invoked inside a CVM to do an attestation check against the West Europe shared attestation endpoint

Expected output:

Running on a CVM (DCa / ECa Series SKU using AMD SEV-SNP hardware)
>    This  Windows  OS is running on  sevsnpvm VM hardware
>    This VM is an Azure compliant CVM attested by  https://sharedweu.weu.attest.azure.net

NOT running on a CVM (any other Azure SKU)
>    This VM is NOT an Azure compliant CVM

You can download the script to a CVM or execute directly from GitHub from your CVM by pasting the following single line Command in a PowerShell session that is running with Administrative permissions (review the script 1st to ensure you are happy with the binaries and packages it installs or download & customize)

```
$ScriptFromGitHub = Invoke-WebRequest -uri https://raw.githubusercontent.com/vinfnet/simple-cvm-cmk-demo/refs/heads/main/WindowsAttest.ps1 ; Invoke-Expression $($ScriptFromGitHub.Content)
```

For more information on Azure confidential Computing see the [public docs](https//aka.ms/accdocs)

# Older Versions

setupcvmAZCLI.ps1 and setupCVMPOSH.ps1 also still work but are less mature than BuildRandomCVM.ps1.
