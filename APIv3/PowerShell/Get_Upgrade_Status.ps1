#title           :upgrade-url.ps1
#description     :This script will upgrade the A10 device using a URL
#author		     :Brandon Marlow
#date            :07/11/17
#version         :2.10
#usage		     :upgrade-url.ps1 -device [device] -detailed -reboot
#==============================================================================

#get the params



Param(
   [Parameter(Mandatory=$True,Position=1)]
   [string[]]$device

)


Add-Type @"
    using System;
    using System.Net;
    using System.Net.Security;
    using System.Security.Cryptography.X509Certificates;
    public class ServerCertificateValidationCallback
    {
        public static void Ignore()
        {
            ServicePointManager.ServerCertificateValidationCallback += 
                delegate
                (
                    Object obj, 
                    X509Certificate certificate, 
                    X509Chain chain, 
                    SslPolicyErrors errors
                )
                {
                    return true;
                };
        }
    }
"@
 
[ServerCertificateValidationCallback]::Ignore();

#force TLS1.2 (necessary for the management interface)
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;




#authenticate
. ".\auth.ps1" $device

$apipath = '/axapi/v3/system/upgrade-status/oper'

#send the request to create the real server
$output = Invoke-WebRequest -Uri https://$adc$apipath -ContentType application/json -Headers $headers -Method Get -TimeoutSec 10000000
#write the result of the commands to the console

Write-host "writing output"

Write-Host $output

write-host "writing status code"

Write-Host $output.StatusCode  

#lets go ahead and log off
. ".\logoff.ps1" $adc