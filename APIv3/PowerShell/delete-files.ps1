#title           :delete-files.ps1
#description     :This script will list local files
#author		     :Brandon Marlow
#date            :07/11/2017
#version         :1.00
#usage		     :delete-files.ps1 -device [device] -file [file]
#==============================================================================

#get the params

Param(
   [Parameter(Mandatory=$True)]
   [string[]]$device,

   [Parameter(Mandatory=$True)]
   [string[]]$file
)

#set the API path
$apipath = "/axapi/v3/delete/guest-file"

#authenticate
. ".\auth.ps1" $device

$body = @"
{"guest-file":{"file-name":"$file"}}
"@

#send the request
$output = Invoke-WebRequest -Uri $adc$apipath -ContentType application/json  -body $body -Headers $headers -Method Post

#write out the response
Write-host "writing output variable"
Write-Host $output

#lets go ahead and log off
. ".\logoff.ps1" $adc