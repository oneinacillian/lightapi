#!/bin/bash

# Function to handle shutdown
shutdown() {
    echo "Received shutdown signal. Gracefully stopping Chronicle..."
    if [ ! -z "$CHRONICLE_PID" ]; then
        kill -SIGTERM $CHRONICLE_PID
        wait $CHRONICLE_PID
    fi
    exit 0
}

# Trap SIGTERM and SIGINT
trap shutdown SIGTERM SIGINT

echo "Starting Chronicle..."

# Function to check lightapi readiness
check_lightapi() {
    nc -z -w 5 lightapi 8100
    return $?
}

# Wait for lightapi with better feedback
echo "Waiting for lightapi service to be ready..."
while ! check_lightapi; do
    echo "Lightapi not ready, retrying in 5 seconds..."
    sleep 5
done
echo "Lightapi service is ready"

while true; do
    # Check if snapshot exists and hasn't been restored yet
    if [ -f "/srv/eos/backups/wax.snapshot" ] && [ ! -f "/srv/eos/chronicle-data/.snapshot_restored" ]; then
        echo "Found snapshot, starting Chronicle with snapshot restoration..."
        /usr/local/sbin/chronicle-receiver \
            --config-dir=/srv/eos/chronicle-config \
            --data-dir=/srv/eos/chronicle-data \
            --restore-snapshot=/srv/eos/backups/wax.snapshot &
        
        CHRONICLE_PID=$!
        wait $CHRONICLE_PID
        EXIT_CODE=$?
        
        if [ $EXIT_CODE -eq 0 ]; then
            echo "Snapshot restored successfully. Creating marker file..."
            touch /srv/eos/chronicle-data/.snapshot_restored
        else
            echo "Snapshot restoration failed with code: $EXIT_CODE"
            sleep 5
            continue
        fi
    fi

    echo "Starting Chronicle for normal operation..."
    
    # Check if state database exists
    if [ ! -d "/srv/eos/chronicle-data/receiver-state" ]; then
        echo "No state database found, starting from block 372398898..."
        /usr/local/sbin/chronicle-receiver \
            --config-dir=/srv/eos/chronicle-config \
            --data-dir=/srv/eos/chronicle-data \
            --start-block=372398898 \
            --end-block=572399898 &
    else
        echo "State database exists, continuing from last processed block..."
        /usr/local/sbin/chronicle-receiver \
            --config-dir=/srv/eos/chronicle-config \
            --data-dir=/srv/eos/chronicle-data \
            --end-block=572399898 &
    fi
    
    CHRONICLE_PID=$!
    echo "Chronicle started with PID: $CHRONICLE_PID"
    
    # Monitor Chronicle process
    while kill -0 $CHRONICLE_PID 2>/dev/null; do
        if ! check_lightapi; then
            echo "Lost connection to lightapi, waiting for reconnection..."
            while ! check_lightapi; do
                sleep 5
            done
            echo "Lightapi connection restored"
        fi
        
        # Give Chronicle time to initialize before checking for hangs
        if [ ! -f "/tmp/chronicle_initialized" ]; then
            # Look for the "All dependent plugins started" message
            if grep -q "All dependent plugins started" /srv/eos/chronicle-data/receiver-state/default.log 2>/dev/null; then
                touch /tmp/chronicle_initialized
                echo "Chronicle initialization completed"
            else
                sleep 5
                continue
            fi
        fi
        
        # Only check for hangs after initialization
        if [ -f "/tmp/chronicle_initialized" ]; then
            LAST_LOG_TIME=$(stat -c %Y /srv/eos/chronicle-data/receiver-state/default.log 2>/dev/null || echo $CURRENT_TIME)
            CURRENT_TIME=$(date +%s)
            TIME_DIFF=$((CURRENT_TIME - LAST_LOG_TIME))
            
            if [ $TIME_DIFF -gt 300 ]; then  # 5 minutes without log updates
                echo "Chronicle appears hung (no log updates for 5 minutes)"
                kill -SIGTERM $CHRONICLE_PID
                wait $CHRONICLE_PID
                rm -f /tmp/chronicle_initialized
                break
            fi
        fi
        
        sleep 5
    done
    
    # Always restart unless explicitly terminated
    EXIT_CODE=$?
    if [ $EXIT_CODE -eq 143 ]; then  # SIGTERM
        echo "Chronicle was terminated, exiting..."
        exit 0
    else
        echo "Chronicle exited with code: $EXIT_CODE, restarting in 5 seconds..."
        sleep 5
    fi
done

# sleep 30000
