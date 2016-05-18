#title           :Create Reals.ps1
#description     :This script will create a real server
#author		     :Brandon Marlow
#date            :04062015
#version         :1.00
#usage		     :Create Reals .ps1 [adc IP] [server name] [server IP]
#==============================================================================

#grab the name and address of the host from positional arguments passed to the script
$adc = $args[0]
$name = $args[1]
$addr = $args[2]

#verify that all the arguments are not null (we aren't doing any deep checking here, just making sure the params have values)
if(-not($adc)) { Throw "You must specify an ADC as the first argument" }
if(-not($name)) { Throw "You must specify the name of the real server as the second argument" }
if(-not($addr)) { Throw "You must specify the IP Address of the server as the third" }

#set the path for real server manipulation
$apipath = "/axapi/v3/slb/server"

#authenticate
. ".\auth.ps1" $adc

#format the body of the json request to create the reals
$body = @"
{"Server-List":[{"name":"$name","host":"$addr"}]}
"@

#send the request to create the real server
Invoke-WebRequest -Uri $adc$apipath -Body "$body" -ContentType application/json -Headers $headers -Method Post    

#lets go ahead and log off
. ".\logoff.ps1" $adc
