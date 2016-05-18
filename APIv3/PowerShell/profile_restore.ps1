#title           :profile_restore.ps1
#description     :This script link a startup-profile to the startup-config, reboot the box, then relink to the default startup-profile
#author		     :Brandon Marlow
#date            :02/24/16
#version         :1.10
#usage		     :profile_restore.ps1 -adc [adc IP] -profile
#==============================================================================

#get the params

Param(
   [Parameter(Mandatory=$True,Position=1)]
   [string[]]$adc,
	
   [Parameter(Mandatory=$true)]
   [string[]]$profile
   
)



#set the path for cli deploy
$clideploy = "/axapi/v3/clideploy"

#set the path for reload
$reload = "/axapi/v3/reload"

#authenticate
. ".\auth.ps1" $adc


#lets build some JSON bodies
$showstartupconfigall = @"
{"commandList": ["show startup-config all"]}
"@

#create new json body for link commands
$linktonewprofile = @"
{"commandList": ["link startup-config $profile"]}
"@

#redfine the commandlist again
$linktodefault = @"
{"commandList": ["link startup-config default"]}
"@

$writememory = @"
{"commandList": [
    "write memory"
]}
"@

Clear-Host

#grab the available profiles
$output = Invoke-WebRequest -Uri $adc$clideploy -Body $showstartupconfigall -ContentType application/json -Headers $headers -Method Post

#write the result of the commands to the console

Write-Host "Original Startup file configuration"
Write-Host "********************************************************************************"
Write-Host $output
Write-Host ""
Write-Host ""
Write-Host ""



#link startup-config to other profile
$linkprofile = Invoke-WebRequest -Uri $adc$clideploy -Body $linktonewprofile -ContentType application/json -Headers $headers -Method Post

Write-Host "Updated Startup file configuration"
Write-Host "********************************************************************************"
Write-Host "********************************************************************************"


#grab the available profiles
$output =Invoke-WebRequest -Uri $adc$clideploy -Body $showstartupconfigall -ContentType application/json -Headers $headers -Method Post
Write-Host $output
Write-Host ""
Write-Host ""
Write-Host ""


$devicereload = Invoke-WebRequest -Uri $adc$reload -ContentType application/json -Headers $headers -Method Post -OutVariable output

Write-Host "Device Reload Beginning"

#give the device a few seconds to start the reload process
Start-Sleep -Seconds 5

$reloading = "yes"
DO
#process to handle inconsistent states that can occur during the device reload
 {
    
    #re-authenticate because you just reloaded so old admin token is no good
    try {
        . ".\auth.ps1" $adc
        #occassionaly we can actually get API responses (HTTP200) before the box is fully up, this catches them and runs us through the loop again
                } 
    #if our authentication request fails (HTTP 4XX/5XX) set reloading to yes
    catch {
        $reloading = "yes"
        Write-Host "$adc is still reloading, please wait..."
        }


    If ($webrequest -match 'error'){
        $reloading = "yes"
        Write-Host "caught an error in comms with LB proccess, retrying..."
        }
    Else {
          $authenticated = "yes"
          }

    #if we made it through the auth without issue, then lets show the startup files


      try {
           # . ".\auth.ps1" $adc
            $output2 = Invoke-WebRequest -Uri $adc$clideploy -Body $showstartupconfigall -ContentType application/json -Headers $headers -Method Post
            #again just in case we catch an inconsistent state with the API (where it will return a 200 but have the body response we requested, this probably isn't necessary, but makes future parsing easier
            If ($output2 -match 'error') {
                $reloading = "yes"
                }
            Else {
               #everytying went smootly, lets break out of the loop
               $reloading = "no"
                }
            }
        
        #if our authentication request fails (HTTP 4XX/5XX) set reloading to yes
        catch {
            $reloading = "yes"
            Write-Host "$adc is still reloading, please wait..."
                }
    
    #lets wait a second before re-running the loop
    Start-Sleep -Seconds 1 
}
While ($reloading -eq "yes")

Write-Host "device finished reloading!"
Write-Host ""
Write-Host ""
Write-Host ""

#link startup-config to other profile
$output = Invoke-WebRequest -Uri $adc$clideploy -Body $linktodefault -ContentType application/json -Headers $headers -Method Post
Write-Host "Default config re-linked!"
Write-Host ""
Write-Host ""
Write-Host ""



Write-Host "Final Startup file configuration"
Write-Host "********************************************************************************"
Write-Host "********************************************************************************"


#re-authenticate as part of the lagging reload process can clear the admin sessions
. ".\auth.ps1" $adc


#grab the available profiles
$output = Invoke-WebRequest -Uri $adc$clideploy -Body $showstartupconfigall -ContentType application/json -Headers $headers -Method Post
Write-Host $output
Write-Host ""
Write-Host ""
Write-Host ""


#save the running config to the default profile
$output = Invoke-WebRequest -Uri $adc$clideploy -Body $writememory -ContentType application/json -Headers $headers -Method Post

Write-Host "Running configuration saved to default startup profile"

Write-Host ""
Write-Host "Logging off..."

#lets go ahead and log off
. ".\logoff.ps1" $adc

Write-Host ""
Write-Host "Finished!"
