### The following files are for a small VPS. I have used them and passed them in my wordpress docker compose, which is attached below: 

```bash

services:
  wordpress:
    image: wordpress:php7.4
    container_name: wordpress
    restart: unless-stopped
    ports:
      - "127.0.0.1:9001:80"
    networks:
      - network
    volumes:
      - /var/www/html:/var/www/html/
      - ./docker-configs/wordpress/php.ini:/usr/local/etc/php/php.ini
      - ./docker-configs/wordpress/conf.d/opcache.ini:/usr/local/etc/php/conf.d/opcache.ini
      - ./docker-configs/wordpress/php-fpm.d:/usr/local/etc/php-fpm.d
    depends_on:
      - db

```
