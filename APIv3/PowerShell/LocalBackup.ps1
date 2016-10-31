#title           :LocalBackup.ps1
#description     :This will create a local profile with the name specified
#author		     :Brandon Marlow
#date            :04062015
#version         :1.00
#usage		     :LocalBackup.ps1 -adc [adc] -profile [profile]
#==============================================================================

#grab the name and address of the host from positional arguments passed to the script
Param(
   [Parameter(Mandatory=$True,Position=1)]
   [string[]]$adc,
   [Parameter(Mandatory=$True,Position=2)]
   [string[]]$profile

)


#set the path for real server manipulation
$apipath = "/axapi/v3/write/memory"

#authenticate
. ".\auth.ps1" $adc

#format the body of the json request to create the reals
$body = @"
{"memory":{"destination":["local"],"profile":"$profile","partition":"all"}}
"@

#send the request to create the real server
Invoke-WebRequest -Uri $adc$apipath -Body $body -ContentType application/json -Headers $headers -Method Post    

#lets go ahead and log off
. ".\logoff.ps1" $adc
