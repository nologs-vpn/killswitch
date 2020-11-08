#!/bin/bash
#
# For documentation about running this script please visit our repo at:
# 	https://github.com/nologs-vpn/killswitch

# https://github.com/andrewgdotcom/openvpn-mac-dns/pull/1
# without usr/sbin into path openvpn fails the up script with
# "networksetup: command not found"
PATH=$PATH:/usr/sbin/
ABSPATH=$(cd "$(dirname "$0")"; pwd -P)
IFS=$'\n' read -d '' -ra adapters < <(networksetup -listallnetworkservices |grep -v denotes) || true
interractive="true"

function log {
	if [[ "$interractive" == "true" ]]; then
		echo "[Killswitch][$(date)] - $1"
	else
		echo "[Killswitch][$(date)] - $1" >> "$ABSPATH/log.txt"
	fi
}

function getVPNInterface {
	log "getVPNInterface"
	# retrieves the current VPN interface. without the utun grep
	# at the end it will pick the default interface when not 
	# connected to a VPN whil will lead to problems. currently
	# we look for a utun prefixed interface to know if it's a
	# VPN interface or not which may or may not be ideal
	# @TODO: find a better way of retrieving a VPN interface
	route -n get google.com | grep "interface: " | sed "s/[^:]*: \(.*\)/\1/" | grep utun
}

function pfConfOutbound {
	local res
	res=""
	for adapter in "${adapters[@]}"
	do
		res="$res\npass out on $adapter proto {tcp, udp} from any to $1"
	done
	echo "$res"
}

function pfConfCreate {
	log "pfConfCreate"
	cat <<EOT >"$ABSPATH/pfctl.conf"
# Options
set block-policy drop
set ruleset-optimization basic
set skip on lo0

# Block everything
block out all
block in all

# Outbound: Allow only VPN 
$(pfConfOutbound "$remote")

# Allow traffic for VPN
pass out on $2 all
EOT
}

function control_c {
	log "stopping"
	pfctl -Fa -f /etc/pf.conf
	rm "$ABSPATH/pfctl.conf"
	rm "$ABSPATH/log.txt"
	exit $?
}

type curl >/dev/null || die "Please install curl and then try again."
set -e

if [[ $EUID -ne 0 ]]
then
	log "Killswitch must be run as root/sudo"
	exit
fi

vpnInterface=""

if [[ -z "${script_type}" ]] && [[ "${script_type}" == "down" ]]; then
	# sent by openvpn via Environmental variables
	log "down command received from openvpn"
	control_c
	exit
fi

if [ -n "$1" ] && [ "$1" = "unlock" ]
then
	log "unlock command"
	control_c
	exit
fi
##########################################################
#	i: vpn interface (ex: tun0, wg0)
#   b: true blocks and waits for CTRL+C
##########################################################
while getopts ":i:r:b:" opt; do
	case $opt in
		i) vpnInterface="$OPTARG"
		;;
		r) remote="$OPTARG"
		;;
		b) interractive="$OPTARG"
		;;
		\?) log "Invalid option -$OPTARG" >&2
		;;
	esac
done

if [ -n "$dev" ]; then
	# sent by openvpn via Environmental variables
	# https://community.openvpn.net/openvpn/wiki/Openvpn23ManPage
	log "openvpn interface received as: $dev"
	vpnInterface=$dev
	interractive="false"
fi

if [[ $vpnInterface == "" ]]; then
	log "no interface yet; will try to guess it"
	vpnInterface=$(getVPNInterface) || true
fi

if [[ "$vpnInterface" == "" ]]; then
	log "VPN interface still not set; will ask the user"

	if [[ "$interractive" == "true" ]]; then
		read -r -p "Enter VPN interface (I was unable to detect it; are you connected?): " vpnInterface
	else
		die "no VPN interface set"
		exit
	fi
fi

if [[ "$remote" == "" ]]; then
	log "no remote; will ask the api"
	remote=$(curl -s api.ipify.org)
fi

pfConfCreate "$vpnInterface"

log "enabling pfctl"
log "loading pfctl config"
pfctl -e -Fa -f "$ABSPATH/pfctl.conf" || true

[[ $interractive == "false" ]] && exit

trap control_c SIGINT
log "Killswitch started. Press ctrl+c to exit."

function isConnected {
	if [ "0" == "$(ifconfig | grep -c "$vpnInterface")" ]; then echo "no"; else echo "yes"; fi
}

if [[ ! $(isConnected) =~ "yes" ]]
then
	log "You do not appear to be connected to a VPN. Connect to a VPN first, and then run Killswitch"
	exit
fi

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