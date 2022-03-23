#!/bin/bash
# Install instructions for clients created by add-client.sh
# (C) 2021 Richard Dawson 

# Ubuntu 18.04
#sudo add-apt-repository ppa:wireguard/wireguard

# Debian
#echo "deb http://deb.debian.org/debian/ unstable main" > /etc/apt/sources.list.d/unstable-wireguard.list
#printf 'Package: *\nPin: release a=unstable\nPin-Priority: 150\n' > /etc/apt/preferences.d/limit-unstable

#Both
sudo apt-get update
sudo apt-get -y install wireguard
sudo apt-get -y install wireguard-tools

# put wg0.conf in `/etc/wireguard/`
sudo cp wg0.conf /etc/wireguard/wg0.conf

# DNS Resolver commands (may be rquired)
#sudo ln -s /usr/bin/resolvectl /usr/local/bin/resolvconf
#sudo systemctl enable systemd-resolved.service

# start wireguard wg0
sudo wg-quick up wg0

# set wireguard wg0 to start on boot
sudo systemctl enable wg-quick@wg0.service 

