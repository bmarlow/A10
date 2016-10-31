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
$apipath = "/axapi/v3/slb/server/V6"
#authenticate
. ".\auth.ps1" $adc


#send the request to create the real server
$output = Invoke-WebRequest -Uri $adc$apipath -ContentType application/json -Headers $headers -Method Get

#write the result of the commands to the console
Write-Host $output.content   

#lets go ahead and log off
. ".\logoff.ps1" $adc
