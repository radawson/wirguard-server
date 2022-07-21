# wireguard-server
### v2.5.1
Script and interface for building and maintaining wireguard networks


## Usage
Run `install-server.sh` to build the server.

I recommend you do not run this script as root. The script will automatically try to prevent this, but you can force it with the `-f` flag.

**Command Line Arguments**

- c CONFIG_DIR	Set configuration directory
- d 		    Run 'dev' branch. WARNING: may have unexpected results!
- f 		    Force run as root. WARNING: may have unexpected results!
- h		        Help displays script usage information
- i IP_RANGE	Set the server network IP range
- n KEY_NAME	Set the server key file name
- p LISTEN_PORT	Set the server listen port
- t TOOL_DIR	Set tool installation directory
- v 		    Verbose mode
