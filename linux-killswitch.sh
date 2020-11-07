#!/bin/bash
#
# For documentation about running this script please visit our repo at:
# 	https://github.com/nologs-vpn/killswitch

function log {
	echo "[Killswitch][$(date)] - $1"
}

defaultIface=$(ip addr | grep "state UP" | cut -d ":" -f 2 | head -n 1 | xargs)
cmd="start"
vpnIface=""
remote=$(curl -s api.ipify.org)
iptablesBackup="./iptables.backup"
#######################################################
#	c: command to run {start,restore}
#	i: vpn interface (ex: tun0, wg0)
#	d: default interface (ex: eth0)
#######################################################
while getopts ":c:i:d:r:" opt; do
	case $opt in
		c) cmd="$OPTARG"
		;;
		i) vpnIface="$OPTARG"
		;;
		r) remote="$OPTARG"
		;;
		d) defaultIface="$OPTARG"
		;;
		\?) log "Invalid option -$OPTARG" >&2
		;;
	esac
done

function clearScreen {
	printf "\033c"
}

function trimSpace {
	echo "$1" | xargs
}

function storeIptables {
	# we're storing the iptables rules before connecting so
	# we can have a return point. We could delete the rules
	# that we placed but that might interfere with existing
	# duplicate rules so it's better we deal with backups
	log "backing up iptables rules"
	iptables-save > "$iptablesBackup"
}

function requestVPNInterface {
	# asks from the user the VPN interface name in case it's missing
	# tries to detect current VPN interfaces and offer a choice
	# for the  user to pick; if no VPN interface is detected or
	# "other" option is selected - the user has to enter one
	# manually
	local options
	local vpnIfaces
	local optionsWithOther
	
	vpnIfaces=$(ip addr | grep "POINTOPOINT" | cut -d ":" -f 2)
	options=()
	while IFS= read -r line; do
		options+=("$(trimSpace "$line")")
	done <<< "$vpnIfaces"

	if (( ${#options[@]} )); then
		# we have some options so let's present them to the user
		optionsWithOther=("other")
		optionsWithOther=("${optionsWithOther[@]}" "${options[@]}")
		clearScreen
		PS3='Please select VPN interface: '
		select opt in "${optionsWithOther[@]}"
		do
			# first item in the array has ot be other so
			# we can target it here
			if [[ "$REPLY" == 1 ]]; then
				read -r -p "What is the VPN interface in use?" vpnIface
				break
			else
				counter=1
				for iface in "${options[@]}"; do
					counter=$((counter+1))
					[ "$counter" != "$REPLY" ] && continue
					vpnIface=$iface
				done
				break
			fi
		done
	else
		read -r -p "What is the VPN interface in use?" vpnIface
	fi

	log "VPN interface set to $vpnIface"
}

function lock {
	# locks down traffic except for our remote VPN ip address
	if test -f "$iptablesBackup"; then
		log "deleting obsolete firewall backup"
		rm "$iptablesBackup"
	fi

	[ -z "$vpnIface" ] && requestVPNInterface

	storeIptables
	iptables -P OUTPUT DROP
	iptables -A INPUT -j ACCEPT -i lo
	iptables -A OUTPUT -j ACCEPT -o lo
	iptables -A OUTPUT -j ACCEPT -d "${remote}"/32 -o "${defaultIface}"
	iptables -A INPUT -j ACCEPT -s "${remote}"/32 -i "${defaultIface}"
	iptables -A INPUT -j ACCEPT -i "${vpnIface}"
	iptables -A OUTPUT -j ACCEPT -o "${vpnIface}"
}

function unlock {
	log "restoring iptables rules"
	if test -f "$iptablesBackup"; then
		iptables-restore < "$iptablesBackup"
		rm "$iptablesBackup"
	fi
	log "done!"
}

function isConnected {
	if [ "0" == "$(ifconfig | grep -c "$vpnIface")" ]; then echo "no"; else echo "yes"; fi
}

function storedIf {
	cat < /tmp/defaultIface | xargs
}

function control_c {
	echo ""
	log "$(date) - Killswitch stopping"
	unlock
	exit $?
}

if [[ $EUID -ne 0 ]]
then
	echo "Killswitch must be run as root/sudo"
	exit
fi

if [ -n "$cmd" ] && [ "$cmd" = "unlock" ]
then
	unlock
	exit
fi

echo "$defaultIface" >/tmp/defaultIface

if [[ ! $(isConnected) =~ "yes" ]]
then
	log "You do not appear to be connected to a VPN. Connect to a VPN first, and then run Killswitch"
	exit
fi

lock

trap control_c SIGINT
log "Killswitch started. Press ctrl+c to exit."

connected=true
while :
do
	if [[ $(isConnected) =~ "no" ]]
	then
		connected=false
		log "connection to VPN was lost -- waiting for a reconnect"
		sleep 1
	else
		if [[ $connected == false ]]
		then
			connected=true
			log "reconnected to VPN"
		fi
	fi
	sleep 1
done
