<#
.SYNOPSIS
    Manipulate Servers in a Lightning Service/Application

.DESCRIPTION
    This script can be used to add or delete (future feature) servers to a service on an A10 Lightning Controller

.PARAMETER Controller
    This is the IP address or DNS name of the Lightning Controller

.PARAMETER User
    This is the username that will be connecting (this is typically an email address)

.PARAMETER Pass
    This si the password associated to the user account

.PARAMETER Tenant
    This is the tenant that the application servers/applications reside in

.PARAMETER App
    The application in which the servers reside

.PARAMETER Service
    --Optional -- The service in which the servers reside (default: Default-Service)

.PARAMETER ServiceGroup
    --Optional -- The ServiceGrop in which the servers reside (default: DefaultServerGroup)

.PARAMETER Action
    The interaction type (add/delete) for the servers

.PARAMETER Server
    --Optional -- The server to be added to the service

.PARAMETER Port
    --Optional -- The Port for the server

.PARAMETER Weight
    --Optional -- The Weight for the server

.PARAMETER Provider
    --Optional -- The provider (or subprovider) the application belongs to (default: root)

.PARAMETER ConfigFile
    --Optional -- A config file that has servers ports and weights, one per line

.PARAMETER UseHTTP
    --Optional -- Switch interactions to HTTP instead of HTTPS (default: use HTTPS)

.EXAMPLE
    lightning_servers.ps1 -controller api.a10networks.com -user somebody@a10networks.com -pass APASSWORD! -provider root -tenant MyTenant -app MyApplication -Service MyService -Action add -Server 1.1.1.1 -Port 80 -Weight 100

.EXAMPLE
    lightning_servers.ps1 -controller api.a10networks.com -user somebody@a10networks.com -pass APASSWORD! -provider root -tenant MyTenant -app MyApplication -Service MyService -Action add -ConfigFile MyConfigFile.txt
    
.EXAMPLE
    lightning_servers.ps1 -controller api.a10networks.com -user somebody@a10networks.com -pass APASSWORD! -provider root -tenant MyTenant -app MyApplication -Service MyService -Action add -ConfigFile MyConfigFile.txt -UseHTTP


.NOTES
    Version:        1.0.0
    Author:         Brandon Marlow - bmarlow@a10networks.com
    Creation Date:  08/02/17
    Rev 1.0:        Initial support adding servers to a service - DOES NOT SUPPORT THE DELETE FUNCTION

.LINK
    www.a10networks.com
#>


#get the params

Param(
   [Parameter(Mandatory=$True)]
   [string]$controller,

   [Parameter(Mandatory=$True)]
   [string]$user,

   [Parameter(Mandatory=$False)]
   [string]$pass,

   [Parameter(Mandatory=$True)]
   [string]$tenant,

   [Parameter(Mandatory=$True)]
   [string]$app,

   [Parameter(Mandatory=$false)]
   [string]$service,

   [Parameter(Mandatory=$false)]
   [string]$servergroups,
   
   [Parameter(Mandatory=$True)] 
   [ValidateSet("add","delete")]
   [string]$action, 

   [Parameter(Mandatory=$False)]
   [string]$server,

   [Parameter(Mandatory=$False)]
   [int]$port,

   [Parameter(Mandatory=$False)]
   [int]$weight,

   [Parameter(Mandatory=$False)]
   [string]$configfile,

   [Parameter(Mandatory=$False)]
   [string]$provider,

   [Parameter(Mandatory=$False)]
   [switch]$usehttp


)


#---------------------------------------------------------[Sanity Checks]--------------------------------------------------------

#you can simultaneously specify a server/port/weight and the configfile
If (($server -and $configfile) -or ($port -and $configfile) -or ($weight -and $configfile)){
    Write-Output "ConfigFile cannot be specified with Server,Port, or Weight.  Exiting..."
    exit -1
}

#if you specify server you must specify port and weight
If (($server) -and ((-not $port) -or (-not $weight))){
    Write-Output "If specifying the server from the command line you must specify the port and host as well"
    exit -1
}

#---------------------------------------------------------[Sanity Checks]--------------------------------------------------------

#---------------------------------------------------------[Initialisations]--------------------------------------------------------

#if you don't specify a password on the command line grab it securely (then unmask so the string can be used)
If (-not $pass){
    $securepass = Read-Host("Please enter the password for user ${user}:") -AsSecureString
    $pass = (New-Object PSCredential "user",$securepass).GetNetworkCredential().Password
}

#if you don't specify a service use the default-service
If ($service -eq $null){
    $service = "default-service"
}

#if you don't specify a server group use the default one
If (-not $servergroups){
    $servergroups = "defaultServerGroup"
    }

#default to https, however for ease of debugging and PCAPs you may wish to switch to HTTP
If ($usehttp -eq $true){
    $prefix = "http://"
}
Else{
    $prefix = "https://"
}

#if you do not specify a provider assume its root
If (-not $provider){
    $provider = "root"
}

#set the method based on the action
If ($action -eq "add"){
    $method = "put"
}
ElseIf ($action -eq "delete"){
    Write-Output "The delete function is not currently supported by this script"
    exit -1
}

#set the API path
$apipath = "/api/v2/"


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

#force TLS1.2 (necessary for the management interface)
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;

#---------------------------------------------------------[Initialisations]--------------------------------------------------------

#---------------------------------------------------------[Functions]--------------------------------------------------------

#fucntion for authenticating
function authenticate {

    #build the user/pass tuple
    $plaincreds = "${user}:${pass}"

    #seriously powershell, no built in base64 encoder/decoder?
    $encodedcreds = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($plaincreds))

    #set your headers
    $headers = @{"Authorization" = "Basic $encodedcreds"; "provider" = "root"}
    $userid = @{"userId" = "${user}"}

    $session = Invoke-RestMethod -Method Post -Uri "${prefix}${controller}${apipath}sessions" -ContentType "application/json" -Headers $headers

    return $session.id

}

#function for logging off
function logoff {

    $headers = @{"Authorization" = "Session $sessionid"; "provider" = "root"}

    #we use webrequest here because we need the HTTP response code, which isn't readily available from invoke-restmethod apparantly
    $logoff = Invoke-WebRequest -Method Delete -Uri "${prefix}${controller}${apipath}sessions/${sessionid}" -ContentType "application/json" -Headers $headers
    
    if ($logoff.statuscode -like '204'){
        Write-Output "Successfully Logged Off"
    }

}

#function for interacting with the service-group
function server {
    #set the session authorization headers
    $headers = @{"Authorization" = "Session $sessionid"; "provider" = "root"; "tenant" = "$tenant"}
 
    #convert the body to JSON
    $body =  ConvertTo-Json -Compress @{"ipAddress" = "$server"; "port" = $port; "weight" = $weight}

    #powershell doesn't like top level arrays for JSON, so we're appending the brackets manually
    $body = "`[$body`]"

    Write-Output "Adding Server $server, with port $port, and weight $weight, to ServerGroup $servergroups in Service $service in Application $app"
    $server = Invoke-WebRequest -Method $method -Uri "${prefix}${controller}${apipath}applications/${app}/hosts/default-host/services/${service}/servergroups/${servergroups}/servers" -ContentType "application/json" -Headers $headers -Body $body

    #check that you got a 200 for success, then write output
    If($server.statuscode -eq '200'){
        Write-Output "Success!"
    }
    #if you didn't get a 200 then something went wrong, its probably time to exit
    Else{
        Write-Output "It looks like the was a problem adding Server $server, with port $port, and weight $weight, to ServerGroup $servergroups in Service $service in Application $app"
        Write-Output "Please double check your config file"
        Write-Output "Previously added servers will remain in the configuration"
        Write-Output "Exiting..."
        exit -1
    }

}

#function for parsing the config file
function useconfigfile{
    #yes, this regex is pretty sloppy, but we're just trying to do really basic validation
    $regex = '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\:[0-9]+\:[0-9]+'
    
    #read the config file into a variable
    $filedata = Get-Content $configfile

    #iterate through each line in the file
    foreach($line in $filedata) {
        #if you have a line that doesn't match your regex, set the error to true and then exit with error
        if($line -notmatch $regex){
            $error = $true
            if($error -eq $true){
                Write-Output "There is a problem with your config file, please make sure that the format matches the following:"
                Write-Output "ipaddress:port:weight"
                Write-Output "For example: 1.1.1.1:80:1"
                Write-Output "Exiting..."
                exit -1
            }
        }

    }
    
    #if the config file looks good, start blasting it out
    Write-Output "File format looks good, proceeding..."
    foreach($line in $filedata) {
            $server,$port,$weight = $line.split(':')
            server $server $port $weight  
    }
}
#---------------------------------------------------------[Functions]--------------------------------------------------------


#---------------------------------------------------------[Script]--------------------------------------------------------


#authenticate and store the session id
$sessionid = authenticate
#this logic is outside of the function since powershell treats any output in a function as return values...

#if you didn't get a sessionid quit
if ($sessionid -eq ""){
    Write-Output "Unable to successfully authenticate, exiting"
    exit -1
}
    
#otherwise give the user something to read
else{
    Write-Output "Successfully authenticated, session-id is: $sessionid"
        
}

#if you specified a config file, use that
if ($configfile){
    useconfigfile $sessionid
}
#otherwise just use the single call method
else{
    server $sessionid
}

#you're done, log off
logoff $sessionid
#---------------------------------------------------------[Script]--------------------------------------------------------
