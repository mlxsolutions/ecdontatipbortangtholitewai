#!/bin/bash

# Block IP addresses using UFW
sudo ufw deny from 172.104.241.92

# Reload UFW to apply changes
sudo ufw reload

# Display the current UFW status with numbered rules
sudo ufw status numbered
