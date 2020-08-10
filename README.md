# Dependencies :

Bash script developped/tested on MacOS Mojave 10.14.6, with sshpass and fping (when using bridged adapter and IP is unknown from the VirtualBox Host)

# What is the script doing 

1. Will list running VMs with VBoxManage whose name does not contain "windows" (ssh is assumed possible on all running VMs but won't work)
2. Then it will SSH to the running VM using password vagrant and user vagrant depending on network configurations :

If using NAT, it will look for rule called `*ssh*` to find local port to use on localhost...

If using bridged network, it will look for ip in `arp -a` and if not found it will scan network using `fping`. It will remove the entry $HOME/.ssh/known_hosts in case the DHCP server assigned the IP previously assigned to some other MAC address

# Usage

The script takes 2 optional parameters with following default values :
./sshPass.sh --username=vagrant --password=vagrant

# See also

Example Vagrantfile is provided : usually on Vagrant boxes SSH using password is disabled so the example uses shell provisioner to allow ssh with password