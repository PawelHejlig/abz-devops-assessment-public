#!/bin/bash
set -e

# ENV VARS NEEDED (passed via Terraform user_data):
# WORDPRESS_DB_HOST, WORDPRESS_DB_USER, WORDPRESS_DB_PASSWORD, WORDPRESS_DB_NAME
# WORDPRESS_ADMIN_USER, WORDPRESS_ADMIN_PASS, WORDPRESS_ADMIN_EMAIL

yum update -y
amazon-linux-extras enable php8.0
yum install -y httpd php php-mysqlnd php-opcache php-pecl-redis mysql unzip wget curl less

systemctl enable httpd
systemctl start httpd

curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp

wget https://wordpress.org/latest.zip -O /tmp/wordpress.zip
unzip /tmp/wordpress.zip -d /var/www/html/
cp -r /var/www/html/wordpress/* /var/www/html/
rm -rf /var/www/html/wordpress /tmp/wordpress.zip
chown -R apache:apache /var/www/html
chmod -R 755 /var/www/html

# Generate wp-config.php from sample
cd /var/www/html
cp wp-config-sample.php wp-config.php

cat <<EOF >> wp-config.php

define('DB_NAME', getenv('WORDPRESS_DB_NAME'));
define('DB_USER', getenv('WORDPRESS_DB_USER'));
define('DB_PASSWORD', getenv('WORDPRESS_DB_PASSWORD'));
define('DB_HOST', getenv('WORDPRESS_DB_HOST'));
define('WP_REDIS_HOST', getenv('WORDPRESS_REDIS_HOST'));
define('WP_REDIS_PORT', getenv('WORDPRESS_REDIS_PORT'));
define('WP_CACHE', true);

EOF

for i in {1..12}; do
  if mysql -h "$WORDPRESS_DB_HOST" -u"$WORDPRESS_DB_USER" -p"$WORDPRESS_DB_PASSWORD" -e "SELECT 1;" "$WORDPRESS_DB_NAME"; then
    echo "MySQL is up!"
    break
  else
    echo "Waiting for MySQL ($i)..."
    sleep 5
  fi
done

if ! wp core is-installed --allow-root; then
  wp core install \
    --url="http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)" \
    --title="Test WordPress Site" \
    --admin_user="$WORDPRESS_ADMIN_USER" \
    --admin_password="$WORDPRESS_ADMIN_PASS" \
    --admin_email="$WORDPRESS_ADMIN_EMAIL" \
    --skip-email \
    --allow-root
fi

# Create read-only reviewer user
REVIEWER_USER="reviewer"
REVIEWER_EMAIL="reviewer@example.com"
REVIEWER_PASS="readonly123"

until wp core is-installed --allow-root; do
  echo "Waiting for WordPress install..."
  sleep 5
done

wp user create "$REVIEWER_USER" "$REVIEWER_EMAIL" --role=editor --user_pass="$REVIEWER_PASS" --allow-root

# Strip write capabilities to make it read-only
wp cap remove "$REVIEWER_USER" \
  edit_posts publish_posts delete_posts upload_files delete_pages delete_others_posts \
  --allow-root

systemctl restart httpd
