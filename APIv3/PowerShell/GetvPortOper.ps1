#title           :getRADIUS.ps1
#description     :This script will grab the RADIUS config from an ADC
#author		     :Brandon Marlow
#date            :05/17/2016
#version         :1.00
#usage		     :getRADIUS.ps1 -adc [adc IP]
#==============================================================================

Param(
   [Parameter(Mandatory=$True,Position=1)]
   [string[]]$adc
   )
#authenticate
. ".\auth.ps1" $adc


#set the path for real server manipulation
$apipath = "/axapi/v3/slb/virtual-server/TRANSPARENT_PROXY/port/80+http/oper"

Invoke-WebRequest -Uri $adc$apipath -Headers $headers -Method Get -OutVariable output

#write the result of the commands to the console
Write-Host $output   

#lets go ahead and log off
. ".\logoff.ps1" $adc
