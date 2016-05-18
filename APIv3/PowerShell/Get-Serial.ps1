#title           :Get-Serial
#description     :This script will grab the serial number and print it out for a group of devices
#author		     :Brandon Marlow
#date            :11062015
#version         :1.00
#usage		     :Get-Serial.ps1 [adc IP1,adc IP2,etc]
#==============================================================================

#grab the name and address of the host from positional arguments passed to the script
$devices = $args[0]


#verify that all the arguments are not null (we aren't doing any deep checking here, just making sure the params have values)
if(-not($devices)) { Throw "You must specify an ADC as the first argument" }


Foreach ($device in $devices){

    #set the path for service-group manipulation
    $apipath = "/axapi/v3/version/oper/"
    . ".\auth.ps1" $device

    $results = Invoke-WebRequest -Uri $adc$apipath -ContentType application/json -Headers $headers -Method Get -OutVariable webrequestoutput| ConvertFrom-Json

    Write-Host $device $results.version.oper."serial-number"

     #lets go ahead and log off
    . ".\logoff.ps1" $adc

}