#title           :GetServiceGroupMember.ps1
#description     :This script will get the version/boot data
#author		     :Brandon Marlow
#date            :02/23/16
#version         :2.00
#usage		     :GetVersion.ps1 [adc]
#==============================================================================

#get the params

Param(
   [Parameter(Mandatory=$True,Position=1)]
   [string[]]$adc,
   
   [Parameter(Mandatory=$True,Position=1)]
   [string[]]$membername,
      
   [Parameter(Mandatory=$True,Position=1)]
   [string[]]$servicegroupname,
   
   [Parameter(Mandatory=$True,Position=1)]
   [string[]]$port
)

#set the path for real server manipulation
$apipath = "/axapi/v3/slb/service-group/" + $servicegroupname + "/member/" + $membername + "+" + $port

Write-Host $apipath
#authenticate
. ".\auth.ps1" $adc

Write-Host $body

#send the request to create the real server
$output = Invoke-WebRequest -Uri $adc$apipath -ContentType application/json -Headers $headers -Method Get -TimeoutSec 10000000
#write the result of the commands to the console

Write-host "writing output variable"

Write-Host $output

write-host "writing content"

Write-Host $output.content   

#lets go ahead and log off
. ".\logoff.ps1" $adc
