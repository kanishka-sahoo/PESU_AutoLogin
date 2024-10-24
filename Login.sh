#!/bin/bash

# Configuration
username=""  # Enter your PRN/SRN
pes_password=""  # Enter your password

# Color definitions
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'  # No Color

# List of preferred SSIDs
preferred_networks=("GJBC_Library" "GJBC" "PESU-Element Block" "PESU-BH")

# Function to get the strongest WiFi network from preferred list
get_strongest_wifi() {
    local strongest_signal=-100
    local strongest_network=""
    
    # Get all available networks with their signal strength using nmcli
    while IFS=':' read -r ssid signal_str; do
        # Clean up the SSID and signal strength
        ssid=$(echo "$ssid" | xargs)
        signal_str=$(echo "$signal_str" | tr -dc '0-9-')
        
        # Check if this network is in our preferred list
        for preferred in "${preferred_networks[@]}"; do
            if [[ "$ssid" == "$preferred" ]]; then
                if [[ $signal_str =~ ^-?[0-9]+$ ]] && (( signal_str > strongest_signal )); then
                    strongest_signal=$signal_str
                    strongest_network=$ssid
                fi
            fi
        done
    done < <(nmcli -t -f SSID,SIGNAL device wifi list)
    
    echo "$strongest_network"
}

# Function to connect to a WiFi network using NetworkManager
connect_to_wifi() {
    local network_name="$1"
    echo -e "${CYAN}Connecting to the strongest WiFi network: $network_name${NC}"
    
    # Check if we're already connected to this network
    current_connection=$(nmcli -t -f NAME connection show --active | grep '^'"$network_name"':' || true)
    
    if [[ -n "$current_connection" ]]; then
        echo -e "${YELLOW}Already connected to $network_name${NC}"
        return 0
    fi
    
    # First try to connect using existing connection profile
    if nmcli connection show | grep -q "^$network_name "; then
        echo "Using existing connection profile..."
        nmcli connection up "$network_name"
    else
        # If no profile exists, create new connection
        echo "Creating new connection profile..."
        nmcli device wifi connect "$network_name"
    fi
    
    # Check if connection was successful
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}Successfully connected to $network_name${NC}"
        return 0
    else
        echo -e "${RED}Failed to connect to $network_name${NC}"
        return 1
    fi
}

# Function to handle Warp connection
warp_disconnect() {
    echo "Disconnecting from Warp..."
    warp-cli disconnect >/dev/null 2>&1
    echo "Warp is Disconnected"
}

warp_connect() {
    echo "Connecting to Warp..."
    warp-cli connect >/dev/null 2>&1
    echo "Warp is Connected"
}

# Function for PES login
pes_login() {
    echo -e "${CYAN}Attempting PES login with username $username${NC}"
    sleep 5
    
    local login_url="https://192.168.254.1:8090/login.xml"
    local payload="mode=191&username=$username&password=$pes_password&a=1713188925839&producttype=0"
    
    # Using curl with --insecure to skip certificate validation
    response=$(curl -s -k -X POST -d "$payload" "$login_url")
    
    if echo "$response" | grep -q "You are signed in as"; then
        echo -e "${GREEN}Successfully connected to PES1UG19CS ID: $username${NC}"
        warp_connect
        exit 0
    else
        message=$(echo "$response" | grep -o '<message>.*</message>' | sed 's/<[^>]*>//g')
        echo -e "${RED}$message${NC}"
    fi
}

# Function for CIE login
cie_login() {
    local cie_username="$1"
    local cie_password="pesu@2020"
    local login_url="https://192.168.254.1:8090/login.xml"
    local payload="mode=191&username=$cie_username&password=$cie_password&a=1713188925839&producttype=0"
    
    echo -e "${CYAN}Trying username $cie_username${NC}"
    
    response=$(curl -s -k -X POST -d "$payload" "$login_url")
    
    if echo "$response" | grep -q "You are signed in as"; then
        echo -e "${GREEN}Successfully connected to CIE ID: $cie_username${NC}"
        warp_connect
        exit 0
    fi
}

# Ensure NetworkManager is running
if ! systemctl is-active --quiet NetworkManager; then
    echo -e "${RED}NetworkManager is not running. Please start NetworkManager first.${NC}"
    exit 1
fi

# Main script execution
warp_disconnect

# Get and connect to strongest network
strongest_network=$(get_strongest_wifi)
if [ -n "$strongest_network" ]; then
    if ! connect_to_wifi "$strongest_network"; then
        echo -e "${RED}Failed to connect to any preferred network${NC}"
        exit 1
    fi
    sleep 2  # Wait for connection to establish
else
    echo -e "${RED}No preferred networks found in the available WiFi networks.${NC}"
    exit 1
fi

# Check current hour and perform appropriate login
current_hour=$(date +%H)

if [ $current_hour -ge 8 ] && [ $current_hour -lt 20 ]; then
    # CIE login attempts during day time (8 AM to 8 PM)
    sleep 5
    for i in $(seq -f "%02g" 7 60); do
        cie_login "CIE$i"
    done
else
    # PES login during night time
    pes_login
fi
