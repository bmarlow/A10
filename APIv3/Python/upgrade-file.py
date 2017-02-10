#!/usr/bin/env python

"""
A script for upgrading one or multiple ACOS 4.x devices.

Example:
    #Upgrade the two devices on the primary partition of the harddrive with the username admin password a10, then update the boot variable and reboot the box
    ./upgrade-file.py -de 10.0.1.221,10.0.1.222 -pa pri -me hd -user admin -password a10 -up -re -uf ./someACOSupgradefile.upg

    #Uprgade the list of devcies (on per line) on the secondary partition of the harddrive, then update the boot variable and reboot
    ./upgrade-file.py -df devices.txt -pa sec -me hd -up -re -uf ./someACOSupgradefile.upg
Notes:
    Rev 1.0:    Initial release
    Rev 1.1:    Added notes and general cleanup for readability and general PEPiness
    Rev 1.2:    Fixed some linux platform issues

TODO:
    Mulithreading - need streaming to make this happen which will probably require the requests-toolbelt library
    Output to logfiles
    Verbosity for legacy upgrades
    ACOS 2.x and 3.x upgrades?
"""
__author__ = "Brandon Marlow"
__version__ = "1.1"
__maintainer__ = "Brandon Marlow"
__email__ = "bmarlow@a10networks.com"
__status__ = "Production"

import os
import sys
import json
import time
import getpass
import hashlib
import argparse
import requests
import subprocess
from functools import partial
# disable SSL warnings for self signed certs
from requests.packages.urllib3.exceptions import InsecureRequestWarning
requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

parser = argparse.ArgumentParser()
parser.add_argument("-de", "--devices", help="devices to upgrade comma delimited", default="")
parser.add_argument("-df", "--devicefile", help="a file of devices to upgrade", default="")
parser.add_argument("-uf", "--upgradefile", help="the ACOS upgrade file")
parser.add_argument("-pa", "--partition", help="the ACOS partition to upgrade", choices=["pri","sec"])
parser.add_argument("-me", "--media", help="the device media to install to", choices=["hd","cf"], default="hd")
parser.add_argument("-m5", "--md5sum", help="the MD5sum of the upgrade file", default="" )
parser.add_argument("-us", "--user", help="an A10 admin user", default="")
parser.add_argument("-pw", "--password", help="the user's password", default="")
parser.add_argument("-up", "--updatebootvar", help="set to update the boot partition", action="store_true")
parser.add_argument("-re", "--reboot", help="reboot after upgrade", action="store_true")
parser.add_argument("-dw", "--dontwaitforreturn", help="dont wait for device to finish reboot before moving to next", action="store_true")
parser.add_argument('-ve', "--version", help="display the script version", action="store_true")
parser.add_argument("-v", "--verbose", help="turn on verbose mode", action="store_true")

args = parser.parse_args()
devices = args.devices.split(",")
device_file = args.devicefile
upgrade_file = args.upgradefile
partition = args.partition
media = args.media
md5sum = args.md5sum
user = args.user
password = args.password
updatebootvar = args.updatebootvar
reboot = args.reboot
dontwaitforreturn = args.dontwaitforreturn
getscriptversion = args.version
verbose = args.verbose

# script version
scriptversion = "1.2"


def main():
    """main loop for script"""

    # a quick way to verify the version
    if getscriptversion:
        print('This script is running version: ' + scriptversion)
        exit(0)

    # verify that environmental and script requirements are met
    requirements()

    # pretty the screen up
    clear()
    # do the MD5 checksum
    checkmd5sum()
    if not user or not password:
        getcreds()

    # if device_file is provided parse the lines into a list of devices
    if device_file:
        with open(device_file) as line:
            devices = line.readlines()
            devices = [x.strip() for x in devices]
    else:
        devices = args.devices.split(",")

    for device in devices:

        device = Acos(device)
        print('')
        print('')
        print(dev_addr + ' ' + '{:*^100}'.format('Begin upgrade log for ' + dev_addr))
        print(dev_addr + ' ' + '{:*^100}'.format('Performing pre-upgrade checks'))

        # check if the device is online before running
        status = device.checkstatus()
        if status == 'FAIL':
            continue

        # authenticate to the device
        response = device.axapi_authenticate(user, password)
        if response == 'FAIL':
            continue
        # get the device hostname
        device.get_hostname()

        # get the currently running version
        version = device.get_running_ver()

        print(dev_addr + ' ' + '{:*^100}'.format(' Performing upgrade'))

        # if we are running 4.1.0 we have to use a different upgrade method
        if '4.1.0' in version:
            response = device.gui_upgrade(user, password)
            if response == 'FAIL':
                continue
        # for other versions just use the normal method
        else:
            response = device.upgrade()
            if response == 'FAIL':
                continue
        bootvar = device.get_bootvar()

        # if the user has specified they'd like to update the boot variable
        if updatebootvar:
            # why do work that we don't have to
            if partition in bootvar:
                print(dev_addr + ' Bootvar update requested, but not necessary, device already set to boot from ' + partition)
            # if you're not already set to boot from the partition we installed to, update the bootvar
            else:
                device.update_bootvar()
            # if the user wants to reboot to initialize the new code reboot the box
            if reboot:
                device.reboot()
                # if the user wants to speed up the script, then just skip monitoring them
                if dontwaitforreturn:
                    print(dev_addr + ' Skipping post-upgrade verification at user request')
                    continue
                # otherwise you probably want to make sure the box comes up first
                else:
                    device.reboot_monitor()
            if not reboot:
                print(dev_addr + '{:*^100}'.format('NOTICE NOTICE NOTICE'))
                print(dev_addr + 'You have requested the device not reboot, in order to initialize the new code you will need to reboot the device')
        # if you install to a partition the device won't reboot to, we probably want to stop you from shooting yourself in the foot
        elif not partition in bootvar:
            print(dev_addr + '{:*^100}'.format('NOTICE NOTICE NOTICE'))
            print(dev_addr + ' You have chosen to install to the partition that the device does not currently boot from.')
            print(dev_addr + ' If you wish for the device to run the new code upon reboot you need to update the boot variable manually.')
            if reboot:
                print(dev_addr + ' You have also requested a reboot which will not invoke the new code, SKIPPING REBOOT')
        elif reboot:
            device.reboot()
            # if the user wants to speed up the script, then just skip monitoring them
            if dontwaitforreturn:
                print(dev_addr + ' Skipping post-upgrade verification at user request')
                continue
            # otherwise you probably want to make sure the box comes up first
            else:
                device.reboot_monitor()
        # technically we could still use the old AXAPI token, however for sake of code clarity we're going to do a quick log off then back on
        # the alternative would be having to shove the remaining steps below into each of the appropriate loops making this a bit more
        # spaghettish than it already is
        else:
            device.axapi_logoff()

        print(dev_addr + ' ' + '{:*^100}'.format(' Performing post-upgrade checks'))

        # since it is very likely the box has rebooted, and our old token is gone, lets get a new one
        response = device.axapi_authenticate(user, password)
        if response == 'FAIL':
            continue

        # find out where the device was booted from
        bootdefault = device.get_bootvar()

        # get the version of the currently booted partition
        device.get_ver(bootdefault)

        # get the current boot variable
        device.get_bootvar()

        # get the current running version
        device.get_running_ver()

        # log off
        device.axapi_logoff()
        print(dev_addr + ' ' + '{:*^100}'.format(' End upgrade log for ' + dev_addr))


def clear():
    """cross-platform screen clear, for prettiness"""
    os.system('cls' if os.name == 'nt' else 'clear')


def requirements():
    """check to make sure that the requirements for execution are met"""
    print('Verifying basic requirements met')
    # python version 3+ is required
    if sys.version_info[0] < 3:
        print('This program requires Python 3')
        print('Exiting')
        exit(1)
    # you must provide a device list or device file
    if device_file == "" and devices == [""]:
        print('You need to either specify the devices (-de) or specify a file with a list of devices one per line (-df)')
        print('No upgrades were performed')
        sys.exit(1)
    if device_file != "" and devices != [""]:
        print('You need to either specify the devices (-de) or specify a file with a list of devices one per line (-df)')
        print('No upgrades were performed')
        sys.exit(1)
    if not partition:
        print('You need to specify a partition (-pa) for upgrade')
        sys.exit(1)
    if not upgrade_file:
        print('You must specify a local file to use for upgrade')
        sys.exit(1)


def checkmd5sum():
    """Do MD5 Checksum Verification"""
    print('Generating MD5 Checksum')
    md5 = md5get(upgrade_file)
    if not md5sum:
        print("You have not provided an MD5 checksum to check against")
        print("")
        print("You can find what the MD5 checksum of your package should be at https://a10networks.com/support/axseries/software-downloads")
        print("")
        cont = input("Would you like to continue anyway? Y/N [N]")
        if cont.lower() == 'y' or cont.lower() == 'yes':
            print("Continuing at user request")
            print("")
        else:
            print("Exiting at user request")
            exit(1)

        print("**************************MD5 Checksum of upgrade file**************************")
        print("Upgrade filename: " + upgrade_file)
        print("Upgrade MD5 Checksum: " + md5)
        print("********************************************************************************")
        print("")
        print("It is suggested that you manually verify the MD5 Checksum against the A10 published checksum before proceeding")
        cont = input("Do you wish to continue? Y/N [N]")
        print(cont)
        if cont.lower() == 'y' or cont.lower() == 'yes':
            print("Continuing")
        elif cont.lower() != 'y' and cont.lower() != 'yes':
            print("Exiting")
            exit(1)

    elif md5sum != md5:
        print("************************************ERROR***********************************")
        print("****************************************************************************")
        print("MD5 provided: " + md5sum + " does not match the calculated MD5 of the upgrade file: " + md5 + ".")
        print("")
        print("Please verify the correct MD5 Checksum is being provided")
        print("If the MD5 Checksum provided matches that of the one listed at https://www.a10networks.com/support/axseries/software-downloads, please re-download the upgrade file")
        print("Exiting...")
        exit(1)
    elif md5sum == md5:
        print("MD5 Checksum provided and MD5 of the upgrade file match, proceeding")


def md5get(filename):
    """read file and generate md5 checksum"""
    with open(filename, mode='rb') as f:
        d = hashlib.md5()
        for buf in iter(partial(f.read, 128), b''):
            d.update(buf)
    return d.hexdigest()


def getcreds():
    """get the username and password"""
    global user
    global password
    if not user:
        user = input("Please enter your username:\n")
    if not password:
        password = getpass.getpass("Please enter password:\n")
    

class Acos(object):
    """docstring for Acos"""

    def __init__(self, address):
        super(Acos, self).__init__()
        global dev_addr
        dev_addr = address
        self.device = address
        self.proto = 'https://'
        self.base_url = self.proto + address + '/axapi/v3/'
        self.gui_url = self.proto + address + '/gui/'
        self.headers = {'content-type': 'application/json'}
        self.token = ''
        self.hostname = ''

    def axapi_authenticate(self, user, password):
        """authenticate to the ACOS device"""
        print(self.device + ' Logging onto device...')
        module = 'auth'
        method = 'POST'
        payload = {"credentials": {"username": user, "password": password}}
        try:
            response = self.axapi_call(module, method, payload)
        except Exception as e:
            print(self.device + ' ERROR: Unable to connect to ' + self.device + ' - ' + str(e))
            print(self.device + ' Authentication failed, moving on to next device')
            return 'FAIL'
        try:
            self.token = response.json()['authresponse']['signature']
            self.headers['Authorization'] =  'A10 {}'.format(self.token)
        except:
            print(self.device + ' ERROR: Login failed!')
            return 'FAIL'

    def axapi_logoff(self):
        """function to log off the AXAPI session for the ACOS device"""
        module = 'logoff'
        method = 'POST'
        response = self.axapi_call(module, method,'')
        if '2' in str(response.status_code):
            print(self.device + ' Successfully logged off of the device')
        else:
            print(self.device + ' There was an error trying to log off of the device')

    def axapi_call(self, module, method, payload=''):
        """generic axapi function for interacting with the api"""
        url = self.base_url + module
        if method == 'GET':
            response = requests.get(url, headers=self.headers, verify=False)
        elif method == 'POST' and payload == '':
            response = requests.post(url, headers=self.headers, verify=False)
        elif method == 'POST':
            response = requests.post(url, data=json.dumps(payload), headers=self.headers, verify=False)
        if verbose:
            print(response.content)
        return response

    def axapi_status(self, result):
        """generic axapi function for interacting with certain endpoints that only respond with HTTP response codes"""
        try:
            status = result.json()['response']['status']
            if status == 'fail':
                error = '\n  ERROR: ' + result.json()['response']['err']['msg']
                return error, status
            else:
                return status
        except:
            good_status_codes = ['<Response [200]>', '<Response [204]>']
            status_code = str(result)
            if status_code in good_status_codes:
                return 'OK'
            else:
                return status_code

    def get_hostname(self):
        """use AXAPI to get the hostname"""
        module = 'hostname'
        method = 'GET'
        response = self.axapi_call(module, method)
        hostname = response.json()['hostname']['value']
        print(self.device + ' Device hostname is: ' + hostname)

    def gui_upgrade(self, user, password):
        """authenticate to the ACOS device via the GUI, needed for early versions of 4.x that don't support AXAPI upgrades"""

        # for whatever reason the GUI is the only place the partitions are called out longhand, so we need to set it
        if partition == 'pri':
            longpartition = 'primary'
        elif partition == 'sec':
            longpartition = 'secondary'

        # take the file string and extract the filename (two commands for cross platform compat)
        filesplit = upgrade_file.replace('\\', '/')
        filesplit = filesplit.split('/')
        shortfilename = filesplit[-1]

        # create a session
        s = requests.session()
        request = s.get(self.gui_url + 'auth/login/', verify=False)

        # now that we have a session lets get those cookies
        cookie_dict = request.cookies.get_dict()
        csrftoken = cookie_dict['csrftoken']

        # create the headers (referrer required during SSL/TLS connections
        headers = {'Content-Type': 'application/x-www-form-urlencoded',
                   'Referrer': self.device}

        #create the body for the auth
        body = 'csrfmiddlewaretoken=' + csrftoken + '&username=' + user + '&password=' + password

        # now log in (via the GUI)
        s.post(self.gui_url + 'auth/login/', headers=headers, data=body, verify=False)

        # after the login a new CSRF token is assigned, so we need to grab that and update the variable
        newcookiejar = s.cookies.get_dict()
        csrftoken = newcookiejar['csrftoken']

        # define new headers to perform the upgrade the X-CSRFToken header is required for a successful upgrade
        newheaders = {'Referer': self.gui_url,
                      'X-CSRFToken': csrftoken}

        # the python requests module has some fun stuff in it that allows for the creation of multipart posts
        files = {'csrfmiddlewaretoken': (None, csrftoken),
                 'destination': (None, longpartition),
                 'staggered_upgrade_mode': (None, '0'),
                 'device': (None, ''),
                 'reboot': (None, '0'),
                 'save_config': (None, '1'),
                 'local_remote': (None, '0'),
                 'use_mgmt_port': (None, '0'),
                 'protocol': (None, 'tftp'),
                 'host': (None, ''),
                 'port': (None, ''),
                 'location': (None, ''),
                 'user': (None, ''),
                 'password': (None, ''),
                 'file': (shortfilename, open(upgrade_file, 'rb'), 'application/octet-stream')}

        # perform the actual upgrade
        print(self.device + ' Performing legacy 4.x ACOS upgrade, please wait, the may take a few minutes depending on your connection...')
        try:
            upgrade = s.post(self.gui_url + 'system/maintenance/upgrade/', headers=newheaders, files=files,verify=False)
            # the message of success is presented in a cookie, so grab that and if we see it we know we were successful
            anothercookiejar = upgrade.cookies.get_dict()
            messages = anothercookiejar['messages']
            if not 'success' in messages:
                print(self.device + 'The device upgrade failed.  Please check logs on the device, or attempt manually.')
                return 'FAIL'
            if 'success' in messages:
                print(self.device + ' The device successfully upgraded')

        except Exception as e:
            print('  ERROR: Upgrade failed on ' + self.device + ' - ' + str(e))
            return 'FAIL'

    def upgrade(self):
        """function for creating and sending an HTTP multipart to perform the upgrade"""
        # replace '\' with '/' (For NT system compatability)
        filesplit = upgrade_file.replace('\\', '/')
        filesplit = filesplit.split('/')
        shortfilename = filesplit[-1]

        #define the JSON data for the multipart
        upgradejsondata = {media: {"image": partition, "image-file": shortfilename, "reboot-after-upgrade": 0}}
        url = self.base_url + 'upgrade/hd'

        #define the headers that have your auth token
        headers = {'Authorization': "A10 " + self.token}
        try:
            print(self.device + ' Performing upgrade, this may take a few minutes depending on your connection, please wait...')
            response = requests.post(url, headers=headers, files={'file': (shortfilename, open(upgrade_file, 'rb'), 'application/octet-stream'), 'json': (None, json.dumps(upgradejsondata), 'application/json'),}, verify=False)
            if response.status_code == 204:
                print(self.device + ' The device successfully upgraded')
        except Exception as e:
            print('  ERROR: Upgrade failed on ' + self.device + ' - ' + str(e))
            return 'FAIL'

    def get_bootvar(self):
        """function to get the currently set boot variable/location"""
        module = 'bootimage/oper'
        method = 'GET'
        response = self.axapi_call(module, method)
        bootdefault = response.json()['bootimage']['oper']['hd-default']
        print(self.device + ' The device is set to boot from: ' + bootdefault + ' in the future')
        return bootdefault

    def update_bootvar(self):
        module = 'bootimage'
        method = 'POST'
        bootvarjson = {"bootimage": {media + '-cfg': {media: 1, partition: 1}}}
        print(self.device + ' Updating bootvar')
        response = self.axapi_call(module, method, bootvarjson)
        if response.json()['response']['status'] == 'OK':
            print(self.device + ' Successfully updated the bootvar')
        else:
            print(self.device + ' There was a problem updating the bootvar')

    def get_ver(self, bootdefault):
        """function to get the currently installed ACOS version"""
        module = 'version/oper'
        method = 'GET'
        response = self.axapi_call(module, method)
        installedver = response.json()['version']['oper'][bootdefault]
        print(self.device + ' The version currently installed on ' + bootdefault + ' is: ' + installedver)

    def get_running_ver(self):
        """function go get the currently running ACOS version"""
        module = 'version/oper'
        method = 'GET'
        response = self.axapi_call(module, method)
        runningver = response.json()['version']['oper']['sw-version']
        currentpart = response.json()['version']['oper']['boot-from']
        print(self.device + ' The current running version is: ' + runningver)
        print(self.device + ' The device is currently booted from: ' + currentpart)
        return runningver

    def reboot(self):
        """function to reboot an ACOS device"""
        module = 'reboot'
        method = 'POST'
        print(self.device + ' Calling reboot command on the device')
        response = self.axapi_call(module, method,'')
        if '2' in str(response.status_code):
            print(self.device + ' Reboot command successfully received, device will reboot momentarily, please wait')
        else:
            print(self.device + ' There was an error in issuing the reboot command, device may not have rebooted, please verify manually')

    def reboot_monitor(self):
        """function built to check the status of the box during a reboot"""
        # define cross-platform /dev/null
        devnull = open(os.devnull, 'w')

        # if the OS is windows
        if os.name == 'nt':
            ping = ['ping', '-n', '1', self.device]

        # if the OS is posix
        else:
            ping = ['ping', '-c', '1', self.device]

        print(self.device + ' Waiting for device to finish rebooting, please wait', end='', flush=True)
        time.sleep(10)
        count = 1
        successcount = 0
        while count < 300:
            print('.', end='', flush=True)
            ping_call = subprocess.Popen(ping, stdout=devnull)
            returncode = ping_call.wait()
            # we need multiple successes to allow this to work, otherwise a single response while the box is still initializing can bite us
            if returncode == 0:
                successcount = successcount + 1
            if successcount == 5:
                break
            time.sleep(1)
            count = count + 1

        print('')
        if count == 300:
            print(self.device + ' Device has not responded to 300 pings, please manually check device')
            print(self.device + ' Exiting...')
        else:
            print(self.device + ' Device is now initializing')
            time.sleep(10)
            print(self.device + ' Device has finished rebooting')

    def checkstatus(self):
        """function built to check if the device is up before running upgrade"""
        # define cross-platform /dev/null
        devnull = open(os.devnull, 'w')

        # if the OS is windows
        if os.name == 'nt':
            ping = ['ping', '-n', '1', self.device]

        # if the OS is posix
        else:
            ping = ['ping', '-c', '1', self.device]

        print(self.device + ' Checking for device availability', end='', flush=True)
        time.sleep(5)
        count = 0
        while count < 2:
            print('.', end='', flush=True)
            ping_call = subprocess.Popen(ping, stdout=devnull)
            returncode = ping_call.wait()
            if returncode == 0:
                break
            time.sleep(1)
            count = count + 1

        print('')
        if count == 2:
            print(self.device + ' Device is not up')
            print(self.device + ' Exiting...')
            return 'FAIL'
        else:
            print(self.device + ' Device is Online')
            print(self.device + ' Please wait for script initialization')
            time.sleep(5)

if __name__ == '__main__':
    main()
