#!/bin/bash

function checkPrerequisites () {
	if ! [ -x "$(command -v sshpass)" ]; then
		echo "ERROR: command sshpass is not found, please install it!"
		exit 404
	fi
	if ! [ -x "$(command -v ssh)" ]; then
		echo "ERROR: ssh is not found, please install it!"
		exit 404
	fi
}

function reformatMac () {
	#input is 080027817EFC - arp -a format truncates leading 0 and lower case
	#example: ? (192.168.1.161) at 8:0:27:81:7e:fc on en0 ifscope [ethernet]
	if [[ ${1:0:1} == "0" ]]; then
		macAddr="${1:1:1}:"
	else
		macAddr="${1:0:2}:"
	fi
	if [[ ${1:2:1} == "0" ]]; then
		macAddr="${macAddr}${1:3:1}:"
	else
		macAddr="${macAddr}${1:2:2}:"
	fi
	if [[ ${1:4:1} == "0" ]]; then
		macAddr="${macAddr}${1:5:1}:"
	else
		macAddr="${macAddr}${1:4:2}:"
	fi
	if [[ ${1:6:1} == "0" ]]; then
		macAddr="${macAddr}${1:7:1}:"
	else
		macAddr="${macAddr}${1:6:2}:"
	fi
	if [[ ${1:8:1} == "0" ]]; then
		macAddr="${macAddr}${1:9:1}:"
	else
		macAddr="${macAddr}${1:8:2}:"
	fi
	if [[ ${1:10:1} == "0" ]]; then
		macAddr="${macAddr}${1:11:1}"
	else
		macAddr="${macAddr}${1:10:2}"
	fi
	macAddr=$(echo "$macAddr" | tr '[:upper:]' '[:lower:]')
	echo "1:$1 findMac returns $macAddr"
}

function findMac () {
	if [[ -z "$1" ]]; then
		echo "findMac function missing vm name or uuid"
		exit 404
	fi
	#extract first mac address (should not need to parse several ATM)
	#NIC 1:                       MAC: 08002745FB92, Attachment: NAT, Cable connected: on, Trace: off (file: none), Type: 82540EM, Reported speed: 0 Mbps, Boot priority: 0, Promisc Policy: deny, Bandwidth group: none
	macAddr=$(vboxmanage showvminfo "$1" | grep MAC | tr -d ' ' | cut -d ":" -f3 | cut -d "," -f1)
	if [[ ! ${#macAddr} -eq 12 ]]; then
		echo "ERROR: finmac - macAddr is not 12 characters : $macAddr"
		exit 505
	fi
}

# https://stackoverflow.com/questions/47746535/bash-how-do-i-convert-a-hex-subnet-mask-into-bit-form-or-the-dot-decimal-addres
function binary () {
    local n bit=""
    printf -v n '%d' "$1"
    for (( ; n>0 ; n >>= 1 )); do  bit="$(( n&1 ))$bit"; done
    printf '%s\n' "$bit"
}

function findIPFromArp () {
	if [[ -z "$1" ]]; then
		echo "findIPFromArp function missing vm name or uuid"
		exit 404
	fi
	findMac $1
	reformatMac $macAddr
	vm_ip=$(arp -a | grep "$macAddr" | awk -F ' ' '{ printf $2; }' | tr -d '()')
	if [[ ! $vm_ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
		if ! [ -x "$(command -v fping)" ]; then
			echo "ERROR IP not in arp table and fping is not installed. Please install fping or use VBox gui to find ip address to ping once"
			echo "command used was : arp -a | grep \"$macAddr\" | awk -F ' ' '{ printf $2; }' | tr -d '()'"
			exit 504
		else
			#fping installed so we can find network of current ip for briged adapter
			netAdapterName=$(VBoxManage showvminfo $1 | grep NIC | grep Bridged | cut -d "'" -f2 | cut -d ":" -f1)
			ipAddr=$(ifconfig $netAdapterName | grep "inet " | cut -d " " -f2)
			ipNetmask=$(ifconfig en0 | grep "inet " | cut -d " " -f4)
			bitmask=$( s=$(binary "$ipNetmask"); s="${s%%0*}"; printf '%d' "${#s}" )
			# echo "adapter is $netAdapterName, ipAddr:$ipAddr, ipNetmask:$ipNetmask, bitmask:$bitmask"
			echo "IP not found in arp -a ==>> will run fping ${ipAddr}/${bitmask}"
			fping -g -r 1 "${ipAddr}/${bitmask}"
			vm_ip=$(arp -a | grep "$macAddr" | awk -F ' ' '{ printf $2; }' | tr -d '()')
			if [[ ! $vm_ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
				echo "IP for bridged vm could still not be found after fping, please use VBox GUI"
				exit 504
			fi
		fi
	fi
}

function connectToSsh () {
	if [[ -z "$1" ]]; then
		echo "ERROR: connectToSsh missing one argument : VM name or uuid"
	else
		localPort=$(VBoxManage showvminfo $1 --machinereadable | grep Forwarding | grep ssh | awk -F '[",]' '/^Forwarding/ { printf ("%-5d", $5); }')
		if [[ -z "$localPort" ]]; then
			#port forward not used, bridged network ?
			tmp_var=$(VBoxManage showvminfo $1 | grep NIC | grep Bridged | wc -l)
			if [[ "$tmp_var" -gt 0 ]]; then
				findIPFromArp $1
				sshConnect "$vm_ip" 22 "$1"
			else
				echo "ERROR: could not find IP address or port for SSH connection for $1"
				echo "##### VM NIC info to report configBuilder issue below"
				VBoxManage showvminfo $1 | grep NIC
				exit 504
			fi
		else
			clearKnownHostEntry "localhost"
			sshConnect "localhost" "$localPort" "$1"
		fi
	fi
}

function chooseRunningVMs () {

	unset options i

	if [[ $(VBoxManage list runningvms | wc -l) = 1 ]]; then
		findIP $(VBoxManage list runningvms | head -n1 | cut -d " " -f2 | tr -d {})
	fi

	echo "SSH from running VMs"

	while IFS= read -r -d $'\n' f; do
  		options[i++]="$f"
	done < <(VBoxManage list runningvms | grep -v 'windows')

	select opt in "${options[@]}" "Stop the script"; do
	  case $opt in
	  	"Stop the script")
		  exit
	      break
	      ;;
	    *)
	      vm_id=$(echo $opt | head -n1 | cut -d " " -f1 | tr -d '"')
	      connectToSsh "${vm_id}"
	      exit
	      ;;
	    *)
	      echo "This is not a number"
	      ;;
	  esac
	done
}

function clearKnownHostEntry () {
	# If ssh detect the ip was used by a machine with different fingerprint for the ECDSA key, it will not allow connection
	if [[ -z "$1" ]]; then
		echo "ERROR: clearKnownHostEntry missing one argument : hostname"
	else
		if [[ -f "$HOME/.ssh/known_hosts" ]]; then
			sed -i '' "/${1}/d" $HOME/.ssh/known_hosts
		fi
	fi
}

function sshConnect () {
	if [[ -z "$1" ]] || [[ -z "$2" ]]; then
		echo "ERROR: sshConnect missing one argument, expected : hostname port"
	else
		sshpass -p "${password}" ssh -o "StrictHostKeyChecking=no" "${username}@$1" -p $2
	fi
}

  while [ $# -gt 0 ]; do
	  case "$1" in
      --password=*)
        password="${1#*=}"
        ;;
      --username=*)
        username="${1#*=}"
        ;;
      *)

        printf "**************************************************************\n"
        printf "*            Error: Invalid argument.                        *\n"
        printf "* $1 *\n"
        printf "**************************************************************\n"
        exit 1
    esac
    shift
  done

function assignSettings () {
	if [[ -z "$username" ]]; then 
		username=vagrant
	fi
	if [[ -z "$password" ]]; then 
		password=vagrant
	fi
}

assignSettings
checkPrerequisites
chooseRunningVMs
