
Param(
   [Parameter(Mandatory=$True,Position=1)]
   [string[]]$adc
   )
#authenticate
. ".\auth.ps1" $adc


#set the path for real server manipulation
$apipath = "/axapi/v3/interface/ethernet/6"

Do{

$body = @"
{"ethernet":{"action":"enable"}}
"@

Invoke-WebRequest -Uri $adc$apipath -Body $body -ContentType application/json -Headers $headers -Method Post -OutVariable output

#write the result of the commands to the console
Write-Host $output   

$body = @"
{"ethernet":{"action":"disable"}}
"@

Invoke-WebRequest -Uri $adc$apipath -Body $body -ContentType application/json -Headers $headers -Method Post -OutVariable output

#write the result of the commands to the console
Write-Host $output   


}
While (1 -eq 1)
#lets go ahead and log off
. ".\logoff.ps1" $adc
