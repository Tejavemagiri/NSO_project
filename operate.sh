#!/bin/bash

# Usage: operate <openrc> <tag> <ssh_key>
#                 $1      $2     $3

. $1

get_current_instances() {
    openstack server list --format value -c Name | grep -E "^vm.*_$1$" | wc -l
}

operation() {
    local new_number=$1
    local tag=$2
    local old_number=$(get_current_instances $tag) 
    local difference=$((new_number - old_number))
    
    echo "File changed! New number is: $new_number"
    echo "Current number of instances is: $old_number"
    echo "Difference is: $difference"
    echo "Tag is: $tag"
    echo "Key is $5"

    if [ $difference -lt 0 ]; then
        # Negative difference: destroy VMs
        for ((i=0; i<-difference; i++)); do
            echo "Destroying VM $((i+1)) of ${difference#-}"
            ./operate_files/destroy.sh "$3" "$4" "$5"
        done
        cd operate_files
        bash install_software.sh "$5"
        cd ..
    elif [ $difference -gt 0 ]; then
        # Positive difference: deploy VMs
        for ((i=0; i<difference; i++)); do
            echo "Deploying VM $((i+1)) of $difference"
            ./operate_files/deploy.sh "$3" "$4" "$5"
        done
        cd operate_files
        bash install_software.sh "$5"
        cd ..
    else
        echo "No change in VM count"
    fi
}

monitor_file() {
    echo "Getting current instances... "
    local filename="$1"
    local last_modified=0
    local last_number=$(get_current_instances $3) 
    echo "Last number of instances is: $last_number"

    while true; do
        if [ -f "$filename" ]; then
            current_modified=$(stat -c %Y "$filename")
            if [ "$current_modified" != "$last_modified" ]; then
                content=$(cat "$filename" | tr -d '[:space:]')
                if [[ "$content" =~ ^[0-9]+$ ]]; then
                    if [ "$content" != "$last_number" ]; then
                        operation "$content" "$3" "$2" "$3" "$4"
                        last_number="$content"
                    fi
                else
                    echo "Invalid content in file: not a number"
                fi
                last_modified="$current_modified"
            fi
        else
            echo "File $filename not found. Waiting for it to be created..."
        fi
        sleep 1
    done
}

# Check if all required arguments are provided
if [ $# -ne 3 ]; then
    echo "Usage: $0 <openrc> <tag> <ssh_key>"
    exit 1
fi

monitor_file "servers.conf" "$1" "$2" "$3"
# openstack server list --format value -c Name | grep -E "^vm.*_r1$" | wc -l
