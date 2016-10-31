#!/usr/bin/env python
#
# 
#2016 - Brandon Marlow (credit to John Lawrence for the bones)
#
#
# Requires:
#   - Python 2.7.x
#   - aXAPI V3
#   - ACOS 3.0 or higher
#
# TODO: Add option to run multiple threads simultaniously
#       Figure out how to deal w/ TLS_1.2 requirement when OpenSSL < 1.0.1


import argparse
import getpass
import json
import logging
import os
import requests
import sys
import time
import datetime



#
# DEFAULT SETTINGS
# Settings here will override the built-in defaults. Can be overridden by 
# runtime arguments supplied at the CLI.
#


#
# Create and capture the command-line arguments
#
parser = argparse.ArgumentParser( description='Running this script will   \
     issue whatever commands are presented to this script.      \
     All commands are issued from configuration mode.')

devices = parser.add_mutually_exclusive_group()

devices.add_argument( '-df', '--devfile', dest='devices_file',
                        help='Simple text file containing a list of devices, \
                        one per line')
devices.add_argument( '-d', '--device', default='',
                        help='A10 device hostname or IP address. Multiple    \
                        devices may be included seperated by a comma.')
parser.add_argument( '-p', '--password',
                        help='user password' )
parser.add_argument( '-u', '--username', default='admin',
                        help='username (default: admin)' )
parser.add_argument( '-cf', '--comfile', dest='commands_file',
                        help='Simple text file containing a list of commands, \
                        one per line')
parser.add_argument( '-c', '--commands', default='',
                        help='Commands to be issued, entered as a comma \
                        seperated string.  Requires double quotes (") if \
                        command contains spaces')
parser.add_argument( '-of', '--outfile', default='',
                        help='prefix for filename output (no file extension required)')
parser.add_argument( '-ofd', '--outfileperdevice', default='',
                        help='prefix for filename output (output file created per device)')
parser.add_argument( '-v', '--verbose', action='count',
                        help='Enable verbose detail')


try:
    args = parser.parse_args()
    devices = args.device.split(',')
    devices_file = args.devices_file
    password = args.password
    username = args.username
    commands = args.commands.split(',')
    commands_file = args.commands_file
    outfile = args.outfile
    outfileperdevice = args.outfileperdevice
    verbose = args.verbose

except IOError, msg:
    parser.error(str(msg))

timestamp = datetime.datetime.fromtimestamp(time.time()).strftime('%Y-%m-%d--%H-%M-%S')

#
# Done with arguments. The actual program begins here.

def main():
    """docstring for main"""
    for appliance in device_list:
        appliance=Acos(appliance)
        global success
        global total
        global error
        global err_array
        global status
        r = appliance.authenticate(username,password)
        if r == 'FAIL':
            print ('Authentication failed for device')
            error = error + 1
            total = total + 1
            err_array.append(dev_addr)
            continue
        appliance.get_hostname()
        appliance.clideploy(commands_list)
        appliance.logoff()
        



def read_devices_file(the_file):
    """docstring for read_devices_file"""
    print('  INFO: Looking for device addresses in ' + the_file)
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
            print ('  INFO: Found ' + str(number_of_devices) + ' address' + plural)
            return devices
    except:
        print('\n  ERROR: Unable to read ' + the_file)
        sys.exit(1)


def read_commands_file(the_file):
    """docstring for read_commands_file"""
    print('  INFO: Looking for commands in ' + the_file )
    try:
        commands_list = []
        plural = ''
        with open(the_file) as f:
            for command in f.readlines():
                if command.startswith('#') or command.rstrip() == '':
                    # Skip comments and blank lines
                    continue
                commands_list.append(command.rstrip())
                number_of_commands = len(commands_list)
            if number_of_commands != 1:
                plural='s'
            print ('  INFO: Found ' + str(number_of_commands) + ' command' + plural)
            return commands_list
    except:
        print('\n  ERROR: Unable to read ' + the_file + '.')
        sys.exit(1)


class Acos(object):
    """docstring for Acos"""
    def __init__(self, address):
        super(Acos, self).__init__()
        global dev_addr
        dev_addr = address
        self.device = address
        self.base_url = 'https://' + address + '/axapi/v3/'
        self.headers = {'content-type': 'application/json'}
        self.token = ''
        self.hostname = ''
        self.versions = {}
    

    def authenticate(self, username, password):
        """docstring for authenticate"""
        print('\nLogging onto ' + self.device + '...')
        module = 'auth'
        method = 'POST'
        payload = {"credentials": {"username": username, "password": password}}
        try:
            r = self.axapi_call(module, method, payload)
        except Exception as e:
            print('  ERROR: Unable to connect to ' + self.device + ' - ' + str(e))
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
            r = requests.post(url, data=json.dumps(payload),
                             headers=self.headers, verify=False)
        if verbose:
            print(r.content)
        return r
    
    
    def axapi_status(self, result):
        """docstring for get_axapi_status"""
        try:
            status = result.json()['response']['status']
            if status == 'fail':
                error = '\n  ERROR: ' + result.json()['response']['err']['msg']
                return (error, status)
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
        print('   Logged on successfully to ' + hostname + ' (' + dev_addr + ')')
        self.hostname = hostname
    

    
    def clideploy(self, commands_list):
        """docstring for clideploy"""
        global error
        global success
        global total
        print('   Issuing '+ '[%s]' % ', '.join(commands_list) +' command(s) on :' + self.hostname )
        module = 'clideploy'
        method = 'POST'
        payload = {"commandList":commands_list}
        r = self.axapi_call(module, method, payload)

        status = self.axapi_status(r)[1]
        print('      ' + str(self.axapi_status(r)[0]) )
        if status != 'fail':
            success = success + 1
            total = total + 1
            #no output file specified, print it to the screen
            if not outfile and not outfileperdevice:
                print('*********BEGIN COMMAND OUTPUT FOR ' + self.hostname + ' (' + dev_addr + ') ' + '*********' )
                print('**COMMANDS EXECUTED: ' + '[%s]' % ', '.join(commands_list))
                print('**COMMANDS EXECUTED AT: ' + datetime.datetime.fromtimestamp(time.time()).strftime('%Y-%m-%d--%H-%M-%S'))
                print('')
                print(r.content)
                print('**********END COMMAND OUTPUT FOR ' + self.hostname + '*********')
            #want an output file per device, insert hostname and timestamp for execution
            if outfileperdevice:
                f = open(outfileperdevice + '--' + self.hostname + '--' + datetime.datetime.fromtimestamp(time.time()).strftime('%Y-%m-%d--%H-%M-%S') + '.txt','a')
                f.write('*********BEGIN COMMAND OUTPUT FOR ' + self.hostname + ' (' + dev_addr + ') ' + '*********' )
                f.write('\n')
                f.write('**COMMANDS EXECUTED AT: ' + datetime.datetime.fromtimestamp(time.time()).strftime('%Y-%m-%d--%H-%M-%S')) 
                f.write('\n')
                f.write('**COMMANDS EXECUTED: ' + '[%s]' % ', '.join(commands_list))
                f.write('\n')
                f.write('\n')
                f.write(r.content)
                f.write('\n')
                f.write('**********END COMMAND OUTPUT FOR ' + self.hostname + '*********')
                f.write('\n')
                f.write('\n')
                f.write('\n')
                f.write('\n')
                f.close()
            #want a monolithic outfile, use global timestamp
            if outfile:
                f = open(outfile + '--' + timestamp + '.txt','a')
                f.write('*********BEGIN COMMAND OUTPUT FOR ' + self.hostname + ' (' + dev_addr + ') ' + '*********' )
                f.write('\n')
                f.write('**COMMANDS EXECUTED AT: ' + datetime.datetime.fromtimestamp(time.time()).strftime('%Y-%m-%d--%H-%M-%S'))
                f.write('\n')
                f.write('**COMMANDS EXECUTED: ' + '[%s]' % ', '.join(commands_list))
                f.write('\n')
                f.write('\n')
                f.write(r.content)
                f.write('\n')
                f.write('**********END COMMAND OUTPUT FOR ' + self.hostname + '*********')
                f.write('\n')
                f.write('\n')
                f.write('\n')
                f.write('\n')
                f.close()
        elif status == 'fail':
            error = error + 1
            total = total + 1
            err_array.append(dev_addr)
            print ('')
            print('  *******COMMAND FAILURE OCCURED*******')
            if not verbose:
                print('  Please execute with -v for more information')
                print ('')
    
    def logoff(self):
        """docstring for logoff"""
        print('   ' + self.hostname + ': Logging off...')
        module = 'logoff'
        method = 'POST'
        r = self.axapi_call(module, method)
        print('      ' + self.axapi_status(r) )



#
# Apply the defaults and arguments
#
print('')
device_list = []

if not devices_file and not args.device:
    print('You need to either specify a file with devices or use the -d option')
    print('No commands were executed')
    sys.exit(1)

if devices_file:
    device_list = read_devices_file(devices_file)
elif devices:
    device_list = devices

if not commands_file and not args.commands:
    print('You need to either specify a file with commnds or use the -c option')
    print('No commands were executed')
    sys.exit(1)

if commands_file:
    commands_list = read_commands_file(commands_file)
elif commands:
    commands_list = commands

if verbose < 2:
    logging.captureWarnings(True)

if not password:
    password = getpass.getpass( '\nEnter password for ' + username + ':')

if __name__ == '__main__':
    finished = False
    while not finished:
        try:
            err_array = []
            success = 0
            error = 0
            total = 0
            main()
            if success != 0:
                print('')
                print('****************************************************')
                print('Execution finished successfully on ' + str(success) + ' of ' + str(total) + ' device(s)')

            if error != 0:
                print('')
                print('****************************************************')
                print('Execution finished with errors on ' + str(error) + ' of ' + str(total) +' device(s)')
                print('Failed Devices: ' + '[%s]' % ', '.join(err_array))
                print('Please Review the log for details')

            finished = True

        except KeyboardInterrupt:
            print('Exiting')
            finished = True