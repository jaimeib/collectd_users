#!/bin/bash
# Script to automate the installation of collectd to monitor the system

#######################################################################
# CONFIGURATION: IP Prefix to match the VLAN
ip_prefix=172
#######################################################################

#######################################################################
# DO NOT MODIFY BELOW THIS LINE
#######################################################################

# COLORS (All colors are bold, in order to identify the output)
BOLD="\033[1m"
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
RESET="\033[0m"

# Print the banner
echo -e "${BOLD}"
echo "  _____  ______  _____                   _____  ____   _       _       ______  _____  _______  _____  "
echo " |_   _||  ____|/ ____|    /\           / ____|/ __ \ | |     | |     |  ____|/ ____||__   __||  __ \ "
echo "   | |  | |__  | |        /  \     __  | |    | |  | || |     | |     | |__  | |        | |   | |  | |"
echo "   | |  |  __| | |       / /\ \   |__| | |    | |  | || |     | |     |  __| | |        | |   | |  | |"
echo "  _| |_ | |    | |____  / ____ \       | |____| |__| || |____ | |____ | |____| |____    | |   | |__| |"
echo " |_____||_|     \_____|/_/    \_\       \_____|\____/ |______||______||______|\_____|   |_|   |_____/ "
echo "                                                                                                      "
echo -e "${RESET}"

# Check if the script is being run as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED} > Please run as root. Exiting... ${RESET}"
    exit
else
    echo -e "${BLUE} > Running as root ${RESET}"
fi

# Get the hostname of the system
hostname=$(hostname -s)

# Get the IP address of the system
network_devices=$(ip -o link show | awk -F': ' '{print $2}')
for device in $network_devices; do
    # Get the IP address of the network device
    ip=$(ip -o -4 addr show $device | awk '{print $4}' | cut -d '/' -f 1)
    # If the IP address starts with ip_prefix and the device is not docker*
    if [[ $ip == $ip_prefix* ]] && [[ $device != docker* ]]; then
        break
    fi
done

# Get the VLAN number of the system
vlan=$(echo $ip | cut -d '.' -f 3)
# Add 2000 to the VLAN number
vlan=$((vlan + 2000))

# Check if the VLAN number is a 4 digit number
if [ ${#vlan} -ne 4 ]; then
    echo -e "${RED} > The VLAN number is not a 4 digit number. Exiting...${RESET}"
    exit
fi

echo -e "${BLUE} > The VLAN number is $vlan ${RESET}"

#Concatenate the hostname and vlan number with the format hostname_vlanXXXX
collectd_hostname="$hostname"_vlan"$vlan"

# Check if the system is RedHat based or Debian based to define directory paths
# If RedHat based system
if [ -f /etc/redhat-release ]; then
    echo -e "${YELLOW} > RedHat based system detected ${RESET}"
    # Define the directory path for the collectd configuration file
    collectd_conf_path="/etc"
    collectd_conf_d_path="/etc/collectd.d"
    collectd_plugin_dir_path="/usr/lib64/collectd"
    collectd_types_db_path="/usr/share/collectd"
    dcgm_bindings_path="/usr/local/dcgm/bindings/python3"
    dcgm_collectd_plugin_path="/usr/lib64/collectd/dcgm"
    libdcgm_path="/usr/lib64"
    pythonlib_path="/usr/lib64"
fi

# If Debian based system
if [ -f /etc/debian_version ]; then
    echo -e "${YELLOW} > Debian based system detected ${RESET}"
    # Define the directory path for the collectd configuration file
    collectd_conf_path="/etc/collectd"
    collectd_conf_d_path="/etc/collectd/collectd.conf.d"
    collectd_plugin_dir_path="/usr/lib/collectd"
    collectd_types_db_path="/usr/share/collectd"
    dcgm_bindings_path="/usr/local/dcgm/bindings/python3"
    dcgm_collectd_plugin_path="/usr/lib/collectd/dcgm"
    libdcgm_path="/usr/lib/x86_64-linux-gnu"
    pythonlib_path="/usr/lib"
fi

# Check if the system has a supported NVIDIA GPU
if nvidia-smi &> /dev/null; then
    echo -e "${YELLOW} > NVIDIA GPU detected ${RESET}"
    nvidia_gpu=true
else
    nvidia_gpu=false
fi

# Install collectd
echo -e "${BLUE} > Installing collectd... ${RESET}"

# If RedHat based system
if [ -f /etc/redhat-release ]; then
    dnf install -y epel-release && dnf install -y collectd

    # If GPU detected
    if $nvidia_gpu; then
        # Install the python-plugin for collectd
        dnf install -y collectd-python
    fi
    

fi

# If Debian based system
if [ -f /etc/debian_version ]; then
    apt-get update && apt-get install -y collectd
fi

echo -e "${BLUE} > Setting up the collectd configuration file... ${RESET}"

# Download the configuration file
wget https://raw.githubusercontent.com/jaimeib/collectd_users/main/collectd/collectd.conf -O $collectd_conf_path/collectd.conf

# Add the hostname to the configuration file (Line starts with Hostname "name_vlanXXXX")
sed -i -e 's|\(Hostname \).*|\1"'"$collectd_hostname"'"|g' $collectd_conf_path/collectd.conf

# Replace current PluginDir with the correct path
sed -i -e 's|\(PluginDir "/usr/lib64/collectd"\)|PluginDir "'"$collectd_plugin_dir_path"'"|g' $collectd_conf_path/collectd.conf

# Replace the current <Include "/etc/collectd/collectd.conf.d"> with the correct path
sed -i -e 's|\(<Include "/etc/collectd/collectd.conf.d">.*\)|<Include "'"$collectd_conf_d_path"'">:|g' $collectd_conf_path/collectd.conf

# GPU monitoring

# Check if the system has a supported NVIDIA GPU
if $nvidia_gpu; then

    echo -e "${BLUE} > Setting up the NVIDIA DCGM... ${RESET}"

    # If Red Hat based system 
    if [ -f /etc/redhat-release ]; then

        # Set up the CUDA network repository meta-data, GPG key:
        dnf config-manager --add-repo https://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/cuda-rhel9.repo

        # Install the DCGM package
        echo -e "${BLUE} > Installing the NVIDIA DCGM package... ${RESET}"
        dnf clean expire-cache && dnf install -y datacenter-gpu-manager
    fi

    # If Debian based system
    if [ -f /etc/debian_version ]; then

        # Get os name (ignore stderr output from lsb_release)
        os_name=$(lsb_release -is 2>/dev/null)
        #Convert os name to lowercase
        os_name=$(echo $os_name | tr '[:upper:]' '[:lower:]')

        # Get os version (ignore stderr output from lsb_release)
        os_version=$(lsb_release -rs 2>/dev/null)

        #If the os name is ubuntu, remove the . from the version
        if [ $os_name == "ubuntu" ]; then
            os_version=$(echo $os_version | tr -d .)
        fi

        # Set up the CUDA network repository meta-data, GPG key:
        echo " > Setting up the CUDA network repository meta-data, GPG key..."
        wget https://developer.download.nvidia.com/compute/cuda/repos/$os_name$os_version/x86_64/cuda-keyring_1.0-1_all.deb
        dpkg -i cuda-keyring_1.0-1_all.deb
        add-apt-repository "deb https://developer.download.nvidia.com/compute/cuda/repos/$os_name$os_version/x86_64/ /"

        # Install the DCGM package
        echo " > Installing the NVIDIA DCGM package..."
        apt-get update && apt-get install -y datacenter-gpu-manager
    fi

    # Enable and start the DCGM service
    echo -e "${YELLOW} > Enabling and starting the NVIDIA DCGM service... ${RESET}"
    systemctl --now enable nvidia-dcgm

    # Check if the DCGM service is running
    if ! systemctl is-active --quiet nvidia-dcgm; then
        echo -e "${RED} > NVIDIA DCGM service is not running. Exiting... ${RESET}"
        exit
    else 
        echo -e "${GREEN} > NVIDIA DCGM service is running ${RESET}"
    fi

    # Setting up the DCGM collectd plugin
    echo -e "${BLUE} > Setting up the DCGM collectd plugin... ${RESET}"

    # Copy the DCGM collectd plugin to the collectd directory (force)
    mkdir -p $dcgm_collectd_plugin_path
    cp -r $dcgm_bindings_path/* $dcgm_collectd_plugin_path

    # Set the correct location of the DCGM library (libdcgm.so) on this system
    sed -i -e 's|\(g_dcgmLibPath =\) '"'"'/usr/lib'"'"'|\1 '"'"$libdcgm_path"'"'|g' $dcgm_collectd_plugin_path/dcgm_collectd_plugin.py

    # Add the DCGM collectd plugin to the collectd configuration file
    echo -e "${BLUE} > Adding the DCGM collectd plugin configuration file... ${RESET}"

    # Download the DCGM collectd configuration file
    wget https://raw.githubusercontent.com/jaimeib/collectd_users/main/collectd/dcgm.conf -O $collectd_conf_d_path/dcgm.conf

    # Replace the current ModulePath of the DCGM collectd plugin with the correct path
    sed -i -e 's|\(ModulePath "/usr/lib64/collectd/dcgm"\)|ModulePath "'"$dcgm_collectd_plugin_path"'"|g' $collectd_conf_d_path/dcgm.conf

    # Add the DCGM collectd types.db file to the collectd configuration file
    echo -e "${BLUE} > Adding the DCGM collectd types.db file... ${RESET}"

    # Download the DCGM collectd types.db file to the collectd directory
    wget https://raw.githubusercontent.com/jaimeib/collectd_users/main/collectd/dcgm_types.db -O $collectd_types_db_path/dcgm_types.db

    # If there are multiple python versions installed
    if [ $(ls $pythonlib_path | grep python | wc -w) -gt 1 ]; then
        echo -e "${YELLOW} > Multiple python versions detected ${RESET}"
        # Fix multple python.so version problem
        echo -e "${BLUE} > Fixing multiple python.so version problem... ${RESET}"
        # Get the path of the libpython.so file
        libpython_path=$(find $pythonlib_path -name "libpython*.so")
        echo -e "${GREEN} > Found libpython.so file: $libpython_path ${RESET}"
        # Set the location of the libpython.so file in the collectd configuration file (/etc/default/collectd)
        echo -e "${GREEN} > Setting the location of the libpython.so file in the collectd configuration file... ${RESET}"
        # Add the LD_PRELOAD line to the collectd configuration file
        echo "LD_PRELOAD=$libpython_path" >> /etc/default/collectd
    fi

fi

# Enable the collectd service
echo -e "${YELLOW} > Enabling the collectd service... ${RESET}"
systemctl enable collectd

# Start the collectd service
echo -e "${YELLOW} > Starting the collectd service... ${RESET}"
systemctl start collectd

# Restart the collectd service (in case it was already running)
systemctl restart collectd

# Check if the collectd service is running
if ! systemctl is-active --quiet collectd; then
    echo -e "${RED} > Collectd service is not running. Exiting... ${RESET}"
    exit
else 
    echo -e "${GREEN} > Collectd service is running ${RESET}"
fi

# Done
echo -e "${GREEN} > Installation complete. Exiting... ${RESET}"

# Print next steps:
echo " "
echo -e "${BOLD} > Next steps: ${RESET}"
echo -e "${BOLD} > Now you can log in into ${BLUE}https://monitor.ifca.es/grafana/${RESET}${BOLD} with your ${BLUE}IFCA${RESET}${BOLD} credentials. ${RESET}" 
echo -e "${BOLD}    1. Go to ${YELLOW}"Home"${RESET}${BOLD} --> ${YELLOW}"Dashboards"${RESET}${BOLD} --> ${YELLOW}"IFCA Monitoring External"${RESET} ${RESET}"
echo -e "${BOLD}    2. You will see 2 dashboards: ${RESET}"
echo -e "${BOLD}       - ${GREEN}"IFCA Cloud VM General":${RESET} This dashboard shows the general information of the VMs in your project. ${RESET}"
echo -e "${BOLD}       - ${GREEN}"IFCA Cloud VM Overview":${RESET} This dashboard shows the detailed information of a specific VM. ${RESET}"
echo -e "${BOLD} > Remember to select your ${YELLOW}VLAN number${RESET}: ${RED}$vlan${RESET}${BOLD} in the ${YELLOW}"VLAN"${RESET}${BOLD} field in the top right corner of the dashboard. ${RESET}"

# Exit the script
exit
