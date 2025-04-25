# Hands-off script to build a windows CVM and then make it do attestation by automating an attestation process /inside/ the VM
# VM will be created in a private vnet with no public IP and can only be accessed over the Internet via the Azure Bastion service
# April 2025 - ported to all native PowerShell code and re-implemented Azure Bastion code and added command line parameters rather than editing file
# Tested on MacOS (PWSH 7.5) & Windows (7.4.6)
# 
# Simon Gallagher, ACC Product Group
# Use at your own risk, no warranties implied, test in a non-production environment first
# based on https://learn.microsoft.com/en-us/azure/confidential-computing/quick-create-confidential-vm-azure-cli
# and
# https://learn.microsoft.com/en-gb/azure/azure-sql/virtual-machines/windows/sql-vm-create-confidential-vm-how-to?view=azuresql
# 
# Clone this repo to a folder (relies on the WindowsAttest.ps1 script being in the same folder as this script)
#
# Usage: ./BuildRandomSQLCVM.ps1 -subsID <YOUR SUBSCRIPTION ID> -basename <YOUR BASENAME>
#
# Basename is a prefix for all resources created, it's used to create unique names for the resources
#
# You'll need to have the latest Azure PowerShell module installed as older versions don't have the parameters for AKV & ACC (update-module -force)
#
