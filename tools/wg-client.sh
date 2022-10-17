#!/bin/bash
# Wireguard Client client handler
# (C) 2021 Richard Dawson
VERSION="2.9.0"

## Global Variables
DISPLAY_QR="false"
FORCE="false"
FQDN=$(hostname -f)
OVERWRITE="false"
PATTERN=" |'"
PEER_IP=""
PEER_NAME=""
RETURN_VALUE="" # Used to return values from a function
SERVER_IP=$(ip -o route get to 1 | sed -n 's/.*src \([0-9.]\+\).*/\1/p')
TOOL_DIR="${HOME}/wireguard"
SERVER_PORT="51820"

# Functions
check_root() {
  # Check to ensure script is not run as root
  if [[ "${UID}" -eq 0 ]]; then
    UNAME=$(id -un)
    printf "\nThis script should not be run as root.\n\n" >&2
    usage
  fi
}

check_string() {
  if [[ "$1" =~ ${PATTERN} ]]; then
    echo "Spaces found for ${2}"
    echo "This may cause issues"
  fi
}

cmd_add() {
  # Get server listen port
  SERVER_PORT="$(grep ListenPort ${TOOL_DIR}/server/wg0.conf | sed 's/ListenPort = //')"

  # Check peer name
  check_string "${@}" "PEER_NAME"
  PEER_NAME="${@}"

  # Check if peer config already exists
  if [[ "${OVERWRITE}" -ne "true" ]]; then
    if [[ -f "${TOOL_DIR}/clients/${PEER_NAME}/wg0.conf" ]]; then
      echo -e "\nConfig for client ${PEER_NAME} found.\n\n"
      cat "${TOOL_DIR}/clients/${PEER_NAME}/wg0.conf"
      # Show QR code on console
      if [[ "${DISPLAY_QR}" == "true" ]]; then
        qrencode -t ansiutf8 <"${TOOL_DIR}"/clients/${PEER_NAME}/wg0.conf
      fi
      echo
      read -p "Overwrite existing config? [y/N] " YESNO
      if [[ "${YESNO}" == "y" || "${YESNO}" == "Y" ]]; then
        return
      else
        exit 10
      fi
    fi
  fi

  echo_out "Creating client config for: ${PEER_NAME}"
  mkdir -p ${TOOL_DIR}/clients/"${PEER_NAME}"
  wg genkey | (umask 0077 && tee "${TOOL_DIR}/clients/${PEER_NAME}/${PEER_NAME}.pri") | wg pubkey >"${TOOL_DIR}/clients/${PEER_NAME}/${PEER_NAME}".pub

  # get command line ip address or generated from last-ip.txt
  if [ -z "${PEER_IP}" ]; then
    PEER_IP="10.100.200."$(expr $(cat "${TOOL_DIR}"/last_ip.txt | tr "." " " | awk '{print $4}') + 1)
    sudo echo "${PEER_IP}" >"${TOOL_DIR}"/last_ip.txt
  fi

  #Try to get server IP address
  if [[ ${SERVER_IP} == "" ]]; then
    echo "Server IP not found automatically. Update wg0.conf before sending to clients"
    SERVER_IP="<Insert IP ADDRESS HERE>"
  fi

  SERVER_PUB_KEY=$(cat "${TOOL_DIR}"/server/server_key.pub)
  IP3=$(echo ${PEER_IP} | cut -d"." -f1-3).0

  # Create the client config
  PEER_PRIV_KEY=$(cat ${TOOL_DIR}/clients/${PEER_NAME}/${PEER_NAME}.pri)
  cat ${TOOL_DIR}/config/wg0-client.example.conf | sed -e 's/:CLIENT_IP:/'"${PEER_IP}"'/' | sed -e 's|:CLIENT_KEY:|'"${PEER_PRIV_KEY}"'|' | sed -e 's/:ALLOWED_IPS:/'"$IP3"'/' | sed -e 's|:SERVER_PUB_KEY:|'"$SERVER_PUB_KEY"'|' | sed -e 's|:SERVER_ADDRESS:|'"$SERVER_IP"'|' | sed -e 's|:SERVER_PORT:|'"${SERVER_PORT}"'|' >clients/${PEER_NAME}/wg0.conf
  cp ${TOOL_DIR}/install-client.sh ${TOOL_DIR}/clients/${PEER_NAME}/install-client.sh

  # Create QR Code for export
  qrencode -o ${TOOL_DIR}/clients/${PEER_NAME}/${PEER_NAME}.png <${TOOL_DIR}/clients/${PEER_NAME}/wg0.conf

  # Compress file contents into packages
  zip -r ${TOOL_DIR}/clients/${PEER_NAME}.zip ${TOOL_DIR}/clients/${PEER_NAME}
  tar czvf ${TOOL_DIR}/clients/${PEER_NAME}.tar.gz ${TOOL_DIR}/clients/${PEER_NAME}
  echo_out "Created config files"

  # Add peer information to the tracking files
  echo
  echo_out "Adding peer ${PEER_NAME} to peer list from /clients"
  PEER_PRIV_KEY=$(cat ${TOOL_DIR}/clients/${PEER_NAME}/${PEER_NAME}.pri)
  PEER_PUB_KEY=$(cat ${TOOL_DIR}/clients/${PEER_NAME}/${PEER_NAME}.pub)
  ADD_LINE="${PEER_IP},${PEER_NAME},${PEER_PUB_KEY}"
  echo "${ADD_LINE}" >>${TOOL_DIR}/peer_list.txt
  echo "${PEER_IP}" >${TOOL_DIR}/last_ip.txt

  # Add peer to server config
  echo_out "Adding peer to server peer list"
  PEER_CONFIG="\n[Peer]\nPublicKey = ${PEER_PUB_KEY} \nAllowedIPs = ${PEER_IP}"
  printf "${PEER_CONFIG}" | sudo tee -a /etc/wireguard/wg0.conf

  # Add peer through the live interface to be sure
  sudo wg set wg0 peer "${PEER_PUB_KEY}" allowed-ips ${PEER_IP}/32
  echo_out "Adding peer to hosts file"
  echo "${PEER_IP} ${PEER_NAME}" | sudo tee -a /etc/hosts
}

cmd_list() {
  printf "\nCurrent Clients:\n"
  local -i COUNT=1
  while IFS= read -r line; do
    echo -e "\t${COUNT}: ${line}" | sed 's/,/\t/g'
    COUNT=${COUNT}+1
  done <"${TOOL_DIR}/peer_list.txt"
  echo
}

cmd_remove() {
  if [[ $(echo "${1: -1}") == "=" ]]; then
    wg_server=$(sudo wg show)
    if [[ "${wg_server}" == *"$1"* ]]; then
      peer_pub_key=$1
    else
      echo "Public key" $1 "not valid"
      exit 1
    fi
  else
    echo "Removing" $1
    # Check to see if client exists
    if [ -f clients/$1/wg0.conf ]; then
      peer_pub_key=$(cat clients/$1/$1.pub)
    else
      echo "Can't find config for client" $1
      exit 1
    fi

    printf "\nRemoving ${1}\n\n"
    sudo wg set wg0 peer $peer_pub_key remove
  fi
}

cmd_update() {
printf "\n\nUpdate command goes here\n"
}

echo_out() {
  local MESSAGE="${@}"
  if [[ "${VERBOSE}" = 'true' ]]; then
    printf "${MESSAGE}\n"
  fi
}

usage() {
  echo "Usage: ${0} [-fhov] [-i IP_ADDRESS] [ ADD | LIST | REMOVE | UPDATE ] PEER_NAME" >&2
  echo "Client/peer handler for wireguard server."
  echo
  echo "-f 		Force run as root. WARNING: may have unexpected results!"
  echo "-i IP_ADDRESS	Set the peer ip address."
  echo "-o 		Overwrite existing client configuration."
  echo "-p SERVER_PORT	Set the server listen port."
  echo "-q		Display QR code on screen."
  echo "-s SERVER_IP	Set the server ip address."
  echo "-t TOOL_DIR	Set the tool installation directory."
  echo "-v 		Verbose mode. Displays the server name before executing COMMAND."
}

## MAIN ##
# Provide usage statement if no parameters
while getopts hi:op:qs:t:v OPTION; do
  case ${OPTION} in
  f)
    # Force the script to run as root
    FORCE='true'
    echo_out "WARNING! Script is running as root."
    ;;
  h)
    # Help = display usage
    usage
    ;;
  i)
    # Set IP address if none specified
    PEER_IP="${OPTARG}"
    echo_out "Client WireGuard IP address is ${IP_ADDRESS}"
    ;;
  o)
    # Set overwrite to true
    OVERWRITE="true"
    ;;
  p)
    # Set server port
    SERVER_PORT="${OPTARG}"
    echo_out "Server port set to ${OPTARG}"
    ;;
  q)
    # Display QR code on screen
    DISPLAY_QR="true"
    echo_out "Display QR code on screen."
    ;;
  s)
    # Set Server IP address
    SERVER_IP="${OPTARG}"
    echo_out "Server IP address set to ${OPTARG}"
    ;;
  t)
    # Set IP address if none specified
    TOOL_DIR="${OPTARG}"
    echo_out "Tool Directory is ${TOOL_DIR}"
    ;;
  v)
    # Verbose is first so any other elements will echo as well
    VERBOSE='true'
    echo_out "Verbose mode on."
    ;;
  ?)
    ;;
  esac
done

# Check if forcing to run as root
if [[ "${FORCE}" != "true" ]]; then
  check_root
fi

# Clear the options from the arguments
shift "$((OPTIND - 1))"

echo ${@}

if [[ $# -eq 0 ]]; then
  usage
  exit 0
fi

# menu logic

if [[ ${#} -eq 1 ]]; then
  COMMAND=$(echo ${1} | tr '[:upper:]' '[:lower:]')
  case $COMMAND in
  help)
    usage
    ;;
  list)
    cmd_list
    exit 0
    ;;
  *)
    echo "Invalid option" >&2
    usage
    exit 1
    ;;
  esac
elif [[ ${#} -eq 2 && ${1} == "add" ]]; then
  shift "$((OPTIND - 1))"
  echo ${@}
  cmd_add ${@}
else
  usage
  exit 1
fi

# Show new server config
sudo wg show

# Show QR code on console
if [[ "${DISPLAY_QR}" == "true" ]]; then
  qrencode -t ansiutf8 <"${TOOL_DIR}"/clients/${PEER_NAME}/wg0.conf
fi
