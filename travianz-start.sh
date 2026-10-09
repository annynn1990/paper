#!/usr/bin/env bash
set -Eeuo pipefail

DB_NAME="${MARIADB_DATABASE:-travian}"
DB_USER="${MARIADB_USER:-travianz}"
DB_PASS="${MARIADB_PASSWORD:-travianzpass}"
DB_HOST="127.0.0.1"
DB_PORT="3306"

[[ "$DB_NAME" =~ ^[A-Za-z0-9_]+$ ]] || { echo "Invalid MARIADB_DATABASE"; exit 1; }
[[ "$DB_USER" =~ ^[A-Za-z0-9_]+$ ]] || { echo "Invalid MARIADB_USER"; exit 1; }
[[ "$DB_PASS" =~ ^[A-Za-z0-9_.@+-]+$ ]] || { echo "MARIADB_PASSWORD contains unsupported characters"; exit 1; }

mkdir -p /run/mysqld
chown mysql:mysql /run/mysqld

if [[ ! -d /var/lib/mysql/mysql ]]; then
  echo "Initializing local MariaDB data directory..."
  mariadb-install-db --user=mysql --datadir=/var/lib/mysql >/tmp/mariadb-install.log
fi

echo "Starting local MariaDB..."
/usr/sbin/mariadbd --user=mysql --datadir=/var/lib/mysql --bind-address=127.0.0.1 >/var/log/mariadb.log 2>&1 &
ready=0
for _ in $(seq 1 60); do
  # Use the explicit Unix socket and an authenticated SQL query. The generic
  # mariadb-admin ping may report failure under container defaults even when
  # the server is already listening, which caused a false startup failure.
  if mariadb --protocol=socket --socket=/run/mysqld/mysqld.sock -uroot -e "SELECT 1" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done

if [[ "$ready" != "1" ]]; then
  echo "MariaDB did not become query-ready; recent log follows:"
  tail -100 /var/log/mariadb.log || true
  exit 1
fi

mariadb --protocol=socket --socket=/run/mysqld/mysqld.sock -uroot <<SQL
CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
ALTER USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
CREATE USER IF NOT EXISTS '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASS';
ALTER USER '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

# TravianZ reads .env directly; keep each setting on a separate line.
printf '%s\n' \
  "MARIADB_ROOT_PASSWORD=${MARIADB_ROOT_PASSWORD:-}" \
  "MARIADB_DATABASE=$DB_NAME" \
  "MARIADB_USER=$DB_USER" \
  "MARIADB_PASSWORD=$DB_PASS" \
  "MYSQL_ROOT_PASSWORD=${MARIADB_ROOT_PASSWORD:-}" \
  "MYSQL_DATABASE=$DB_NAME" \
  "MYSQL_USER=$DB_USER" \
  "MYSQL_PASSWORD=$DB_PASS" \
  "DB_HOST=$DB_HOST" \
  "DB_PORT=$DB_PORT" > /var/www/html/.env
chown www-data:www-data /var/www/html/.env
chmod 600 /var/www/html/.env

# Installer pages can run before the game config constant exists.
sed -i 's/<?php echo TZ_SERVER_RUNNING_ON; ?>/<?php echo defined("TZ_SERVER_RUNNING_ON") ? TZ_SERVER_RUNNING_ON : "TravianZ"; ?>/' /var/www/html/Templates/footer.tpl

cron
echo "TravianZ web and local database are ready."
exec apache2-foreground
