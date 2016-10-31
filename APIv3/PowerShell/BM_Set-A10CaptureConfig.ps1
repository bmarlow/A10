<#
.SYNOPSIS
    Execute a packet capture for a protected object.

.DESCRIPTION
    This will instruct an A10 TPS appliance to run a packet capture to collect forensic data.

.PARAMETER DeviceAddress
    The IP address or hostname of the A10 TPS appliance you want to perform your packet capture.

.PARAMETER ProtectedObject
    The address of the object you want to target the packet capture against.

.EXAMPLE
    Get-LastBootTime -ComputerName localhost

.NOTES
    Version:        1.0
    Author:         jlawrence@a10networks.com
    Creation Date:  09/20/2016
    Purpose/Change: Initial script development

.LINK
    www.a10networks.com
#>
param (
    [Parameter(Mandatory=$True)] 
    [string]$DeviceAddress, 
  
    [Parameter(Mandatory=$False)] 
    [string]$ProtectedObject,

    [Parameter(Mandatory=$True)]
    [string]$method,

    [Parameter(Mandatory=$True)]
    [string]$module,

    [Parameter(Mandatory=$False)]
    [string]$body,

    [Parameter(Mandatory=$False)]
    [string]$user,

    [Parameter(Mandatory=$False)]
    [string]$pass
)




#---------------------------------------------------------[Initialisations]--------------------------------------------------------
#Set Error Action to Silently Continue
#$ErrorActionPreference = "SilentlyContinue"

# Allow the use of self-signed SSL certificates

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


#force TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;



$global:headers = @{}
$global:results = @{}


#----------------------------------------------------------[Declarations]----------------------------------------------------------
#Script Version
$sScriptVersion = "1.0"

#Set AXAPI location
$axapi = "axapi/v3"

#Set the base URI
#add https later
$baseURI = "https://$deviceAddress/$axapi"

#-----------------------------------------------------------[Functions]------------------------------------------------------------
<#
Function <FunctionName>{
  Param()
  
  Begin{
    Log-Write -LogPath $sLogFile -LineValue "<description of what is going on>..."
  }
  
  Process{
    Try{
      <code goes here>
    }
    
    Catch{
      Log-Error -LogPath $sLogFile -ErrorDesc $_.Exception -ExitGracefully $True
      Break
    }
  }
  
  End{
    If($?){
      Log-Write -LogPath $sLogFile -LineValue "Completed Successfully."
      Log-Write -LogPath $sLogFile -LineValue " "
    }
  }
}
#>

function call-axapi($module, $method, $body){

    Begin{
        #Write-Host "Sending $module to $deviceAddress."
        
        #Write-Host "method is:" $method "module is:" $module "body is:" $body 
    }
    Process{
        Try{
            if ($body) {
                #Write-Host "I think I have body to send"
                $result = Invoke-RestMethod -Uri $baseURI/$module -Method $method -Headers $global:headers -Body $body -ContentType application/json
            } else {
                #Write-Host "I'll issue the request w/o a body"
                $result = Invoke-RestMethod -Uri $baseURI/$module -Method $method -Headers $global:headers -ContentType application/json
            }
            $result
            

        }
        Catch{
            Write-Host ""
            Write-Host "*************************************************************************************"
            Write-Host $_.Exception
            Write-Host "*************************************************************************************"
            Write-Host ""
            Write-Host "There was an error, please check your configuration and try again"
            Break
        }
    }
}

function authenticate {
    #Write-Output "authenticating"
    If ($user -and $pass){
        $creds=@"
{"credentials": {"username": "$user", "password": "$pass"}}
"@
    }
    If (-Not $user -and $pass){
        $Credentials=Get-Credential -Message "Enter the network credentials for $deviceAddress"
        $creds=[ordered]@{credentials=[ordered]@{username=$Credentials.UserName;password=$Credentials.GetNetworkCredential().Password}} | ConvertTo-Json
    }
    #store the result of the function in the response (this is a PS object
    $response = call-axapi "auth" "Post" $creds
    
    #now we've got the value for the authorization signature
    $signature = $response.authresponse.signature
    
    #now we need to set the headers for global use
    $global:headers = @{ Authorization= "A10 $Signature" }
 #   Write-Host "The Result is:" $response
    
}


function hostname {
    $response = call-axapi "hostname" "Get"
    $HostName = $response.hostname.value
    Write-Host "Device Hostname is: $Hostname"

}

function make-call(){
    $nonjson = call-axapi $module $method $body
    
    $nonjson | ConvertTo-Json


}

function logoff(){
    $logoff = call-axapi "logoff" "post"

    If (($logoff.statuscode -notlike '5') -and ($logoff.statuscode -notlike '4')){
        write-host "successfully logged off"
    }
    Else{
        Write-Host "Hrmmm something went wrong during logoff"
}
}


#-----------------------------------------------------------[Execution]------------------------------------------------------------

#"Instructing $DeviceAddress to perform a capture for dropped packets to $ProtectedObject."
authenticate
hostname
make-call
logoff


