#title           :Get Virtual Server.ps1
#description     :This script will create a vritual server
#author		     :Brandon Marlow
#date            :04062015
#version         :1.00
#usage		     :Get Config for Virtual Server.ps1 [adc IP] [virtual server name] 
#==============================================================================

#grab the name and address of the host from positional arguments passed to the script
$adc = $args[0]
$name = $args[1]


#verify that all the arguments are not null (we aren't doing any deep checking here, just making sure the params have values)
if(-not($adc)) { Throw "You must specify an ADC as the first argument" }
if(-not($name)) { Throw "You must specify the name of the Virtual Server as the second argument" }


#set the path for virtual server manipulation
$apipath = "/axapi/v3/slb/virtual-server/$name"

#authenticate
. ".\auth.ps1" $adc

#send the request to get the config for the virtual server
$output = Invoke-WebRequest -Uri $adc$apipath -ContentType application/json -Headers $headers -Method Get    
Write-Host $output