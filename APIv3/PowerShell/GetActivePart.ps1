#title           :GetVersion.ps1
#description     :This script will get the version/boot data
#author		     :Brandon Marlow
#date            :02/23/16
#version         :2.00
#usage		     :GetVersion.ps1 [adc]
#==============================================================================

#get the params

Param(
   [Parameter(Mandatory=$True,Position=1)]
   [string[]]$adc
)

#set the path for real server manipulation
$apipath = "/axapi/v3/version/oper"

#authenticate
. ".\auth.ps1" $adc

Write-Host $body

$prot = "https://"

#send the request to create the real server
$output = Invoke-WebRequest -Uri $prot$adc$apipath -ContentType application/json -Headers $headers -Method Get

#write the result of the commands to the console
Write-Host $output.content   

#lets go ahead and log off
. ".\logoff.ps1" $adc
