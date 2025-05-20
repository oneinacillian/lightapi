# Enhanced LightAPI & Chronicle Configuration

This repository contains an optimized and enhanced configuration for running LightAPI and Chronicle services, specifically tuned for high-performance WAX blockchain data processing.

## 🌟 Key Features

### LightAPI Enhancements

#### WebSocket Optimizations
- Advanced flow control with configurable queue sizes and processing delays
- Intelligent connection management with heartbeat monitoring
- Automatic reconnection handling for improved reliability
- Performance monitoring and logging capabilities
- Adaptive message batching for optimal throughput

#### Database Optimizations
- Optimized MariaDB configuration for 128GB systems
- Buffer pool size set to 64GB for maximum performance
- Enhanced I/O thread configuration
- Optimized temporary table settings
- Improved query performance with disabled query cache

#### Resource Management
- Configurable memory limits (up to 96GB)
- CPU allocation management (8-16 cores)
- Optimized file descriptor limits
- Enhanced system resource utilization

### Chronicle Configuration

#### Reliability Features
- Automatic snapshot restoration
- Intelligent process monitoring
- Graceful shutdown handling
- Connection health checking
- Automatic restart on failures

#### Performance Tuning
- Optimized queue sizes and acknowledgment settings
- Configurable block processing parameters
- Table blacklisting for improved efficiency
- Stale transaction handling
- Customizable reporting intervals

## 🚀 Architecture

The setup consists of two main services:

### LightAPI Service
- Runs multiple WebSocket API servers (ports 5101-5105)
- Main API service on port 5001
- Database write service on port 8100
- MariaDB database for data storage

### Chronicle Service
- Connects to WAX blockchain nodes
- Processes and filters blockchain data
- Streams data to LightAPI via WebSocket
- Supports snapshot restoration

## 💻 System Requirements

- Minimum 128GB RAM recommended
- 16+ CPU cores
- High-performance storage system
- Ubuntu 22.04 LTS

## 🔧 Configuration Files

### LightAPI
- `docker-compose.yml`: Service orchestration
- `mariadb.cnf`: Database optimization settings
- `wsapi_patch.js`: WebSocket enhancements
- `setup-db.sh`: Database initialization and monitoring

### Chronicle
- `config.ini`: Chronicle service configuration
- `start-chronicle.sh`: Process management and monitoring
- `Dockerfile`: Service containerization

## 📊 Monitoring & Maintenance

The setup includes comprehensive monitoring:
- Memory usage logging every 5 minutes
- WebSocket connection statistics
- Database performance metrics
- Process health monitoring
- Automatic service recovery

## 🔐 Security Features

- Separate read-only database user
- Configurable connection timeouts
- Process isolation
- Resource limits enforcement

## 🚦 Health Checks

Both services implement health checks:
- LightAPI service monitoring
- Chronicle process monitoring
- Database connection verification
- WebSocket connection health checks

## 📈 Performance Optimizations

### Database
- Optimized InnoDB buffer pool configuration
- Enhanced I/O thread settings
- Temporary table optimizations
- Network timeout configurations

### WebSocket
- Message queue management
- Connection pooling
- Adaptive batch processing
- Backpressure handling

### System
- Resource allocation management
- Process monitoring and recovery
- Automatic service restoration
- Performance logging and analysis

## 🛠 Usage

1. Clone this repository
2. Configure environment variables if needed
3. Run with Docker Compose:
   ```bash
   docker-compose up -d
   ```

## 📝 Notes

- The configuration is optimized for WAX blockchain
- Supports automatic snapshot restoration
- Includes comprehensive error handling
- Provides detailed logging and monitoring

## ⚠️ Important Considerations

- Monitor system resources regularly
- Check logs for performance issues
- Adjust memory settings based on system capacity
- Maintain regular backups
- Monitor disk space usage

## 🔄 Restore Process (Beta)

> ⚠️ **Important Note**: The restore functionality is currently in beta. While the basic synchronization with a clean database works reliably, full database restoration is still being optimized to address synchronization issues.

### Current Status
- ✅ Clean database synchronization works perfectly
- ⚠️ Full database restore needs additional testing and optimization
- 🔄 Active development to improve restoration reliability

### Restore Prerequisites
Place the following files in the `./backups/` directory:
- `lightapi_backup.sql`: Database backup file
- `wax.snapshot`: Chronicle snapshot file

### Running a Restore
1. Place backup files in the `./backups/` directory
2. Execute the restore script:
   ```bash
   ./restore.sh
   ```

The restore process:
1. Stops all running containers
2. Configures MariaDB for optimal restore performance
3. Restores the database and snapshot
4. Resets database configuration for normal operation

### Restore Optimizations
The restore process includes several performance optimizations:
- Temporary disabling of doublewrite buffer
- Optimized I/O capacity settings
- Modified buffer pool configuration
- Adjusted flush log settings

### Known Limitations
- Synchronization issues may occur with full database restores
- Recommended to start with a clean database for most reliable operation
- Snapshot restoration is more reliable than full database restore

We are actively working on improving the restore process. For now, if you experience issues with a full restore, we recommend starting with a clean database and letting it sync naturally.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
