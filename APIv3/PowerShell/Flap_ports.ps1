#title           :print_cidr.ps1
#description     :This will print out a wad of cidr blocks
#author		     :Brandon Marlow
#date            :
#version         :
#usage		     :
#==============================================================================

#get the params

Do{
  ./clideploy -adc 10.3.147.36 -commands "interface 6, disable"

  sleep -Milliseconds 500

  ./clideploy -adc 10.3.147.36 -commands "interface 6, enable"

  sleep -Milliseconds 500
}
While (1 -eq 1)


