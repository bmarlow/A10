<#
.SYNOPSIS
    Upgrade one or multiple ACOS devices simultaneously

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

.PARAMETER UpdateBootImage
    --Optional -- Whether or not to update the boot location for the device to the new image

.PARAMETER User
    --Optional -- The username of the admin to log into the A10 device

.PARAMETER Pass
    --Optional -- The password of the admin to log into the A10 device

.EXAMPLES

    ./upgrade.ps1 -DeviceAddress 10.0.0.1 -UpgradeFile "C:\Users\admin\ACOS_non_FTA_4_1_1_267.64.upg" -Partition "pri" -Media "hd" -MD5SUM "9FB4D5EC641220C2FC9DB285BF91F453" -reboot
    

.NOTES
    Version:        1.0
    Author:         Brandon Marlow - bmarlow@a10networks.com
    Creation Date:  12/22/2016
    Purpose/Change: Initial script development
    Credit:         Thanks to John Lawrence for building much of the inital framework that was re-used by this script

.LINK
    www.a10networks.com
#>



#jobify stuff
#general cleanup





param (
    [Parameter(Mandatory=$True)] 
    [string]$DeviceAddress,
    
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
    [switch]$updatebootimage, 
    
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


#force TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;



$script:headers = @{}
$script:results = @{}


#check to see if the media was specified, if not default to the harddrive
   
If (!($media)){
    $media="hd"
}

#----------------------------------------------------------[Declarations]----------------------------------------------------------
#Script Version
$sScriptVersion = "1.0"

#Set AXAPI location
$axapi = "axapi/v3"



$user = "admin"
$pass = "a10"




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


function call-axapi($deviceAddress, $module, $method, $body){


    Begin{
        #Write-Host "Sending $module to $deviceAddress."
        
        #Write-Host "method is:" $method "module is:" $module "body is:" $body 
    }
    Process{
        Try{
            #Set the base URI
            #UPDATE TO HTTPS
            $baseURI = "http://$deviceAddress/$axapi"

            if ($body) {
                #Write-Host "I think I have body to send"
                $result = Invoke-RestMethod -Uri $baseURI/$module -Method $method -Headers $script:headers -Body $body -ContentType application/json
            } else {
                #Write-Host "I'll issue the request w/o a body"
                $result = Invoke-RestMethod -Uri $baseURI/$module -Method $method -Headers $script:headers -ContentType application/json
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

function call-axapi-code-reponse($deviceAddress, $module, $method, $body){
    #seperate function written for when an AXAPI call may only give an HTTP response code as notification of success/failure
    #we have to use the invoke-webrequest commandlet because invoke-restmethod doesn't return the HTTP response code as a property, WTF?

    Begin{
        #Write-Host "Sending $module to $deviceAddress."
        
        #Write-Host "method is:" $method "module is:" $module "body is:" $body 
    }
    Process{
        Try{
            #Set the base URI
            #UPDATE TO HTTPS
            $baseURI = "http://$deviceAddress/$axapi"
            
            if ($body) {
                #Write-Host "I think I have body to send"
                $result = Invoke-WebRequest -Uri $baseURI/$module -Method $method -Headers $script:headers -Body $body -ContentType application/json
            } else {
                #Write-Host "I'll issue the request w/o a body"
                $result = Invoke-WebRequest -Uri $baseURI/$module -Method $method -Headers $script:headers -ContentType application/json
            }
            $result.statuscode
            

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



function authenticate($DeviceAddress) {
    #Write-Output "authenticating"
    If ($user -and $pass){
        $creds=@"
{"credentials": {"username": "$user", "password": "$pass"}}
"@
    }
    If (-Not $user -and $pass){

    $Creds = Get-Credential

    $user =  $creds.username
    $pass = $creds.GetNetworkCredential().password

    }

    $jsoncreds = @"
{"credentials": {"username": "$user", "password": "$pass"}}
"@


    #store the result of the function in the response (this is a PS object
    $response = call-axapi $DeviceAddress "auth" "Post" $jsoncreds
    
    #now we've got the value for the authorization signature
    $signature = $response.authresponse.signature
    
    #now we need to set the headers for global use
    $script:headers = @{ Authorization= "A10 $Signature" }
    Write-Host "The Result is:" $response
    
}

function hostname {
    $response = call-axapi $deviceAddress "hostname" "Get"
    $HostName = $response.hostname.value
    Write-Host "Device Hostname is: $Hostname"

}

function check-md5sum {
    
    If (!($MD5SUM)){
    Write-Host "You have not provided an MD5 Checksum to check against"
    Write-Host ""
    Write-Host "You can find what the MD5 Checksum of your package should be at https://www.a10networks.com/support/axseries/software-downloads"
    $continue = Read-Host "Would you like to continue anyway? Y/N [N]"
    
    Write-Host $continue.ToLower()
        If (($continue.ToLower() -eq "y") -or ($continue.ToLower() -eq "yes")){
            #$continue = $true
            Write-Host "Continuing at user request"
        }
        Else {
            Write-Host "Exiting at user request"
            exit(1)
        }
    }
    
    Write-Host "Getting MD5 Checksum of upgrade file..."
    $MD5 = Get-FileHash $UpgradeFile -Algorithm MD5

    If ($continue){

        Write-Host "Upgrade file name: $($MD5.path)"
        Write-Host "Upgrade MD5 Checksum: $($MD5.hash)"
        Write-Host "It is suggested that you manually verify the MD5 Checksum against the A10 published checksum before proceeding"
        $continue = Read-Host "Do you wish to continue? Y/N [N]"
        
        If (($continue.ToLower() -eq "y") -or ($continue.ToLower() -eq "yes")){
            #$continue = $true
            Write-Host "Continuing at user request"
        }
        Else {
            Write-Host "Exiting at user request"
            exit(1)
        }
    }
        
    ElseIf ($MD5.hash -ne $MD5SUM){
        Write-Host "************************************ERROR***********************************"
        Write-Host "****************************************************************************"
        Write-Host "MD5 provided: ( $MD5SUM ) does not match the calculated MD5 of the upgrade file ( $($MD5.hash) )"
        Write-Host ""
        Write-Host "Please verify the correct MD5 Checksum is being provided"
        Write-Host "If the MD5 Checksum provided matches that of the one listed at https://www.a10networks.com/support/axseries/software-downloads, please re-download the upgrade file"
        Write-Host "Exiting..."
        Pause
        Exit(1)
    }
    ElseIf ($MD5.hash -eq $MD5SUM){
        Write-Host "MD5 Checksum provided and MD5 of the upgrade file match, proceeding with upgrade"
    }
}

function file-load-encode {
    #because we only want to read the file into memory once (not once for each device!), we break the upgrade into two functions


    #read the file into memory (For parsing and the like, this is the easiest way to do this without doing some longer stuff in .NET
    $filebin = [System.IO.File]::ReadAllBytes($UpgradeFile)

    #set the encoding method for the file upload
    $enc = [System.Text.Encoding]::GetEncoding("iso-8859-1")

    #properly encode the file for multipart upload and make avialable outside the function
    $script:encodedfile = $enc.GetSTring($filebin)
}


function stage-upgrade {

    #we'll need the short filename later one so we split it, then grab the last part
    $filesplit = $UpgradeFile.split("\")
    
    $script:shortfilename = $filesplit[-1]
    

  
    #check if the reboot swtich is set, if it is set the reboot value to 1
    If ($reboot -eq "True"){
        $reboot="1"
    }
    Else {
        $reboot="0"
    }
    
    #build the json for the upgrade
    $script:upgradejsondata = @"
{"$media":{"image":"$partition","image-file":"$script:shortfilename","reboot-after-upgrade":$reboot}}
"@

}


function upgrade ($DeviceAddress) {

    #define an arbitrary and unique string for the multipart boundary (this runs in the upgrade section so that we can use the boundary to uniquely identify jobs)
    $boundary = [guid]::NewGuid().ToString()


    Write-Host "upgradejsondata defined"
    
    #build the multipart (numeric values populated by the field formatting in the body definition
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


    $body = $multipartdata -f $boundary, $script:shortfilename, $script:encodedfile, $script:upgradejsondata
    Write-Host "body defined"
    Write-Host "posting file"
    $response = Invoke-RestMethod -Uri https://$deviceAddress/axapi/v3/upgrade/$media -Method Post -ContentType "multipart/form-data; boundary=$boundary" -Body $body -Headers $script:headers 
    Write-Host $response.statuscode
}

function update-bootvar ($DeviceAddress){
    
    $bootvarjson=@"
{"bootimage":{"$media-cfg":{"$media":1,"$partition":1}}}
"@
    Write-Host "Updating bootvar"
    $response = call-axapi $DeviceAddress "bootimage" "Post" $bootvarjson
    Write-Host $response.response.msg
}


function get-bootvar ($DeviceAddress){
    $response = call-axapi $DeviceAddress "bootimage/oper" "get"
    Write-Host "Device is currently set to boot from the following location:" $response.bootimage.oper."hd-default"
}

function get-ver ($DeviceAddress){
    $response = call-axapi $DeviceAddress "version/oper" "get"
    $runningver = $response.version.oper."$media-$partition"
    Write-Host "The version currently installed on $media-$partition is $runningver"
}


function reboot ($DeviceAddress){
    
    Write-Host "Calling reboot"
    $response = call-axapi-code-reponse $DeviceAddress "reboot" "Post"
 
}

function logoff($DeviceAddress){
    $logoff = call-axapi-code-reponse $deviceAddress "logoff" "Post"
    If (($logoff -notlike '5') -and ($logoff -notlike '4') -and ($logoff -notlike '203')){
        write-host "successfully logged off"
    }
    ElseIf ($logoff -eq '203'){
        Write-Host "Logoff attempted, but no auth token was presented.  Most likely there was a problem with authentication or the authorization token was missing."
    }

    Else{
        Write-Host "Logoff attempted, but server returned a response code of $logoff, this may occur if trying to run this script against the box while it is booting, please try again."
}
}




#-----------------------------------------------------------[Execution]------------------------------------------------------------



check-md5sum
authenticate $DeviceAddress
#hostname

get-ver $DeviceAddress
update-bootvar $DeviceAddress
get-bootvar $DeviceAddress

file-load-encode
stage-upgrade
upgrade $DeviceAddress
reboot $DeviceAddress
#logoff $DeviceAddress

#workflow:
#get current version from partition
#run upgrade without reboot
#get new version from partition
#if new != old update bootvar (if set)
#if new != old reboot (if set)


    #Write-Host $DeviceAddress
    authenticate $DeviceAddress
    #get-ver $DeviceAddress
    #logoff $DeviceAddress


