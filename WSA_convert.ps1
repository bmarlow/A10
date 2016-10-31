[xml]$xml = Get-Content "C:\Users\bud\Dropbox (A10 Networks)\Configs\Retail\S170-A4934CAB1174-FTX1628M039-20160920T150106.xml"

$script:classlistblock = @()
$script:authservers = @()
$script:devicetimezone = ""

#hey you gotta start somehwere, right?
#$foo = $xml.config.wga_config.prox_acl_custom_categories | Select -ExpandProperty childnodes | where {$_.prox_acl_custom_category_name -like 'PP XBOX'} | select -ExpandProperty prox_acl_custom_category_servers
#$foo | select -ExpandProperty childnodes


Function WriteSection($sectionname,$sectiondata){
    Write-Host ""
    Write-Host "###Begin $sectionname Section###"
    Write-Host ""
    $sectiondata    
    Write-Host ""
    Write-Host "###End $sectionname Section###"
    Write-Host ""
}

Function CreateClassListDictionary(){
    #we have to create a dictionary of category names to their ID's because WSA likes to intermix them
     $section = "Class-List Dictionary"
     $global:acllist = @{}
     $acls = $xml.SelectNodes("//prox_acl_custom_categories").get_childnodes()

     ForEach ($acl in $acls){
        $categoryname =  $acl.prox_acl_custom_category_name
        $categorycode = $acl.prox_acl_custom_category_code
        $acllist.add($categorycode, $categoryname)
     }
    #$acllist.GetEnumerator()
}



Function ConvertClassLists(){
    $section = "Class-List"
    $classlists = $xml.config.wga_config.prox_acl_custom_categories.prox_acl_custom_category.prox_acl_custom_category_name

    BeginSection $section
    
    ForEach ($classlist in $classlists){
    

    #Write-host $classlist
    Write-Host " "
    $classlistproperties = $xml.config.wga_config.prox_acl_custom_categories | Select -ExpandProperty childnodes | where {$_.prox_acl_custom_category_name -like $classlist} | select -ExpandProperty childnodes
    
    $classlist = $classlist -replace ' ','_'

    $sites = $classlistproperties[4] | select -ExpandProperty prox_acl_custom_category_server

    #write out each site in the list
    
    $script:classlistblock += "class-list $classlist ac"

    #Write-Host "class-list" $classlist "ac"
        
        ForEach ($site in $sites){
            $script:classlistblock += " contains $site"
     #       write-host " contains" $site
        }

    }
    EndSection $section
}

Function ConvertRADIUSServers(){
   $section = "RADIUS Servers"
   $RADIUSData = $xml.SelectNodes("//radius_service_hosts").get_childnodes()
   $RADIUSSecret = Read-Host -Prompt "Please enter your RADIUS secret"
   BeginSection $section

   ForEach ($RADIUSNode in $RADIUSData){
        $RADIUSServer = $RADIUSNode.radius_hostname
        $RADIUSPort = $RADIUSNode.radius_port
        $RADIUSTimeout = $RADIUSNode.radius_timeout
        $script:authservers += "raidus-server host $RADIUSServer secret $RADIUSSecret auth-port $RADIUSPort timeout $RADIUSTimeout"
   }
   EndSection $section

}

Function ConvertTimeZone(){
    $section = "TimeZone"
    $TimeZone = $xml.SelectNodes("//timezone").get_innertext()
    $script:devicetimezone = $TimeZone
}

Function ConvertPolicy(){
    $section = "Proxy Policy"

    $policies = $xml.SelectNodes("//prox_acl_policy_groups").get_childnodes()


########
#need to parse the the sources into appropriate class-lists, then associate those sources with the proxy policy

#########

    ForEach ($policy in $policies){
        $policyid = $policy.prox_acl_group_id
        $policyuid = $policy.prox_acl_group_uid
        $policydesc = $policy.prox_acl_group_description
        $policyident = $policy.prox_acl_group_identities.prox_acl_group_identity.prox_acl_group_identity_name
        $rulegroups = $policy.prox_acl_group_customcat_actions.prox_acl_group_customcat_action
    
        
        If (-not $policyid){
            $policyid = "Default"
        }    
        
        #comment this out later    
        Write-Host $policyid

        $identity = $xml.SelectNodes("//prox_acl_identity_groups").get_childnodes() | Where { $_.prox_acl_group_id -like $policyident}

        Try{
                $ips = $identity.prox_acl_group_ips.get_childnodes() | Select -ExpandProperty innertext
        }
            
        Catch{
            $ips = "0.0.0.0/0"
        }

        #Getting the source networks for each policy


        $script:classlistblock += "class-list $policyid ipv4"
        Write-Host " class-list $policyid ipv4"

        ForEach ($ip in $ips){
            #Write-Host "  $ip"
            $script:classlistblock += " $ip"
        }

        ForEach ($rulegroup in $rulegroups){
        
            $categoryid =  $rulegroup.category_id
            $action = $rulegroup.category_action
            $categoryname = $acllist.Get_Item($categoryid)
            #comment the following line out later
            Write-Host ""$categoryname " --> " $action
    }





    }


}


Function MapAclGroupIDtoAclGroupIdenity(){
    #pretty sure that this is irrelevant and can be 
    
    $section = "MapAclGroupIDtoAclGroupIdenity"
    $global:policytoidentdict = @{}
    
    $prox_acl_group = $xml.SelectNodes("//prox_acl_policy_groups").get_childnodes()
    
    #this maps the prx_acl_group to the prx_acl_group_ident_name
    ForEach ($i in $prox_acl_group){
        
        $groupid = $i.prox_acl_group_id
        $identname = $i.prox_acl_group_identities.prox_acl_group_identity.prox_acl_group_identity_name
        
        If (-not $groupid){
            $groupid = "Default"
        }

        $policytoidentdict.add($groupid, $identname)
    }
    $policytoidentdict.GetEnumerator()
}


Function WriteTheConfig(){
    
    WriteSection "Class-Lists" $script:classlistblock
    #write the class-lists
    #$classlistblock

    WriteSection "Authentication Servers" $script:authservers
    #write the authentication servers
    #$authservers

    WriteSection "TimzeZone" $script:devicetimezone
    #write the timezone
    #$devicetimezone
}



#okay, now what you need to do is create the source class-lists
#then create the proxy policy where you map the source class-lists to the appropriate destinations


CreateClassListDictionary
#MapAclGroupIDtoAclGroupIdenity
ConvertClassLists
ConvertPolicy

ConvertRADIUSServers
ConvertTimeZone

WriteTheConfig