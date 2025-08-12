#!/bin/bash

#===============================================================================
# AppDynamics Machine Agent Management Script
# Description: Upgrade, remove, or manage AppDynamics Machine Agent
# Version: 1.0
# Author: System Administrator
# Last Updated: $(date +%Y-%m-%d)
#===============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

#===============================================================================
# Global Configuration
#===============================================================================

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="/var/log/appdynamics-management.log"
readonly BACKUP_BASE_DIR="/opt/appdynamics/backups"
readonly BACKUP_DIR="${BACKUP_BASE_DIR}/$(date +%Y%m%d_%H%M%S)"

# Environment settings
readonly HOSTNAME="${HOSTNAME:-$(hostname)}"
readonly SHORT_HOSTNAME="${HOSTNAME%%.*}"
readonly CURRENT_USER="$(whoami)"
readonly REQUIRED_USER="root"
readonly BASE_INSTALL_DIR="/tmp"
readonly APPDYNAMICS_HOME="/opt/appdynamics"
readonly MACHINE_AGENT_DIR="${APPDYNAMICS_HOME}/machine-agent"

# Service configuration
readonly SERVICE_NAME="appdynamics-machine-agent"
readonly SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# Script modes
readonly MODE_UPGRADE="upgrade"
readonly MODE_REMOVE="remove"
readonly MODE_STATUS="status"
readonly MODE_BACKUP="backup"
readonly MODE_RESTORE="restore"
readonly MODE_RESTART="restart"

#===============================================================================
# Logging Functions
#===============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

print_banner() {
    local message="$1"
    echo ""
    echo "==============================================================================="
    echo "  $message"
    echo "==============================================================================="
    echo ""
}

print_usage() {
    cat << EOF
Usage: $SCRIPT_NAME [COMMAND] [OPTIONS]

COMMANDS:
    upgrade [package]    Upgrade the AppDynamics Machine Agent
                        - package: path to new agent package (optional, will search /tmp)
    
    remove              Completely remove the AppDynamics Machine Agent
                        --force: skip confirmation prompts
                        --keep-config: preserve configuration files
    
    status              Show current agent status and version information
    
    backup              Create a backup of the current installation
    
    restore [backup]    Restore from a backup
                        - backup: specific backup directory (optional, will list available)
    
    restart             Restart the AppDynamics Machine Agent service
    
    --help, -h          Show this help message

EXAMPLES:
    $SCRIPT_NAME status
    $SCRIPT_NAME upgrade
    $SCRIPT_NAME upgrade /path/to/new-agent.zip
    $SCRIPT_NAME remove --force
    $SCRIPT_NAME backup
    $SCRIPT_NAME restore
    $SCRIPT_NAME restart

EOF
}

#===============================================================================
# Validation Functions
#===============================================================================

validate_user() {
    if [[ "$CURRENT_USER" != "$REQUIRED_USER" ]]; then
        log_error "This script must be run as $REQUIRED_USER user"
        log_error "Current user: $CURRENT_USER"
        log_error "Please run: sudo $0"
        exit 1
    fi
}

validate_installation() {
    if [[ ! -d "$MACHINE_AGENT_DIR" ]]; then
        log_error "AppDynamics Machine Agent is not installed"
        log_error "Installation directory not found: $MACHINE_AGENT_DIR"
        exit 1
    fi
}

validate_service_exists() {
    if ! systemctl list-unit-files | grep -q "$SERVICE_NAME"; then
        log_error "AppDynamics Machine Agent service not found"
        exit 1
    fi
}

#===============================================================================
# Service Management Functions
#===============================================================================

get_service_status() {
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        echo "running"
    elif systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        echo "stopped"
    else
        echo "disabled"
    fi
}

stop_service() {
    local force=${1:-false}
    
    log_info "Stopping AppDynamics Machine Agent service..."
    
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        if [[ "$force" == "true" ]]; then
            systemctl stop "$SERVICE_NAME" || {
                log_warn "Graceful stop failed, forcing termination..."
                systemctl kill "$SERVICE_NAME" 2>/dev/null || true
                sleep 2
            }
        else
            systemctl stop "$SERVICE_NAME"
        fi
        log_info "Service stopped successfully"
    else
        log_info "Service is not running"
    fi
}

start_service() {
    log_info "Starting AppDynamics Machine Agent service..."
    
    systemctl daemon-reload
    
    if ! systemctl start "$SERVICE_NAME"; then
        log_error "Failed to start service"
        log_error "Check logs: journalctl -u $SERVICE_NAME -n 50"
        return 1
    fi
    
    # Wait and verify
    sleep 5
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_info "Service started successfully"
        return 0
    else
        log_error "Service failed to start properly"
        return 1
    fi
}

restart_service() {
    log_info "Restarting AppDynamics Machine Agent service..."
    stop_service
    start_service
}

#===============================================================================
# Backup and Restore Functions
#===============================================================================

create_backup() {
    local backup_name="${1:-$(date +%Y%m%d_%H%M%S)}"
    local target_dir="${BACKUP_BASE_DIR}/${backup_name}"
    
    log_info "Creating backup: $backup_name"
    
    mkdir -p "$target_dir"
    
    # Backup installation directory
    if [[ -d "$MACHINE_AGENT_DIR" ]]; then
        cp -r "$MACHINE_AGENT_DIR" "$target_dir/"
        log_info "Installation directory backed up"
    fi
    
    # Backup service file
    if [[ -f "$SERVICE_FILE" ]]; then
        cp "$SERVICE_FILE" "$target_dir/"
        log_info "Service file backed up"
    fi
    
    # Create backup metadata
    cat > "$target_dir/backup_info.txt" << EOF
Backup Created: $(date)
Hostname: $HOSTNAME
Agent Version: $(get_agent_version 2>/dev/null || echo "Unknown")
Service Status: $(get_service_status)
Backup Type: Manual
EOF
    
    log_info "Backup completed: $target_dir"
    echo "$target_dir"
}

list_backups() {
    if [[ ! -d "$BACKUP_BASE_DIR" ]]; then
        echo "No backups found"
        return
    fi
    
    echo "Available backups:"
    echo "=================="
    
    for backup_dir in "$BACKUP_BASE_DIR"/*; do
        if [[ -d "$backup_dir" ]]; then
            local backup_name="$(basename "$backup_dir")"
            local backup_info=""
            
            if [[ -f "$backup_dir/backup_info.txt" ]]; then
                backup_info=$(grep "Backup Created:" "$backup_dir/backup_info.txt" | cut -d: -f2- | xargs)
            fi
            
            printf "  %-20s %s\n" "$backup_name" "$backup_info"
        fi
    done
}

restore_from_backup() {
    local backup_name="$1"
    local backup_dir="${BACKUP_BASE_DIR}/${backup_name}"
    
    if [[ ! -d "$backup_dir" ]]; then
        log_error "Backup not found: $backup_dir"
        return 1
    fi
    
    log_info "Restoring from backup: $backup_name"
    
    # Stop service first
    stop_service true
    
    # Create current backup before restore
    local pre_restore_backup
    pre_restore_backup=$(create_backup "pre_restore_$(date +%H%M%S)")
    log_info "Created pre-restore backup: $pre_restore_backup"
    
    # Restore installation directory
    if [[ -d "$backup_dir/machine-agent" ]]; then
        rm -rf "$MACHINE_AGENT_DIR"
        cp -r "$backup_dir/machine-agent" "$MACHINE_AGENT_DIR"
        chown -R "$REQUIRED_USER:$REQUIRED_USER" "$MACHINE_AGENT_DIR"
        chmod -R 755 "$MACHINE_AGENT_DIR"
        log_info "Installation directory restored"
    fi
    
    # Restore service file
    if [[ -f "$backup_dir/${SERVICE_NAME}.service" ]]; then
        cp "$backup_dir/${SERVICE_NAME}.service" "$SERVICE_FILE"
        log_info "Service file restored"
    fi
    
    # Restart service
    systemctl daemon-reload
    
    if start_service; then
        log_info "Restore completed successfully"
    else
        log_warn "Restore completed but service failed to start"
    fi
}

#===============================================================================
# Information Functions
#===============================================================================

get_agent_version() {
    local version_file="${MACHINE_AGENT_DIR}/VERSION"
    local jar_file="${MACHINE_AGENT_DIR}/machineagent.jar"
    
    if [[ -f "$version_file" ]]; then
        cat "$version_file"
    elif [[ -f "$jar_file" ]]; then
        # Try to extract version from JAR manifest
        unzip -p "$jar_file" META-INF/MANIFEST.MF 2>/dev/null | grep -i "Implementation-Version" | cut -d: -f2 | xargs || echo "Unknown"
    else
        echo "Unknown"
    fi
}

show_status() {
    print_banner "AppDynamics Machine Agent Status"
    
    echo "Installation Status:"
    if [[ -d "$MACHINE_AGENT_DIR" ]]; then
        echo "  ✓ Agent installed at: $MACHINE_AGENT_DIR"
        echo "  ✓ Agent version: $(get_agent_version)"
    else
        echo "  ✗ Agent not installed"
        return
    fi
    
    echo ""
    echo "Service Status:"
    local status=$(get_service_status)
    case "$status" in
        "running")
            echo "  ✓ Service is running"
            echo "  ✓ Service is enabled"
            ;;
        "stopped")
            echo "  ✗ Service is stopped"
            echo "  ✓ Service is enabled"
            ;;
        "disabled")
            echo "  ✗ Service is disabled"
            ;;
    esac
    
    echo ""
    echo "Configuration:"
    local config_file="${MACHINE_AGENT_DIR}/conf/controller-info.xml"
    if [[ -f "$config_file" ]]; then
        echo "  ✓ Configuration file: $config_file"
        
        # Extract key configuration values
        local controller_host=$(grep -o '<controller-host>[^<]*' "$config_file" | cut -d'>' -f2 || echo "Not configured")
        local app_name=$(grep -o '<application-name>[^<]*' "$config_file" | cut -d'>' -f2 || echo "Not configured")
        local tier_name=$(grep -o '<tier-name>[^<]*' "$config_file" | cut -d'>' -f2 || echo "Not configured")
        
        echo "  - Controller: $controller_host"
        echo "  - Application: $app_name"
        echo "  - Tier: $tier_name"
    else
        echo "  ✗ Configuration file not found"
    fi
    
    echo ""
    echo "Recent Logs:"
    if command -v journalctl &> /dev/null; then
        journalctl -u "$SERVICE_NAME" -n 5 --no-pager 2>/dev/null || echo "  No recent logs available"
    fi
    
    echo ""
    echo "Available Backups:"
    list_backups
}

#===============================================================================
# Upgrade Functions
#===============================================================================

find_upgrade_package() {
    local specified_path="$1"
    
    if [[ -n "$specified_path" ]]; then
        if [[ -f "$specified_path" ]]; then
            echo "$specified_path"
            return
        else
            log_error "Specified package not found: $specified_path"
            exit 1
        fi
    fi
    
    # Search for packages in common locations
    local package_file
    package_file=$(find "$BASE_INSTALL_DIR" -name "machineagent-bundle*" -type f | head -1)
    
    if [[ -z "$package_file" ]]; then
        log_error "No upgrade package found in $BASE_INSTALL_DIR"
        log_error "Please specify the package path or place it in $BASE_INSTALL_DIR"
        exit 1
    fi
    
    echo "$package_file"
}

perform_upgrade() {
    local package_path="$1"
    
    print_banner "Upgrading AppDynamics Machine Agent"
    
    # Validate current installation
    validate_installation
    
    # Find upgrade package
    local upgrade_package
    upgrade_package=$(find_upgrade_package "$package_path")
    log_info "Using upgrade package: $upgrade_package"
    
    # Get current version for comparison
    local current_version
    current_version=$(get_agent_version)
    log_info "Current version: $current_version"
    
    # Create pre-upgrade backup
    local backup_dir
    backup_dir=$(create_backup "pre_upgrade_$(date +%H%M%S)")
    log_info "Pre-upgrade backup created: $backup_dir"
    
    # Stop the service
    stop_service
    
    # Extract new agent to temporary location
    local temp_dir="/tmp/appdynamics-upgrade-$$"
    local temp_zip="${temp_dir}/machine-agent.zip"
    
    mkdir -p "$temp_dir"
    cp "$upgrade_package" "$temp_zip"
    
    log_info "Extracting new agent version..."
    if ! unzip -q "$temp_zip" -d "$temp_dir"; then
        log_error "Failed to extract upgrade package"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    # Find the extracted agent directory
    local extracted_dir
    extracted_dir=$(find "$temp_dir" -maxdepth 2 -name "bin" -type d | head -1 | xargs dirname)
    
    if [[ -z "$extracted_dir" || ! -d "$extracted_dir" ]]; then
        log_error "Could not find valid agent structure in upgrade package"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    # Preserve current configuration
    local config_backup="${temp_dir}/controller-info.xml.backup"
    if [[ -f "${MACHINE_AGENT_DIR}/conf/controller-info.xml" ]]; then
        cp "${MACHINE_AGENT_DIR}/conf/controller-info.xml" "$config_backup"
        log_info "Current configuration backed up"
    fi
    
    # Replace agent files (preserve conf directory)
    log_info "Installing new agent files..."
    
    # Remove old agent files but preserve conf
    find "$MACHINE_AGENT_DIR" -mindepth 1 -not -path "*/conf/*" -delete 2>/dev/null || true
    
    # Copy new agent files
    cp -r "$extracted_dir"/* "$MACHINE_AGENT_DIR"/
    
    # Restore configuration if it was backed up
    if [[ -f "$config_backup" ]]; then
        cp "$config_backup" "${MACHINE_AGENT_DIR}/conf/controller-info.xml"
        log_info "Configuration restored"
    fi
    
    # Set proper permissions
    chown -R "$REQUIRED_USER:$REQUIRED_USER" "$MACHINE_AGENT_DIR"
    chmod -R 755 "$MACHINE_AGENT_DIR"
    
    # Update service file if needed
    local new_service_file="${MACHINE_AGENT_DIR}/etc/systemd/system/${SERVICE_NAME}.service"
    if [[ -f "$new_service_file" ]]; then
        # Configure service file for root user
        sed -i "s/User=appdynamics-machine-agent/User=$REQUIRED_USER/" "$new_service_file"
        sed -i "s/Environment=MACHINE_AGENT_USER=appdynamics-machine-agent/Environment=MACHINE_AGENT_USER=$REQUIRED_USER/" "$new_service_file"
        
        cp "$new_service_file" "$SERVICE_FILE"
        log_info "Service file updated"
    fi
    
    # Clean up temporary files
    rm -rf "$temp_dir"
    
    # Start the service
    if start_service; then
        local new_version
        new_version=$(get_agent_version)
        log_info "Upgrade completed successfully"
        log_info "Previous version: $current_version"
        log_info "New version: $new_version"
        
        echo ""
        echo "Upgrade Summary:"
        echo "==============="
        echo "Previous version: $current_version"
        echo "New version: $new_version"
        echo "Backup location: $backup_dir"
        echo "Service status: $(get_service_status)"
    else
        log_error "Upgrade completed but service failed to start"
        log_error "You may need to restore from backup: $backup_dir"
        exit 1
    fi
}

#===============================================================================
# Removal Functions
#===============================================================================

confirm_removal() {
    local force="$1"
    
    if [[ "$force" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo "WARNING: This will completely remove the AppDynamics Machine Agent!"
    echo "This action cannot be undone unless you have backups."
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " -r response
    
    case "$response" in
        [Yy][Ee][Ss]|[Yy])
            return 0
            ;;
        *)
            echo "Removal cancelled."
            exit 0
            ;;
    esac
}

perform_removal() {
    local force="$1"
    local keep_config="$2"
    
    print_banner "Removing AppDynamics Machine Agent"
    
    # Validate installation exists
    if [[ ! -d "$MACHINE_AGENT_DIR" ]] && [[ ! -f "$SERVICE_FILE" ]]; then
        log_info "AppDynamics Machine Agent is not installed"
        return 0
    fi
    
    # Confirm removal
    confirm_removal "$force"
    
    # Create final backup
    local final_backup=""
    if [[ -d "$MACHINE_AGENT_DIR" ]]; then
        final_backup=$(create_backup "final_backup_$(date +%H%M%S)")
        log_info "Final backup created: $final_backup"
    fi
    
    # Stop and disable service
    log_info "Stopping and disabling service..."
    stop_service true
    
    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        systemctl disable "$SERVICE_NAME"
        log_info "Service disabled"
    fi
    
    # Remove service file
    if [[ -f "$SERVICE_FILE" ]]; then
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
        log_info "Service file removed"
    fi
    
    # Remove installation directory
    if [[ -d "$MACHINE_AGENT_DIR" ]]; then
        if [[ "$keep_config" == "true" ]]; then
            # Keep only configuration
            local config_backup_dir="${APPDYNAMICS_HOME}/config-backup-$(date +%Y%m%d_%H%M%S)"
            mkdir -p "$config_backup_dir"
            
            if [[ -d "${MACHINE_AGENT_DIR}/conf" ]]; then
                cp -r "${MACHINE_AGENT_DIR}/conf" "$config_backup_dir/"
                log_info "Configuration preserved at: $config_backup_dir"
            fi
        fi
        
        rm -rf "$MACHINE_AGENT_DIR"
        log_info "Installation directory removed"
    fi
    
    # Remove parent directory if empty
    if [[ -d "$APPDYNAMICS_HOME" ]] && [[ -z "$(ls -A "$APPDYNAMICS_HOME" 2>/dev/null)" ]]; then
        rmdir "$APPDYNAMICS_HOME"
        log_info "Empty AppDynamics directory removed"
    fi
    
    log_info "AppDynamics Machine Agent removal completed"
    
    if [[ -n "$final_backup" ]]; then
        echo ""
        echo "Removal completed successfully!"
        echo "Final backup available at: $final_backup"
        if [[ "$keep_config" == "true" ]]; then
            echo "Configuration preserved separately"
        fi
    fi
}

#===============================================================================
# Main Function
#===============================================================================

main() {
    local command="${1:-}"
    local force=false
    local keep_config=false
    
    # Initialize logging
    mkdir -p "$(dirname "$LOG_FILE")"
    log_info "Starting AppDynamics Management Script"
    log_info "Command: $command"
    log_info "User: $CURRENT_USER"
    
    # Parse command line arguments
    case "$command" in
        "upgrade")
            validate_user
            shift
            local package_path="${1:-}"
            perform_upgrade "$package_path"
            ;;
            
        "remove")
            validate_user
            shift
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --force)
                        force=true
                        shift
                        ;;
                    --keep-config)
                        keep_config=true
                        shift
                        ;;
                    *)
                        log_error "Unknown option: $1"
                        exit 1
                        ;;
                esac
            done
            perform_removal "$force" "$keep_config"
            ;;
            
        "status")
            show_status
            ;;
            
        "backup")
            validate_user
            validate_installation
            backup_dir=$(create_backup)
            echo "Backup created: $backup_dir"
            ;;
            
        "restore")
            validate_user
            shift
            local backup_name="${1:-}"
            
            if [[ -z "$backup_name" ]]; then
                echo ""
                list_backups
                echo ""
                read -p "Enter backup name to restore: " -r backup_name
            fi
            
            if [[ -n "$backup_name" ]]; then
                restore_from_backup "$backup_name"
            else
                log_error "No backup specified"
                exit 1
            fi
            ;;
            
        "restart")
            validate_user
            validate_installation
            validate_service_exists
            restart_service
            ;;
            
        "--help"|"-h"|"help"|"")
            print_usage
            exit 0
            ;;
            
        *)
            log_error "Unknown command: $command"
            print_usage
            exit 1
            ;;
    esac
}

#===============================================================================
# Error Handling
#===============================================================================

cleanup_on_error() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Operation failed with exit code: $exit_code"
        log_error "Check the log file for details: $LOG_FILE"
    fi
}

trap cleanup_on_error EXIT

#===============================================================================
# Script Execution
#===============================================================================

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi