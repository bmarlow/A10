#title           :Get-TechSupport
#description     :This script will get the techsupport info of an ADC/TPS
#author		     :Brandon Marlow
#date            :10302015
#version         :1.00
#usage		     :Get-Config.ps1 [adc IP]
#==============================================================================

#grab the name and address of the host from positional arguments passed to the script
$adc = $args[0]


#verify that all the arguments are not null (we aren't doing any deep checking here, just making sure the params have values)
if(-not($adc)) { Throw "You must specify an ADC as the first argument" }



#set the path for service-group manipulation
$apipath = "/axapi/v3/copy/"
. ".\auth.ps1" $adc


$body = @"
{
    "running-config": "1",
    "remote-file": "sftp://bud@10.0.1.20/home/bud/",
    "use-mgmt-port":"1"
}
"@


#$body =@"
#{["running-config":"1","remote-file":"sftp://bud@10.0.1.20/home/bud/"]}
#"@


Invoke-WebRequest -Uri $adc$apipath -Body "$body" -ContentType application/json -Headers $headers -Method Post    

