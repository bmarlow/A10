#!/usr/bin/env python
#
# Copyright 2016, John Lawrence <jlawrence AT a10networks DOT com>
#
# v0.3: 20160720 - Display the ACOS installed versions
# v0.4: 20160721 - Added option to reboot following an upgrade
# v0.5: 20160721 - Improved handling of connection errors
# v0.6: 20160725 - Allow multiple devices to be included in the arguments list
# v0.7: 20160728 - Corrected axapi_status() to not crash
# v0.8: 20160730 - Minor formatting and improvements
#
# Requires:
#   - Python 2.7.x
#   - aXAPI V3
#   - ACOS 3.0 or higher
#
# TODO: Add option to run multiple threads simultaniously
#       Figure out how to deal w/ TLS_1.2 requirement when OpenSSL < 1.0.1
#       Read defaults from an external file (e.g. acos_upgrade.config)



import argparse
import getpass
import json
import logging
import os
import requests
import sys



#
# DEFAULT SETTINGS
# Settings here will override the built-in defaults. Can be overridden by 
# runtime arguments supplied at the CLI.
#

#default_upgrade_url = 'tftp://10.8.8.1/ACOS_non_FTA_3_2_1-SP2_4.64.upg'
#default_devices_file = 'hosts.txt'
#default_use_management = False



#
# Create and capture the command-line arguments
#
parser = argparse.ArgumentParser( description='Running this script will use the A10 AXAPI to copy a file to/from one or more devices.')
devices = parser.add_mutually_exclusive_group()
devices.add_argument( '-df', '--devicesfile', default='', dest='devices_file', help='Simple text file containing a list of devices, one per line')
devices.add_argument( '-d', '--devices', default='', help='A10 device hostname or IP address. Multiple devices may be included seperated by a comma.')

#add an overwrrite flag at some point
#parser.add_argument( '--overwrite', action='store_true', help='Overwrite the currently booted image. Default action will upgrade the non-booted image version')


#local a10 user information
parser.add_argument( '-ap', '--a10_password', default='', help='A10 administrator password' )
parser.add_argument( '-au', '--a10_username', default='', help='A10 administrator username' )

#remote (non a10) user information
parser.add_argument( '-rp', '--remote_password', default='', help='Remote password' )
parser.add_argument( '-ru', '--remote_username', default='', help='Remote username' )

#path and file args
parser.add_argument( '-pr', '--protocol', default='', help='Specify what protocol to use for copying the file')
parser.add_argument( '-p', '--path', default='', help='Remote file path for uploading/downloading file')
parser.add_argument( '-f', '--filename', default='', help='name of the file to be copied')

parser.add_argument( '-di', '--direction', default='', help='Specify the direction of the file transfer [inbound/outbound] direction is relative to the A10 device')
parser.add_argument( '-m', '--use-mgmt', dest='use_mgmt', action='store_const', const=1, default=0, help='Use the management port for the file transfer')

parser.add_argument( '-v', '--verbose', action='count', help='Enable verbose detail')



try:
    args = parser.parse_args()
    devices = args.devices.split(',')
    devices_file = args.devices_file
 #   overwrite_bootimage = args.overwrite
    a10_password = args.a10_password
    a10_username = args.a10_username
    remote_password = args.remote_password
    remote_username = args.remote_username
    protocol = args.protocol
    path = args.path
    filename = args.filename
    direction = args.direction
    use_mgmt = args.use_mgmt
    verbose = args.verbose
except IOError, msg:
    parser.error(str(msg))


#
# Done with arguments. The actual program begins here.
#

def main():
    print ('hello from main()')
    
    for appliance in device_list:
        appliance=Acos(appliance)

        r = appliance.authenticate(a10_username, a10_password)
        if r == 'FAIL':
            continue
        appliance.get_hostname()
        appliance.file_copy()
        print(r)


        appliance.logoff()
    print('')
    print('DONE at main()\n')





def oldmain():
    """docstring for main"""
    upgrade = get_url_components(upgrade_url)

    for appliance in device_list:
        appliance=Acos(appliance)

        r = appliance.authenticate(username, password)
        if r == 'FAIL': continue
        
        appliance.get_hostname()

        appliance.show_version()

        r = appliance.get_bootimage()
        if r == 'FAIL': continue

        if overwrite_bootimage:
            appliance.upgrade_image(upgrade, 'active')
        else:
            appliance.upgrade_image(upgrade)
        appliance.show_bootimage()

        if write_memory:
            appliance.write_memory()
        if reboot:
            appliance.write_memory()
            appliance.reboot()
        else:
            appliance.logoff()
        print('')
    print('DONE\n')


def read_devices_file(the_file):
    """docstring for read_devices_file"""
    print('  INFO: Looking for device addresses in %s' %the_file)
    try:
        devices = []
        plural = ''
        with open(the_file) as f:
            for device in f.readlines():
                if device.startswith('#') or device.rstrip() == '':
                    # Skip comments and blank lines
                    continue
                devices.append(device.rstrip())
                number_of_devices = len(devices)
            if number_of_devices != 1:
                plural='es'
            print ('  INFO: Found %d device address%s.'
                  %(number_of_devices, plural))
            return devices
    except:
        print('\n  ERROR: Unable to read %s.' %the_file)
        sys.exit(1)


def get_url_components(url):
    """docstring for get_url_components"""
    sliced_url = url.split('://',1)
    upgrade_protocol = sliced_url[0]
    remainder = sliced_url[1]
    
    sliced_url = remainder.split('/',1)
    server = sliced_url[0]
    path_and_file = sliced_url[1]
    upgrade_file = path_and_file[
        path_and_file.rfind('/', 0, len(path_and_file)) + 1:len(path_and_file)]
    server_has_credentials = server.find('@',0,len(server))
    if server_has_credentials > 0:
        server_sliced = server.split('@',1)
        server_authentication = server_sliced[0]
        server_address = server_sliced[1]
    else:
        server_authentication = ''
        server_address = server
    
    components = {'protocol': upgrade_protocol.upper(),
                'authentication': server_authentication,
                'address': server_address,
                'path': path_and_file,
                'filename': upgrade_file ,
                'uri': url }
    return components


class Acos(object):
    """docstring for Acos"""
    def __init__(self, address):
        super(Acos, self).__init__()
        self.device = address
        self.base_url = 'https://' + address + '/axapi/v3/'
        self.headers = {'content-type': 'application/json'}
        self.token = ''
        self.hostname = ''
        self.versions = {}
    
    def authenticate(self, username, password):
        """docstring for authenticate"""
        print('\nLogging onto %s...' % self.device)
        module = 'auth'
        method = 'POST'
        payload = {"credentials": {"username": username, "password": password}}
        try:
            r = self.axapi_call(module, method, payload)
        except Exception as e:
            print('  ERROR: Unable to connect to %s - %s' %(self.device, e))
            return 'FAIL'
        try:
            token =  r.json()['authresponse']['signature']
            self.headers['Authorization'] =  'A10 {}'.format(token)
        except:
            print('\n  ERROR: Login failed!')
            return 'FAIL'
    
    
    def axapi_call(self, module, method='GET', payload=''):
        """docstring for axapi"""
        url = self.base_url + module
        if method == 'GET':
            r = requests.get(url, headers=self.headers, verify=False)
        elif method == 'POST':
            r = requests.post(url, data=json.dumps(payload), headers=self.headers, verify=False)
        if verbose:
            print(r.content)
        return r
    
    
    def axapi_status(self, result):
        """docstring for get_axapi_status"""
        try:
            status = result.json()['response']['status']
            if status == 'fail':
                error = '\n  ERROR: ' + result.json()['response']['err']['msg']
                return error
            else:
                return status
        except:
            good_status_codes = ['<Response [200]>','<Response [204]>']
            status_code = str(result)
            if status_code in good_status_codes:
                return 'OK'
            else:
                return status_code
    
    
    def get_hostname(self):
        """docstring for get_hostname"""
        module = 'hostname'
        r = self.axapi_call(module)
        hostname = r.json()['hostname']['value']
        self.hostname = hostname
        print('    ' + self.device + ' Hostname is : ' + hostname )

    def file_import(self):
        module = 'import'
        method = 'POST'
        payload = {""}

    def file_export(self):
        module = 'export'
        method = 'POST'
        payload = {""}

    def file_copy(self):
        module = 'copy'
        method = 'POST'
        payload = {"copy":{"running-config":1,"dest-remote-file":"sftp://bud:Mazda84!@10.0.1.20:/home/bud/acos-running-config"}}
        r = self.axapi_call(module, method, payload)
        print(r)

    
    def show_version(self):
        """docstring for show_version"""
        module = 'version/oper'
        r = self.axapi_call(module)
        self.versions = r.json()['version']['oper']
    
    
    def get_bootimage(self):
        """docstring for bootimage"""
        try:
            boot_location = self.versions['boot-from']
            if boot_location == 'HD_PRIMARY':
                self.current_image = 'primary'
            elif boot_location == 'HD_SECONDARY':
                self.current_image = 'secondary'
        except:
            print('\n  ERROR: Cannot determine boot location!')
            return 'FAIL'
        print("   %s: Booted from the %s image" 
             %(self.hostname, self.current_image) )
        return self.current_image
    
    
    def upgrade_image(self, upgrade, image_location='standby'):
        """docstring for upgrade_image"""
        if image_location == 'active':
            upgrade_location = self.current_image
        elif image_location == 'standby':
            if self.current_image == 'primary':
                upgrade_location = 'secondary'
            elif self.current_image == 'secondary':
                upgrade_location = 'primary'
            else:
                print('Something went wrong')
        else:
            print('\n  ERROR: Invalid upgrade location')
        
        short_upgrade_location = upgrade_location[:3]
        print("   %s: Upgrading %s image using %s" 
            %(self.hostname,
            upgrade_location,
            upgrade['protocol'] ))
        print('      This may take some time...')
        module = 'upgrade/hd'
        method = 'POST'
        payload = { "hd": { "image": short_upgrade_location,
                            "use-mgmt-port": upgrade_use_mgmt,
                            "file-url": upgrade['uri'] } }
        r = self.axapi_call(module, method, payload)
        print('      %s' %self.axapi_status(r) )
        
        
        
        if set_bootimage:
            print("   %s Updating bootimage to %s..." 
                %(self.hostname, upgrade_location))
            module = 'bootimage'
            method = 'POST'
            payload = {"bootimage": {"hd-cfg": {"hd": 1, short_upgrade_location: 1}}}
            r = self.axapi_call(module, method, payload)
            print('      %s' %self.axapi_status(r) )
    
    
    def write_memory(self):
        """docstring for write_memory"""
        print("   %s: Saving configuration" %self.hostname)
        module = 'write/memory'
        method = 'POST'
        r = self.axapi_call(module, method)
        print('      %s' %self.axapi_status(r) )
    
    
    def show_bootimage(self):
        """docstring for show_bootimage"""
        module = 'bootimage/oper'
        r = self.axapi_call(module)
        bootimage = r.json()['bootimage']['oper']
        star='(*)'
        pri_star=''
        sec_star=''
        if bootimage['hd-default']=='hd-pri':
            pri_star = star
        elif bootimage['hd-default']=='hd-sec':
            sec_star = star
        print('')
        print('      %s: ACOS Versions' %self.hostname)
        print('      --------------------------------------------')
        print('      HD Primary:   %s %s' %(bootimage['hd-pri'], pri_star))
        print('      HD Secondary: %s %s' %(bootimage['hd-sec'], sec_star))
        print('      --------------------------------------------')
        print('')
        pass
    
    
    def reboot(self):
        """docstring for reboot"""
        print("   %s: Rebooting. The appliance will be unavailable for up to 5 minutes..." 
            %self.hostname)
        module = 'reboot'
        method = 'POST'
        payload = {'reboot': {'reason': 'ACOS upgrade'}}
        r = self.axapi_call(module, method, payload)
        print('      %s' %self.axapi_status(r) )
    
    
    def logoff(self):
        """docstring for logoff"""
        print("   %s: Logging off..." %self.hostname)
        module = 'logoff'
        method = 'POST'
        r = self.axapi_call(module, method)
        print('      %s' %self.axapi_status(r) )


def checkinputs():

    global devices_file
    global device_list
    global devices_file
    global verbose
    global a10_username
    global a10_password
    global remote_username
    global remote_password
    global protocol
    global filename
    global path
    global direction


    if not devices_file and devices[0] == '':
        print('you must specify either a file containing devices or a comma sperated list (use -h for usage)')
        sys.exit(1)
   
    device_list = []
    
    if devices_file:
        device_list = read_devices_file(devices_file)
    elif devices:
        device_list = devices
   
    if verbose < 2:
        logging.captureWarnings(True)

    if not a10_username:
        a10_username = raw_input('\nEnter A10 username: ')

    if not a10_password:
        a10_password = getpass.getpass('\nEnter password for ' + a10_username + ':')

    if not remote_username:
        remote_username = raw_input('\nEnter Remote username: ')

    if not remote_password:
        remote_password = getpass.getpass('\nEnter password for ' + remote_username + ':')

    if not protocol:
        while protocol != 'sftp' and protocol != 'scp' and protocol != 'ftp' and protocol != 'tftp':   
            protocol = raw_input('Please enter a vaild protocol for the file transfer: ')
            protocol = protocol.lower()
            continue

    if protocol:
        while protocol != 'sftp' and protocol != 'scp' and protocol != 'ftp' and protocol != 'tftp':   
            print('Sorry, ' + protocol + ' is not a valid choice')
            protocol = raw_input('Please enter a vaild protocol for the file transfer: ')
            protocol = protocol.lower()
            continue


    if not filename:
        filename = raw_input('\nPlease enter the name of the file to be transferred: ')

    if not path:
        path = raw_input('\nPlease enter the remote path of the file: ')
        if path.endswith('\\') or path.endswith('/'):
            path = path[:-1]
            print(path)


    
    if not direction:
        while True:
            print('not direction')
            direction = raw_input('\nPlease enter the direction of the file transfer relative to the A10 device [INBOUND/OUTBOUND]: ')
            direction = direction.lower()
            if direction != 'inbound' and direction != 'outbound':
                print('Sorry, ' + direction + ' is not a valid selction.')
                print('Please try again')
                continue
            elif direction == 'inbound':
                print('File will be transferred TO the A10 device(s)')
                break
            elif direction == 'outbound':
                print('File will be transferred FROM the A10 device(s)')
                break 

    if direction:
        while direction != 'inbound' and direction != 'outbound':
            print('Sorry, ' + direction + ' is not a valid selection.')
            direction = raw_input('\nPlease enter the dicrection of the file transfer relative to the A10 device [INBOUND/OUTBOUND]: ')
            direction = direction.lower()
            continue



if __name__ == '__main__':
    finished = False
    while not finished:
        try:
            checkinputs()
            main()
            finished = True

        except KeyboardInterrupt:
            print('Exiting')
            finished = True