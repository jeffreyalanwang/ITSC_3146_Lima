#!/bin/bash

instance_name="ITSC-3146"

# create image
echo "Create Lima instance ${instance_name}..."
limactl create --tty=false "https://raw.githubusercontent.com/jeffreyalanwang/Lima_itsc_3146/refs/heads/main/pub/${instance_name}.yaml"

# configure host SSH
echo "Adding instance SSH config to ~/.ssh/config..."
echo 'Include ~/.lima/*/ssh.config' >> ~/.ssh/config # a live-updating version of the below
#limactl show-ssh --format=config "$instance_name" >> ~/.ssh/config