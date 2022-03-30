#!/bin/bash
# Install wireguard on Ubuntu Server
# (C) 2021 Richard Dawson
# v2.0.0

# Ubuntu 18.04
#sudo add-apt-repository ppa:wireguard/wireguard

# Default variables
# Change these if you need to
INSTALL_DIRECTORY="/etc/wireguard"
SERVER_IP="10.100.200.1"
SERVER_PRIVATE_FILE="server_key.pri"
SERVER_PUBLIC_FILE="server_key.pub"
TOOL_DIR="${HOME}/wireguard"

# Functions
check_root() {
  # Check to ensure script is not run as root
  if [[ "${UID}" -eq 0 ]]; then
    UNAME=$(id -un)
    printf "This script must not be run as root" >&2
    usage
  fi
}

echo_out() {
  local MESSAGE="${@}"
  if [[ "${VERBOSE}" = 'true' ]]; then
    printf "${MESSAGE}\n"
  fi
}

usage() {
  echo "Usage: ${0} [-v] [-i IP_RANGE] [-n KEY_NAME] [-t TOOL_DIR]" >&2
  echo "Sets up and starts wireguard server."
  echo "Do not run as root."
  echo "-i IP_RANGE	Set the server network IP range."
  echo "-n KEY_NAME	Set the server key file name."
  echo "-t TOOL_DIR	Set tool installation directory."
  echo "-v 			Verbose mode. Displays the server name before executing COMMAND."
  exit 1
}

## MAIN ##
check_root

# Provide usage statement if no parameters
while getopts i:n:t:v OPTION; do
  case ${OPTION} in
    v)
      # Verbose is first so any other elements will echo as well
      VERBOSE='true'
      echo_out "Verbose mode on."
      ;;
    i)
	# Set IP range if none specified
      SERVER_IP="${OPTARG}"
      echo_out "Server IP address is ${IP_ADDRESS}"
      ;;
	n)
	# Set the key file name
	  SERVER_PRIVATE_FILE="${OPTARG}.pri"
	  SERVER_PUBLIC_FILE="${OPTARG}.pub"
	  echo_out "Server key file named ${OPTARG}."
	  ;;
	t)
	# Set tool installation directory
	  TOOL_DIRECTORY="${OPTARG}"
	  echo_out "Tool installation directory set to ${TOOL_DIR}."
	  ;;
    ?)
      echo "invalid option" >&2
      usage
      ;;
  esac
done

# Clear the options from the arguments
shift "$(( OPTIND - 1 ))"

# Ubuntu
echo_out "Updating the OS."
apt-get update
echo_out "Installing WireGuard"
apt-get -y install wireguard
apt-get -y install wireguard-tools
echo_out "WireGuard installed"

# Install zip
echo_out "Installing zip."
apt-get -y install zip
echo_out "Zip installed."

# Install QR Encoder
echo_out "Installing QR encoder."
apt-get install -y qrencode
echo_out "QR encoder installed."

# Create Server Keys
echo_out "Creating server keys."
if [ -f $INSTALL_DIRECTORY/wg0.conf ]
then
	echo "${INSTALL_DIRECTORY}/wg0.conf exists"
	echo "This process could over-write existing keys!"
	echo
	while true; do
		read -p "Do you wish to overwrite existing keys?" yn
		case $yn in
			[Yy]* ) OVERWRITE=1; break;;
			[Nn]* ) OVERWRITE=0; break;;
			* ) echo "Please answer y or n.";;
		esac
	done
else
	echo "Creating ${INSTALL_DIRECTORY}"
	mkdir -m 0700 ${INSTALL_DIRECTORY}
fi

# Switch to server installation directory
cd ${INSTALL_DIRECTORY}

# Check for a pre-existing installation
if [ -f ${SERVER_PRIVATE_FILE} ] && [ ${OVERWRITE} == 0 ]
then
	echo "${SERVER_PRIVATE_FILE} exists, skipping."
else
	umask 077; wg genkey | tee ${SERVER_PRIVATE_FILE} | wg pubkey > ${SERVER_PUBLIC_FILE}
fi

# Get config
echo_out "Downloading WG adapter config files..."
sudo wget https://raw.githubusercontent.com/radawson/wireguard-server/master/config/wg0-server.example.conf 
sudo wget https://raw.githubusercontent.com/radawson/wireguard-server/master/config/wg0-client.example.conf
echo_out "WG adapter config files downloaded."

# Check if wg0.conf already exists
echo_out "Building custom configuration files..."
if [ -f ${INSTALL_DIRECTORY}/wg0.conf ] && [ $OVERWRITE == 0 ] 
then
	echo_out "$INSTALL_DIRECTORY/wg0.conf exists, skipping."
else
	# Add server key to config
	SERVER_PRI_KEY=$(cat ${INSTALL_DIRECTORY}/${SERVER_PRIVATE_FILE})
	cat $INSTALL_DIRECTORY/wg0-server.example.conf | sed -e 's/:SERVER_IP:/'"${SERVER_IP}"'/' | sed -e 's|:SERVER_KEY:|'"${SERVER_PRI_KEY}"'|' > $INSTALL_DIRECTORY/wg0.conf
	echo_out "Private key added to configuration."
fi

# Create tool directory
echo_out "Creating tool directory"
mkdir -p ${TOOL_DIR}

# Change to tool directory
cd ${TOOL_DIR}

# Add server IP to last-ip.txt file
ADD_LINE=${SERVER_IP} + ":server"
echo "${ADD_LINE}" >> ${TOOL_DIR}/peer_list.txt
echo ${SERVER_IP} > ${TOOL_DIR}/last_ip.txt

# Get run scripts/master/wg0-server
echo_out "Downloading tool scripts"
wget https://raw.githubusercontent.com/radawson/wireguard-server/master/tools/add-client.sh
chmod +x add-client.sh
wget https://raw.githubusercontent.com/radawson/wireguard-server/master/tools/install-client.sh
chmod +x install-client.sh
wget https://raw.githubusercontent.com/radawson/wireguard-server/master/tools/remove-client.sh
chmod +x remove-client.sh
echo_out "Tool scripts installed to ${TOOL_DIR}"

# Start up server
echo "Server Starting..."
sudo sysctl -p
echo 1 > ./ip_forward
sudo cp ./ip_forward /proc/sys/net/ipv4/

sudo wg-quick up wg0

# Open firewall ports
echo_out "Open firewall port 51820"
sudo ufw allow 51820/udp
echo "Server started"

# Use this to forward traffic from the server
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf
sudo sysctl -p /etc/sysctl.conf
#ufw route allow in on wg0 out on enp5s0

# Set up wireguard to run on boot
sudo systemctl enable wg-quick@wg0.service
