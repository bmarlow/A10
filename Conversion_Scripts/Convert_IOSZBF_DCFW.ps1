##Version 0.91

Param(
   [Parameter(Mandatory=$True,Position=1)]
   [string[]]$file,

#   [Parameter(Mandatory=$True,Position=1)]
#   [string[]]$portdictionary,
   
   [Parameter(Mandatory=$True,Position=1)]
   [string[]]$srczone,

   [Parameter(Mandatory=$True,Position=1)]
   [string[]]$dstzone

)


function ConvertWCtoCIDR($WC){
    $octet = $WC -split "\."
    $a = 255 - $octet[0]
    $b = 255 - $octet[1]
    $c = 255 - $octet[2]
    $d = 255 - $octet[3]
    $SM = "" + $a + "." + $b + "." + $c + "." + $d + ""
    Convert-RvNetSubnetMaskClassesToCidr($SM)
    #Write-Host $subnetMaskCidr
    

}

###Here be dragons###

Function Convert-RvNetSubnetMaskClassesToCidr($SubnetMask){ 
   
    [int64]$subnetMaskInt64 = Convert-RvNetIpAddressToInt64 -IpAddress $SubnetMask 
 
    $subnetMaskCidr32Int = 2147483648 # 0x80000000 - Same as Convert-RvNetIpAddressToInt64 -IpAddress '255.255.255.255' 
 
    $subnetMaskCidr = 0 
    for ($i = 0; $i -lt 32; $i++) 
    { 
        if (!($subnetMaskInt64 -band $subnetMaskCidr32Int) -eq $subnetMaskCidr32Int) { break } # Bitwise and operator - Same as "&" in C# 
 
        $subnetMaskCidr++ 
        $subnetMaskCidr32Int = $subnetMaskCidr32Int -shr 1 # Bit shift to the right - Same as ">>" in C# 
    } 
 
    # Return 
    $subnetMaskCidr 
}


###Here be bigger dragons###

Function Convert-RvNetIpAddressToInt64($IpAddress) { 
  
    $ipAddressParts = $IpAddress.Split('.') # IP to it's octets 
 
    # Return 
    [int64]([int64]$ipAddressParts[0] * 16777216 + 
            [int64]$ipAddressParts[1] * 65536 + 
            [int64]$ipAddressParts[2] * 256 + 
            [int64]$ipAddressParts[3]) 
}


##Cisco auto converts ports to protocol names which makes things complicated
##Here we build a a dictionary with a port to protocol name mapping of the common IOS protocol conversions
$ports = Import-Csv -Path port-dictionary.csv
$portdictionary=@{}
foreach ($port in $ports){
    $portdictionary[$port.Description]=$port.port
}

#Simple function used to determine if a string value is numeric
function isNumeric ($x) {
    try {
        0 + $x | Out-Null
        return $true
    } catch {
        return $false
    }
}


#load the file with the ACL
$filecontents = Get-Content $file
$num = 1

#split each line into an array
Foreach ($line in $filecontents){
    $element = $line -split " "

    ###Start writing the rule
        
        ##Write your rule number        
        Write-Output $("Rule " + $num + "")
        Write-Output $(" action " + $element[0] + "")

        ##Source address block
        
        ##If format is permit udp host
        If ($element[2] -eq "host"){
            Write-Output $(" source ipv4-address " + $element[3] + "")
            }
        
        ##If format is permit udp any
        ElseIf ($element[2] -eq "any"){
            Write-Output " source ipv4-address any"
            }
        
        ##If we don't match the first two 
        Else {
            Write-Output $(" source ipv4-address " + $element[2] + "/" + $(ConvertWCtoCIDR($element[3])))
            }
        
        ##Putting in the source zone
        Write-Output $(" source zone " + $srczone + "")
        
        
        ###Destination Address Block

        ##If format is permit udp 1.1.1.1 0.0.0.0 host 2.2.2.2 eq 53
        If ($element[4] -eq "host"){
            Write-Output $(" dest ipv4-address " + $element[5] + "")
            }
        
        ##If format is permit udp 1.1.1.1 0.0.0.0 any eq 53
        ##Or if format is permit udp any any eq 53
        ElseIf ($element[3] -eq "any" -Or $element[4] -eq "any"){
            Write-Output " dest ipv4-address any"
            }

        ##If format is permit udp any 1.1.1.1 0.0.0.0 eq 53
        ElseIf ($element[2] -eq "any"){
            Write-Output $(" dest ipv4-address " + $element[3] + "/" + $(ConvertWCtoCIDR($element[4])))
            }
        
        ##If format is permit udp 1.1.1.1 0.0.0.0 2.2.2.2 0.0.0.0 eq 53
        Else {
            Write-Output $(" dest ipv4-address " + $element[4] + "/" + $(ConvertWCtoCIDR($element[5])))
            }
        

        ##Putting in the destination zone
        Write-Output $(" dest zone " + $dstzone + "")
             
  
  


        If ($element[-3] -eq "range"){

        $port1 = isnumeric($element[-2])
        $port2 = isnumeric($element[-1])

            If ($port1-eq $true -And $port2 -eq $true){
                Write-Output $(" service " + $element[1] + " dst range " + $element[-2] + " " + $element[-1] + "")
                }
                

            ElseIf ($port1 -eq $true -And $port2 -eq $false){
                $portnum = $portdictionary.Item($element[-1])
                Write-Output $(" service " + $element[1] + " dst range " + $element[-2] + " " + $portnum + "")
                }
           
            ElseIf ($port1-eq $false -And $port2 -eq $true){
                $portnum = $portdictionary.Item($element[-2])
                Write-Output $(" service " + $element[1] + " dst range " + $portnum + " " + $element[-1] + "")
                }
           
            ElseIf ($port1 -eq $false -And $port2 -eq $false){
                $portnum1 = $portdictionary.Item($element[-2])
                $portnum2 = $portdictionary.Item($element[-1])
                Write-Output $(" service " + $element[1] + " dst range " + $portnum1 + " " + $portnum2 + "")
                }
            Else {
                Write-Output "You didn't match any"
                }


            }
        
        Else {
            If (isNumeric($element[-1]) -eq $true){
                Write-Output $(" service " + $element[1] + " dst " + $element[-2] + " " + $element[-1] + "")
            }
            Else {
                $portnum = $portdictionary.Item($element[-1])
                Write-Output $(" service " + $element[1] + " dst " + $element[-2] + " " + $portnum + "")
                }
        }

        pause

   $num = $num + 1
    }






<#

    ######There are 8 ACL formats that we need to be able to deal with:
    ###### host --> host:port
    ###### host --> host:range
    ###### host --> network:port
    ###### host --> network:range
    ###### network --> host:port
    ###### network --> host:range
    ###### network --> network:port
    ###### network --> network:range
    #### elements of the array start at 0
    ##if element 2 & 4 are host its host to host
    ##if element 2 is host and 4 is not host, we know its host to network
    ##if element 2 is not host and 4 is host, we know its network to host
    ##if element 2 is not host and 4 is not host we know its network to network
    ##ranges if element 6 == range we know its a range


function HostToHostWithRange($element){
}
function HostToHostWithoutRange($element){
}
function HostToNetworkWithRange($element){
}
function HostToNetworkWithoutRange($element){
}
function NetworkToHostWithRange($element){
}
function NetworkToHostWithoutRange($element){
}
function NetworkToNetworkWithRange($element){
}
function NetworkToNetworkWithoutRange($element){
}




    
   #Host to host check
   If ($element[2] -And $element[4] -eq 'host'){
     If ($element[6] -eq 'range'){
        HostToHostWithRange($line)
        }
     Else{
        HostToHostWithoutRange($line)
        }
     }
   #Host to network check
   ElseIf (($element[2] -eq 'host') -And ($element[4] -ne 'host')){
     If ($element[6] -eq 'range'){
        HostToNetworkWithRange($line)
        }
     Else{
        HostToNetworkWithoutRange($line)
        }
     }

   #Network to host check
   ElseIf (($element[2] -ne 'host') -And ($element[4] -eq 'host')){
     If ($element[6] -eq 'range'){
        NetworkToHostWithRange($line)
        }
     Else{
        NetworkToHostWithoutRange($line)
        }
     }
    #Network to network check
    ElseIf (($element[2] -ne 'host') -And ($element[4] -ne 'host')){
     If ($element[6] -eq 'range'){
        NetworkToNetworkWithRange($line)
        }
     Else{
        NetworkToNetworkWithoutRange($line)
        }
     }
#>