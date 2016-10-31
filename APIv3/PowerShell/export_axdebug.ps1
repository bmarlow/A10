#title           :logparser.ps1
#description     :This script will grab the logs off of an A10 device parse them for keywords, then provide a popup if a keyword is matched, there is an option for clearing the log after the script has found a match
#author		     :Brandon Marlow
#date            :6/10/16
#version         :1.00
#usage		     :logparser.ps1 -adc [adc IP] -keystring [string to parse for] -clearonmatch (optional)
#==============================================================================

#get the params

Param(
   [Parameter(Mandatory=$True,Position=1)]
   [string[]]$adc,
	
   [Parameter(Mandatory=$false)]
   [string[]]$keystring,

   [Parameter(Mandatory=$false)]
   [int[]]$sleeptime,

   [Parameter(Mandatory=$false)]
   [switch] $clearonmatch

)


#set the path for API call
$apipath = "/axapi/v3/export"

#authenticate
. ".\auth.ps1" $adc

#create the json body
$body = @"
{"Axdebug": "TEST1234"}
"@




    #send the request to create the real server
    $output = Invoke-WebRequest -Uri $adc$apipath -Body $body -ContentType application/json -Headers $headers -Method Post

Write-Host "logging off"
#lets go ahead and log off
. ".\logoff.ps1" $adc
