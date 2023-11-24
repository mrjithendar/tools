dnf install mariadb-server -y

systemctl start mariadb
systemctl enable mariadb

mysql_secure_installation

dnf install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
dnf install https://rpms.remirepo.net/enterprise/remi-release-8.rpm

dnf module reset php -y
dnf module install php:remi-8.0 -y

dnf install php php-mysqlnd php-fpm php-opcache php-curl php-json php-gd php-xml php-mbstring php-zip -y

php -v

nano /etc/php-fpm.d/www.conf
user = nginx
group = nginx

systemctl start php-fpm
systemctl enable php-fpm

mysql -u root -p

CREATE DATABASE wordpressdb;
CREATE/ALTER USER `wordpressuser`@`localhost` IDENTIFIED BY 'securepassword';
GRANT ALL ON wordpressdb.* TO `wordpressuser`@`localhost`;
FLUSH PRIVILEGES;
EXIT;

mkdir -p /var/www/html/decodedevops.com
cd /var/www/html/decodedevops.com
wget https://wordpress.org/latest.tar.gz -O /tmp/wp.tar.gz
tar -xvzf /tmp/wp.tar.gz --directory /tmp
mv -fv /tmp/wordpress/* /var/www/html/decodedevops.com

chown -R nginx:nginx /var/www/html/decodedevops.com

echo 'server {
   listen 80;
   server_name decodedevops.com www.decodedevops.com;

   root /var/www/html/decodedevops.com;
   index index.php index.html index.htm;

   location / {
      try_files $uri $uri/ =404;
   }
   error_page 404 /404.html;
   error_page 500 502 503 504 /50x.html;
   location = /50x.html {
      root /usr/share/nginx/html;
   }

   location ~ \.php$ {
      try_files $uri =404;
      fastcgi_pass unix:/var/run/php-fpm/www.sock;
      fastcgi_index index.php;
      fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
      include fastcgi_params;
   }
}' > /etc/nginx/conf.d/decodedevops.conf

nginx -t

systemctl enable nginx
systemctl restart nginx

systemctl status nginx


certbot --nginx --agree-tos --redirect --hsts --uir --staple-ocsp --email user@decodedevops.com -d decodedevops.com,www.decodedevops.com
