# automatically upgrades 

apt install unattended-upgrades
dpkg-reconfigure --priority=low unattended-upgrades

# create a non-root user with root privileges 

adduser [username]
usermod -aG sudo [username]

# create a SSH key & copy the public key to the server

ssh-keygen -b 4096
ssh-copy-id user@ip

# update /etc/ssh/sshd_config

PasswordAuthentication no 
PubkeyAuthentication yes 
AuthorizedKeysFile .ssh/authorized_keys
PermitRootLogin no 
Port [any] 
AddressFamily inet

sudo systemctl restart ssh 

# enable firewall

sudo ufw allow [ssh port]

# Disable PING 

sudo iptables -I INPUT -p icmp --icmp-type echo-request -j DROP 
sudo ip6tables -I INPUT -p icmpv6 --icmpv6-type echo-request -j DROP

sudo ufw reload
sudo reboot
