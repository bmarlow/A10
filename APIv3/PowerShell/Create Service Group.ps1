#title           :Create Service Group.ps1
#description     :This script will create a service group
#author		     :Brandon Marlow
#date            :04062015
#version         :1.00
#usage		     :Create Service Group.ps1 [adc IP] [service group name] [service group protocol IP]
#==============================================================================

#grab the name and address of the host from positional arguments passed to the script
$adc = $args[0]
$name = $args[1]
$protocol = $args[2]

#verify that all the arguments are not null (we aren't doing any deep checking here, just making sure the params have values)
if(-not($adc)) { Throw "You must specify an ADC as the first argument" }
if(-not($name)) { Throw "You must specify the name of the service group as the second argument" }
if(-not($protocol)) { Throw "You must specify the protocol of the service group as the third argument (TCP/UDP)" }

#set the path for service-group manipulation
$apipath = "/axapi/v3/slb/service-group"

#authenticate
. ".\auth.ps1" $adc

#format the body of the json request to create the reals
$body = @"
{"service-group-list":[{"name":"$name","protocol":"$protocol"}]}
"@

#send the request to create the real server
Invoke-WebRequest -Uri $adc$apipath -Body "$body" -ContentType application/json -Headers $headers -Method Post    

