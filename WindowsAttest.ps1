#Simple script to do an in-guest attestation in a Confidential VM - https://aka.ms/accdocs
#More detailed version https://github.com/Azure/confidential-computing-cvm-guest-attestation/tree/main/cvm-platform-checker-exe
#and you'll need something to decode the JSON like https://jsonformatter.org/json-parser - or code below uses a community module to decode it
#TODO replace the AttestationClientApp.exe and do the call inside the PowerShell script rather than using an external (albeit open source) binary
#No warranty, use at your own risk, etc.

#PowerShell module required to decode the JWT token from the attestation service https://github.com/darrenjrobinson/JWTDetails
install-module -name JWTDetails

Invoke-WebRequest -uri https://github.com/Azure/confidential-computing-cvm-guest-attestation/raw/main/cvm-platform-checker-exe/Windows/cvm_windows_attestation_client.zip -OutFile windowsattestationclient.zip
Expand-Archive -Path .\windowsattestationclient.zip -DestinationPath .
cd .\cvm_windows_attestation_client
# need to install the VC++ redistributable 1st - do silent install
.\VC_redist.x64.exe /q /norestart
start-sleep -Seconds 15 # wait for install to finish - hacky but works
#TODO loop to check for vcredist registry key

#get the JWT output 
$attestationJWT = .\AttestationClientApp.exe -a "sharedweu.weu.attest.azure.net" -n "12345" -o token
$attestationJSON = Get-JWTDetails($attestationJWT)
Write-Host "This " $attestationJSON."x-ms-azurevm-ostype" " OS is running on " $attestationJSON."x-ms-isolation-tee"."x-ms-attestation-type" "VM hardware"

if ($attestationJSON."x-ms-isolation-tee"."x-ms-compliance-status" -eq "azure-compliant-cvm") 
{
    Write-Host "This VM is an Azure compliant CVM attested by " $attestationJSON.iss
}
else {
    Write-Host "This VM is NOT an Azure compliant CVM"
}
# optional - uninstall VC redist afterwards
# .\VC_redist.x64.exe /u



