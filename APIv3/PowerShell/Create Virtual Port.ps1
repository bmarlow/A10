#title           :Create Virtual Port.ps1
#description     :This script will create a vritual service
#author		     :Brandon Marlow
#date            :04062015
#version         :1.00
#usage		     :Create Virtual Server.ps1 [adc IP] [virtual server name] [port number] [protocol] [service group]
#==============================================================================
#grab the name and address of the host from positional arguments passed to the script
$adc = $args[0]
$vip = $args[1]
$portnumber = $args[2]
$protocol = $args[3]
$servicegroup = $args[4]

#verify that all the arguments are not null (we aren't doing any deep checking here, just making sure the params have values)
if(-not($adc)) { Throw "You must specify an ADC as the first argument" }
if(-not($vip)) { Throw "You must specify the name of the virtual server as the second argument" }
if(-not($portnumber)) { Throw "You must specify the port number for the virtual service as the third argument" }
if(-not($protocol)) { Throw "You must specify the protocol as the fourth argument" }
if(-not($servicegroup)) { Throw "You must specify the name of the associated service group as the fourth argument" }
#set the path for virtual server manipulation
$apipath = "/axapi/v3/slb/virtual-server/$vip/port"

#authenticate
. ".\auth.ps1" $adc

#format the body of the json request to create the VIP
$body = @"
{"port-list":[{"port-number":"$portnumber","protocol":"$protocol","service-group":"$servicegroup"}]}
"@

#send the request to create the real server
Invoke-WebRequest -Uri $adc$apipath -Body $body -ContentType application/json -Headers $headers -Method Post    