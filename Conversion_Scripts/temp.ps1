#title           :Convert_IOSZBF_DCFW.ps1
#description     :This script will take an IOS configuration using ZBF and convert it to the appropriate A10 config (policy only)
#author		     :Brandon Marlow
#date            :05/17/2016
#version         :1.0
#usage		     :Convert_IOSZBF_DCFW.ps1 -file [IOS config] >> OUTPUTFILENAME.txt
#==============================================================================


<#The Script flows as follows:
Read the contents of the IOS config into memory
Find the lines that contain the zone-pair service-policies
Store those values (the line numbers) in a hash table
Iterate through that hashtable to lookup the lines and then parse out the zone pairing as well as the associated service policy
Store that data in a new hash table
Iterate through the new hash table to find the policy maps associated to the service-policy
Store that data in a new hash table
Iterate through the new hash table to find the ACLs referenced by the policy maps
Store that data in a new hash table
Itertate through that hashtable to get the access-list data
Store the lines of the access lists in an array
Loop through each item of the array, breaking it into individual elements
Check some element values to see what we should pull for the ACOS firewall config
Write out the firewall rules

Yes, we could have just updated the same hashtable over and over with new values, but by using different hashtables we can go back and verifiy if something goes wrong more easily


#>

#get the params


Param(
   [Parameter(Mandatory=$True,Position=1)]
   [string[]]$file

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

#common ip protocol numbers
$protocolids = @{"0"="HOPOPT";"1"="ICMP";"2"="IGMP";"3"="GGP";"4"="IP-in-IP";"5"="ST";"6"="TCP";"7"="CBT";"8"="EGP";"9"="IGP";"10"="BBN-RCC-MON";"11"="NVP-II";"12"="PUP";"13"="ARGUS";"14"="EMCON";"15"="XNET";"16"="CHAOS";"17"="UDP";"18"="MUX";"19"="DCN-MEAS";"20"="HMP";"21"="PRM";"22"="XNS-IDP";"23"="TRUNK-1";"24"="TRUNK-2";"25"="LEAF-1";"26"="LEAF-2";"27"="RDP";"28"="IRTP";"29"="ISO-TP4";"30"="NETBLT";"31"="MFE-NSP";"32"="MERIT-INP";"33"="DCCP";"34"="3PC";"35"="IDPR";"36"="XTP";"37"="DDP";"38"="IDPR-CMTP";"39"="TP++";"40"="IL";"41"="IPv6";"42"="SDRP";"43"="IPv6-Route";"44"="IPv6-Frag";"45"="IDRP";"46"="RSVP";"47"="GRE";"48"="MHRP";"49"="BNA";"50"="ESP";"51"="AH";"52"="I-NLSP";"53"="SWIPE";"54"="NARP";"55"="MOBILE";"56"="TLSP";"57"="SKIP";"58"="IPv6-ICMP";"59"="IPv6-NoNxt";"60"="IPv6-Opts";"62"="CFTP";"64"="SAT-EXPAK";"65"="KRYPTOLAN";"66"="RVD";"67"="IPPC";"69"="SAT-MON";"70"="VISA";"71"="IPCU";"72"="CPNX";"73"="CPHB";"74"="WSN";"75"="PVP";"76"="BR-SAT-MON";"77"="SUN-ND";"78"="WB-MON";"79"="WB-EXPAK";"80"="ISO-IP";"81"="VMTP";"82"="SECURE-VMTP";"83"="VINES";"84"="TTP";"85"="NSFNET-IGP";"86"="DGP";"87"="TCF";"88"="EIGRP";"89"="OSPF";"90"="Sprite-RPC";"91"="LARP";"92"="MTP";"93"="AX.25";"94"="IPIP";"95"="MICP";"96"="SCC-SP";"97"="ETHERIP";"98"="ENCAP";"100"="GMTP";"101"="IFMP";"102"="PNNI";"103"="PIM";"104"="ARIS";"105"="SCPS";"106"="QNX";"107"="A/N";"108"="IPComp";"109"="SNP";"110"="Compaq-Peer";"111"="IPX-in-IP";"112"="VRRP";"113"="PGM";"115"="L2TP";"116"="DDX";"117"="IATP";"118"="STP";"119"="SRP";"120"="UTI";"121"="SMP";"122"="SM";"123"="PTP";"124"="IS-IS-over-IPv4";"125"="FIRE";"126"="CRTP";"127"="CRUDP";"128"="SSCOPMCE";"129"="IPLT";"130"="SPS";"131"="PIPE";"132"="SCTP";"133"="FC";"134"="RSVP-E2E-IGNORE";"135"="Mobility Header";"136"="UDPLite";"137"="MPLS-in-IP";"138"="manet";"139"="HIP";"140"="Shim6";"141"="WESP";"142"="ROHC"}


#common tcp/udp protocol translations used by cisco in their ACLs
$portdictionary = @{"aol"="5190";"bgp"="179";"biff"="512";"bootpc"="68";"bootps"="67";"chargen"="19";"citrix-ica"="1494";"cmd"="514";"ctiqbe"="2748";"daytime"="13";"discard"="9";"domain"="53";"dnsix"="195";"echo"="7";"exec"="512";"finger"="79";"ftp"="21";"ftp-data"="20";"gopher"="70";"https"="443";"h323"="1720";"hostname"="101";"ident"="113";"imap4"="143";"irc"="194";"isakmp"="500";"kerberos"="750";"klogin"="543";"kshell"="544";"ldap"="389";"ldaps"="636";"lpd"="515";"login"="513";"lotusnotes"="1352";"mobile-ip"="434";"nameserver"="42";"netbios-ns"="137";"netbios-dgm"="138";"netbios-ssn"="139";"nntp"="119";"ntp"="123";"pcanywhere-status"="5632";"pcanywhere-data"="5631";"pim-auto-rp"="496";"pop2"="109";"pop3"="110";"pptp"="1723";"radius"="1645";"radius-acct"="1646";"rip"="520";"secureid-"="5510";"smtp"="25";"snmp"="161";"snmptrap"="162";"sqlnet"="1521";"ssh"="22";"sunrpc"="111";"syslog"="514";"tacacs"="49";"telnet"="23";"tftp"="69";"time"="37";"uucp"="540";"who"="513";"whois"="43";"www"="80";"xdmcp"="177"}



#$ports = Import-Csv -Path port-dictionary.csv
#$portdictionary=@{}
#foreach ($port in $ports){
#    $portdictionary[$port.Description]=$port.port
#}

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



#Get the zone pairs and their associated service-policy

    #create the hash table for the line numbers of the zone-pair and policy
    $zonepairandpolicylines = @{} 
    
    #create a hash table for the source+dest zone and service-policy pairs
    $zonepairandpolicy = @{}

    #create a hash table for the source+dest zone and the associated classmap
    $zonepairandclassmap = @{}

    #create a hash table for the source+dest zone and the associated ACL
    $zonepairandacl = @{}

    #create the zone pair index
    $zpindex = 1

#run through the policy and find any lines that use 'zone-pair' and store the line number in a hash table
Foreach ($line in $filecontents){

    If ($line.StartsWith("zone-pair") -eq "True"){
       $begin = $filecontents.IndexOf($line)
       $end = $begin + 1

       $zonepairandpolicylines.Add($zpindex,$begin)

       $zpindex = $zpindex + 1

       
        }

    }
#zonepairandpolicylines


#iterate through the hash table of lines to do stuff and determine the source and destination zone as well as the policy map associated, then put it in a new hash table
ForEach($value in $zonepairandpolicylines.Values){
 

    
    $numvalue = [int]$value
    $numnextvalue = $numvalue + 1

    $line1 = $filecontents[$numvalue]
    $line2 = $filecontents[$numnextvalue]

    $elements1 = $line1 -split " "
    
    ForEach($element in $elements1){
        
        If ($element -eq "source"){
            [int]$srcelement = $elements1.IndexOf($element)
            $srczoneelement = ($srcelement + 1)
            $srczone = $elements1[$srczoneelement]
            }
        
        If ($element -eq "destination"){
            [int]$dstelement = $elements1.IndexOf($element)
            $dstzoneelement = ($dstelement + 1)
            $dstzone = $elements1[$dstzoneelement]
            }   
        
            
        }
    $elements2 = $line2 -split " "
    $servicepolicy = $elements2[-1]



           $zonepairandpolicy.Add($srczone + "-->" +$dstzone,$servicepolicy)
           
    

    }
#$zonepairandpolicy


        
#iterate through the hash table of policy maps to get the corresponding classmaps, then put it in a new hash table
ForEach($name in $zonepairandpolicy.Keys){

    $policymap =  $zonepairandpolicy.Get_Item($name)
    ForEach($line in $filecontents){
    

        If ($line.StartsWith("policy-map type inspect " + $policymap) -eq "True"){
            $begin = $filecontents.IndexOf($line)
            
            $end = $begin + 1

            $classmapline = $filecontents[$end]

            $elements = $classmapline -split " "


            $classmap = $elements[-1]
            }
        }
    $zonepairandclassmap.Add($name,$classmap)
}
#$zonepairandclassmap


#iterate through the hash table of policy maps to get the corresponding classmaps, then put it in a new hash table
ForEach($name in $zonepairandclassmap.Keys){
    
    $classmap =  $zonepairandclassmap.Get_Item($name)
    ForEach($line in $filecontents){

        If ($line.StartsWith("class-map type inspect match-all " + $classmap) -eq "True"){
            $begin = $filecontents.IndexOf($line)

            $end = $begin + 1

            $aclline = $filecontents[$end]

            $elements = $aclline -split " "


            $acl = $elements[-1]
            }
        }
    $zonepairandacl.Add($name,$acl)
}#
$zonepairandacl
pause

#iterate through the hash table of acls to get the entries for each ACL

$num = 1
ForEach($name in $zonepairandacl.Keys){
    
    $acl =  $zonepairandacl.Get_Item($name)
    #Write-Host $acl
    #pause


    ForEach($line in $filecontents){

        If ($line.Equals("ip access-list extended " + $acl) -eq "True"){
            $aclarray = @()
            $acldef = $filecontents.IndexOf($line)
            $acldef = $acldef + 1

            $aclstart = $filecontents | select -Skip $acldef
            
            $zonepairandaclentry = $zonepairandacl.GetEnumerator() | Where-Object -Match -Property "value" -value $acl
            
            $zonepair = $zonepairandaclentry.key
            #$srczone,$dstzone = $zonepair.split('-->')
            
            #$aclcount = 0

            ForEach($aclline in $aclstart){
                #$aclcount = $aclcount + 1
                If ($aclline.StartsWith(" ") -eq "True"){
                    $aclline = $aclline.Trim()
                    $aclarray = $aclarray += $aclline
                    }
                Else{
                    
                    #split each line into an array
                    Foreach ($acl in $aclarray){
                        $element = $acl -split " "

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

                            
                       $num = $num + 1
                        }
                    #$aclcount = $aclcount - 1
                    #Write-Host $aclcount
                    #pause
                    Break
                    }
                }
            }
        }
    }

