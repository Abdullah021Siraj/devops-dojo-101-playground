# HOW TO ADD CUSTOM SSH PORT WITHOUT LOCKING YOURSELF OUT 

```

sudo nano /etc/ssh/sshd_config

```

### Add custom port in a new line while keeping port 22

```

Port 22222 # any custom port you want 

```

### NOTE: KEEP PORT 22 FOR NOW 
```

Port 22

```
### Restart
```

sudo systemctl restart ssh

```
## Enable UFW Firewall Rules 
```

sudo ufw allow 22222/tcp
sudo ufw reload

```
### Test on another terminal 
```

ssh -p 22222 -i ~/.ssh/key.pem root@ip-address

```
### Stop and mask the old socket (port 22)
```

sudo systemctl stop ssh.socket
sudo systemctl disable ssh.socket
sudo systemctl mask ssh.socket

```

### Now port 22 is fully gone.

### Remove port 22 from sshd_config
```

sudo nano /etc/ssh/sshd_config

```
### Delete or comment out 22
```

Port 22

```

### Restart ssh 
```

sudo systemctl restart ssh

```

### Test once again on new terminal 
```

ssh -p 22222 -i ~/.ssh/key.pem root@ip-address

```
