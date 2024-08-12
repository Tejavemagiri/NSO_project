#!/bin/bash

# VM creation function
# $1: openrc
# $2: tag
# $3: ssh_key

SECURITY_GROUP_NAME="security_$2"
NETWORK_NAME="network_$2"
KEY_NAME="$3"

# Function to get flavor ID based on criteria
get_flavor_id() {
    local FLAVOR_NAME=$(openstack flavor list -c ID -c RAM -c Disk -c VCPUs -f csv | awk -F ',' '$2 == 2048 && $3 == 20 && $4 == 2 {print $1}' | sed 's/"//g' | head -n 1)
    
    if [ -z "$FLAVOR_NAME" ]; then
        echo "No suitable flavor found."
        exit 1
    fi

    echo $FLAVOR_NAME
}

create_vm() {
    local VM_NAME=$1
    local TAG=$2
    local KEY_NAME=$3
    local FLAVOR_NAME=$4
    
    echo "Key Name is: $KEY_NAME"
    echo "Creating VM: $VM_NAME"
    
    # Create the VM and capture its ID
    vm_id=$(openstack server create \
        --flavor "$FLAVOR_NAME" \
        --image "Ubuntu 20.04 Focal Fossa x86_64" \
        --security-group $SECURITY_GROUP_NAME \
        --key-name "$KEY_NAME" \
        --network $NETWORK_NAME \
        "$VM_NAME" -f value -c id)
    
    echo "VM created with ID: $vm_id"
    
    # Wait for the VM to be active
    echo "Waiting for VM to become active..."
    while true; do
        status=$(openstack server show "$vm_id" -c status -f value)
        if [ "$status" = "ACTIVE" ]; then
            break
        fi
        sleep 20 # Wait for 20 seconds before checking again
    done
    
    # Get the VM's IP address
    vm_ip=$(openstack server show "$vm_id" -c addresses -f value | grep -oP '\d+\.\d+\.\d+\.\d+')
    
    if [ -n "$vm_ip" ]; then
        echo "Adding IP $vm_ip to ./ips file"
        echo "$vm_ip" >> ./storage/ips
    else
        echo "No IP found for the VM"
    fi
}

# Get the appropriate flavor name
FLAVOR_NAME=$(get_flavor_id)

# Generate a 6-digit Unix time
timestamp=$(date +%s | tail -c3)

# VM name with 6-digit Unix time
VM_NAME="vm${timestamp}_$2"
create_vm "$VM_NAME" "$2" "$3" "$FLAVOR_NAME"
