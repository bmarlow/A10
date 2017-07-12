#title           :Create Radius Server.ps1
#description     :This script will create a Radius Server
#author		     :Brandon Marlow
#date            :05112017
#version         :1.00
#usage		     :Create Radius Server .ps1 [adc IP] [server name] [server IP]
#==============================================================================

#grab the name and address of the host from positional arguments passed to the script
param (
    [Parameter(Mandatory=$True)] 
    [string]$adc,
    
    [Parameter(Mandatory=$False)] 
    [string]$rad_server,
     
    [Parameter(Mandatory=$True)] 
    [string]$rad_secret
)

#set the path for real server manipulation
$apipath = "/axapi/v3/radius-server"

#authenticate
. ".\auth.ps1" $adc

#format the body of the json request to create the reals
$body = @"
{
    "radius-server": {
        "default-privilege-read-write": 1, 
        "host": {
            "ipv4-list": [
                {
                    "ipv4-addr": "$rad_server", 
                    "secret": {
                        "secret-value": "$rad_secret", 
                        "port-cfg": {
                            "auth-port": 1
                        }
                    }
                }
            ]
        }
    }
}
"@

Write-Output $body

#send the request to create the real server
Invoke-WebRequest -Uri $adc$apipath -Body "$body" -ContentType application/json -Headers $headers -Method Post    

#lets go ahead and log off
. ".\logoff.ps1" $adc
