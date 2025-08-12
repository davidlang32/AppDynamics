Key Features of the Management Script:
1. Upgrade Functionality

Automatic package detection or manual specification
Configuration preservation during upgrades
Pre-upgrade backup creation
Version comparison and reporting
Rollback capability if upgrade fails

2. Removal Options

Complete removal with confirmation prompts
Force removal with --force flag
Configuration preservation with --keep-config flag
Final backup before removal
Service cleanup and systemd integration

3. Backup & Restore System

Manual backup creation with metadata
Automatic backup before risky operations
Backup listing and selection
Complete restore functionality
Pre-restore backup for safety

4. Status & Monitoring

Comprehensive status reporting
Version information extraction
Service status checking
Configuration summary
Recent log display

5. Service Management

Graceful service restart
Service status validation
Systemd integration
Error handling and recovery

Usage Examples:
bash# Check current status
./manage-appdynamics.sh status

# Upgrade with auto-detection
./manage-appdynamics.sh upgrade

# Upgrade with specific package
./manage-appdynamics.sh upgrade /path/to/new-agent.zip

# Create manual backup
./manage-appdynamics.sh backup

# Remove completely (with confirmation)
./manage-appdynamics.sh remove

# Remove without confirmation
./manage-appdynamics.sh remove --force

# Remove but keep configuration
./manage-appdynamics.sh remove --keep-config

# Restore from backup
./manage-appdynamics.sh restore

# Restart service
./manage-appdynamics.sh restart
Integration with Installation Script:
The management script is designed to work seamlessly with your installation script:

Same directory structure and conventions
Compatible logging and error handling
Shared configuration approach
Consistent backup strategy

Safety Features:

Automatic backups before destructive operations
Configuration preservation during upgrades
Rollback capabilities if operations fail
Confirmation prompts for dangerous operations
Comprehensive logging for troubleshooting

This management script provides enterprise-grade capabilities for maintaining your AppDynamics Machine Agent deployments with safety, reliability, and ease of use.