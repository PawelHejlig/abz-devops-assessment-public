#!/bin/bash
set -e

# ENV VARS NEEDED (passed via Terraform user_data):
# WORDPRESS_DB_HOST, WORDPRESS_DB_USER, WORDPRESS_DB_PASSWORD, WORDPRESS_DB_NAME
# WORDPRESS_ADMIN_USER, WORDPRESS_ADMIN_PASS, WORDPRESS_ADMIN_EMAIL
# WORDPRESS_REDIS_HOST, WORDPRESS_REDIS_PORT

# Update system and install dependencies
yum update -y
amazon-linux-extras enable php8.0
yum install -y httpd php php-mysqlnd php-opcache php-pecl-redis mysql unzip wget curl less redis

# Configure and start Apache
systemctl enable --now httpd

# Install WP-CLI properly
curl -o /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x /usr/local/bin/wp

# Install WordPress
wget https://wordpress.org/latest.zip -O /tmp/wordpress.zip
unzip /tmp/wordpress.zip -d /tmp/
rm -rf /var/www/html/*
cp -r /tmp/wordpress/* /var/www/html/
rm -rf /tmp/wordpress /tmp/wordpress.zip

# Set proper permissions
chown -R apache:apache /var/www/html
find /var/www/html -type d -exec chmod 755 {} \;
find /var/www/html -type f -exec chmod 644 {} \;

# Create wp-config.php with proper Redis and DB settings
cat <<EOF > /var/www/html/wp-config.php
<?php
define('DB_NAME', '${WORDPRESS_DB_NAME}');
define('DB_USER', '${WORDPRESS_DB_USER}');
define('DB_PASSWORD', '${WORDPRESS_DB_PASSWORD}');
define('DB_HOST', '${WORDPRESS_DB_HOST}');
define('DB_CHARSET', 'utf8');
define('DB_COLLATE', '');

define('WP_REDIS_HOST', '${WORDPRESS_REDIS_HOST}');
define('WP_REDIS_PORT', ${WORDPRESS_REDIS_PORT});
define('WP_CACHE', true);
define('WP_CACHE_KEY_SALT', 'wordpress_test_');

/* Authentication Keys & Salts - using random values */
define('AUTH_KEY',         '$(openssl rand -base64 48)');
define('SECURE_AUTH_KEY',  '$(openssl rand -base64 48)');
define('LOGGED_IN_KEY',    '$(openssl rand -base64 48)');
define('NONCE_KEY',        '$(openssl rand -base64 48)');
define('AUTH_SALT',        '$(openssl rand -base64 48)');
define('SECURE_AUTH_SALT', '$(openssl rand -base64 48)');
define('LOGGED_IN_SALT',   '$(openssl rand -base64 48)');
define('NONCE_SALT',       '$(openssl rand -base64 48)');

\$table_prefix = 'wp_';
define('WP_DEBUG', true);
define('WP_DEBUG_LOG', true);
define('WP_DEBUG_DISPLAY', false);

if (!defined('ABSPATH')) {
    define('ABSPATH', __DIR__ . '/');
}

require_once ABSPATH . 'wp-settings.php';
EOF

# Set strict permissions for wp-config.php
sudo chown apache:apache /var/www/html/wp-config.php
sudo chmod 640 /var/www/html/wp-config.php

# Wait for MySQL to be available
for i in {1..12}; do
  if mysql -h "$WORDPRESS_DB_HOST" -u"$WORDPRESS_DB_USER" -p"$WORDPRESS_DB_PASSWORD" -e "SELECT 1;" "$WORDPRESS_DB_NAME"; then
    echo "MySQL is up!"
    break
  else
    echo "Waiting for MySQL ($i)..."
    sleep 5
  fi
done

# Install WordPress core
sudo -u apache /usr/local/bin/wp --path=/var/www/html core install \
  --url="http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)" \
  --title="Test WordPress Site" \
  --admin_user="$WORDPRESS_ADMIN_USER" \
  --admin_password="$WORDPRESS_ADMIN_PASS" \
  --admin_email="$WORDPRESS_ADMIN_EMAIL" \
  --skip-email

# Create read-only reviewer user
REVIEWER_USER="reviewer"
REVIEWER_EMAIL="reviewer@example.com"
REVIEWER_PASS="readonly123"

sudo -u apache /usr/local/bin/wp --path=/var/www/html user create "$REVIEWER_USER" "$REVIEWER_EMAIL" \
  --role=editor \
  --user_pass="$REVIEWER_PASS"

# Strip write capabilities to make it read-only
sudo -u apache /usr/local/bin/wp --path=/var/www/html cap remove "$REVIEWER_USER" \
  edit_posts publish_posts delete_posts upload_files delete_pages delete_others_posts

# Install and configure Redis Object Cache
sudo -u apache /usr/local/bin/wp --path=/var/www/html plugin install redis-cache --activate
sudo -u apache /usr/local/bin/wp --path=/var/www/html redis enable

# Configure SELinux
setenforce 0
sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config

# Restart services
systemctl restart httpd
systemctl restart redis

echo "WordPress installation completed successfully!"