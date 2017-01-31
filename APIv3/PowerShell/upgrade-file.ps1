<#
.SYNOPSIS
    Upgrade one or multiple ACOS devices

.DESCRIPTION
    This script will build a multipart payload that can be used to upgrade an ACOS device without using an external server.

.PARAMETER DeviceAddress
    The IP address or hostname of the A10 appliance you want to upgrade, multiple devices can be seperated by commas.

.PARAMETER DeviceFile
    A file containing multiple addresses or hostnames (one per line) that you wish to upgrade

.PARAMETER UpgradeFile
    The full local path of the upgrade file to be used

.PARAMETER Partition
    The partition which you would like to have upgraded pri or sec are acceptable values

.PARAMETER Media
    --Optional -- The install location of the new image cf or hd are acceptable values (hd is default)

.PARAMETER MD5SUM
    --Optional -- The MD5 Checksum of the upgrade file.  This can be obtained at https://www.a10networks.com/support/axseries/software-downloads

.PARAMETER Reboot
    --Optional -- Whether or not you would like to have the box reboot after the install has been performed

.PARAMETER UpdateBootVar
    --Optional -- Whether or not to update the boot location for the device to the new image

.PARAMETER DontWaitForReturn
    --Optional -- Whether or not we should wait for the device to come back and check version before moving to the next device

.PARAMETER User
    --Optional -- The username of the admin to log into the A10 device

.PARAMETER Pass
    --Optional -- The password of the admin to log into the A10 device

.EXAMPLE
    upgrade.ps1 -Devices 10.0.0.1,10.0.0.2,10.0.0.3 -UpgradeFile "C:\Users\admin\ACOS_non_FTA_4_1_1_267.64.upg" -Partition "sec" -Media "hd" -updatebootvar -reboot

.EXAMPLE
    upgrade.ps1 -DeviceFile "C:\Users\admin\devices.txt" -UpgradeFile "C:\Users\admin\ACOS_non_FTA_4_1_1_267.64.upg" -Partition "pri" -Media "cf" -updatebootvar -reboot
    
.EXAMPLE
    upgrade.ps1 -DeviceFile "C:\Users\admin\devices.txt" -UpgradeFile "C:\Users\admin\ACOS_non_FTA_4_1_1_267.64.upg" -Partition "pri" -Media "cf" -updatebootvar -reboot -user "admin" -pass "a10"


.NOTES
    Version:        1.2
    Author:         Brandon Marlow - bmarlow@a10networks.com
    Creation Date:  12/22/2016
    Rev 1.0:        Initial support for 4.x ACOS devices running AXAPIv3
    Rev 1.1:        Support added for 4.1.0 devices which don't fully use AXAPv3 for the upgrade
    Rev 1.2:        Intelligence added around checking device status before attempting upgrade (and not exiting the whole script on a failure)
    Credit:         Thanks to John Lawrence for building much of the inital framework that was re-used by this script

.LINK
    www.a10networks.com
#>

param (
    [Parameter(Mandatory=$False)] 
    [array]$Devices,
    
    [Parameter(Mandatory=$False)] 
    [string]$DeviceFile,
     
    [Parameter(Mandatory=$True)] 
    [string]$UpgradeFile, 
    
    [Parameter(Mandatory=$True)] 
    [ValidateSet("pri","sec")]
    [string]$partition, 
  
    [Parameter(Mandatory=$false)] 
    [ValidateSet("hd","cf")]
    [string]$media, 

    [Parameter(Mandatory=$false)] 
    [switch]$reboot, 

    [Parameter(Mandatory=$false)] 
    [switch]$updatebootvar, 

    [Parameter(Mandatory=$false)] 
    [switch]$dontwaitforreturn, 
    
    [Parameter(Mandatory=$False)] 
    [string]$MD5SUM, 
  
    [Parameter(Mandatory=$False)]
    [string]$user,

    [Parameter(Mandatory=$False)]
    [string]$pass
)
 
#---------------------------------------------------------[Initialisations]--------------------------------------------------------

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

$script:headers = @{}
$script:results = @{}

#--------------------------------------------------[Declarations and Sanity Checks]--------------------------------------------------
#Script Version
$sScriptVersion = "1.2"

#Set AXAPI location
$axapi = "axapi/v3"

#if you just want to use vanilla http (why?) you can change this to http
$prefix = "https:"

#get powershell version
$powershellversion = $PSVersionTable.PSVersion.Major

#require powershell version 4 or greater
If ($powershellversion -lt 4){
    cls
    Write-Output ""
    Write-Output "***************************************Error****************************************"
    Write-Output "This script requires powershell version 4 or higher for the functions that it uses."
    Write-Output "Please install PowerShell version 4 or greater, then try running the script again."
    exit(1)
}

If ((($Devices -eq $False) -and ($DeviceFile -eq $False)) -or (($Devices -eq $True) -and ($DeviceFile -eq $True))){
    Write-Output "You must specify either the -Devices --OR-- the -DeviceFile parameter"
    exit(1)
}

#if a file is specified read the file into an array
If ($DeviceFile){
    $Devices = Get-Content $DeviceFile
}

#check to see if the media was specified, if not default to the harddrive
If (!($media)){
    $media="hd"
}

If ($partition -eq "pri"){
    $script:longpartition = "primary"    
}
ElseIf ($partition -eq "sec"){
    $script:longpartition = "secondary"
}
#-----------------------------------------------------------[Functions]------------------------------------------------------------

#functions that can run outside of the loop
function check-md5sum {
    
    If (!($MD5SUM)){
    Write-Output "You have not provided an MD5 Checksum to check against"
    Write-Output ""
    Write-Output "You can find what the MD5 Checksum of your package should be at https://www.a10networks.com/support/axseries/software-downloads"
    Write-Output ""
    $continue = Read-Host "Would you like to continue anyway? Y/N [N]"
    
        If (($continue.ToLower() -eq "y") -or ($continue.ToLower() -eq "yes")){
            #$continue = $true
            Write-Output "Continuing at user request"
            Write-Output ""
        }
        Else {
            Write-Output "Exiting at user request"
            exit(1)
        }
    }
    
    Write-Output "*******************Getting MD5 Checksum of upgrade file***************************"
    $MD5 = Get-FileHash $UpgradeFile -Algorithm MD5
    If ($continue){

        Write-Output "Upgrade file name: $($MD5.path)"
        Write-Output "Upgrade MD5 Checksum: $($MD5.hash)"
        Write-Output "******************************************************************************"
        Write-Output ""
        Write-Output "It is suggested that you manually verify the MD5 Checksum against the A10 published checksum before proceeding"

        $continue = Read-Host "Do you wish to continue? Y/N [N]"
        
        If (($continue.ToLower() -eq "y") -or ($continue.ToLower() -eq "yes")){
            Write-Output "Continuing..."
        }
        Else {
            Write-Output "Exiting..."
            exit(1)
        }
    }
        
    ElseIf ($MD5.hash -ne $MD5SUM){
        Write-Output "************************************ERROR***********************************"
        Write-Output "****************************************************************************"
        Write-Output "MD5 provided: ( $MD5SUM ) does not match the calculated MD5 of the upgrade file ( $($MD5.hash) )"
        Write-Output ""
        Write-Output "Please verify the correct MD5 Checksum is being provided"
        Write-Output "If the MD5 Checksum provided matches that of the one listed at https://www.a10networks.com/support/axseries/software-downloads, please re-download the upgrade file"
        Write-Output "Exiting..."
        Exit(1)
    }
    ElseIf ($MD5.hash -eq $MD5SUM){
        Write-Output "MD5 Checksum provided and MD5 of the upgrade file match, proceeding"
    }
}

function get-creds {
    #if either user or pass is missing promt the user for it
    If ((-not $user) -or (-not $pass)){

        $Creds = Get-Credential -Message "Please enter administrator level credintials for the A10 Device"

        $script:user =  $creds.username
        #yes, technically this isn't saved into a secure string, but because we have to post the password in a json body we need the plaintext version
        $script:pass = $creds.GetNetworkCredential().password

    }

}

function stage-upgrade {

    #we'll need the short filename later one so we split it, then grab the last part
    $filesplit = $UpgradeFile.split("\")
    
    $script:shortfilename = $filesplit[-1]
    
    #build the json for the upgrade (we don't specify reboot here, but rather in a seperate function
    $script:upgradejsondata = @"
{"$media":{"image":"$partition","image-file":"$script:shortfilename","reboot-after-upgrade":0}}
"@

}

#functions that run inside of the loop

function call-axapi($device, $module, $method, $body){
    #a handy function wrapping axapi calls without having to write the invoke-restmethod every time, a good starting point if you need something for another script

    Begin{
        #if you need some pre-process stuff, add it here
    }
    Process{
        Try{
            #Set the base URI

            if ($body) {
                #for requests that have a body
                $result = Invoke-RestMethod -Uri $prefix//$device/$axapi/$module -Method $method -Headers $script:headers -Body $body -ContentType application/json
            } else {
                #for requests without a body
                $result = Invoke-RestMethod -Uri $prefix//$device/$axapi/$module -Method $method -Headers $script:headers -ContentType application/json
              }
            $result
            

        }
        Catch{
            invoke-web-failure
            Break
        }
    }
}

function call-axapi-code-reponse($device, $module, $method, $body){
    #seperate function written for when an AXAPI call may only give an HTTP response code as notification of success/failure
    #we have to use the invoke-webrequest commandlet because invoke-restmethod doesn't return the HTTP response code as a property, WTF?

    Begin{
        #if you need some pre-process stuff, add it here
    }
    Process{
        Try{
            #Set the base URI
            
            if ($body) {
                $result = Invoke-WebRequest -Uri $prefix//$device/$axapi/$module -Method $method -Headers $script:headers -Body $body -ContentType application/json
            } else {
                $result = Invoke-WebRequest -Uri $prefix//$device/$axapi/$module -Method $method -Headers $script:headers -ContentType application/json
            }
            $result.statuscode
            

        }
        Catch{
            invoke-web-failure
            Break
        }
    }
}

function authenticate($device) {
    Write-Output "$device Authenticating"
    $jsoncreds = @"
{"credentials": {"username": "$script:user", "password": "$script:pass"}}
"@

    #store the result of the function in the response (this is a PS object
    $response = call-axapi $device "auth" "Post" $jsoncreds
    
    #now we've got the value for the authorization signature
    $signature = $response.authresponse.signature
    
    #now we need to set the headers for global use
    $script:headers = @{ Authorization= "A10 $Signature" }

    Write-Output "$device Successfully authenticated"
}

function file-load-encode ($device) {
    #this function was stripped out of the upgrade function because of a desire to parallelize it without having to read the file into memory for each job, however that failed miserably, but I'll leave it like this
    #just in case I have an epiphany on how to handle it (or powershell jobs become a bit less hostile

    #read the file into memory (For parsing and the like, this is the easiest way to do this without doing some longer stuff in .NET (also, I don't know .NET, so there's that)
    
    Write-Output "$device Reading file into memory"
    $filebin = [System.IO.File]::ReadAllBytes($UpgradeFile)

    Write-Output "$device Setting encoding method for file"
    #set the encoding method for the file upload
    $enc = [System.Text.Encoding]::GetEncoding("iso-8859-1")

    Write-Output "$device Encoding file for upload"
    #properly encode the file for multipart upload and make avialable outside the function
    $script:encodedfile = $enc.GetSTring($filebin)

}

function legacy-upgrade ($device, $script:encodedfile){
    Write-Output "$device Entering Legacy Upgrade loop"
    #in early verisons of 4.1.0 the GUI upgrade did not 'fully' use the API
    #in this instance we must mimic a web session by authenticating through the GUI
    Write-Output "$device Creating Session"
    $url = "$prefix//$device/gui/auth/login/" 
    try{
        $webrequest = Invoke-WebRequest -Uri $url -SessionVariable websession
    }
    catch{
        invoke-web-failure
    }
    
    $cookies = $websession.Cookies.GetCookies($url) 

    $csrftoken = $cookies[1].Value

    $csrftoken = $csrftoken.Replace('"','')

    $body = "csrfmiddlewaretoken=$csrftoken&username=$script:user&password=$script:pass"

    try{
        $authrequest = Invoke-WebRequest -uri "$prefix//$device/gui/auth/login/" -Websession $websession -Body $body -Method Post
    }
    catch{
        Write-Output "$device Authentcation failed"
        invoke-web-failure
    }
    #after the authentication the cookie order is changed and the CSRF token is updated
    $cookies = $websession.Cookies.GetCookies($url) 

    $csrftoken = $cookies[0].Value

    $csrftoken = $csrftoken.Replace('"','')

    Write-Output "$device Authenticating"
    If ($authrequest.Content -like "*forbidden*"){
        Write-Output "$device Authentication failed"
    }
    Else{
        Write-Output "$device Successfully Authenticated"
    }
   
   
   
    #define an arbitrary and unique string for the multipart boundary (this runs in the upgrade section so that we can use the boundary to uniquely identify jobs)
    $boundary = [guid]::NewGuid().ToString()
    Write-Output "$device GUID generated for multipart boundary"

    #build the multipart (numeric values populated by the field formatting in the body definition)
    #the payload here consists of two parts, 1: the file stream, 2 the json for the axapi endpoint
    $multipartdata = @'
--{0}
Content-Disposition: form-data; name="csrfmiddlewaretoken"

{1}
--{0}
Content-Disposition: form-data; name="destination"

{2}
--{0}
Content-Disposition: form-data; name="staggered_upgrade_mode"

0
--{0}
Content-Disposition: form-data; name="device"


--{0}
Content-Disposition: form-data; name="reboot"

0
--{0}
Content-Disposition: form-data; name="save_config"

1
--{0}
Content-Disposition: form-data; name="local_remote"

0
--{0}
Content-Disposition: form-data; name="use_mgmt_port"

0
--{0}
Content-Disposition: form-data; name="protocol"

tftp
--{0}
Content-Disposition: form-data; name="host"


--{0}
Content-Disposition: form-data; name="port"


--{0}
Content-Disposition: form-data; name="location"


--{0}
Content-Disposition: form-data; name="user"


--{0}
Content-Disposition: form-data; name="password"


--{0}
Content-Disposition: form-data; name="upgrade_file_upload"; filename="{3}"
Content-Type: application/octet-stream

{4}
--{0}--

'@

    Write-Output "$device Multi-Part template defined"

    #Set required headers as dictated by the A10 device
    $headers = @{ "X-CSRFToken" = "$csrftoken"; "Referer" = "$prefix//$device/gui" }

    #defining the body of the axapi call by calling our mutlipart variable and then pouplating the fields (this is necessary with variables because the $encodedfile variable is ginormous)
    $body = $multipartdata -f $boundary, $csrftoken, $script:longpartition, $script:shortfilename, $script:encodedfile
    
    Write-Output "$device Multi-Part template populated"

    Write-Output "$device Uploading upgrade file, this may take a few minutes depending on your connection to the A10 Device, please wait"
    
    #you'll notice that we don't use one of the call-axapi methods above, its because this particular call is unique in that it is a multi-part upload
    
    try{ $response = Invoke-WebRequest -Uri $prefix//$device/gui/system/maintenance/upgrade/ -Method Post -ContentType "multipart/form-data; boundary=$boundary" -Body $body -WebSession $websession -headers $headers -TimeoutSec 999
    }
    catch{
        invoke-web-failure
    }       
    $responsecode = $response.statuscode
    
    If ($responsecode -notlike '2*'){
        Write-Host -BackgroundColor:Black -ForegroundColor:Red "$device Looks like there was a problem with the upgrade possibly the file is corrupt.  Did you verify the MD5 Checksum?"
        Write-Host -BackgroundColor:Black -ForegroundColor:Redt "$device Upgrade failed"
        continue
    }
    Else{
        Write-Output "$device Successfully upgraded, continuing with process"
    }

}

function invoke-web-failure {
    $global:helpme = $body
    $global:helpmoref = $moref
    $global:result = $_.Exception.Response.GetResponseStream()
    $global:reader = New-Object System.IO.StreamReader($global:result)
    $global:responseBody = $global:reader.ReadToEnd();
    Write-Host -BackgroundColor:Black -ForegroundColor:Red "$device Status: A system exception was caught."
    Write-Host -BackgroundColor:Black -ForegroundColor:Red "$device The failed request body was $global:helpme"
    Write-Output "Exiting"
    continue
}

function upgrade ($device, $script:encodedfile){

    #define an arbitrary and unique string for the multipart boundary (this runs in the upgrade section so that we can use the boundary to uniquely identify jobs)
    $boundary = [guid]::NewGuid().ToString()
    Write-Output "$device GUID generated for multipart boundary"

    #build the multipart (numeric values populated by the field formatting in the body definition)
    #the payload here consists of two parts, 1: the file stream, 2 the json for the axapi endpoint
    $multipartdata = @'
--{0}
Content-Disposition: form-data; name="file"; filename="{1}"
Content-Type: application/octet-stream

{2}
--{0}
Content-Disposition: form-data; name="json"; filename="blob"
Content-Type: application/json

{3}
--{0}--

'@

    Write-Output "$device Multi-Part template defined"

    #defining the body of the axapi call by calling our mutlipart variable and then pouplating the fields (this is necessary with variables because the $encodedfile variable is ginormous)
    $body = $multipartdata -f $boundary, $script:shortfilename, $encodedfile, $script:upgradejsondata
    Write-Output "$device Multi-Part template populated"
    
    Write-Output "$device Uploading upgrade file, this may take a few minutes depending on your connection to the A10 Device, please wait"
    
    #you'll notice that we don't use one of the call-axapi methods above, its because this particular call is unique in that it is a multi-part upload
    
    try{
        $response = Invoke-WebRequest -Uri $prefix//$device/$axapi/upgrade/hd -Method Post -ContentType "multipart/form-data; boundary=$boundary" -Body $body -Headers $script:headers -TimeoutSec 999
    }
    catch{
        invoke-web-failure
        continue
    }   
    $responsecode = $response.statuscode
    
    If ($responsecode -notlike '2*'){
        Write-Host -BackgroundColor:Black -ForegroundColor:Red "$device Looks like there was a problem with the upgrade possibly the file is corrupt.  Did you verify the MD5 Checksum?"
        Write-Host -BackgroundColor:Black -ForegroundColor:Red "$device Upgrade Failed"
        continue
    }
    Else{
        Write-Output "$device Successfully upgraded, continuing with process"
    }
}

function update-bootvar ($device){
    #if you're installing to the non-current partition, you'll probably want to update the boot variable

    $bootvarjson=@"
{"bootimage":{"$media-cfg":{"$media":1,"$partition":1}}}
"@
    Write-Output "$device Updating bootvar"
    
    $response = call-axapi $device "bootimage" "Post" $bootvarjson

    If($response.response.status -eq "OK"){
        Write-Output "$device Successfully updated the boot variable to $media-$partition"
        Write-Output "$device At next reboot the device will boot from $media-$partition"
    }
    Else{
        Write-Host -BackgroundColor:Black -ForegroundColor:Red "$device looks like there was a problem updating the boot variable"
        Write-Host -BackgroundColor:Black -ForegroundColor:Red "$device Failure to update the bootvariable may be indicitative of other problems"
        Write-Host -BackgroundColor:Black -ForegroundColor:Redt "$device Stopping this device upgrade process"
        continue
    }
}

function get-bootvar ($device){
    $response = call-axapi $device "bootimage/oper" "get"
    $bootdefault = $response.bootimage.oper."hd-default"
    Write-Output "$device Device is currently set to boot from the following location: $bootdefault"
}

function get-ver ($device){
    $response = call-axapi $device "version/oper" "get"
    $script:installedver = $response.version.oper."$media-$partition"
    Write-Output "$device The version currently installed on $media-$partition is $script:installedver"
}

function get-running-ver ($device){
    $response = call-axapi $device "version/oper" "get"
    $runningver = $response.version.oper."sw-version"
    $currentpart = $response.version.oper."boot-from"
    Write-Output "$device The current running version is $runningver"
    Write-Output "$device The Device is currently booted from $currentpart"

}

function reboot ($device){
    
    Write-Output "$device Calling reboot"
    $response = call-axapi-code-reponse $device "reboot" "Post"
    If ($response -like '2*'){
        Write-Output "$device Reboot command successfully received, device will reboot momentarily, please wait"
    }
 
}

function rebootmonitor ($device){
    $pingcount = 0
    do {
        $ping = Test-Connection $device -Quiet -Count 1
        Write-Output "$device Waiting for device to finish rebooting, please wait"
        $pingcount = $pingcount + 1
    }
    Until (($ping -eq $True) -or ($pingcount -eq 300))
        If ($ping -eq $true){
            #the device has started responding to ping but that doesn't mean that axapi is working yet, so we give it a few more seconds to initalize after the first ping responses
            Write-Output "$device Device is now initializing"
            Start-Sleep -Seconds 10
            Write-Output "$device Device has finished rebooting"
      
        }
        #if the pingcount goes above 300 there is probably an issue with the box that needs to be resolved manually
        ElseIf ($pingcount -eq 300){
            Write-Host -BackgroundColor:Black -ForegroundColor:Red "$device Device has not responded to 300 pings, please manually check device"
            Write-Host -BackgroundColor:Black -ForegroundColor:Red "$device Exiting..."
            continue
        }

}

function checkstatus ($device){
    $pingcount = 0
    do {
        $ping = Test-Connection $device -Quiet -Count 1
        Write-Output "$device Waiting for device to finish initialization, please wait"
        $pingcount = $pingcount + 1
    }
    Until (($ping -eq $True) -or ($pingcount -eq 2))
        If ($ping -eq $true){
            #the device has started responding to ping but that doesn't mean that axapi is working yet, so we give it a few more seconds to initalize after the first ping responses
            Write-Output "$device is Online."
            Write-Output "$device Please wait for device to finish initialization"
            Start-Sleep -Seconds 5
            Write-Output "$device is now ready"
      
        }
        #if the pingcount goes above 300 there is probably an issue with the box that needs to be resolved manually
        ElseIf ($pingcount -eq 2){
            Write-Host -BackgroundColor:Black -ForegroundColor:Red "$device Device is not up"
            Write-Host -BackgroundColor:Black -ForegroundColor:Red "$device Exiting"
            continue
        }

}


function logoff($device){
    $logoff = call-axapi-code-reponse $device "logoff" "Post"
    If (($logoff -notlike '5*') -and ($logoff -notlike '4*') -and ($logoff -notlike '203')){
        Write-Output "$device successfully logged off"
    }
    ElseIf ($logoff -like '2*'){
        Write-Output "$device Logoff attempted, but no auth token was presented.  Most likely there was a problem with authentication or the authorization token was missing."
    }

    Else{
        Write-Output "$device Logoff attempted, but server returned a response code of $logoff, this may occur if trying to run this script against the box while it is booting, please try again."
}
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------

#getting the MD5 of your upgrade file and whatnot
check-md5sum

#get creds (if applicable)
get-creds

#build some json for the loop
stage-upgrade

#iterating through each device that you provided
Foreach ($device in $devices){
    Write-Output ""
    Write-Output ""
    Write-Output "Results for $device"
    Write-Output "**************************************************************************************"
    Write-Output "**************************************************************************************"
    Write-Output ""
    checkstatus($device)
    authenticate $device
    get-ver $device
    get-bootvar $device
    file-load-encode $device
    
    #the initial release of 4.1.0 didn't support the full API upgrade methods in the GUI, this works around that
    if ($script:installedver -eq "4.1.0.454"){
        legacy-upgrade $device $script:encodedfile
    }
    Else{
        upgrade $device $script:encodedfile
    }

    get-ver $device
    get-bootvar $device
    
    #if you want to update the boot variable
    If ($updatebootvar -eq $True){
        update-bootvar $device
    }
    #if you don't want to update the boot variable we'll let you know
    Elseif ($updatebootvar -ne $True){
        Write-Output ""
        Write-Output "***************************NOTICE*NOTICE*NOTICE***************************************"
        Write-Output "Upgrade has been performed, however the bootvariable has not been updated"
    }

    #if you want to reboot
    If ($reboot -eq $True){
        reboot $device
                
        #if you don't set the don't wait for return flag on the command we will make sure that each has come up before proceeding and will exit if one fails
        If ($dontwaitforreturn -ne $True){
            #we issue a sleep here so that any delays in the reboot don't end up with us responding to a ping prematurely (and blowing up the rest of the script)
            #if you are having issues perhaps make this sleep command longer
            Start-Sleep -Seconds 10
            rebootmonitor $device
            #now we re-auth, get the version again and logoff
            authenticate $device
            get-running-ver $device
            logoff $device
            Write-Output "$device Upgrade successfully completed"
        }
        Else {
            Write-Output "$device The -dontwaitforreturn flag was set.  Immediately moving to the next device."
        }
    }
    
    #if you didn't set the reboot flag we'll let you know
    Elseif ($reboot -ne $True){
        Write-Output ""
        Write-Output "***************************NOTICE*NOTICE*NOTICE***************************************"
        Write-Output "Upgrade has been performed, however the device still needs to be rebooted to initialize the new code"
        logoff $device
    }
    
    Write-Output "**************************************************************************************"
    Write-Output "**************************************************************************************"
    Write-Output ""
    Write-Output ""
}
