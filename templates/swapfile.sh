sudo fallocate -l 2G /swapfile #2GB
sudo chmod 0600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
