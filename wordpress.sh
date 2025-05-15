#!/bin/bash

set -e

yum update -y
amazon-linux-extras enable php8.0
yum install -y httpd php php-mysqlnd php-opcache php-pecl-redis wget unzip

systemctl enable httpd
systemctl start httpd

wget https://wordpress.org/latest.zip -O /tmp/wordpress.zip
unzip /tmp/wordpress.zip -d /var/www/html/
cp -r /var/www/html/wordpress/* /var/www/html/
rm -rf /var/www/html/wordpress /tmp/wordpress.zip

chown -R apache:apache /var/www/html
chmod -R 755 /var/www/html

cp /var/www/html/wp-config-sample.php /var/www/html/wp-config.php

cat <<EOF >> /var/www/html/wp-config.php

// DB credentials from environment
define('DB_NAME', getenv('WORDPRESS_DB_NAME'));
define('DB_USER', getenv('WORDPRESS_DB_USER'));
define('DB_PASSWORD', getenv('WORDPRESS_DB_PASSWORD'));
define('DB_HOST', getenv('WORDPRESS_DB_HOST'));

// Redis for sessions
define('WP_REDIS_HOST', getenv('WORDPRESS_REDIS_HOST'));
define('WP_REDIS_PORT', getenv('WORDPRESS_REDIS_PORT'));

define('WP_CACHE', true);

EOF

systemctl restart httpd
