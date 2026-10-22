#!/bin/bash

CONFIG_DIR="$HOME/.network_spoof"
PROFILE_FILE="$CONFIG_DIR/profiles.conf"
SESSION_FILE="$CONFIG_DIR/session_info"

mkdir -p "$CONFIG_DIR"

usage() {
    echo "                                                                       
                             ::::::::                                        
                           :=-::::::::::::                                   
                          ::==-::::::::::::-                                 
                          :-==-::::::::::::::-                               
                          :-==-::::::::::::::::-                             
                          ::==-:::::::::::::::::::                           
                           :--:::::::::::::::::::::                          
                            ::::::::::::::::::::::::                         
                                   ::::::::::::::::-                         
                                    ::::::::::::::::-                        
                                      ::<::::::--::::                        
                                      :> O :::; O ::::                       
                                $     :::::____::::::=                       
                                 <-   :::::::::::::::=                       
                                    *+:::::::::::::::=                       
                                      :::::::::::::-::                       
                                     ::::::::::::::-[                        
                                    ::::::::::::::::-%                       
                                 ::::::::::::::::::-  >                      
                          ::::::::::::::::::::::::-   %                      
                         :-=-::::::::::::::::::::-                           
                        ::===:::::::::::::::::::=                            
                        ::===:::::::::::::::::-                              
                        :-===:::::::::::::::-:                               
                        ::==::::::::::::::*:                                 
                         :::::::::::::::   %                                 
                            :::::::-        -                                
                                   -        >                                
                               __)*      __#                               
    "
    echo "Network Spoofing Tool"
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -c      Create a new spoofing profile"
    echo "  -l      List all available profiles"
    echo "  -u NAME  Use existing profile (NAME)"
    echo "  -g      Generate completely new spoofing identity"
    echo "  -s      Make changes temporary (session only)"
    echo "  -p      Make changes persistent until manually changed"
    echo "  -r      Reset to original network configuration"
    echo "  -h      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -c -s"
    echo "  $0 -u work_device -p"
    echo "  $0 -g -s"
    echo "  $0 -r"
}

generate_random_mac() {
    printf '02:%02x:%02x:%02x:%02x:%02x\n' \
        $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) \
        $((RANDOM%256)) $((RANDOM%255))
}

generate_random_ip() {
    printf '%d.%d.%d.%d\n' \
        $((RANDOM%255+1)) $((RANDOM%255+1)) $((RANDOM%255+1)) $((RANDOM%255+1))
}

create_profile() {
    local profile_name="$1"
    local ip_addr=""
    local mac_addr=""
    
    echo "Creating new profile: $profile_name"
    
    # Get IP address (or generate random)
    read -p "Enter IP address (or press Enter for random): " ip_addr
    if [[ -z "$ip_addr" ]]; then
        ip_addr=$(generate_random_ip)
    fi
    
    # Get MAC address (or generate random)
    read -p "Enter MAC address (or press Enter for random): " mac_addr
    if [[ -z "$mac_addr" ]]; then
        mac_addr=$(generate_random_mac)
    fi
    
    # Save profile
    echo "$profile_name|$ip_addr|$mac_addr" >> "$PROFILE_FILE"
    echo "Profile '$profile_name' created successfully!"
}

list_profiles() {
    echo "Available Profiles:"
    if [[ -f "$PROFILE_FILE" ]]; then
        while IFS='|' read -r name ip mac; do
            echo "  $name - IP: $ip, MAC: $mac"
        done < "$PROFILE_FILE"
    else
        echo "  No profiles found. Create one with --create-profile"
    fi
}

check_interface() {
    local interface="$1"
    if ! ip link show "$interface" >/dev/null 2>&1; then
        echo "Interface $interface not found!"
        exit 1
    fi
    if ! ip link show "$interface" | grep -q 'state UP'; then
        echo "Interface $interface is not up!"
        exit 1
    fi
}

get_interface() {
    local interface=$(ip route | grep '^default' | awk '{print $5}' | head -1)
    if [[ -z "$interface" ]]; then
        interface="wlan0"
    fi
    echo "$interface"
}

reset_network() {
    echo "Resetting network configuration..."
    
    # Restore original MAC address (if saved)
    if [[ -f "$SESSION_FILE" ]]; then
        local original_mac=$(grep 'original_mac=' "$SESSION_FILE" | cut -d'=' -f2)
        local interface=$(grep 'interface=' "$SESSION_FILE" | cut -d'=' -f2)
        
        if [[ -n "$original_mac" && -n "$interface" ]]; then
            echo "Restoring original MAC address: $original_mac"
            sudo ip link set "$interface" down
            sudo macchanger -m "$original_mac" "$interface" 2>/dev/null || true
            sudo ip link set "$interface" up
            
            # Clear any existing IP addresses and reconfigure
            sudo ip addr flush dev "$interface"
            
            # Bring interface back up with original settings
            sudo dhclient -r "$interface" 2>/dev/null || true
            sudo dhclient "$interface" 2>/dev/null || true
            
            echo "Original MAC address restored: $original_mac"
        fi
        
        # Rmv session file
        rm -f "$SESSION_FILE"
    else
        echo "No session information found to reset."
    fi
    
    # Force refresh of network configuration
    local interface=$(get_interface)
    sudo ip link set "$interface" down
    sudo ip link set "$interface" up
    
    echo "Network configuration reset complete."
}

apply_spoofing() {
    local profile_name="$1"
    local is_persistent="$2"
    local new_ip=""
    local new_mac=""
    local interface=""
    
    # Get current interface
    interface=$(get_interface)
    
    echo "Applying spoofing on interface: $interface"
    
    if [[ -n "$profile_name" ]]; then
        # Use existing profile
        if grep -q "^$profile_name|" "$PROFILE_FILE"; then
            new_ip=$(grep "^$profile_name|" "$PROFILE_FILE" | cut -d'|' -f2)
            new_mac=$(grep "^$profile_name|" "$PROFILE_FILE" | cut -d'|' -f3)
            echo "Using profile: $profile_name"
        else
            echo "Profile '$profile_name' not found!"
            exit 1
        fi
    else
        # Gen new id
        new_ip=$(generate_random_ip)
        new_mac=$(generate_random_mac)
        echo "Generated new spoofing identity:"
        echo "  IP: $new_ip"
        echo "  MAC: $new_mac"
    fi
    
    if [[ ! -f "$SESSION_FILE" ]]; then
        local original_mac=$(cat /sys/class/net/"$interface"/address 2>/dev/null || echo "00:00:00:00:00:00")
        echo "original_mac=$original_mac" > "$SESSION_FILE"
        echo "interface=$interface" >> "$SESSION_FILE"
    fi
    
    echo "Stopping network services..."
    sudo systemctl stop NetworkManager 2>/dev/null || true
    sudo ip link set "$interface" down
    
    echo "Setting new MAC address: $new_mac"
    sudo macchanger -m "$new_mac" "$interface" 2>/dev/null || true
    
    echo "Setting new IP address: $new_ip"
    sudo ip addr flush dev "$interface" 2>/dev/null || true
    sudo ip addr add "$new_ip"/24 dev "$interface" 2>/dev/null || true
    
    echo "Bringing interface up..."
    sudo ip link set "$interface" up 2>/dev/null || true
    
    # Restart
    sudo systemctl start NetworkManager 2>/dev/null || true
    
    # Force refresh with dhclient
    sudo dhclient -r "$interface" 2>/dev/null || true
    sudo dhclient "$interface" 2>/dev/null || true
    
    echo "Spoofing applied successfully!"
    echo "Interface: $interface"
    echo "New IP: $new_ip"
    echo "New MAC: $new_mac"
    
    # Verify
    echo ""
    echo "Current network configuration:"
    echo "IP Address: $(ip addr show "$interface" | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)"
    echo "MAC Address: $(cat /sys/class/net/"$interface"/address 2>/dev/null || echo 'Not found')"
    
    if [[ "$is_persistent" == "true" ]]; then
        echo "Configuration will persist until manually changed."
    else
        echo "Configuration will be reset on next reboot."
    fi
}

# Main execution logic
main() {
    local create_profile=false
    local list_profiles=false
    local use_profile=""
    local generate_new=false
    local session_only=true
    local persistent=false
    local reset=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c)
                create_profile=true
                shift
                ;;
            -l)
                list_profiles=true
                shift
                ;;
            -u)
                use_profile="$2"
                shift 2
                ;;
            -g)
                generate_new=true
                shift
                ;;
            -s)
                session_only=true
                persistent=false
                shift
                ;;
            -p)
                persistent=true
                session_only=false
                shift
                ;;
            -r)
                reset=true
                shift
                ;;
            -h)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Validate
    if [[ "$create_profile" == "true" && ( "$use_profile" != "" || "$generate_new" == "true" ) ]]; then
        echo "Error: Cannot create profile while also using existing profile or generating new."
        exit 1
    fi
    
    if [[ "$list_profiles" == "true" && ( "$create_profile" == "true" || "$use_profile" != "" || "$generate_new" == "true" ) ]]; then
        echo "Error: Cannot list profiles while in other mode."
        exit 1
    fi
    
    # Execute
    if [[ "$reset" == "true" ]]; then
        reset_network
        exit 0
    fi
    
    if [[ "$list_profiles" == "true" ]]; then
        list_profiles
        exit 0
    fi
    
    if [[ "$create_profile" == "true" ]]; then
        read -p "Enter profile name: " profile_name
        if [[ -z "$profile_name" ]]; then
            echo "Profile name cannot be empty!"
            exit 1
        fi
        create_profile "$profile_name"
        exit 0
    fi
    
    # Apply
    if [[ "$use_profile" != "" || "$generate_new" == "true" ]]; then
        apply_spoofing "$use_profile" "$persistent"
    else
        usage
        exit 1
    fi
}

# Run dat shit
main "$@"
