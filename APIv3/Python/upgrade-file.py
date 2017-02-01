import argparse
import hashlib
import getpass
from functools import partial
import sys
print(sys.version)

parser = argparse.ArgumentParser()
parser.add_argument("-de", "--devices", help="devices to upgrade comma delimited")
parser.add_argument("-df", "--devicefile", help="a file of devices to upgrade", default="")
parser.add_argument("-uf", "--upgradefile", help="the ACOS upgrade file")
parser.add_argument("-pa", "--partition", help="the ACOS partition to upgrade", choices=["pri","sec"])
parser.add_argument("-me", "--media", help="the device media to install to", choices=["hd","cf"], default="hd")
parser.add_argument("-m5", "--md5sum", help="the MD5sum of the upgrade file", default="" )
parser.add_argument("-us", "--user", help="an A10 admin user", default="")
parser.add_argument("-pw", "--password", help="the user's password", default="")
parser.add_argument("-up", "--updatebootvar", help="set to update the boot partition", action="store_true")
parser.add_argument("-re", "--reboot", help="reboot after ugprade", action="store_true")
parser.add_argument("-dw", "--dontwaitforreturn", help="dont wait for device to finish reboot before moving to next", action="store_true")

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

#script version
scriptversion = "0.1"

#if you want to use vanilla http just update this
prefix = "http"

def requirements():
	'''check to make sure we are running the correct version of python'''
	if sys.version_info[0] < 3:
		print("This program requires Python 3")
		print("Exiting")
		exit(1)

def checkmd5sum():
	md5 = md5get(upgrade_file)
	if not md5sum:
		print("you have not provided an MD5 checksum to check against")
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
	'''read file and generate md5 checksum'''
	with open(filename, mode='rb') as f:
		d = hashlib.md5()
		for buf in iter(partial(f.read, 128), b''):
			d.update(buf)
	return d.hexdigest()

def getcreds():
	'''get the username and password'''
	global user
	global password
	user = input("Please enter your username")
	password = getpass.getpass("Please enter password")
	
def stageupgrade():
	'''build the JSON payload for the API upgrade'''
	global upgradejsondata
	filesplit = upgrade_file.split(",")
	shortfilename = filesplit[-1]
	upgradejsondata = {media:{"image":partition,"image-file":shortfilename,"reboot-after-upgrade":0}}

def main():
	requirements()
	#checkmd5sum()
	if not user or not password:
		getcreds()
	stageupgrade()

def axapi_call(self, module, method, payload):
"""docstring for axapi"""
	url = self.base_url + module
	if method == 'GET':
		response = requests.get(url, headers=self.headers, verify=False)
	elif method == 'POST':
		response = requests.post(url, data=json.dumps(payload), headers=self.headers, verify=False)
return response


if __name__ == '__main__':
	main()