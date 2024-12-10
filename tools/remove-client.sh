#!/bin/bash
# Add Wireguard Client to Ubuntu Server
# (C) 2021 Richard Dawson
# v2.0.0

## Global Variables
FQDN=$(hostname -f)
PATTERN=" |'"
PEER_IP=""
PEER_NAME=""
TOOL_DIR="${HOME}/wireguard"

# Functions
check_root() {
  # Check to ensure script is not run as root
  if [[ "${UID}" -eq 0 ]]; then
    UNAME=$(id -un)
    printf "\nThis script must not be run as root.\n\n" >&2
    usage
  fi
}

check_string() {
  if [[ "$1" =~ ${PATTERN} ]]   
  then
    echo "Spaces found for ${2}"
	echo "This may cause issues"
  fi
}

echo_out() {
  local MESSAGE="${@}"
  if [[ "${VERBOSE}" = 'true' ]]; then
    printf "${MESSAGE}\n"
  fi
}

usage() {
  echo "Usage: ${0} [-dv] [-t TOOL_DIR] PEER_NAME" >&2
  echo "Creates a new client on the wireguard server."
  echo "Do not run as root."
  echo "-d			Delete config files"
  echo "-t TOOL_DIR	Set the tool installation directory."
  echo "-v 			Verbose mode. Displays the server name before executing COMMAND."
  exit 1
}

## MAIN ##
check_root
# Provide usage statement if no parameters
while getopts dvt: OPTION; do
  case ${OPTION} in
    v)
      # Verbose is first so any other elements will echo as well
      VERBOSE='true'
      echo_out "Verbose mode on."
      ;;
    d)
	# Delete configuration files
      PEER_IP="${OPTARG}"
      echo_out "Client WireGuard IP address is ${IP_ADDRESS}"
      ;;
	t)
	# Set IP address if none specified
      TOOL_DIR="${OPTARG}"
      echo_out "Tool Directory is ${TOOL_DIR}"
      ;;
    ?)
      echo "Invalid option" >&2
      usage
      ;;
  esac
done

# Clear the options from the arguments
shift "$(( OPTIND - 1 ))"

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