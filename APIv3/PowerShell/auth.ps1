#title           :auth.ps1
#description     :This script will authenticate to the ADC
#author		     :Brandon Marlow
#date            :04062015
#version         :1.00
#usage		     :auth.ps1 [adc IP]
#==============================================================================

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



#grab the IP of the ADC
$adc = $args[0]

#verify that all the arguments are not null (we aren't doing any deep checking here, just making sure the params have values)
if(-not($adc)) { Throw "You must specify an ADC as the first argument" }

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



#set username and pass
$username = "admin"
$pass = "a10"

#build the json body
$body = @"
{"credentials": {"username": "$username", "password": "$pass"}}
"@


#authenticate
<<<<<<< HEAD
$auth = Invoke-RestMethod -Uri https://$adc/axapi/v3/auth -Body $body -ContentType application/json -Method Post
=======
$auth = Invoke-RestMethod -Method Post -Uri https://$adc/axapi/v3/auth -Body $body -ContentType application/json 
>>>>>>> master


#extract the signature
$signature = $auth.authresponse.signature

#set the authentication headers for future API requests
$headers = @{ Authorization= "A10 $signature" }
