#title           :clideploy.ps1
#description     :This script will run whatever commands are issued then print the output of said commands
#author		     :Brandon Marlow
#date            :02/23/16
#version         :2.00
#usage		     :clideploy.ps1 -adc [adc IP] -commandlist "command1, command2" or clideploy.ps1 [adc IP] -file [filename
#==============================================================================

#get the params

Param(
   [Parameter(Mandatory=$True,Position=1)]
   [string[]]$adc
)

#set the path for real server manipulation
$apipath = "/axapi/v3/reboot"

#authenticate
. ".\auth.ps1" $adc

Write-Host $body

#send the request to create the real server
$output = Invoke-WebRequest -Uri $adc$apipath -ContentType application/json -Headers $headers -Method Post

#write the result of the commands to the console
Write-Host $output.content   
Write-Host $output

#lets go ahead and log off
. ".\logoff.ps1" $adc
