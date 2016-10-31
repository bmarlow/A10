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
   [string[]]$adc,
	
   [Parameter(Mandatory=$false)]
   [string[]]$commands,

   [Parameter(Mandatory=$false)]
   [string] $file

)

#either $commands or $file can be set, not both.  but since they can't be mandatory we need to make sure that they both are not set, as well as that they both are not null.
if((-not($commands) -and (-not($file)))) { Throw "You must specify either a commandlist OR a file" }

if($commands -and $file) { Throw "You must specify either a commandlist or a file" }


#store the commands in the command list variable based on where we read them from
if($file) {$commandlist = Get-Content $file}
else {$commandlist = $commands}

#convert the commandlist from string to array
$commandlistarr = $commandlist.split(",")

#format the array as JSON (make sure to call it as an array otherwise single item arrays get treated as strings and break the message expected by A10
$jsoncommandlist = ConvertTo-Json @($commandlistarr)

#set the path for real server manipulation
$apipath = "/axapi/v3/clideploy"

#authenticate
. ".\auth.ps1" $adc

#create the json body
$body = @"
{"commandList": $jsoncommandlist}
"@
Write-Host $body

#send the request to create the real server
$output = Invoke-WebRequest -Uri $adc$apipath -Body $body -ContentType application/json -Headers $headers -Method Post

#write the result of the commands to the console
Write-Host $output.content   

#lets go ahead and log off
. ".\logoff.ps1" $adc
