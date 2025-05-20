#!/bin/bash

# Check if backup files exist
if [ ! -f "./backups/lightapi_backup.sql" ] || [ ! -f "./backups/wax.snapshot" ]; then
    echo "Error: Required backup files not found in ./backups/"
    echo "Need: lightapi_backup.sql and wax.snapshot"
    exit 1
fi

echo "Starting restore process..."

# Stop any running containers and clean volumes
docker compose down -v

# Start only the lightapi container for restore
echo "Starting lightapi container for database restore..."
docker compose up -d lightapi

# Wait for MariaDB to be ready
echo "Waiting for database to be ready..."
until docker compose exec lightapi mysqladmin ping -h localhost --silent; do
    sleep 2
done

# Create restore flag
docker compose exec lightapi touch /tmp/db_restore_in_progress

# Create database and user before restore
echo "Creating database and user..."
docker compose exec lightapi mysql -e "CREATE DATABASE IF NOT EXISTS lightapi;"
docker compose exec lightapi mysql -e "CREATE USER IF NOT EXISTS 'lightapi'@'localhost' IDENTIFIED BY 'ce1Shish';"
docker compose exec lightapi mysql -e "CREATE USER IF NOT EXISTS 'lightapi'@'%' IDENTIFIED BY 'ce1Shish';"
docker compose exec lightapi mysql -e "GRANT ALL ON lightapi.* TO 'lightapi'@'localhost';"
docker compose exec lightapi mysql -e "GRANT ALL ON lightapi.* TO 'lightapi'@'%';"
docker compose exec lightapi mysql -e "FLUSH PRIVILEGES;"

# # Configure MySQL for faster restore
echo "Configuring MySQL for restore performance..."
docker compose exec lightapi mysql -e "
SET GLOBAL innodb_buffer_pool_size = 8589934592;
SET GLOBAL innodb_flush_log_at_trx_commit = 0;
SET GLOBAL innodb_flush_method = O_DIRECT;
SET GLOBAL innodb_doublewrite = 0;
SET GLOBAL sync_binlog = 0;
SET GLOBAL innodb_io_capacity = 2000;
SET GLOBAL innodb_io_capacity_max = 4000;
"

# Restore database using the mounted path inside container
echo "Restoring database..."
docker compose exec -T lightapi mysql lightapi < ./backups/lightapi_backup.sql

# # Reset MySQL configuration for normal operation
echo "Resetting MySQL configuration..."
docker compose exec lightapi mysql -e "
SET GLOBAL innodb_flush_log_at_trx_commit = 1;
SET GLOBAL innodb_doublewrite = 1;
SET GLOBAL sync_binlog = 1;
SET GLOBAL innodb_io_capacity = 200;
SET GLOBAL innodb_io_capacity_max = 2000;
"

# Remove restore flag
docker compose exec lightapi rm /tmp/db_restore_in_progress

echo "Restore completed successfully!"
echo "You can now start the services with: docker compose up -d"
