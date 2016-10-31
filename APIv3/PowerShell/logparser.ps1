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
	
   [Parameter(Mandatory=$True)]
   [string[]]$keystring,

   [Parameter(Mandatory=$false)]
   [int[]]$sleeptime,

   [Parameter(Mandatory=$false)]
   [switch] $clearonmatch

)


#set the path for API call
$apipath = "/axapi/v3/clideploy"

#authenticate
. ".\auth.ps1" $adc

#create the json body
$body = @"
{"commandList": ["show log"]}
"@




:outer While ($true){

    #send the request to create the real server
    $output = Invoke-WebRequest -Uri $adc$apipath -Body $body -ContentType application/json -Headers $headers -Method Post

    #write the result of the commands to the console
    #rite-Host $output   

    #by default the output of our call is stored as a multiline string, which won't work for parsing and matching
    #so we split it on the new line and store it in an array
    $outputarray = $output -split '[\r\n]'


    #createa function for the window popup, because this method is ugly
    function popup{
    $popupobject = new-object -comobject wscript.shell
    $popup = $popupobject.popup("The following log message:
    $line
    Matched your string:$keystring"
    ,0,"Found Log message that matches string!",1)
        }

    #iterate through each line in the array and look for our keystring
    #if the keystring is there, issue a popup
    foreach ($outputline in $outputarray){
        $line = Select-String -pattern $keystring -inputobject $outputline
        If ($line -ne $null){
            popup
            Break outer
            }
        }


    #there isn't much use to hammering the box API as fast as we can
        If ($sleeptime -eq $null){
            sleep -Seconds 1
            }
        Else{
            sleep -seconds $sleeptime[0]
            }


    }





#clear the log if we find a match (helpful for not generating matches on old data)
If ($clearonmatch -eq $True){
    #create the json body
$body = @"
{"commandList": ["clear logging"]}
"@

    #send the request to create the real server
    $clearoutput = Invoke-WebRequest -Uri $adc$apipath -Body $body -ContentType application/json -Headers $headers -Method Post
    }


Write-Host "logging off"
#lets go ahead and log off
. ".\logoff.ps1" $adc
