#title           :Upgrade.ps1
#description     :This script will get the version/boot data
#author		     :Brandon Marlow
#date            :02/23/16
#version         :2.00
#usage		     :Upgrade.ps1 [device]
#==============================================================================

#get the params

Param(
   [Parameter(Mandatory=$True,Position=1)]
   [string[]]$device,

   [Parameter(Mandatory=$True)]
   [string[]]$image,

   [Parameter(Mandatory=$True)]
   [string[]]$url
)


$devicelist = $device.split(",")


#set the path for real server manipulation
$apipath = "/axapi/v3/upgrade/hd"




#authenticate
. ".\auth.ps1" $device

$body = @"
{"hd":{"image":"$image","use-mgmt-port":1,"file-url":"$url"}}
"@

Write-Host $body

#send the request to create the real server
$output = Invoke-WebRequest -Uri $adc$apipath -ContentType application/json -Headers $headers -Method Post -Body $body -TimeoutSec 10000000
#write the result of the commands to the console

Write-host "writing output variable"

Write-Host $output

write-host "writing status code"

Write-Host $output.StatusCode  

#lets go ahead and log off
. ".\logoff.ps1" $adc