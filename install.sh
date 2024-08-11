#!/bin/bash

# Usage: install <openrc> <tag> <ssh_key>
#                   $1      $2     $3

. $1

rm /root/.ssh/known_hosts
# Generating keys.
openstack keypair delete $3 > /dev/null 2>&1
openstack keypair create $3 > ./storage/$3
cp ./storage/$3 ./operate_files/$3
echo "Generated keys."

echo "Checking for free floating IPs"
FREE_FLOATING_IPS=$(openstack floating ip list --status DOWN -c "Floating IP Address" -f value)

if [ -z "$FREE_FLOATING_IPS" ]; then
    echo "No free floating IPs found, creating two"
    FLOATING_IP1=$(openstack floating ip create ext-net --tag $2 -f value -c floating_ip_address)
    FLOATING_IP2=$(openstack floating ip create ext-net --tag $2 -f value -c floating_ip_address)
    echo "Floating IPs created: $FLOATING_IP1 and $FLOATING_IP2"
else
    IP_COUNT=$(echo "$FREE_FLOATING_IPS" | wc -l)
    
    if [ "$IP_COUNT" -ge 2 ]; then
        FLOATING_IP1=$(echo "$FREE_FLOATING_IPS" | head -n 1)
        FLOATING_IP2=$(echo "$FREE_FLOATING_IPS" | head -n 2 | tail -n 1)
        echo "Using existing free floating IPs: $FLOATING_IP1 and $FLOATING_IP2"
    else
        FLOATING_IP1=$(echo "$FREE_FLOATING_IPS")
        FLOATING_IP2=$(openstack floating ip create --tag $2 ext-net -f value -c floating_ip_address)
        echo "Using existing free IP $FLOATING_IP1 and created new IP $FLOATING_IP2"
    fi
fi

# Create network and subnet
NETWORK_NAME="network_$2"
SUBNET_NAME="subnet_$2"
CIDR="10.0.0.0/24"  

echo "Creating network: $NETWORK_NAME"
NETWORK_ID=$(openstack network create --tag $2 $NETWORK_NAME -f value -c id)

if [ -z "$NETWORK_ID" ]; then
    echo "Failed to create network"
    exit 1
fi

echo "Creating subnet: $SUBNET_NAME"
openstack subnet delete $SUBNET_NAME 2>/dev/null
SUBNET_ID=$(openstack subnet create $SUBNET_NAME --tag $2 --network $NETWORK_ID --subnet-range $CIDR -f value -c id)

if [ -z "$SUBNET_ID" ]; then
    echo "Failed to create subnet"
    exit 1
fi

echo "Network $NETWORK_NAME and subnet $SUBNET_NAME created successfully"

# Create and configure router
ROUTER_NAME="router_$2"
echo "Creating router: $ROUTER_NAME"
openstack router delete $ROUTER_NAME 2>/dev/null
ROUTER_ID=$(openstack router create --tag $2 $ROUTER_NAME -f value -c id)

if [ -z "$ROUTER_ID" ]; then
    echo "Failed to create router"
    exit 1
fi

echo "Setting external gateway for router"
openstack router set $ROUTER_NAME --external-gateway ext-net

echo "Adding subnet interface to router"
openstack router add subnet $ROUTER_NAME $SUBNET_NAME

echo "Router $ROUTER_NAME created and configured successfully"


# Create security group
SECURITY_GROUP_NAME="security_$2"
SECURITY_GROUP_NAME2="security2_$2"
echo "Creating security group: $SECURITY_GROUP_NAME"
openstack security group delete $SECURITY_GROUP_NAME 2>/dev/null
openstack security group delete $SECURITY_GROUP_NAME2 2>/dev/null
openstack security group create $SECURITY_GROUP_NAME --tag $2
openstack security group create $SECURITY_GROUP_NAME2 --tag $2

# Configure security group rules
echo "Configuring security group rules"
openstack security group rule create $SECURITY_GROUP_NAME --protocol tcp --remote-ip 0.0.0.0/0
openstack security group rule create $SECURITY_GROUP_NAME --protocol udp --remote-ip 0.0.0.0/0
openstack security group rule create $SECURITY_GROUP_NAME --protocol icmp --remote-ip 0.0.0.0/0



## VM creation function
create_vm() {
    local VM_NAME=$1
    local TAG=$2
    local KEY_NAME=$3
    
    echo "Key Name is: $KEY_NAME"
    echo "Creating VM: $VM_NAME"
    openstack server create \
        --flavor "2C-2GB-20GB" \
        --image "Ubuntu 20.04 Focal Fossa x86_64" \
        --security-group $SECURITY_GROUP_NAME \
        --key-name "$KEY_NAME" \
        --network $NETWORK_NAME \
        "$VM_NAME"
}

# Create 5 VMs
create_vm "bastion_$2" "$2" "$3"
create_vm "proxy_$2" "$2" "$3"
create_vm "vm1_$2" "$2" "$3"
create_vm "vm2_$2" "$2" "$3"
create_vm "vm3_$2" "$2" "$3"

echo "VM creation completed"

# Assign floating IPs to bastion and proxy
echo "Assigning floating IP $FLOATING_IP1 to bastion_$2"
openstack server add floating ip "bastion_$2" $FLOATING_IP1

echo "Assigning floating IP $FLOATING_IP2 to proxy_$2"
openstack server add floating ip "proxy_$2" $FLOATING_IP2

echo "Floating IPs assigned successfully"

# Store IPs in files
echo "$FLOATING_IP1" > ./storage/ips
echo "$FLOATING_IP2" >> ./storage/ips
# Get and store local IPs for vm1, vm2, and vm3
for vm in "vm1_$2" "vm2_$2" "vm3_$2"; do
    IP=$(openstack server show $vm -f value -c addresses | sed -n "s/.*'\(.*\)'.*/\1/p")
    echo "$IP" >> ./storage/ips
    echo "$IP" >> ./storage/serverips
done
cp servers.conf ./operate_files/history_servers.conf
cd install_files
bash install_software.sh $3 $FLOATING_IP1


