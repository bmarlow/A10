#title           :auth.ps1
#description     :This script will authenticate to the ADC
#author		     :Brandon Marlow
#date            :04062015
#version         :1.00
#usage		     :auth.ps1 [adc IP]
#==============================================================================

#grab the IP of the ADC
$adc = $args[0]

#verify that all the arguments are not null (we aren't doing any deep checking here, just making sure the params have values)
if(-not($adc)) { Throw "You must specify an ADC as the first argument" }


#set username and pass
$username = "rouser"
$pass = "changeme"

#build the json body
$body = @"
{"credentials": {"username": "$username", "password": "$pass"}}
"@


#authenticate
$auth = Invoke-RestMethod -Uri $adc/axapi/v3/auth -Body $body -ContentType application/json -Method Post


#extract the signature
$signature = $auth.authresponse.signature

#set the authentication headers for future API requests
$headers = @{ Authorization= "A10 $signature" }