#!/bin/bash

# Datadog Agent Installation and Configuration Script for Ubuntu 22 and macOS
# This script installs Datadog Agent and configures APM, tracing, and log collection

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Install and configure Datadog Agent with APM, tracing, and log collection.
Supports Ubuntu 22 and macOS systems.

OPTIONS:
    -k, --api-key KEY       Datadog API Key (32 characters)
    -l, --logs-dir PATH     Path to logs directory (default: ~/.pm2/logs)
    -s, --service-name NAME Service name for monitoring
    -e, --environment ENV   Environment (development|production|sandbox)
    -p, --port PORT         Node.js application port (default: 3000)
    -t, --site SITE         Datadog site (datadoghq.com|us3.datadoghq.com|us5.datadoghq.com|eu1.datadoghq.com|ap1.datadoghq.com)
    -h, --help              Show this help message

EXAMPLES:
    # Interactive mode (prompts for all inputs)
    $0

    # Non-interactive mode with all arguments
    $0 -k your_api_key_here -l /var/log/myapp -s myapp -e production -p 8080 -t datadoghq.com

    # Mixed mode (some arguments, prompts for missing ones)
    $0 -k your_api_key_here -e production -t datadoghq.com

NOTES:
    - If any required option is not provided, the script will prompt interactively
    - The script requires sudo privileges to install and configure Datadog Agent
    - Do not run this script as root user

EOF
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -k|--api-key)
                DD_API_KEY="$2"
                shift 2
                ;;
            -l|--logs-dir)
                LOGS_DIR="$2"
                shift 2
                ;;
            -s|--service-name)
                SERVICE_NAME="$2"
                shift 2
                ;;
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -p|--port)
                NODE_PORT="$2"
                shift 2
                ;;
            -t|--site)
                DD_SITE="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Function to validate input for YAML safety
validate_yaml_string() {
    local input="$1"
    local field_name="$2"
    
    # Check for potentially dangerous characters
    if [[ "$input" =~ [\"\'\\\$\\\|\&\;\(\)\<\>\[\]\{\}] ]] || [[ "$input" == *'`'* ]]; then
        print_error "$field_name contains invalid characters that could break YAML configuration"
        return 1
    fi
    
    # Check for reasonable length
    if [[ ${#input} -gt 100 ]]; then
        print_error "$field_name is too long (max 100 characters)"
        return 1
    fi
    
    return 0
}

# Function to validate path input
validate_path() {
    local path="$1"
    local field_name="$2"
    
    # Check for path injection attempts
    if [[ "$path" =~ \.\./|\$\(|\\\`|\| ]]; then
        print_error "$field_name contains potentially dangerous path characters"
        return 1
    fi
    
    # Expand and validate path
    path=$(eval echo "$path")
    if [[ ! "$path" = /* ]]; then
        print_error "$field_name must be an absolute path"
        return 1
    fi
    
    return 0
}

# Function to detect OS and set appropriate commands
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        STAT_USER_CMD="stat -f %Su"
        STAT_GROUP_CMD="stat -f %Sg"
        OS_TYPE="macos"
        INSTALL_SCRIPT_URL="https://install.datadoghq.com/scripts/install_mac_os.sh"
    else
        STAT_USER_CMD="stat -c %U"
        STAT_GROUP_CMD="stat -c %G"
        OS_TYPE="linux"
        INSTALL_SCRIPT_URL="https://s3.amazonaws.com/dd-agent/scripts/install_script_agent7.sh"
    fi
}

# Function to check system requirements
check_requirements() {
    print_status "Checking system requirements..."
    
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        print_error "curl is required but not installed. Please install curl first."
        exit 1
    fi
    
    # Check service management availability based on OS
    if [[ "$OS_TYPE" == "macos" ]]; then
        # Check if launchctl is available (should be on all macOS systems)
        if ! command -v launchctl &> /dev/null; then
            print_error "launchctl is required for macOS service management."
            exit 1
        fi
    else
        # Check if systemctl is available for Linux
        if ! command -v systemctl &> /dev/null; then
            print_error "systemctl is required. This script is designed for systemd-based systems."
            exit 1
        fi
    fi
    
    # Check sudo privileges
    if ! sudo -n true 2>/dev/null; then
        print_error "This script requires sudo privileges. Please ensure you can run sudo commands."
        exit 1
    fi
    
    print_success "System requirements check passed for $OS_TYPE!"
}

# Function to check if Datadog agent is already installed
check_datadog_installed() {
    print_status "Checking if Datadog agent is already installed..."
    
    if command -v datadog-agent &> /dev/null; then
        print_status "Datadog agent found. Checking status..."
        if sudo datadog-agent status &> /dev/null; then
            print_success "Datadog agent is already installed and running!"
            read -p "Do you want to reconfigure it? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_status "Exiting without changes."
                exit 0
            fi
        else
            print_warning "Datadog agent is installed but not running properly."
        fi
    else
        print_status "Datadog agent not found. Will proceed with installation."
        return 1
    fi
    return 0
}

# Function to get user inputs (modified to support command line arguments)
get_user_inputs() {
    print_status "Validating and collecting configuration..."
    
    # API Key
    if [[ -n "${DD_API_KEY:-}" ]]; then
        print_status "Using provided API key"
        if [[ ${#DD_API_KEY} -ne 32 ]]; then
            print_warning "API Key should be 32 characters long. Please verify."
            read -p "Continue with this API key? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_error "Please provide a valid API key"
                exit 1
            fi
        fi
    else
        while [[ -z "${DD_API_KEY:-}" ]]; do
            read -p "Enter your Datadog API Key: " -s DD_API_KEY
            echo
            if [[ -z "$DD_API_KEY" ]]; then
                print_error "API Key cannot be empty!"
            elif [[ ${#DD_API_KEY} -ne 32 ]]; then
                print_warning "API Key should be 32 characters long. Please verify."
                read -p "Continue with this API key? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    DD_API_KEY=""
                    continue
                fi
            fi
        done
    fi
    
    # Logs directory with PM2 default
    if [[ -n "${LOGS_DIR:-}" ]]; then
        print_status "Using provided logs directory: $LOGS_DIR"
        if ! validate_path "$LOGS_DIR" "Logs directory"; then
            print_error "Invalid logs directory path provided"
            exit 1
        fi
        LOGS_DIR=$(eval echo "$LOGS_DIR")
    else
        print_status "Default PM2 logs directory is typically: ~/.pm2/logs"
        while [[ -z "${LOGS_DIR:-}" ]]; do
            read -p "Enter logs directory path (default: $HOME/.pm2/logs): " LOGS_DIR
            if [[ -z "$LOGS_DIR" ]]; then
                LOGS_DIR="$HOME/.pm2/logs"
            fi
            
            # Validate and expand path
            if ! validate_path "$LOGS_DIR" "Logs directory"; then
                LOGS_DIR=""
                continue
            fi
            
            LOGS_DIR=$(eval echo "$LOGS_DIR")
            break
        done
    fi
    
    # Validate logs directory
    if [[ ! -d "$LOGS_DIR" ]]; then
        print_warning "Directory $LOGS_DIR does not exist."
        if [[ -n "${DD_API_KEY:-}" && -n "${SERVICE_NAME:-}" && -n "${ENVIRONMENT:-}" ]]; then
            # Non-interactive mode - auto-create directory
            print_status "Creating directory automatically in non-interactive mode"
            if ! mkdir -p "$LOGS_DIR"; then
                print_error "Failed to create directory: $LOGS_DIR"
                exit 1
            fi
            print_success "Created directory: $LOGS_DIR"
        else
            # Interactive mode - ask user
            read -p "Do you want to create it? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                if ! mkdir -p "$LOGS_DIR"; then
                    print_error "Failed to create directory: $LOGS_DIR"
                    exit 1
                fi
                print_success "Created directory: $LOGS_DIR"
            else
                print_error "Logs directory is required. Exiting."
                exit 1
            fi
        fi
    fi
    
    # Service name
    if [[ -n "${SERVICE_NAME:-}" ]]; then
        print_status "Using provided service name: $SERVICE_NAME"
        if ! validate_yaml_string "$SERVICE_NAME" "Service name"; then
            print_error "Invalid service name provided"
            exit 1
        fi
    else
        while [[ -z "${SERVICE_NAME:-}" ]]; do
            read -p "Enter service name (e.g., pm2-docker-app): " SERVICE_NAME
            if [[ -z "$SERVICE_NAME" ]]; then
                print_error "Service name cannot be empty!"
            elif ! validate_yaml_string "$SERVICE_NAME" "Service name"; then
                SERVICE_NAME=""
                continue
            fi
        done
    fi
    
    # Environment
    if [[ -n "${ENVIRONMENT:-}" ]]; then
        print_status "Using provided environment: $ENVIRONMENT"
        if [[ "$ENVIRONMENT" != "development" && "$ENVIRONMENT" != "production" && "$ENVIRONMENT" != "sandbox" ]]; then
            print_error "Environment must be either 'development', 'production', or 'sandbox'!"
            exit 1
        fi
    else
        while [[ "${ENVIRONMENT:-}" != "development" && "${ENVIRONMENT:-}" != "production" && "${ENVIRONMENT:-}" != "sandbox" ]]; do
            read -p "Enter environment (development/production/sandbox): " ENVIRONMENT
            if [[ "$ENVIRONMENT" != "development" && "$ENVIRONMENT" != "production" && "$ENVIRONMENT" != "sandbox" ]]; then
                print_error "Environment must be either 'development', 'production', or 'sandbox'!"
            fi
        done
    fi
    
    # Node.js port
    if [[ -n "${NODE_PORT:-}" ]]; then
        print_status "Using provided Node.js port: $NODE_PORT"
        if ! [[ "$NODE_PORT" =~ ^[0-9]+$ ]] || [[ "$NODE_PORT" -lt 1 ]] || [[ "$NODE_PORT" -gt 65535 ]]; then
            print_error "Port must be a valid number between 1 and 65535!"
            exit 1
        fi
    else
        while [[ -z "${NODE_PORT:-}" ]]; do
            read -p "Enter Node.js application port (default: 3000): " NODE_PORT
            if [[ -z "$NODE_PORT" ]]; then
                NODE_PORT="3000"
            elif ! [[ "$NODE_PORT" =~ ^[0-9]+$ ]] || [[ "$NODE_PORT" -lt 1 ]] || [[ "$NODE_PORT" -gt 65535 ]]; then
                print_error "Port must be a valid number between 1 and 65535!"
                NODE_PORT=""
                continue
            fi
        done
    fi
    
    # Datadog site
    if [[ -n "${DD_SITE:-}" ]]; then
        print_status "Using provided Datadog site: $DD_SITE"
        if [[ ! "$DD_SITE" =~ ^(datadoghq\.com|us3\.datadoghq\.com|us5\.datadoghq\.com|eu1\.datadoghq\.com|ap1\.datadoghq\.com)$ ]]; then
            print_error "Invalid Datadog site. Must be one of: datadoghq.com, us3.datadoghq.com, us5.datadoghq.com, eu1.datadoghq.com, ap1.datadoghq.com"
            exit 1
        fi
    else
        print_status "Available Datadog sites:"
        echo "  1. datadoghq.com (US1 - default)"
        echo "  2. us3.datadoghq.com (US3)"
        echo "  3. us5.datadoghq.com (US5)"
        echo "  4. eu1.datadoghq.com (EU1)"
        echo "  5. ap1.datadoghq.com (AP1)"
        echo
        while [[ -z "${DD_SITE:-}" ]]; do
            read -p "Enter Datadog site (default: datadoghq.com): " DD_SITE
            if [[ -z "$DD_SITE" ]]; then
                DD_SITE="datadoghq.com"
            elif [[ ! "$DD_SITE" =~ ^(datadoghq\.com|us3\.datadoghq\.com|us5\.datadoghq\.com|eu1\.datadoghq\.com|ap1\.datadoghq\.com)$ ]]; then
                print_error "Invalid site. Please enter one of: datadoghq.com, us3.datadoghq.com, us5.datadoghq.com, eu1.datadoghq.com, ap1.datadoghq.com"
                DD_SITE=""
                continue
            fi
        done
    fi
    
    print_success "Configuration collected successfully!"
}

# Function to create a safe temporary file
create_temp_file() {
    local temp_file
    
    # Try different locations for temporary files
    local temp_dirs=(
        "${TMPDIR:-}"
        "/tmp"
        "/var/tmp"
        "$HOME/.cache"
        "$(pwd)"
    )
    
    for temp_dir in "${temp_dirs[@]}"; do
        if [[ -n "$temp_dir" && -d "$temp_dir" && -w "$temp_dir" ]]; then
            if temp_file=$(mktemp "$temp_dir/datadog_install.XXXXXX" 2>/dev/null); then
                echo "$temp_file"
                return 0
            fi
        fi
    done
    
    # Fallback: create a temporary file in current directory
    temp_file="./datadog_install_tmp_$$_$(date +%s)"
    touch "$temp_file" 2>/dev/null && echo "$temp_file" && return 0
    
    print_error "Failed to create temporary file"
    return 1
}

# Function to verify installation script integrity
verify_installation_script() {
    local script_url="$INSTALL_SCRIPT_URL"
    
    print_status "Verifying installation script integrity for $OS_TYPE..."
    
    # Download script to temporary location
    local temp_script
    if ! temp_script=$(create_temp_file); then
        print_error "Failed to create temporary file"
        return 1
    fi
    
    if ! curl -sL "$script_url" -o "$temp_script"; then
        print_error "Failed to download installation script from $script_url"
        rm -f "$temp_script"
        return 1
    fi
    
    # Note: In a real implementation, you would verify against known good hash
    # For now, we'll just check if the file was downloaded successfully
    if [[ ! -s "$temp_script" ]]; then
        print_error "Downloaded script is empty"
        rm -f "$temp_script"
        return 1
    fi
    
    echo "$temp_script"
    return 0
}

# Function to install Datadog agent
install_datadog() {
    print_status "Installing Datadog agent for $OS_TYPE..."
    
    # Install Datadog agent using provided site configuration
    # Download and execute the script directly to avoid file path issues
    if ! DD_API_KEY="$DD_API_KEY" DD_SITE="$DD_SITE" DD_ENV="$ENVIRONMENT" bash <(curl -sL "$INSTALL_SCRIPT_URL"); then
        print_error "Failed to install Datadog agent on $OS_TYPE!"
        exit 1
    fi
    print_success "Datadog agent installed successfully on $OS_TYPE!"
}

# Function to configure Datadog agent
configure_datadog() {
    print_status "Configuring Datadog agent..."
    
    # Set configuration path based on OS
    if [[ "$OS_TYPE" == "macos" ]]; then
        DATADOG_CONF_DIR="/opt/datadog-agent/etc"
    else
        DATADOG_CONF_DIR="/etc/datadog-agent"
    fi
    
    # Backup original config if it exists
    if [[ -f "$DATADOG_CONF_DIR/datadog.yaml" ]]; then
        if ! sudo cp "$DATADOG_CONF_DIR/datadog.yaml" "$DATADOG_CONF_DIR/datadog.yaml.backup.$(date +%Y%m%d_%H%M%S)"; then
            print_warning "Failed to backup existing configuration"
        fi
    fi
    
    # Create main configuration
    sudo tee "$DATADOG_CONF_DIR/datadog.yaml" > /dev/null << EOF
# Datadog Agent Configuration
api_key: $DD_API_KEY
site: $DD_SITE

# Hostname and tags
hostname: $(hostname)
tags:
  - env:$ENVIRONMENT
  - service:$SERVICE_NAME
  - version:1.0.0

# APM Configuration
apm_config:
  enabled: true
  env: $ENVIRONMENT
  receiver_port: 8126
  apm_non_local_traffic: true
  max_traces_per_second: 10
  trace_buffer: 5000
  
# Process Collection
process_config:
  enabled: "true"

# Network Performance Monitoring
network_config:
  enabled: true

# Log Collection
logs_enabled: true
logs_config:
  container_collect_all: false
  processing_rules:
    - type: multi_line
      name: log_start_with_date
      pattern: \d{4}\-(0?[1-9]|1[012])\-(0?[1-9]|[12][0-9]|3[01])

# Dogstatsd
dogstatsd_config:
  enabled: true
  bind_host: 0.0.0.0
  port: 8125

# JMX
jmx_check_period: 15000

# Inventories
inventories_configuration_enabled: true
inventories_checks_configuration_enabled: true

# Security
compliance_config:
  enabled: false

# OTLP
otlp_config:
  receiver:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318
EOF

    if [[ $? -ne 0 ]]; then
        print_error "Failed to create Datadog configuration"
        exit 1
    fi

    print_success "Main Datadog configuration created!"
}

# Function to configure log collection
configure_logs() {
    print_status "Configuring log collection for directory: $LOGS_DIR"
    
    # Create logs configuration directory
    if ! sudo mkdir -p "$DATADOG_CONF_DIR/conf.d/nodejs.d"; then
        print_error "Failed to create configuration directory"
        exit 1
    fi
    
    # Configure log collection for individual PM2 out and error logs (better log level separation)
    sudo tee "$DATADOG_CONF_DIR/conf.d/nodejs.d/conf.yaml" > /dev/null << EOF
logs:
  - type: file
    path: "$LOGS_DIR/out*.log"
    service: "$SERVICE_NAME"
    source: nodejs
    sourcecategory: sourcecode
    tags:
      - env:$ENVIRONMENT
      - service:$SERVICE_NAME
      - log_level:info
    log_processing_rules:
      - type: multi_line
        name: out_log_start_with_date
        pattern: \d{4}-\d{2}-\d{2}
  - type: file
    path: "$LOGS_DIR/error*.log"
    service: "$SERVICE_NAME"
    source: nodejs
    sourcecategory: sourcecode
    tags:
      - env:$ENVIRONMENT
      - service:$SERVICE_NAME
      - log_level:error
    log_processing_rules:
      - type: multi_line
        name: error_log_start_with_date
        pattern: \d{4}-\d{2}-\d{2}

# Node.js Integration
init_config:

instances:
  - host: localhost
    port: $NODE_PORT
    tags:
      - env:$ENVIRONMENT
      - service:$SERVICE_NAME
EOF

    if [[ $? -ne 0 ]]; then
        print_error "Failed to create log configuration"
        exit 1
    fi

    print_success "Log collection and Node.js integration configured!"
}

# Function to set proper permissions
set_permissions() {
    print_status "Setting up proper permissions..."
    
    # Fix configuration file permissions first (critical for agent startup)
    print_status "Fixing configuration file permissions..."
    
    # Ensure dd-agent user and group exist (for Linux systems)
    if [[ "$OS_TYPE" != "macos" ]]; then
        if ! id "dd-agent" &>/dev/null; then
            print_status "Creating dd-agent user..."
            sudo useradd -r -s /bin/false dd-agent 2>/dev/null || true
        fi
        
        if ! getent group dd-agent >/dev/null 2>&1; then
            print_status "Creating dd-agent group..."
            sudo groupadd dd-agent 2>/dev/null || true
        fi
        
        # Set ownership to dd-agent user/group
        if sudo chown -R dd-agent:dd-agent "$DATADOG_CONF_DIR" 2>/dev/null; then
            print_success "Set ownership to dd-agent:dd-agent"
        else
            print_warning "Could not set ownership (dd-agent user/group may not exist)"
        fi
        
        # Set appropriate permissions
        if sudo chmod -R 755 "$DATADOG_CONF_DIR" 2>/dev/null; then
            print_success "Set directory permissions to 755"
        else
            print_warning "Could not set directory permissions"
        fi
        
        # Set specific permissions for configuration files (readable by everyone)
        if sudo chmod 644 "$DATADOG_CONF_DIR/datadog.yaml" 2>/dev/null; then
            print_success "Set datadog.yaml permissions to 644 (readable by everyone)"
        else
            print_warning "Could not set datadog.yaml permissions"
        fi
        
        # Verify the agent can read the configuration
        print_status "Verifying configuration readability..."
        if sudo -u dd-agent test -r "$DATADOG_CONF_DIR/datadog.yaml" 2>/dev/null; then
            print_success "Agent can read configuration file"
        else
            print_error "Agent cannot read configuration file - permission issue detected"
            print_status "This may cause the agent to hang during startup"
            return 1
        fi
    else
        # For macOS, use datadog-agent user
        if sudo chown -R datadog-agent:datadog-agent "$DATADOG_CONF_DIR" 2>/dev/null; then
            print_success "Set ownership to datadog-agent:datadog-agent (macOS)"
        fi
        
        if sudo chmod -R 755 "$DATADOG_CONF_DIR" 2>/dev/null; then
            print_success "Set directory permissions to 755"
        fi
        
        if sudo chmod 644 "$DATADOG_CONF_DIR/datadog.yaml" 2>/dev/null; then
            print_success "Set datadog.yaml permissions to 644 (readable by everyone)"
        fi
    fi
    
    # Add datadog-agent user to necessary groups to read logs
    if [[ -d "$LOGS_DIR" ]]; then
        # Get the owner of the logs directory using OS-appropriate command
        if ! LOG_OWNER=$($STAT_USER_CMD "$LOGS_DIR" 2>/dev/null); then
            print_warning "Could not determine logs directory owner"
            return 0
        fi
        
        if [[ "$LOG_OWNER" != "datadog-agent" ]]; then
            # Add datadog-agent to the owner's group with OS-specific commands
            if LOG_GROUP=$($STAT_GROUP_CMD "$LOGS_DIR" 2>/dev/null); then
                if [[ "$OS_TYPE" == "macos" ]]; then
                    # macOS uses dscl for group management
                    if ! sudo dscl . -append /Groups/"$LOG_GROUP" GroupMembership datadog-agent 2>/dev/null; then
                        print_warning "Could not add datadog-agent to group $LOG_GROUP on macOS"
                        print_status "This is often expected on macOS and may not affect log collection"
                    fi
                else
                    # Linux uses usermod
                    if ! sudo usermod -a -G "$LOG_GROUP" datadog-agent 2>/dev/null; then
                        print_warning "Could not add datadog-agent to group $LOG_GROUP"
                    fi
                fi
            fi
        fi
        
        # Ensure logs directory is readable and executable by datadog-agent
        if ! sudo chmod -R +r "$LOGS_DIR" 2>/dev/null; then
            print_warning "Could not set read permissions on logs directory"
        fi
        
        # Critical: Set execute permissions on directories so agent can traverse them
        if ! sudo find "$LOGS_DIR" -type d -exec chmod +x {} \; 2>/dev/null; then
            print_warning "Could not set execute permissions on log directories"
        fi
        
        # Ensure the parent directories are also executable
        local current_dir="$LOGS_DIR"
        while [[ "$current_dir" != "/" && "$current_dir" != "." ]]; do
            if sudo test -d "$current_dir"; then
                sudo chmod +x "$current_dir" 2>/dev/null || true
            fi
            current_dir=$(dirname "$current_dir")
        done
    fi
    
    print_success "Permissions configured!"
}

# Function to fix log directory permissions specifically
fix_log_permissions() {
    print_status "Fixing log directory permissions for Datadog agent..."
    
    if [[ ! -d "$LOGS_DIR" ]]; then
        print_warning "Logs directory does not exist: $LOGS_DIR"
        return 0
    fi
    
    # Show current permissions
    print_status "Current log directory permissions:"
    ls -la "$LOGS_DIR" | head -5
    
    # Set read permissions on all files
    print_status "Setting read permissions on log files..."
    sudo find "$LOGS_DIR" -type f -exec chmod 644 {} \; 2>/dev/null || true
    
    # Set execute permissions on all directories (critical for traversal)
    print_status "Setting execute permissions on directories..."
    sudo find "$LOGS_DIR" -type d -exec chmod 755 {} \; 2>/dev/null || true
    
    # Ensure parent directories are executable
    print_status "Ensuring parent directories are executable..."
    local current_dir="$LOGS_DIR"
    while [[ "$current_dir" != "/" && "$current_dir" != "." ]]; do
        if sudo test -d "$current_dir"; then
            sudo chmod +x "$current_dir" 2>/dev/null || true
        fi
        current_dir=$(dirname "$current_dir")
    done
    
    # Add datadog-agent to the owner's group if possible
    if [[ "$OS_TYPE" != "macos" ]]; then
        local log_owner
        if log_owner=$(stat -c '%U' "$LOGS_DIR" 2>/dev/null); then
            print_status "Log directory owner: $log_owner"
            if [[ "$log_owner" != "datadog-agent" && "$log_owner" != "dd-agent" ]]; then
                local log_group
                if log_group=$(stat -c '%G' "$LOGS_DIR" 2>/dev/null); then
                    print_status "Adding datadog-agent to group: $log_group"
                    sudo usermod -a -G "$log_group" datadog-agent 2>/dev/null || true
                    sudo usermod -a -G "$log_group" dd-agent 2>/dev/null || true
                fi
            fi
        fi
    fi
    
    # Test if datadog-agent can access the directory
    print_status "Testing if agent can access log directory..."
    if sudo -u datadog-agent test -r "$LOGS_DIR" 2>/dev/null; then
        print_success "Agent can read log directory"
    else
        print_warning "Agent cannot read log directory, trying alternative permissions..."
        sudo chmod 755 "$LOGS_DIR" 2>/dev/null || true
    fi
    
    # Test if agent can read log files
    print_status "Testing if agent can read log files..."
    local test_file
    test_file=$(find "$LOGS_DIR" -name "*.log" | head -1)
    if [[ -n "$test_file" ]]; then
        if sudo -u datadog-agent test -r "$test_file" 2>/dev/null; then
            print_success "Agent can read log files"
        else
            print_warning "Agent cannot read log files, setting more permissive permissions..."
            sudo chmod -R 666 "$LOGS_DIR"/*.log 2>/dev/null || true
        fi
    fi
    
    print_status "New log directory permissions:"
    ls -la "$LOGS_DIR" | head -5
    
    print_success "Log directory permissions fixed!"
}

# Function to validate configuration
validate_configuration() {
    print_status "Validating Datadog configuration..."
    
    # Check if configuration file exists
    if [[ ! -f "$DATADOG_CONF_DIR/datadog.yaml" ]]; then
        print_error "Configuration file not found: $DATADOG_CONF_DIR/datadog.yaml"
        return 1
    fi
    
    # Check if configuration file is readable
    if [[ ! -r "$DATADOG_CONF_DIR/datadog.yaml" ]]; then
        print_error "Configuration file is not readable: $DATADOG_CONF_DIR/datadog.yaml"
        return 1
    fi
    
    # Check if configuration file is valid YAML using Python
    if command -v python3 &> /dev/null; then
        # First check if PyYAML is installed
        if python3 -c "import yaml" 2>/dev/null; then
            # Try to validate the YAML file
            local validation_result
            validation_result=$(python3 -c "
import yaml
import sys
try:
    with open('$DATADOG_CONF_DIR/datadog.yaml', 'r') as f:
        yaml.safe_load(f)
    print('YAML validation successful')
    sys.exit(0)
except yaml.YAMLError as e:
    print(f'YAML syntax error: {e}')
    sys.exit(1)
except Exception as e:
    print(f'Error reading file: {e}')
    sys.exit(1)
" 2>&1)
            
            local exit_code=$?
            if [[ $exit_code -ne 0 ]]; then
                print_error "YAML configuration validation failed:"
                echo "  $validation_result"
                print_status "Configuration file location: $DATADOG_CONF_DIR/datadog.yaml"
                return 1
            fi
            print_status "YAML syntax validation passed"
        else
            print_warning "PyYAML not installed, skipping YAML syntax validation"
            print_status "You can install it with: pip3 install PyYAML"
        fi
    else
        print_warning "Python3 not found, skipping YAML validation"
    fi
    
    # Basic file content validation
    if grep -q "api_key:" "$DATADOG_CONF_DIR/datadog.yaml" && \
       grep -q "logs_enabled:" "$DATADOG_CONF_DIR/datadog.yaml" && \
       grep -q "apm_config:" "$DATADOG_CONF_DIR/datadog.yaml"; then
        print_success "Configuration validation passed!"
    else
        print_error "Configuration file appears to be missing required sections"
        print_status "Please check the file: $DATADOG_CONF_DIR/datadog.yaml"
        return 1
    fi
}

# Function to start and enable services
start_services() {
    print_status "Starting Datadog agent service..."
    
    # Ensure proper permissions before starting (critical fix for permission issues)
    print_status "Ensuring proper permissions before starting agent..."
    
    # Create dd-agent user and group if they don't exist (Linux systems)
    if [[ "$OS_TYPE" != "macos" ]]; then
        if ! id "dd-agent" &>/dev/null; then
            print_status "Creating dd-agent user..."
            sudo useradd -r -s /bin/false dd-agent 2>/dev/null || true
        fi
        
        if ! getent group dd-agent >/dev/null 2>&1; then
            print_status "Creating dd-agent group..."
            sudo groupadd dd-agent 2>/dev/null || true
        fi
        
        # Fix ownership and permissions
        print_status "Fixing configuration file permissions..."
        sudo chown -R dd-agent:dd-agent "$DATADOG_CONF_DIR" 2>/dev/null || true
        sudo chmod -R 755 "$DATADOG_CONF_DIR" 2>/dev/null || true
        sudo chmod 644 "$DATADOG_CONF_DIR/datadog.yaml" 2>/dev/null || true
        
        # Verify the agent can read the configuration
        if ! sudo -u dd-agent test -r "$DATADOG_CONF_DIR/datadog.yaml" 2>/dev/null; then
            print_error "Agent cannot read configuration file - critical permission issue"
            print_status "Attempting to fix with more permissive settings..."
            sudo chmod 666 "$DATADOG_CONF_DIR/datadog.yaml" 2>/dev/null || true
        fi
    fi
    
    # Stop the agent first to ensure clean start
    print_status "Stopping any existing Datadog agent..."
    sudo datadog-agent stop 2>/dev/null || true
    
    # Force stop if needed (for stuck processes)
    sudo pkill -f datadog-agent 2>/dev/null || true
    sleep 2
    
    # Start the Datadog agent with better error handling
    print_status "Starting Datadog agent..."
    
    # Try systemctl first (for systemd systems)
    if command -v systemctl >/dev/null 2>&1; then
        print_status "Using systemctl to start agent..."
        if sudo systemctl start datadog-agent 2>/dev/null; then
            print_success "Agent started via systemctl"
        else
            print_status "systemctl failed, trying direct start..."
            # Fall back to direct start with timeout
            if ! timeout 15 sudo datadog-agent start >/dev/null 2>&1; then
                print_status "Direct start timed out, trying background start..."
                sudo datadog-agent start >/dev/null 2>&1 &
                disown 2>/dev/null || true
            fi
        fi
    else
        # For non-systemd systems, use direct start with timeout
        if ! timeout 15 sudo datadog-agent start >/dev/null 2>&1; then
            print_status "Direct start timed out, trying background start..."
            sudo datadog-agent start >/dev/null 2>&1 &
            disown 2>/dev/null || true
        fi
    fi
    
    # Give the agent time to initialize
    sleep 5
    
    # Wait for service to start
    print_status "Waiting for agent to start..."
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        # Check if agent is running by testing status command
        if sudo datadog-agent status >/dev/null 2>&1; then
            print_success "Datadog agent is running!"
            return 0
        fi
        
        sleep 2
        ((attempt++))
        
        if [[ $((attempt % 5)) -eq 0 ]]; then
            print_status "Still waiting... (attempt $attempt/$max_attempts)"
        fi
    done
    
    print_error "Failed to start Datadog agent after $max_attempts attempts!"
    print_status "=== Troubleshooting Information ==="
    print_status "1. Check agent status: sudo datadog-agent status"
    print_status "2. Check agent logs: sudo datadog-agent logs"
    print_status "3. Check system logs: sudo journalctl -u datadog-agent -n 50"
    print_status "4. Check configuration: sudo datadog-agent configcheck"
    print_status "5. Check permissions: ls -la /etc/datadog-agent/"
    print_status "6. Check if agent is running: ps aux | grep datadog"
    
    # Try to get some diagnostic information
    echo
    print_status "=== Current Diagnostic Info ==="
    echo "Processes:"
    ps aux | grep datadog | grep -v grep || echo "No datadog processes found"
    echo
    echo "Configuration check:"
    sudo datadog-agent configcheck 2>&1 | head -10 || echo "Config check failed"
    echo
    echo "Recent logs:"
    sudo datadog-agent logs 2>&1 | tail -5 || echo "Could not retrieve logs"
    
    exit 1
}

# Function to verify installation
verify_installation() {
    print_status "Verifying Datadog agent installation..."
    
    # Create a proper temporary file
    local temp_status
    if ! temp_status=$(create_temp_file); then
        print_error "Failed to create temporary file for status check"
        return 1
    fi
    
    # Check agent status
    if sudo datadog-agent status > "$temp_status" 2>&1; then
        print_success "Datadog agent status check passed!"
        
        # Show key information
        echo
        print_status "=== Datadog Agent Status Summary ==="
        if grep -E "(Agent|Logs|APM|Status)" "$temp_status" | head -10; then
            echo
        else
            print_warning "Could not extract status summary"
        fi
        
        print_success "Installation and configuration completed successfully!"
        echo
        print_status "=== Configuration Summary ==="
        echo "• API Key: [HIDDEN]"
        echo "• Datadog Site: $DD_SITE"
        echo "• Service: $SERVICE_NAME"
        echo "• Environment: $ENVIRONMENT"
        echo "• Logs Directory: $LOGS_DIR"
        echo "• Node.js Port: $NODE_PORT"
        echo "• APM: Enabled"
        echo "• Log Collection: Enabled"
        echo "• Tracing: Enabled"
        echo
        print_status "Next steps:"
        echo "1. Verify API key is working: sudo datadog-agent status | grep 'API Key'"
        echo "2. Restart your Node.js application to enable tracing"
        echo "3. Install Datadog tracing library: npm install dd-trace"
        echo "4. Add tracing to your app.js: require('dd-trace').init()"
        echo "5. Check your Datadog dashboard at https://app.$DD_SITE"
        
    else
        print_error "Datadog agent status check failed!"
        print_status "Status output:"
        cat "$temp_status"
        
        # Check if it's an API key issue
        if grep -qi "api.*key.*invalid\|403\|unauthorized" "$temp_status"; then
            show_troubleshooting_guide
        else
            print_status "For general troubleshooting:"
            if [[ "$OS_TYPE" == "macos" ]]; then
                print_status "Check logs with: sudo datadog-agent logs"
            else
                print_status "Check logs with: sudo journalctl -u datadog-agent -f"
            fi
        fi
        
        rm -f "$temp_status"
        exit 1
    fi
    
    # Clean up temporary file
    rm -f "$temp_status"
}

# Function to provide troubleshooting guidance for API key issues
show_troubleshooting_guide() {
    echo
    print_status "=== API Key Troubleshooting Guide ==="
    echo
    print_error "If you're seeing 'API Key invalid' errors, try these steps:"
    echo
    echo "1. Verify your API key is correct:"
    echo "   • Log into your Datadog account"
    echo "   • Go to Organization Settings > API Keys"
    echo "   • Copy the correct API key (32 characters)"
    echo
    echo "2. Verify you're using the correct Datadog site:"
    echo "   • Check your Datadog URL in the browser"
    echo "   • US1: app.datadoghq.com → use datadoghq.com"
    echo "   • US3: us3.datadoghq.com → use us3.datadoghq.com"
    echo "   • US5: us5.datadoghq.com → use us5.datadoghq.com"
    echo "   • EU1: app.datadoghq.eu → use eu1.datadoghq.com"
    echo "   • AP1: ap1.datadoghq.com → use ap1.datadoghq.com"
    echo
    echo "3. If the site is wrong, reconfigure the agent:"
    echo "   • Stop the agent: sudo datadog-agent stop"
    echo "   • Edit the config: sudo nano $DATADOG_CONF_DIR/datadog.yaml"
    echo "   • Change the 'site:' line to match your account"
    echo "   • Restart: sudo datadog-agent start"
    echo
    echo "4. Test the configuration:"
    echo "   • Run: sudo datadog-agent status"
    echo "   • Look for 'API Key valid: True'"
    echo
}

# Function to show Node.js integration instructions
show_nodejs_instructions() {
    echo
    print_status "=== Node.js Application Integration ==="
    echo "Add this to the very beginning of your app.js file:"
    echo
    echo "const tracer = require('dd-trace').init({"
    echo "  service: '$SERVICE_NAME',"
    echo "  env: '$ENVIRONMENT',"
    echo "  version: '1.0.0'"
    echo "});"
    echo
    echo "Then install the tracing library:"
    echo "npm install dd-trace"
    echo
    echo "For PM2, you can also set these environment variables:"
    echo "DD_SERVICE=$SERVICE_NAME"
    echo "DD_ENV=$ENVIRONMENT"
    echo "DD_VERSION=1.0.0"
}

# Main execution
main() {
    echo
    print_status "=== Datadog Agent Installation Script for Ubuntu 22 and macOS ==="
    echo
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Detect OS and set appropriate commands
    detect_os
    
    # Check system requirements
    check_requirements
    
    # Check if already installed
    ALREADY_INSTALLED=0
    if check_datadog_installed; then
        ALREADY_INSTALLED=1
    fi
    
    # Get user inputs (or validate provided arguments)
    get_user_inputs
    
    # Install if not already installed
    if [[ $ALREADY_INSTALLED -eq 0 ]]; then
        install_datadog
    fi
    
    # Configure Datadog
    configure_datadog
    configure_logs
    set_permissions
    fix_log_permissions
    validate_configuration
    start_services
    verify_installation
    show_nodejs_instructions
    
    echo
    print_success "🎉 Datadog agent installation and configuration completed!"
    print_status "Visit your Datadog dashboard to see metrics and logs."
}

# Run main function
main "$@" 