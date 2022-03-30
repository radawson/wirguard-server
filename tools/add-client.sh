#!/bin/bash
# Add Wireguard Client to Ubuntu Server
# (C) 2021 Richard Dawson
# v2.0.0

## Global Variables
FQDN=$(hostname -f)
HOSTIP=$(ip -o route get to 1 | sed -n 's/.*src \([0-9.]\+\).*/\1/p')
peer_name=""

## MAIN ##
# Check to ensure script is run as root
if [[ "${UID}" -ne 0 ]]; then
  UNAME=$(id -un)
  printf "This script must be run as root" >&2
  usage
fi

if [ $# -eq 0 ]
then
	echo "You must pass a client name as an arg: add-client.sh <new-client>"
	exit 1
elif [ $1 == "-c" ]
then
	peer_name=$2
	echo "Creating client config for: ${peer_name}"
	mkdir -p clients/$peer_name
	wg genkey | (umask 0077 && tee clients/$peer_name/$peer_name.priv) | wg pubkey > clients/$peer_name/$peer_name.pub
	
	# get command line ip address or generated from last-ip.txt
	if [ -z "$3" ]
	then
		reldir=`dirname $0`
		ip="10.100.200."$(expr $(cat /etc/wireguard/last-ip.txt | tr "." " " | awk '{print $4}') + 1)
		sudo echo $ip > /etc/wireguard/last-ip.txt
	else
		ip=$3
	fi
	#Try to get server IP address
	if [[ ${HOSTIP} == "" ]]
	then
	    echo "Server IP not found automatically. Update wg0.conf before sending to clients"
		HOSTIP="<Insert IP HERE>"
	fi
	server_pub_key=$(cat /etc/wireguard/server_public_key)
	ip3=`echo $ip | cut -d"." -f1-3`.0
	
	# Create the client config
	priv_key=$(cat clients/$peer_name/$peer_name.priv)
    cat /etc/wireguard/wg0-client.example.conf | sed -e 's/:CLIENT_IP:/'"$ip"'/' | sed -e 's|:CLIENT_KEY:|'"$priv_key"'|' | sed -e 's/:ALLOWED_IPS:/'"$ip3"'/' | sed -e 's|:SERVER_PUB_KEY:|'"$server_pub_key"'|' | sed -e 's|:SERVER_ADDRESS:|'"$HOSTIP"'|' > clients/$peer_name/wg0.conf
	cp install-client.sh clients/$peer_name/install-client.sh
	# Create QR Code for export
	qrencode -o clients/$peer_name/$peer_name.png < clients/$peer_name/wg0.conf
	# Compress file contents into packages
	zip -r clients/$peer_name.zip clients/$peer_name
	tar czvf clients/$peer_name.tar.gz clients/$peer_name
	echo "Created config files"
else
	peer_name=$1
	# get command line ip address or generated from last-ip.txt
	if [ -z "$2" ]
	then
		# get ip address from wg0.conf
		ip=$(sed -n -e '/Address=/ s/.*\= *//p' /clients/$1/wg0.conf)
	else
		ip=$2
	fi
fi
echo ""
echo "Adding peer" $peer_name "to peer list from /clients"
priv_key=$(cat clients/$peer_name/$peer_name.priv)
pub_key=$(cat clients/$peer_name/$peer_name.pub)
    
# Add client (peer) to server config
peer_config="\n[Peer]\nPublicKey = ${pub_key} \nAllowedIPs = ${ip}"
sudo printf "$peer_config" >> /etc/wireguard/wg0.conf
sudo systemctl restart wg-quick@wg0.service
	
sudo wg set wg0 peer $(cat clients/$peer_name/$peer_name.pub) allowed-ips $ip/32
echo "Adding peer to hosts file"
echo $ip" "$peer_name | sudo tee -a /etc/hosts
# Show new server config
sudo wg show
# Show QR code in bash
qrencode -t ansiutf8 < clients/$peer_name/wg0.conf


