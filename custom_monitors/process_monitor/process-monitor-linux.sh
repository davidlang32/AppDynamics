#!/bin/bash

#######################################################################
# Enhanced Process Monitor for AppDynamics Custom Metrics (Linux)
#
# Description: Monitors specified processes and outputs custom metrics 
#              in AppDynamics format. Supports configuration files, 
#              logging, and flexible output formats.
#
# Author: David Lang
# Version: 2.0
# Compatible with: AppDynamics Machine Agent custom metrics
#
# Requirements: jq (for JSON parsing)
#
# Usage:
#   ./process_monitor.sh
#   ./process_monitor.sh -c processes.json -f JSON -l monitor.log
#   ./process_monitor.sh -d -f Console
#######################################################################

# Script version and configuration
SCRIPT_VERSION="2.0"
SCRIPT_NAME="$(basename "$0")"

# Default configuration
DEFAULT_PROCESSES=(
    "CSFalconService" "falcon-sensor" "BESClient" "QualysAgent"
    "splunkd" "logger" "FillDB" "GatherDB" "BESRootServer"
    "BESWebReportsServer" "BESPluginService" "BESWebUI" "BESRelay"
    "BESPluginPortal" "certsrv" "K2HostServer" "SourceCode.Configuration.Api"
    "K2ServerEvent" "Nanobot" "apache2.conf" "java" "Services.msc"
    "BrokerAgent" "BrokerService" "CdfSvc" "httpd" "apache2"
    "nginx" "mysqld" "postgres" "redis-server" "mongod"
    "docker" "dockerd" "containerd" "kubelet" "kube-proxy"
    "asm_pmon_+ASM" "ora_pmon_cdb12201" "ora_pmon_cdb19300" "tnslsnr"
)

# Configuration variables
CONFIG_FILE=""
OUTPUT_FORMAT="AppDynamics"
LOG_FILE=""
INCLUDE_DETAILS=false
QUIET=false
METRIC_PREFIX="Custom Metrics|ProcessMon"
TIMEOUT_SECONDS=30

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

#######################################################################
# Utility Functions
#######################################################################

show_usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Enhanced Process Monitor for AppDynamics Custom Metrics (Linux)

OPTIONS:
    -c, --config FILE       Path to JSON configuration file
    -f, --format FORMAT     Output format: AppDynamics, JSON, CSV, Console (default: AppDynamics)
    -l, --log FILE          Path to log file (optional)
    -d, --details           Include additional process details (CPU, Memory)
    -q, --quiet             Suppress console output except for metrics
    -h, --help              Show this help message
    -v, --version           Show version information

EXAMPLES:
    $SCRIPT_NAME
    $SCRIPT_NAME -c processes.json -f JSON -l monitor.log
    $SCRIPT_NAME -d -f Console
    $SCRIPT_NAME -q -c production.json

REQUIREMENTS:
    - jq (for JSON configuration file parsing)
    - Standard Linux utilities: ps, awk, grep

EOF
}

show_version() {
    echo "$SCRIPT_NAME version $SCRIPT_VERSION"
    echo "Compatible with AppDynamics Machine Agent custom metrics"
}

log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="[$timestamp] [$level] $message"
    
    # Console output (unless quiet mode)
    if [[ "$QUIET" != true ]] || [[ "$level" == "ERROR" ]]; then
        case "$level" in
            "INFO")    echo -e "${NC}$log_entry${NC}" ;;
            "WARNING") echo -e "${YELLOW}$log_entry${NC}" ;;
            "ERROR")   echo -e "${RED}$log_entry${NC}" ;;
            "SUCCESS") echo -e "${GREEN}$log_entry${NC}" ;;
            "DEBUG")   echo -e "${GRAY}$log_entry${NC}" ;;
            *)         echo "$log_entry" ;;
        esac
    fi
    
    # File logging
    if [[ -n "$LOG_FILE" ]]; then
        echo "$log_entry" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

check_requirements() {
    local missing_tools=()
    
    # Check for jq if config file is specified
    if [[ -n "$CONFIG_FILE" ]] && ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi
    
    # Check for basic utilities
    for tool in ps awk grep; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_message "ERROR" "Missing required tools: ${missing_tools[*]}"
        log_message "ERROR" "Please install missing tools and try again"
        exit 1
    fi
}

load_configuration() {
    local config_file="$1"
    
    if [[ -z "$config_file" ]] || [[ ! -f "$config_file" ]]; then
        log_message "INFO" "Using default configuration"
        PROCESS_NAMES=("${DEFAULT_PROCESSES[@]}")
        return 0
    fi
    
    log_message "INFO" "Loading configuration from: $config_file"
    
    # Validate JSON file
    if ! jq empty "$config_file" 2>/dev/null; then
        log_message "WARNING" "Invalid JSON configuration file. Using defaults."
        PROCESS_NAMES=("${DEFAULT_PROCESSES[@]}")
        return 1
    fi
    
    # Load process names
    local process_array
    if process_array=$(jq -r '.ProcessNames[]?' "$config_file" 2>/dev/null); then
        mapfile -t PROCESS_NAMES <<< "$process_array"
    else
        log_message "WARNING" "Could not load ProcessNames from config. Using defaults."
        PROCESS_NAMES=("${DEFAULT_PROCESSES[@]}")
    fi
    
    # Load metric prefix
    local metric_prefix
    if metric_prefix=$(jq -r '.MetricPrefix // empty' "$config_file" 2>/dev/null); then
        [[ -n "$metric_prefix" ]] && METRIC_PREFIX="$metric_prefix"
    fi
    
    # Load timeout
    local timeout
    if timeout=$(jq -r '.TimeoutSeconds // empty' "$config_file" 2>/dev/null); then
        [[ -n "$timeout" ]] && TIMEOUT_SECONDS="$timeout"
    fi
    
    log_message "INFO" "Configuration loaded successfully. Monitoring ${#PROCESS_NAMES[@]} processes"
    return 0
}

get_process_details() {
    local pid="$1"
    local name="$2"
    
    # Get basic process info
    local ps_info
    ps_info=$(ps -p "$pid" -o pid,ppid,cmd,etime,pcpu,pmem,rss,vsz --no-headers 2>/dev/null)
    
    if [[ -z "$ps_info" ]]; then
        return 1
    fi
    
    # Parse ps output
    local cpu_percent memory_percent rss_kb vsz_kb
    read -r _ _ _ _ cpu_percent memory_percent rss_kb vsz_kb <<< "$ps_info"
    
    # Convert memory to MB
    local working_set_mb=$((rss_kb / 1024))
    local virtual_memory_mb=$((vsz_kb / 1024))
    
    # Create process detail object
    cat << EOF
{
    "Name": "$name",
    "Id": $pid,
    "CPU": $cpu_percent,
    "WorkingSet": $working_set_mb,
    "VirtualMemory": $virtual_memory_mb,
    "Status": "Running"
}
EOF
}

find_monitored_processes() {
    local process_results=()
    local found_count=0
    
    log_message "INFO" "Starting process scan..."
    
    for process_name in "${PROCESS_NAMES[@]}"; do
        # Find processes matching the name
        local pids
        pids=$(pgrep -f "$process_name" 2>/dev/null || true)
        
        if [[ -n "$pids" ]]; then
            while IFS= read -r pid; do
                if [[ -n "$pid" ]]; then
                    log_message "DEBUG" "Found: $process_name (PID: $pid)"
                    
                    if [[ "$INCLUDE_DETAILS" == true ]]; then
                        local process_detail
                        process_detail=$(get_process_details "$pid" "$process_name")
                        if [[ -n "$process_detail" ]]; then
                            process_results+=("$process_detail")
                        fi
                    else
                        process_results+=("{\"Name\": \"$process_name\", \"Id\": $pid, \"Status\": \"Running\"}")
                    fi
                    ((found_count++))
                fi
            done <<< "$pids"
        else
            log_message "DEBUG" "Not running: $process_name"
        fi
    done
    
    log_message "INFO" "Process scan completed. Found $found_count running processes"
    
    # Export results for use in format functions
    printf '%s\n' "${process_results[@]}"
}

format_appdynamics_output() {
    while IFS= read -r process_json; do
        if [[ -n "$process_json" ]]; then
            local name
            name=$(echo "$process_json" | jq -r '.Name')
            echo "name=$METRIC_PREFIX|$name,value=1"
            
            if [[ "$INCLUDE_DETAILS" == true ]]; then
                local cpu working_set
                cpu=$(echo "$process_json" | jq -r '.CPU // 0')
                working_set=$(echo "$process_json" | jq -r '.WorkingSet // 0')
                
                if [[ "$cpu" != "null" ]] && [[ "$cpu" != "0" ]]; then
                    echo "name=$METRIC_PREFIX|$name|CPU,value=$cpu"
                fi
                if [[ "$working_set" != "null" ]] && [[ "$working_set" != "0" ]]; then
                    echo "name=$METRIC_PREFIX|$name|Memory,value=$working_set"
                fi
            fi
        fi
    done
}

format_json_output() {
    local processes=()
    local total_count=0
    
    while IFS= read -r process_json; do
        if [[ -n "$process_json" ]]; then
            processes+=("$process_json")
            ((total_count++))
        fi
    done
    
    # Join processes array
    local processes_json
    if [[ ${#processes[@]} -gt 0 ]]; then
        processes_json=$(printf '%s\n' "${processes[@]}" | jq -s '.')
    else
        processes_json="[]"
    fi
    
    # Create final JSON output
    cat << EOF
{
    "Timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
    "Processes": $processes_json,
    "Summary": {
        "Total": $total_count,
        "MonitoredProcesses": ${#PROCESS_NAMES[@]}
    }
}
EOF
}

format_csv_output() {
    local header_printed=false
    
    while IFS= read -r process_json; do
        if [[ -n "$process_json" ]]; then
            if [[ "$header_printed" == false ]]; then
                if [[ "$INCLUDE_DETAILS" == true ]]; then
                    echo "Name,Id,CPU,WorkingSet,VirtualMemory,Status"
                else
                    echo "Name,Id,Status"
                fi
                header_printed=true
            fi
            
            local name id cpu working_set virtual_memory status
            name=$(echo "$process_json" | jq -r '.Name')
            id=$(echo "$process_json" | jq -r '.Id')
            status=$(echo "$process_json" | jq -r '.Status')
            
            if [[ "$INCLUDE_DETAILS" == true ]]; then
                cpu=$(echo "$process_json" | jq -r '.CPU // 0')
                working_set=$(echo "$process_json" | jq -r '.WorkingSet // 0')
                virtual_memory=$(echo "$process_json" | jq -r '.VirtualMemory // 0')
                echo "$name,$id,$cpu,$working_set,$virtual_memory,$status"
            else
                echo "$name,$id,$status"
            fi
        fi
    done
}

format_console_output() {
    local processes=()
    local total_count=0
    
    while IFS= read -r process_json; do
        if [[ -n "$process_json" ]]; then
            processes+=("$process_json")
            ((total_count++))
        fi
    done
    
    echo ""
    echo -e "${GREEN}=== Process Monitor Results ===${NC}"
    echo -e "${GRAY}Timestamp: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${GRAY}Processes Found: $total_count / ${#PROCESS_NAMES[@]} monitored${NC}"
    echo ""
    
    if [[ ${#processes[@]} -eq 0 ]]; then
        echo "No monitored processes found"
        return
    fi
    
    # Print table header
    if [[ "$INCLUDE_DETAILS" == true ]]; then
        printf "%-20s %-8s %-8s %-12s %-12s %-10s\n" "Name" "PID" "CPU%" "Memory(MB)" "Virtual(MB)" "Status"
        printf "%-20s %-8s %-8s %-12s %-12s %-10s\n" "----" "---" "----" "---------" "----------" "------"
    else
        printf "%-20s %-8s %-10s\n" "Name" "PID" "Status"
        printf "%-20s %-8s %-10s\n" "----" "---" "------"
    fi
    
    # Print process data
    for process_json in "${processes[@]}"; do
        local name id cpu working_set virtual_memory status
        name=$(echo "$process_json" | jq -r '.Name')
        id=$(echo "$process_json" | jq -r '.Id')
        status=$(echo "$process_json" | jq -r '.Status')
        
        if [[ "$INCLUDE_DETAILS" == true ]]; then
            cpu=$(echo "$process_json" | jq -r '.CPU // 0')
            working_set=$(echo "$process_json" | jq -r '.WorkingSet // 0')
            virtual_memory=$(echo "$process_json" | jq -r '.VirtualMemory // 0')
            printf "%-20s %-8s %-8s %-12s %-12s %-10s\n" \
                "${name:0:19}" "$id" "$cpu" "$working_set" "$virtual_memory" "$status"
        else
            printf "%-20s %-8s %-10s\n" "${name:0:19}" "$id" "$status"
        fi
    done
}

format_output() {
    local format="$1"
    
    case "$format" in
        "AppDynamics")
            format_appdynamics_output
            ;;
        "JSON")
            format_json_output
            ;;
        "CSV")
            format_csv_output
            ;;
        "Console")
            format_console_output
            ;;
        *)
            log_message "ERROR" "Unknown output format: $format"
            exit 1
            ;;
    esac
}

#######################################################################
# Main Execution
#######################################################################

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -f|--format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            -l|--log)
                LOG_FILE="$2"
                shift 2
                ;;
            -d|--details)
                INCLUDE_DETAILS=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            *)
                log_message "ERROR" "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Validate output format
    case "$OUTPUT_FORMAT" in
        "AppDynamics"|"JSON"|"CSV"|"Console") ;;
        *)
            log_message "ERROR" "Invalid output format: $OUTPUT_FORMAT"
            log_message "ERROR" "Valid formats: AppDynamics, JSON, CSV, Console"
            exit 1
            ;;
    esac
    
    # Initialize logging
    if [[ -n "$LOG_FILE" ]]; then
        local log_dir
        log_dir=$(dirname "$LOG_FILE")
        if [[ ! -d "$log_dir" ]]; then
            mkdir -p "$log_dir" 2>/dev/null || {
                log_message "ERROR" "Cannot create log directory: $log_dir"
                exit 1
            }
        fi
        log_message "INFO" "Logging to: $LOG_FILE"
    fi
    
    log_message "SUCCESS" "Process Monitor Starting..."
    log_message "INFO" "Output Format: $OUTPUT_FORMAT"
    
    # Check requirements
    check_requirements
    
    # Load configuration
    load_configuration "$CONFIG_FILE"
    
    # Find and format processes
    local process_output
    process_output=$(find_monitored_processes)
    
    if [[ -n "$process_output" ]]; then
        echo "$process_output" | format_output "$OUTPUT_FORMAT"
    else
        case "$OUTPUT_FORMAT" in
            "JSON")
                echo '{"Timestamp": "'$(date '+%Y-%m-%d %H:%M:%S')'", "Processes": [], "Summary": {"Total": 0, "MonitoredProcesses": '${#PROCESS_NAMES[@]}'}}'
                ;;
            "CSV")
                echo "Name,Id,Status"
                ;;
            "Console")
                echo ""
                echo -e "${GREEN}=== Process Monitor Results ===${NC}"
                echo -e "${GRAY}Timestamp: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
                echo -e "${GRAY}Processes Found: 0 / ${#PROCESS_NAMES[@]} monitored${NC}"
                echo ""
                echo "No monitored processes found"
                ;;
        esac
    fi
    
    log_message "SUCCESS" "Process monitoring completed successfully"
    exit 0
}

# Error handling
set -eE
trap 'log_message "ERROR" "Script execution failed at line $LINENO"; exit 1' ERR

# Run main function
main "$@"