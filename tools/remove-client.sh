#!/bin/bash

if [ $# -eq 0 ]
then
	echo "You must specify a valid client name or public key"
	sudo wg show
	exit 1
elif [ $(echo "${1: -1}") == "=" ] 
then
	wg_server=$(sudo wg show)
	if [[ "${wg_server}" == *"$1"* ]]
	then
		peer_pub_key=$1
	else
		echo "Public key" $1 "not valid"
		exit 1
	fi
else
	echo "Removing" $1
	# Check to see if client exists
	if [ -f clients/$1/wg0.conf ]
	then
		peer_pub_key=$(cat clients/$1/$1.pub)
	else
		echo "Can't find config for client" $1
		exit 1
	fi
fi
echo "Removing" $1
sudo wg set wg0 peer $peer_pub_key remove
sudo wg show