#title           :list-files.ps1
#description     :This script will list local files
#author		     :Brandon Marlow
#date            :07/11/2017
#version         :1.00
#usage		     :list-files.ps1 -device [device]
#==============================================================================

#get the params

Param(
   [Parameter(Mandatory=$True)]
   [string[]]$device
)

#set the API path
$apipath = "/axapi/v3/system/guest-file/oper"

#authenticate
. ".\auth.ps1" $device

#send the request
$output = Invoke-WebRequest -Uri $adc$apipath -Headers $headers -Method Get

#write out the response
Write-host "writing output variable"
Write-Host $output

#lets go ahead and log off
. ".\logoff.ps1" $adc