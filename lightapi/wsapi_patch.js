// WebSocket Flow Control and Connection Management Patch

// Configuration
const KEEPALIVE_INTERVAL = 30000;
const MAX_QUEUE_SIZE = 1000; // Reduced queue size for better stability
const PROCESSING_DELAY = 100; // Increased delay between processing messages
const BATCH_SIZE = 50; // Smaller batches for more stability
const CONNECTION_TIMEOUT = 300000; // 5 minutes timeout for connections
const RECONNECT_DELAY = 5000; // 5 seconds delay before reconnecting

// Heartbeat function for connection liveness
const heartbeat = function () { 
  this.isAlive = true;
  this.lastActivity = Date.now();
};

// Setup WebSocket connection management
function setupWebSocketConnection() {
  // Add connection handler with liveness tracking
  rpc.wss.on("connection", function connection(ws, req) {
    const clientIP = req.socket.remoteAddress;
    const clientPort = req.socket.remotePort;
    console.log(`New WebSocket connection established from ${clientIP}:${clientPort}`);
    
    // Initialize connection state
    ws.isAlive = true;
    ws.lastActivity = Date.now();
    ws.connectionTime = Date.now();
    ws.clientIP = clientIP;
    ws.clientPort = clientPort;
    
    // Track pongs for liveness
    ws.on("pong", heartbeat);
    
    // Track messages for activity
    const originalOnMessage = ws.onmessage;
    ws.onmessage = function(event) {
      ws.lastActivity = Date.now();
      if (originalOnMessage) {
        originalOnMessage.call(this, event);
      }
    };
    
    // Add error handler with detailed logging
    ws.on("error", function(error) {
      console.log(`WebSocket error from ${ws.clientIP}:${ws.clientPort}: ${error.message}`);
      console.log(`Connection was alive for ${Math.round((Date.now() - ws.connectionTime)/1000)} seconds`);
    });
    
    // Add close handler with reconnection logic for dbwrite
    ws.on("close", function(code, reason) {
      const duration = Math.round((Date.now() - ws.connectionTime)/1000);
      console.log(`WebSocket closed from ${ws.clientIP}:${ws.clientPort} with code ${code}, reason: ${reason || 'No reason provided'}`);
      console.log(`Connection was alive for ${duration} seconds`);
      
      // Check if this might be the dbwrite service
      if (duration < 60) { // If connection lasted less than a minute
        console.log("Short-lived connection detected, possibly dbwrite service. Consider increasing timeouts in Chronicle configuration.");
      }
    });
    
    // Message queue with controlled processing
    ws.messageQueue = [];
    ws.processingMessages = false;
    
    // Override send method to implement flow control
    const originalSend = ws.send;
    ws.send = function(data, options, callback) {
      // Update activity timestamp
      ws.lastActivity = Date.now();
      
      // Add to queue instead of sending immediately
      ws.messageQueue.push({
        data: data,
        options: options,
        callback: callback
      });
      
      // Start processing if not already in progress
      if (!ws.processingMessages) {
        processQueue(ws, originalSend);
      }
      
      // Apply backpressure if queue gets too large
      if (ws.messageQueue.length > MAX_QUEUE_SIZE) {
        console.warn(`WebSocket queue size exceeded limit (${MAX_QUEUE_SIZE}) for ${ws.clientIP}:${ws.clientPort}, applying backpressure`);
        return false; // Signal backpressure to caller
      }
      
      return true;
    };
    
    // Function to process the message queue with controlled pacing
    function processQueue(ws, sendFn) {
      ws.processingMessages = true;
      
      function processNextBatch() {
        // Check if connection is still open
        if (ws.readyState !== 1) { // 1 = OPEN
          ws.processingMessages = false;
          console.log(`Stopping message processing for closed connection ${ws.clientIP}:${ws.clientPort}`);
          return;
        }
        
        // Process a batch of messages
        const batchSize = Math.min(BATCH_SIZE, ws.messageQueue.length);
        if (batchSize === 0) {
          ws.processingMessages = false;
          return;
        }
        
        // Only log if significant queue
        if (ws.messageQueue.length > BATCH_SIZE) {
          console.log(`Processing batch of ${batchSize} messages for ${ws.clientIP}:${ws.clientPort}, ${ws.messageQueue.length} remaining`);
        }
        
        // Process the batch
        let successCount = 0;
        for (let i = 0; i < batchSize; i++) {
          if (ws.messageQueue.length === 0) break;
          
          const msg = ws.messageQueue.shift();
          try {
            sendFn.call(ws, msg.data, msg.options, function() {
              successCount++;
              if (msg.callback) msg.callback.apply(this, arguments);
            });
          } catch (err) {
            console.error(`Error sending message to ${ws.clientIP}:${ws.clientPort}:`, err);
            // Put message back in queue for retry if connection still open
            if (ws.readyState === 1) {
              ws.messageQueue.unshift(msg);
            }
          }
        }
        
        // Adaptive delay - slow down if errors occurred
        const currentDelay = (successCount < batchSize) ? PROCESSING_DELAY * 2 : PROCESSING_DELAY;
        
        // Schedule next batch with a delay
        setTimeout(processNextBatch, currentDelay);
      }
      
      processNextBatch();
    }

    // Add to your WebSocket connection handler
    let lastBlockNum = 0;
    ws.on("message", function(data) {
      try {
        const message = JSON.parse(data);
        if (message && message.this_block && message.this_block.block_num) {
          const blockNum = message.this_block.block_num;
          
          // Check for large block jumps (more than 1000 blocks)
          if (lastBlockNum > 0 && blockNum - lastBlockNum > 1000) {
            console.warn(`Large block jump detected: ${lastBlockNum} to ${blockNum} (gap of ${blockNum - lastBlockNum} blocks)`);
          }
          
          lastBlockNum = blockNum;
        }
      } catch (e) {
        // Not a JSON message or doesn't have block info
      }
    });
  });
  
  // Set up the ping interval for connection liveness with more detailed monitoring
  const interval = setInterval(function ping() {
    const now = Date.now();
    
    rpc.wss.clients.forEach(function each(ws) {
      // Check for inactive connections
      const inactiveTime = now - ws.lastActivity;
      
      // Terminate if no response to ping
      if (ws.isAlive === false) {
        console.log(`Terminating unresponsive client ${ws.clientIP}:${ws.clientPort}, no pong received`);
        return ws.terminate();
      }
      
      // Terminate if inactive for too long
      if (inactiveTime > CONNECTION_TIMEOUT) {
        console.log(`Terminating inactive client ${ws.clientIP}:${ws.clientPort}, inactive for ${Math.round(inactiveTime/1000)} seconds`);
        return ws.terminate();
      }
      
      // Mark as not alive, will be reset when pong is received
      ws.isAlive = false;
      
      // Send ping
      try {
        ws.ping(() => {});
      } catch (err) {
        console.error(`Error sending ping to ${ws.clientIP}:${ws.clientPort}:`, err);
      }
      
      // Log queue status for monitoring if significant
      if (ws.messageQueue && ws.messageQueue.length > 0) {
        console.log(`Client ${ws.clientIP}:${ws.clientPort} has ${ws.messageQueue.length} messages queued, connected for ${Math.round((now - ws.connectionTime)/1000)} seconds`);
      }
    });
  }, KEEPALIVE_INTERVAL);
  
  rpc.wss.on("close", function close() {
    clearInterval(interval);
  });
}

// Initialize the WebSocket connection management
setupWebSocketConnection();

// Add performance monitoring
setInterval(function() {
  const memoryUsage = process.memoryUsage();
  console.log(`Memory usage: RSS=${Math.round(memoryUsage.rss / 1024 / 1024)}MB, Heap=${Math.round(memoryUsage.heapUsed / 1024 / 1024)}/${Math.round(memoryUsage.heapTotal / 1024 / 1024)}MB`);
  
  // Log client count and queue sizes
  let totalClients = 0;
  let totalQueueSize = 0;
  let longRunningClients = 0;
  
  rpc.wss.clients.forEach(function(ws) {
    totalClients++;
    if (ws.messageQueue) {
      totalQueueSize += ws.messageQueue.length;
    }
    
    // Track long-running connections (over 5 minutes)
    if (ws.connectionTime && (Date.now() - ws.connectionTime > 300000)) {
      longRunningClients++;
    }
  });
  
  console.log(`WebSocket clients: ${totalClients} (${longRunningClients} long-running), Total queue size: ${totalQueueSize}`);
}, 60000);

// End of patch 