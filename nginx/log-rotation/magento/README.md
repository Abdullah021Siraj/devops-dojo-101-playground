## Ensure the log file exists and has correct permissions:

```bash
sudo touch /var/log/nginx/magento2_error.log
sudo chown www-data:adm /var/log/nginx/magento2_error.log
sudo chmod 640 /var/log/nginx/magento2_error.log
```

## Test log rotation: 

```bash
sudo logrotate -f /etc/logrotate.d/nginx-magento-logrotate.conf
```
