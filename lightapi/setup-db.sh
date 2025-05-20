#!/bin/bash

# Start MySQL service
service mariadb start

# Wait for MySQL to be ready
until mysqladmin ping --silent; do
    echo "Waiting for MySQL to be ready..."
    sleep 2
done

echo "MySQL is ready"

# Verify and set MySQL settings
mysql -e "
SET GLOBAL innodb_buffer_pool_size = $(( 64 * 1024 * 1024 * 1024 ));
SET GLOBAL innodb_log_buffer_size = $(( 2 * 1024 * 1024 * 1024 ));
"

# Log the current settings
echo "Current MySQL settings:"
mysql -e "
SHOW VARIABLES LIKE 'innodb_buffer_pool_size';
SHOW VARIABLES LIKE 'innodb_log_buffer_size';
SHOW VARIABLES LIKE 'innodb_log_file_size';
"

# Check if this is a restore scenario
if [ -f "/srv/eos/backups/lightapi_backup.sql" ]; then
    echo "Backup file detected, checking for restore process..."
    
    # Check if database is empty (likely needs restore)
    DB_COUNT=$(mysql -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'lightapi'")
    
    if [ "$DB_COUNT" -eq "0" ]; then
        echo "Empty database detected with backup present, waiting for restore..."
        
        # Wait for restore to start (up to 5 minutes)
        TIMEOUT=150
        COUNT=0
        while [ ! -f "/tmp/db_restore_in_progress" ] && [ $COUNT -lt $TIMEOUT ]; do
            echo "Waiting for restore to start... ($COUNT/150)"
            sleep 2
            COUNT=$((COUNT + 1))
        done

        if [ -f "/tmp/db_restore_in_progress" ]; then
            echo "Restore process started, waiting for completion..."
            while [ -f "/tmp/db_restore_in_progress" ]; do
                echo "Database restore in progress, waiting..."
                sleep 10
            done
            echo "Restore completed, proceeding with service startup..."
        else
            echo "Warning: Backup file present but restore didn't start within timeout."
            echo "Proceeding with normal initialization..."
        fi
    else
        echo "Database already contains tables, skipping restore wait..."
    fi
fi

# Initialize database and users
mysql -e "CREATE DATABASE IF NOT EXISTS lightapi;"

# Create users and grant privileges
mysql -e "CREATE USER IF NOT EXISTS 'lightapi'@'localhost' IDENTIFIED BY 'ce1Shish';"
mysql -e "CREATE USER IF NOT EXISTS 'lightapi'@'%' IDENTIFIED BY 'ce1Shish';"
mysql -e "CREATE USER IF NOT EXISTS 'lightapiro'@'localhost' IDENTIFIED BY 'lightapiro';"
mysql -e "CREATE USER IF NOT EXISTS 'lightapiro'@'%' IDENTIFIED BY 'lightapiro';"

# Grant privileges
mysql -e "GRANT ALL ON lightapi.* TO 'lightapi'@'localhost';"
mysql -e "GRANT ALL ON lightapi.* TO 'lightapi'@'%';"
mysql -e "GRANT SELECT ON lightapi.* TO 'lightapiro'@'localhost';"
mysql -e "GRANT SELECT ON lightapi.* TO 'lightapiro'@'%';"
mysql -e "FLUSH PRIVILEGES;"

# Create initial tables
mysql lightapi << 'EOF'
CREATE TABLE IF NOT EXISTS NETWORKS
(
 network           VARCHAR(15) PRIMARY KEY,
 chainid           VARCHAR(64) NOT NULL,
 description       VARCHAR(256) NOT NULL,
 systoken          VARCHAR(7) NOT NULL,
 decimals          TINYINT NOT NULL,
 production        TINYINT NOT NULL DEFAULT 1,
 rex_enabled       TINYINT NOT NULL DEFAULT 0
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS SYNC
(
 network           VARCHAR(15) PRIMARY KEY,
 block_num         BIGINT NOT NULL,
 block_time        DATETIME NOT NULL,
 irreversible      BIGINT NOT NULL 
) ENGINE=InnoDB;
EOF

# Create tables and add network configuration
cd /opt/eosio_light_api/sql
sh create_tables.sh wax
sh /opt/eosio_light_api/setup/add_wax_mainnet.sh

# Create directories and config files
mkdir -p /var/log/lightapi
mkdir -p /var/run/lightapi
mkdir -p /etc/default

# Write configuration files
cat > /etc/default/lightapi_wax <<EOF
DBWRITE_OPTS="--network=wax --port=8100 --dbuser=lightapi --dbpw=ce1Shish"
EOF

cat > /etc/default/lightapi_api <<EOF
LIGHTAPI_HOME=/opt/eosio_light_api
LISTEN=0.0.0.0:5001
WORKERS=6
EOF

cat > /etc/default/lightapi_wsapi <<EOF
WSAPI_HOME=/opt/eosio_light_api/wsapi
NODE=/usr/bin/node
EOF

# Start the dbwrite service
cd /opt/eosio_light_api
echo "Starting dbwrite service..."
PERL_ITHREADS=1 PERL_MAX_MEMORY=12G PERL_DESTRUCT_LEVEL=2 perl scripts/lightapi_dbwrite.pl \
    --network=wax \
    --port=8100 \
    --dsn="DBI:MariaDB:database=lightapi;host=0.0.0.0" \
    --dbuser=lightapi \
    --dbpw=ce1Shish \
    --ack=2 > /var/log/lightapi/dbwrite_wax.log 2>&1 &

# Start the API service
echo "Starting API service..."
/usr/local/bin/starman \
    --listen 0.0.0.0:5001 \
    --workers 6 \
    /opt/eosio_light_api/api/lightapi.psgi > /var/log/lightapi/api.log 2>&1 &

# Start WebSocket API servers
echo "Starting WebSocket API servers..."
WSAPI_HOME=/opt/eosio_light_api/wsapi
NODE=/usr/bin/node

for port in 5101 5102 5103 5104 5105; do
    echo "Starting WebSocket API on port ${port}..."
    cd ${WSAPI_HOME}
    ${NODE} lightapi_wsapi.js --httpport=${port} --httphost=0.0.0.0 > /var/log/lightapi/wsapi_${port}.log 2>&1 &
    echo $! > /var/run/lightapi/wsapi_${port}.pid
done

# Start the monitoring loop
(
while true; do
    # Monitor and restart services as needed
    if ! pgrep -f "lightapi_dbwrite.pl" > /dev/null; then
        echo "Restarting dbwrite service..."
        cd /opt/eosio_light_api
        PERL_ITHREADS=1 PERL_MAX_MEMORY=12G PERL_DESTRUCT_LEVEL=2 MOJO_MAX_WEBSOCKET_SIZE=0 MOJO_MAX_MESSAGE_SIZE=0 MOJO_MAX_BUFFER_SIZE=0 MOJO_REACTOR=Mojo::Reactor::Poll perl scripts/lightapi_dbwrite.pl \
            --network=wax \
            --port=8100 \
            --dsn="DBI:MariaDB:database=lightapi;host=0.0.0.0" \
            --dbuser=lightapi \
            --dbpw=ce1Shish \
            --ack=2 > /var/log/lightapi/dbwrite_wax.log 2>&1 &
    fi
    
    if ! pgrep -f "starman" > /dev/null; then
        echo "Restarting API service..."
        /usr/local/bin/starman \
            --listen 0.0.0.0:5001 \
            --workers 6 \
            /opt/eosio_light_api/api/lightapi.psgi > /var/log/lightapi/api.log 2>&1 &
    fi

    for port in 5101 5102 5103 5104 5105; do
        if ! pgrep -f "lightapi_wsapi.js.*${port}" > /dev/null; then
            echo "Restarting WebSocket API on port ${port}..."
            cd ${WSAPI_HOME}
            ${NODE} lightapi_wsapi.js --httpport=${port} --httphost=0.0.0.0 > /var/log/lightapi/wsapi_${port}.log 2>&1 &
            echo $! > /var/run/lightapi/wsapi_${port}.pid
        fi
    done
    
    # Log memory usage every 5 minutes
    if [ $(( $(date +%s) % 300 )) -eq 0 ]; then
        echo "=== Memory Usage Report ===" >> /var/log/lightapi/memory.log
        date >> /var/log/lightapi/memory.log
        free -h >> /var/log/lightapi/memory.log
        mysql -e "SHOW ENGINE INNODB STATUS\G" | grep -A 20 "BUFFER POOL AND MEMORY" >> /var/log/lightapi/memory.log
        echo "=========================" >> /var/log/lightapi/memory.log
    fi

    sleep 30
done
) &

# Keep container running and log output
tail -f /var/log/lightapi/*.log