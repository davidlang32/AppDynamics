#!/bin/bash

#===============================================================================
# AppDynamics Machine Agent Installation Script
# Description: Automated installation and configuration of AppDynamics Machine Agent
# Version: 2.0
# Author: David Lang
# Last Updated: 6/5/2025
#===============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

#===============================================================================
# Global Configuration
#===============================================================================

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="/var/log/appdynamics-install.log"
readonly BACKUP_DIR="/opt/appdynamics/backups/$(date +%Y%m%d_%H%M%S)"

# Environment settings
readonly HOSTNAME="${HOSTNAME:-$(hostname)}"
readonly SHORT_HOSTNAME="${HOSTNAME%%.*}"
readonly CURRENT_USER="$(whoami)"
readonly REQUIRED_USER="root"
readonly BASE_INSTALL_DIR="/tmp"
readonly APPDYNAMICS_HOME="/opt/appdynamics"
readonly MACHINE_AGENT_DIR="${APPDYNAMICS_HOME}/machine-agent"

# Application configuration (customize these values)
readonly APPLICATION_NAME="${APPDYNAMICS_APP_NAME:-Application}"
readonly TIER_NAME="${APPDYNAMICS_TIER_NAME:-App}"
readonly NODE_NAME="${APPDYNAMICS_NODE_NAME:-${HOSTNAME}}"

# Controller configuration (set via environment variables or modify here)
readonly CONTROLLER_HOST="${APPDYNAMICS_CONTROLLER_HOST:-}"
readonly CONTROLLER_PORT="${APPDYNAMICS_CONTROLLER_PORT:-443}"
readonly CONTROLLER_SSL="${APPDYNAMICS_CONTROLLER_SSL:-true}"
readonly ENABLE_ORCHESTRATION="${APPDYNAMICS_ORCHESTRATION:-false}"
readonly UNIQUE_HOST_ID="${APPDYNAMICS_UNIQUE_HOST_ID:-${SHORT_HOSTNAME}}"
readonly ACCOUNT_ACCESS_KEY="${APPDYNAMICS_ACCESS_KEY:-}"
readonly ACCOUNT_NAME="${APPDYNAMICS_ACCOUNT_NAME:-}"
readonly SIM_ENABLED="${APPDYNAMICS_SIM_ENABLED:-true}"
readonly IS_SAP_MACHINE="${APPDYNAMICS_SAP_MACHINE:-}"
readonly MACHINE_PATH="${APPDYNAMICS_MACHINE_PATH:-}"

# Service configuration
readonly SERVICE_NAME="appdynamics-machine-agent"
readonly SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

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

#===============================================================================
# Validation Functions
#===============================================================================

validate_user() {
    log_info "Validating user permissions..."
    if [[ "$CURRENT_USER" != "$REQUIRED_USER" ]]; then
        log_error "This script must be run as $REQUIRED_USER user"
        log_error "Current user: $CURRENT_USER"
        log_error "Please run: sudo $0"
        exit 1
    fi
    log_info "User validation passed"
}

validate_required_vars() {
    log_info "Validating required configuration variables..."
    local missing_vars=()
    
    [[ -z "$CONTROLLER_HOST" ]] && missing_vars+=("CONTROLLER_HOST")
    [[ -z "$ACCOUNT_ACCESS_KEY" ]] && missing_vars+=("ACCOUNT_ACCESS_KEY")
    [[ -z "$ACCOUNT_NAME" ]] && missing_vars+=("ACCOUNT_NAME")
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required configuration variables:"
        printf '%s\n' "${missing_vars[@]}" | sed 's/^/  - /'
        log_error "Set these as environment variables or modify the script"
        exit 1
    fi
    log_info "Configuration validation passed"
}

validate_system() {
    log_info "Validating system requirements..."
    
    # Check if systemd is available
    if ! command -v systemctl &> /dev/null; then
        log_error "systemctl not found. This script requires systemd."
        exit 1
    fi
    
    # Check if unzip is available
    if ! command -v unzip &> /dev/null; then
        log_error "unzip not found. Please install unzip package."
        exit 1
    fi
    
    log_info "System validation passed"
}

find_agent_package() {
    log_info "Looking for AppDynamics Machine Agent package..."
    local package_file
    
    # Look for the agent package
    package_file=$(find "$BASE_INSTALL_DIR" -name "machineagent-bundle*" -type f | head -1)
    
    if [[ -z "$package_file" ]]; then
        log_error "AppDynamics Machine Agent package not found in $BASE_INSTALL_DIR"
        log_error "Please download and place the machineagent-bundle file in $BASE_INSTALL_DIR"
        exit 1
    fi
    
    log_info "Found agent package: $package_file"
    echo "$package_file"
}

#===============================================================================
# Installation Functions
#===============================================================================

create_backup() {
    if [[ -d "$MACHINE_AGENT_DIR" ]]; then
        log_info "Creating backup of existing installation..."
        mkdir -p "$BACKUP_DIR"
        cp -r "$MACHINE_AGENT_DIR" "$BACKUP_DIR/" 2>/dev/null || true
        log_info "Backup created at: $BACKUP_DIR"
    fi
}

stop_existing_agent() {
    log_info "Stopping existing AppDynamics Machine Agent service..."
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        systemctl stop "$SERVICE_NAME" || log_warn "Failed to stop service gracefully"
        sleep 3
    fi
    
    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        systemctl disable "$SERVICE_NAME" || log_warn "Failed to disable service"
    fi
}

remove_existing_installation() {
    if [[ -d "$MACHINE_AGENT_DIR" ]]; then
        log_info "Removing existing AppDynamics Machine Agent installation..."
        rm -rf "$MACHINE_AGENT_DIR"
    fi
}

create_directories() {
    log_info "Creating AppDynamics directory structure..."
    mkdir -p "$APPDYNAMICS_HOME"
    mkdir -p "$(dirname "$LOG_FILE")"
}

extract_agent() {
    local package_file="$1"
    local temp_zip="${BASE_INSTALL_DIR}/machine-agent.zip"
    
    log_info "Extracting AppDynamics Machine Agent..."
    
    # Copy and rename the package
    cp "$package_file" "$temp_zip"
    
    # Extract the agent
    if ! unzip -q "$temp_zip" -d "$MACHINE_AGENT_DIR"; then
        log_error "Failed to extract agent package"
        exit 1
    fi
    
    # Move contents up one level if they're in a subdirectory
    local subdir
    subdir=$(find "$MACHINE_AGENT_DIR" -maxdepth 1 -type d -name "machineagent*" | head -1)
    if [[ -n "$subdir" ]]; then
        mv "$subdir"/* "$MACHINE_AGENT_DIR"/ 2>/dev/null || true
        rmdir "$subdir" 2>/dev/null || true
    fi
    
    # Clean up
    rm -f "$temp_zip"
    
    log_info "Agent extraction completed"
}

configure_agent() {
    local config_file="${MACHINE_AGENT_DIR}/conf/controller-info.xml"
    
    log_info "Configuring AppDynamics Machine Agent..."
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        exit 1
    fi
    
    # Create backup of original config
    cp "$config_file" "${config_file}.backup"
    
    # Configure controller settings
    sed -i "s|<controller-host>.*</controller-host>|<controller-host>$CONTROLLER_HOST</controller-host>|" "$config_file"
    sed -i "s|<controller-port>.*</controller-port>|<controller-port>$CONTROLLER_PORT</controller-port>|" "$config_file"
    sed -i "s|<controller-ssl-enabled>.*</controller-ssl-enabled>|<controller-ssl-enabled>$CONTROLLER_SSL</controller-ssl-enabled>|" "$config_file"
    sed -i "s|<enable-orchestration>.*</enable-orchestration>|<enable-orchestration>$ENABLE_ORCHESTRATION</enable-orchestration>|" "$config_file"
    sed -i "s|<unique-host-id>.*</unique-host-id>|<unique-host-id>$UNIQUE_HOST_ID</unique-host-id>|" "$config_file"
    sed -i "s|<account-access-key>.*</account-access-key>|<account-access-key>$ACCOUNT_ACCESS_KEY</account-access-key>|" "$config_file"
    sed -i "s|<account-name>.*</account-name>|<account-name>$ACCOUNT_NAME</account-name>|" "$config_file"
    sed -i "s|<sim-enabled>.*</sim-enabled>|<sim-enabled>$SIM_ENABLED</sim-enabled>|" "$config_file"
    
    # Configure optional settings if provided
    [[ -n "$IS_SAP_MACHINE" ]] && sed -i "s|<is-sap-machine>.*</is-sap-machine>|<is-sap-machine>$IS_SAP_MACHINE</is-sap-machine>|" "$config_file"
    [[ -n "$MACHINE_PATH" ]] && sed -i "s|<machine-path>.*</machine-path>|<machine-path>$MACHINE_PATH</machine-path>|" "$config_file"
    
    # Add application hierarchy if not present
    if ! grep -q "<application-name>" "$config_file"; then
        sed -i "/<\/unique-host-id>/a\\    <application-name>$APPLICATION_NAME</application-name>" "$config_file"
    else
        sed -i "s|<application-name>.*</application-name>|<application-name>$APPLICATION_NAME</application-name>|" "$config_file"
    fi
    
    if ! grep -q "<tier-name>" "$config_file"; then
        sed -i "/<\/application-name>/a\\    <tier-name>$TIER_NAME</tier-name>" "$config_file"
    else
        sed -i "s|<tier-name>.*</tier-name>|<tier-name>$TIER_NAME</tier-name>|" "$config_file"
    fi
    
    if ! grep -q "<node-name>" "$config_file"; then
        sed -i "/<\/tier-name>/a\\    <node-name>$NODE_NAME</node-name>" "$config_file"
    else
        sed -i "s|<node-name>.*</node-name>|<node-name>$NODE_NAME</node-name>|" "$config_file"
    fi
    
    log_info "Agent configuration completed"
}

setup_service() {
    local original_service="${MACHINE_AGENT_DIR}/etc/systemd/system/${SERVICE_NAME}.service"
    
    log_info "Setting up systemd service..."
    
    if [[ ! -f "$original_service" ]]; then
        log_error "Service file not found: $original_service"
        exit 1
    fi
    
    # Set proper permissions
    chmod -R 755 "$MACHINE_AGENT_DIR"
    chown -R "$REQUIRED_USER:$REQUIRED_USER" "$MACHINE_AGENT_DIR"
    
    # Configure service file
    sed -i "s/User=appdynamics-machine-agent/User=$REQUIRED_USER/" "$original_service"
    sed -i "s/Environment=MACHINE_AGENT_USER=appdynamics-machine-agent/Environment=MACHINE_AGENT_USER=$REQUIRED_USER/" "$original_service"
    
    # Copy service file
    cp "$original_service" "$SERVICE_FILE"
    
    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    
    log_info "Service setup completed"
}

start_service() {
    log_info "Starting AppDynamics Machine Agent service..."
    
    if ! systemctl start "$SERVICE_NAME"; then
        log_error "Failed to start AppDynamics Machine Agent service"
        log_error "Check logs: journalctl -u $SERVICE_NAME"
        exit 1
    fi
    
    # Wait and verify service is running
    sleep 5
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_info "AppDynamics Machine Agent service started successfully"
    else
        log_error "AppDynamics Machine Agent service failed to start"
        log_error "Check logs: journalctl -u $SERVICE_NAME"
        exit 1
    fi
}

#===============================================================================
# Main Installation Process
#===============================================================================

main() {
    print_banner "AppDynamics Machine Agent Installation Starting"
    
    # Initialize logging
    mkdir -p "$(dirname "$LOG_FILE")"
    log_info "Starting AppDynamics Machine Agent installation"
    log_info "Script: $SCRIPT_NAME"
    log_info "User: $CURRENT_USER"
    log_info "Hostname: $HOSTNAME"
    
    # Validation phase
    validate_user
    validate_system
    validate_required_vars
    
    # Find agent package
    local package_file
    package_file=$(find_agent_package)
    
    # Installation phase
    print_banner "Stopping Existing Installation"
    stop_existing_agent
    create_backup
    remove_existing_installation
    
    print_banner "Installing AppDynamics Machine Agent"
    create_directories
    extract_agent "$package_file"
    configure_agent
    
    print_banner "Setting Up Service"
    setup_service
    start_service
    
    print_banner "Installation Complete"
    log_info "AppDynamics Machine Agent installation completed successfully"
    log_info "Service status: $(systemctl is-active $SERVICE_NAME)"
    log_info "Service logs: journalctl -u $SERVICE_NAME -f"
    log_info "Configuration: ${MACHINE_AGENT_DIR}/conf/controller-info.xml"
    log_info "Installation log: $LOG_FILE"
    
    echo "Installation completed successfully!"
    echo "Service status: $(systemctl is-active $SERVICE_NAME)"
    echo "To view logs: journalctl -u $SERVICE_NAME -f"
}

#===============================================================================
# Error Handling
#===============================================================================

cleanup_on_error() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Installation failed with exit code: $exit_code"
        log_error "Check the log file for details: $LOG_FILE"
        
        # Attempt to restore from backup if it exists
        if [[ -d "$BACKUP_DIR" ]]; then
            log_info "Attempting to restore from backup..."
            rm -rf "$MACHINE_AGENT_DIR" 2>/dev/null || true
            mv "$BACKUP_DIR/machine-agent" "$MACHINE_AGENT_DIR" 2>/dev/null || true
        fi
    fi
}

# Set up error handling
trap cleanup_on_error EXIT

#===============================================================================
# Script Execution
#===============================================================================

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi