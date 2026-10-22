#!/bin/bash

CONFIG_DIR="$HOME/.network_spoof"
PROFILE_FILE="$CONFIG_DIR/profiles.conf"
SESSION_FILE="$CONFIG_DIR/session_info"

# Create config dir if it no exist
mkdir -p "$CONFIG_DIR"

usage() {
    echo "Network Spoofing Tool"
    echo "Usage: $0 [OPTIONS]"
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
    echo "Options:"
    echo "  -cp         --create-profile     Create a new spoofing profile"
    echo "  -lp         --list-profiles      List all available profiles"
    echo "  -up NAME    --use-profile NAME   Use existing profile (NAME)"
    echo "  -gn         --generate-new       Generate completely new spoofing identity"
    echo "  -so         --session-only       Make changes temporary (session only)"
    echo "  -p          --persistent         Make changes persistent until manually changed"
    echo "  -r          --reset              Reset to original network configuration"
    echo "  -h          --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -cp -so"
    echo "  $0 -up work_device -p"
    echo "  $0 -gn -so"
    echo "  $0 -r"
}

generate_random_mac() {
    printf '02:%02x:%02x:%02x:%02x:%02x\n' \
        $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) \
        $((RANDOM%256)) $((RANDOM%256))
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
            sudo ip link set "$interface" down
            sudo macchanger -m "$original_mac" "$interface"
            sudo ip link set "$interface" up
            echo "Original MAC address restored: $original_mac"
        fi
        
        # Rmv session file
        rm -f "$SESSION_FILE"
    else
        echo "No session information found to reset."
    fi
    
    # flush
    local interface=$(get_interface)
    sudo ip link set "$interface" down
    sudo ip link set "$interface" up
    
    echo "Network configuration reset complete."
}

# Apply spoof
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
    
    # Save OG MAC address for reset
    if [[ ! -f "$SESSION_FILE" ]]; then
        local original_mac=$(cat /sys/class/net/"$interface"/address)
        echo "original_mac=$original_mac" > "$SESSION_FILE"
        echo "interface=$interface" >> "$SESSION_FILE"
    fi
    
    # Apply new config
    sudo ip link set "$interface" down
    sudo macchanger -m "$new_mac" "$interface"
    sudo ip addr flush dev "$interface"
    sudo ip addr add "$new_ip"/24 dev "$interface"
    sudo ip link set "$interface" up
    
    echo "Spoofing applied successfully!"
    echo "Interface: $interface"
    echo "New IP: $new_ip"
    echo "New MAC: $new_mac"
    
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
            -cp)
                create_profile=true
                shift
                ;;
            -lp)
                list_profiles=true
                shift
                ;;
            -up)
                use_profile="$2"
                shift 2
                ;;
            -gn)
                generate_new=true
                shift
                ;;
            -so)
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
    
    # Apply spoof
    if [[ "$use_profile" != "" || "$generate_new" == "true" ]]; then
        apply_spoofing "$use_profile" "$persistent"
    else
        usage
        exit 1
    fi
}

# Run dat shit
main "$@"
