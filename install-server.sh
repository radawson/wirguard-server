#!/bin/bash
# Install wireguard on Ubuntu Server
# (C) 2021-2024 Richard Dawson
VERSION="2.12.1"

# Ubuntu 18.04
#sudo add-apt-repository ppa:wireguard/wireguard

# Default variables
# Change these if you need to
ADAPTER=$(ip route | grep default | sed -e "s/^.*dev.//" -e "s/.proto.*//")
BRANCH="main"
FORCE="false"
INSTALL_DIRECTORY="/etc/wireguard"
MA_MODE="false"
SERVER_IP="10.100.200.1"
SERVER_PORT="51820"
SERVER_PRIVATE_FILE="server_key.pri"
SERVER_PUBLIC_FILE="server_key.pub"
TOOL_DIR="${HOME}/wireguard"
CONFIG_DIR="${TOOL_DIR}/config"
START_DIR=$(pwd)

# Functions
check_ip(){
	local ip="$1"
	
    # Regular expression for validating IPv4 addresses
    if [[ "$ip" =~ ^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$ ]]; then
        echo "$ip"  # Return the valid IP address
    else
        echo "Error: '$ip' is not a valid IP address." >&2
        exit 1
    fi
}

check_root() {
	# Check to ensure script is not run as root
	if [[ "${UID}" -eq 0 ]]; then
		UNAME=$(id -un)
		printf "\nThis script should not be run as root.\n\n" >&2
		usage
	fi
}

echo_out() {
  local MESSAGE="${@}"
  if [[ -t 0 ]]; then
    # No pipe, just print the arguments
    if [[ "${VERBOSE}" = 'true' ]]; then
      printf "${MESSAGE}\n"
    fi
  else
    # Read from pipe and print if VERBOSE is true
    if [[ "${VERBOSE}" = 'true' ]]; then
      while IFS= read -r line; do
        printf "${line}\n"
      done
    fi
  fi
}

usage() {
	echo "Usage: ${0} [-dfhv] [-c CONFIG_DIR] [-i IP_RANGE] [-n KEY_NAME] [-p LISTEN_PORT] [-t TOOL_DIR]" >&2
	echo "Sets up and starts wireguard server."
	echo
	echo "-c CONFIG_DIR	Set configuration directory."
	echo "-d 		Run 'dev' branch. WARNING: may have unexpected results!"
	echo "-f 		Force run as root. WARNING: may have unexpected results!"
	echo "-h		Help displays script usage information."
	echo "-i IP_RANGE	Set the server network IP range."
	echo "-m		Route all traffic through wireguard Server."
	echo "-n KEY_NAME	Set the server key file name."
	echo "-p LISTEN_PORT	Set the server listen port"
	echo "-t TOOL_DIR	Set tool installation directory."
	echo "-v 		Verbose mode."
	exit 1
}

## MAIN ##
# Provide usage statement if no parameters
while getopts c:dfhi:mn:p:t:v OPTION; do
	case ${OPTION} in
	c)
		# Verbose is first so any other elements will echo as well
		CONFIG_DIR="${OPTARG}"
		echo_out "Configuration directory set to ${CONFIG_DIR}"
		;;
	d)
		# Set installation to dev branch
		BRANCH="dev"
		echo_out "Branch set to dev branch"
		;;
	f)
		# Force the script to run as root
		FORCE='true'
		;;
	h)
		# Help = display usage
		usage
		;;
	i)
		# Set IP range if none specified
		SERVER_IP=$(check_ip "${OPTARG}")
		echo_out "Internal server IP address is ${SERVER_IP}"
		;;
	m)
		# Activate MA mode, which routes ALL traffic through WG server
		MA_MODE="true"
		;;
	n)
		# Set the key file name
		SERVER_PRIVATE_FILE="${OPTARG}.pri"
		SERVER_PUBLIC_FILE="${OPTARG}.pub"
		echo_out "Server key file named ${OPTARG}."
		;;
	p)
		# Set the server listen port
		SERVER_PORT="${OPTARG}"
		echo_out "Server listen port set to ${OPTARG}."
		;;
	t)
		# Set tool installation directory
		TOOL_DIRECTORY="${OPTARG}"
		echo_out "Tool installation directory set to ${TOOL_DIR}."
		;;
	v)
		# Verbose is first so any other elements will echo as well
		VERBOSE='true'
		echo_out "Verbose mode on."
		;;
	?)
		echo "invalid option" >&2
		usage
		;;
	esac
done

# Check if forcing to run as root
if [[ "${FORCE}" != "true" ]]; then
	check_root
fi

# Clear the options from the arguments
shift "$((OPTIND - 1))"

# OS Update
echo_out "Updating the OS."
sudo apt-get update
sudo apt-get -y dist-upgrade

# Install wireguard
if [[ -z $(apt list --installed | grep ^wireguard) ]]; then
	echo_out "Installing WireGuard"
	sudo apt-get -y install wireguard
	sudo apt-get -y install wireguard-tools
fi
echo_out "WireGuard installed"

# Install zip
if [[ -z $(apt list --installed | grep ^zip) ]]; then
	echo_out "Installing zip."
	sudo apt-get -y install zip
fi
echo_out "Zip installed."

# Install QR Encoder
echo_out "Installing QR encoder."
sudo apt-get install -y qrencode
echo_out "QR encoder installed."

# Create tool directory
echo_out "Creating tool directory"
mkdir -p "${CONFIG_DIR}"

# Write the config file
cat > ${TOOL_DIR}/server.conf <<_EOF
VERSION="${VERSION}"
ADAPTER="${ADAPTER}"
BRANCH="${BRANCH}"
FORCE="${FORCE}"
INSTALL_DIRECTORY="${INSTALL_DIRECTORY}"
MA_MODE="${MA_MODE}"
SERVER_IP="${SERVER_IP}"
SERVER_PORT="${SERVER_PORT}"
SERVER_PRIVATE_FILE="${SERVER_PRIVATE_FILE}"
SERVER_PUBLIC_FILE="${SERVER_PUBLIC_FILE}"
TOOL_DIR="${TOOL_DIR}"
CONFIG_DIR="${CONFIG_DIR}"
_EOF

# Get config templates
echo_out "Downloading WG adapter config files..."
cd "${TOOL_DIR}"/config
wget https://raw.githubusercontent.com/radawson/wireguard-server/${BRANCH}/config/wg0-server.example.conf
wget https://raw.githubusercontent.com/radawson/wireguard-server/${BRANCH}/config/wg0-client.example.conf
echo_out "WG adapter config files downloaded."

# Create server directory
mkdir -p "${TOOL_DIR}"/server

# Create Server Keys
echo_out "Creating server keys."
cd "${TOOL_DIR}"/server
if [ -f ${INSTALL_DIRECTORY}/wg0.conf ]; then
	echo "${INSTALL_DIRECTORY}/wg0.conf exists"
	echo "This process could over-write existing keys!"
	echo
	while true; do
		read -p "Do you wish to overwrite existing keys?" yn
		case $yn in
		[Yy]*)
			OVERWRITE=1
			break
			;;
		[Nn]*)
			OVERWRITE=0
			break
			;;
		*) echo "Please answer y or n." ;;
		esac
	done
else
	echo "Creating ${INSTALL_DIRECTORY}"
	sudo mkdir -m 0700 ${INSTALL_DIRECTORY}
fi

# Check for a pre-existing installation
if [ -f ${SERVER_PRIVATE_FILE} ] && [ ${OVERWRITE} == 0 ]; then
	echo "${SERVER_PRIVATE_FILE} exists, skipping."
else
	umask 077
	wg genkey | tee ${SERVER_PRIVATE_FILE} | wg pubkey >${SERVER_PUBLIC_FILE}
fi

# Check if wg0.conf already exists
echo_out "Building custom configuration files..."
if [ -f ${TOOL_DIR}/server/wg0.conf ] && [ ${OVERWRITE} == 0 ]; then
	echo_out "${TOOL_DIR}/server/wg0.conf exists, skipping."
else
	# Add server key to config
	SERVER_PRI_KEY=$(cat ${TOOL_DIR}/server/${SERVER_PRIVATE_FILE})
	cat ${CONFIG_DIR}/wg0-server.example.conf | sed -e 's/:SERVER_IP:/'"${SERVER_IP}"'/' | sed -e 's/:SERVER_PORT:/'"${SERVER_PORT}"'/' | sed -e 's|:SERVER_KEY:|'"${SERVER_PRI_KEY}"'|' >"${TOOL_DIR}"/server/wg0.conf
	echo_out "Private key added to configuration."
fi

# Copy wg0.conf to /etc/wireguard
sudo cp "${TOOL_DIR}"/server/wg0.conf /etc/wireguard/wg0.conf

# Change to tool directory
cd ${TOOL_DIR}

# Add server IP to last-ip.txt file
SERVER_PUB_KEY=$(cat ${TOOL_DIR}/server/${SERVER_PUBLIC_FILE})
ADD_LINE="${SERVER_IP},server,${SERVER_PUB_KEY}"
echo "${ADD_LINE}" >>${TOOL_DIR}/peer_list.txt
echo "${SERVER_IP}" >${TOOL_DIR}/last_ip.txt

# Download tool scripts
echo_out "Downloading tool scripts"
wget https://raw.githubusercontent.com/radawson/wireguard-server/${BRANCH}/tools/add-client.sh
wget https://raw.githubusercontent.com/radawson/wireguard-server/${BRANCH}/tools/install-client.sh
wget https://raw.githubusercontent.com/radawson/wireguard-server/${BRANCH}/tools/remove-client.sh
wget https://raw.githubusercontent.com/radawson/wireguard-server/${BRANCH}/tools/wg-client.sh
sudo chmod 755 *.sh
sudo cp wg-client.sh /usr/local/bin/wg-client
rm wg-client.sh
echo_out "Tool scripts installed to ${TOOL_DIR}"

# Start up server
echo "Server Starting..."
sudo sysctl -p
echo 1 | sudo tee /proc/sys/net/ipv4//ip_forward

sudo wg-quick up wg0

# Open firewall ports
echo_out "Open firewall port ${SERVER_PORT}"
sudo ufw allow "${SERVER_PORT}"/udp
echo "Server started"

if [[ ${MA_MODE} == "true" ]]; then
	# Use this to forward traffic from the server
	sudo sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf
	sudo sysctl -p 
    sudo ufw route allow in on wg0 out on ${ADAPTER}
fi

# Set up wireguard to run on boot
sudo systemctl enable wg-quick@wg0.service

# Clean up
cd ${START_DIR}
rm -- "$(readlink -f -- "${BASH_SOURCE[0]:-$0}" 2>'/dev/null')"

printf "\n\nWireguard tools installed at ${TOOL_DIR}.\n"
