[xml]$xml = Get-Content C:\Users\bud\Dropbox\a10\Configs\Retail\S170-A4934CAB1174-FTX1628M039-20160920T150106.xml


#hey you gotta start somehwere, right?
#$foo = $xml.config.wga_config.prox_acl_custom_categories | Select -ExpandProperty childnodes | where {$_.prox_acl_custom_category_name -like 'PP XBOX'} | select -ExpandProperty prox_acl_custom_category_servers
#$foo | select -ExpandProperty childnodes

$listnames = $xml.config.wga_config.prox_acl_custom_categories.prox_acl_custom_category.prox_acl_custom_category_name


ForEach ($listname in $listnames)
    {
    
    Write-host $listname
    Write-Host " "
    $sites = $xml.config.wga_config.prox_acl_custom_categories | Select -ExpandProperty childnodes | where {$_.prox_acl_custom_category_name -like $listname} | select -ExpandProperty prox_acl_custom_category_servers
    $sites | select -ExpandProperty innerxml

    pause
    }
