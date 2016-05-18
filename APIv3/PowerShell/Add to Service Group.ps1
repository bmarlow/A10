#title           :Add to Service Group.ps1
#description     :This script will add a real server to a service group
#author		     :Brandon Marlow
#date            :04062015
#version         :1.00
#usage		     :Add to Service Group.ps1 [adc IP] [service group name] [real server name] [port number]
#==============================================================================

#grab the name and address of the host from positional arguments passed to the script
$adc = $args[0]
$servicegroup = $args[1]
$name = $args[2]
$port = $args[3]

#verify that all the arguments are not null (we aren't doing any deep checking here, just making sure the params have values)
if(-not($adc)) { Throw "You must specify an ADC as the first argument" }
if(-not($adc)) { Throw "You must specify the service group name as the second argument" }
if(-not($adc)) { Throw "You must specify the name of the real server as the third argument" }
if(-not($adc)) { Throw "You must specify the port as the fourth argument" }


#set the path for service-group manipulation
$apipath = "/axapi/v3/slb/service-group/$servicegroup/member"

#authenticate
. ".\auth.ps1" $adc

#format the body of the json request to create the reals
$body = @"
{"member-list":[{"name":"$name","port":"$port"}]}
"@

#send the request to create the real server
Invoke-WebRequest -Uri $adc$apipath -Body "$body" -ContentType application/json -Headers $headers -Method Post    

