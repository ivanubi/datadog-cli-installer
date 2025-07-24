# Datadog Agent Installation Script

A comprehensive shell script for automated installation and configuration of Datadog Agent with APM, distributed tracing, and log collection support for Ubuntu 22.04 and macOS systems.

## 🚀 Features

- ✅ **Cross-platform Support** - Works on Ubuntu 22.04 and macOS
- ✅ **Interactive & Non-interactive Modes** - Flexible usage options
- ✅ **Automatic Installation Check** - Detects existing Datadog installations
- ✅ **Complete APM Setup** - Enables Application Performance Monitoring
- ✅ **Distributed Tracing** - Configures trace collection and analysis
- ✅ **Log Collection** - Monitors all .log files in specified directories
- ✅ **Node.js Integration** - Pre-configured for Express/PM2 applications
- ✅ **PM2 Integration** - Defaults to PM2 log directories
- ✅ **Environment Support** - Handles development and production environments
- ✅ **Validation & Error Handling** - Comprehensive checks and user feedback

## 📋 Prerequisites

- **Operating System**: Ubuntu 22.04 LTS or macOS
- **User Privileges**: User with sudo privileges (do not run as root)
- **Network**: Internet connection for downloading packages
- **Datadog Account**: Valid Datadog API key (32 characters)

## 🎯 Usage

### Interactive Mode (Recommended)

Run the script without arguments to use the interactive mode:

```bash
./install-datadog.sh
```

The script will prompt you for:
- Datadog API Key (input hidden for security)
- Logs directory path (default: `~/.pm2/logs`)
- Service name for monitoring
- Environment (development/production)
- Node.js application port (default: 3000)
- Datadog site region

### Non-Interactive Mode

Provide all arguments via command line for automated installations:

```bash
./install-datadog.sh \
  --api-key your_32_char_api_key_here \
  --logs-dir /var/log/myapp \
  --service-name myapp \
  --environment production \
  --port 8080 \
  --site datadoghq.com
```

### Mixed Mode

Provide some arguments and get prompted for the rest:

```bash
./install-datadog.sh \
  --api-key your_api_key_here \
  --environment production \
  --site eu1.datadoghq.com
```

## 🔧 Command Line Options

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--api-key` | `-k` | Datadog API Key (32 characters) | Interactive prompt |
| `--logs-dir` | `-l` | Path to logs directory | `~/.pm2/logs` |
| `--service-name` | `-s` | Service name for monitoring | Interactive prompt |
| `--environment` | `-e` | Environment (development\|production) | Interactive prompt |
| `--port` | `-p` | Node.js application port | `3000` |
| `--site` | `-t` | Datadog site region | `datadoghq.com` |
| `--help` | `-h` | Show help message | - |

### Supported Datadog Sites

- `datadoghq.com` (US1 - Default)
- `us3.datadoghq.com` (US3)
- `us5.datadoghq.com` (US5)
- `eu1.datadoghq.com` (Europe)
- `ap1.datadoghq.com` (Asia Pacific)

## 📂 What the Script Does

### 1. System Validation
- Detects operating system (Ubuntu 22.04 or macOS)
- Checks for required system utilities
- Verifies user permissions (non-root with sudo)
- Validates internet connectivity

### 2. Installation Check
- Detects existing Datadog Agent installations
- Checks service status with `datadog-agent status`
- Offers reconfiguration option for existing installations

### 3. Datadog Agent Installation
- Downloads and installs Datadog Agent 7 using official installation script
- Handles different package managers (apt for Ubuntu, brew for macOS)
- Verifies successful installation

### 4. Configuration Setup

#### Main Agent Configuration (`/etc/datadog-agent/datadog.yaml`)
- API key configuration
- Site/region settings
- Hostname and tags
- APM and tracing enablement
- Log collection activation

#### APM Configuration
- Enables Application Performance Monitoring
- Configures trace agent settings
- Sets up distributed tracing
- Optimizes for Node.js applications

#### Log Collection Setup
- Configures log file monitoring
- Sets up log parsing rules
- Creates service-specific log configurations
- Handles PM2 log integration

### 5. Permissions & Services
- Sets appropriate file permissions
- Configures log directory access
- Starts Datadog Agent services
- Validates service health

### 6. Verification
- Tests agent connectivity to Datadog
- Validates configuration files
- Confirms log collection setup
- Provides status report

## 🔗 Node.js Integration

After installation, integrate Datadog tracing in your Node.js application:

### 1. Install the tracing library
```bash
npm install dd-trace
```

### 2. Initialize at the top of your main file
```javascript
const tracer = require('dd-trace').init({
  service: 'your-service-name',
  env: 'production',
  version: '1.0.0'
});
```

### 3. For PM2 applications, set environment variables
```bash
export DD_SERVICE=your-service-name
export DD_ENV=production
export DD_VERSION=1.0.0
```

## 🔍 Troubleshooting

### Common Issues

1. **Permission Denied**
   - Ensure you're not running as root
   - User must have sudo privileges

2. **API Key Validation Failed**
   - Verify API key is exactly 32 characters
   - Check for trailing spaces or special characters

3. **Logs Directory Not Found**
   - Verify the path exists and is accessible
   - For PM2 apps: `~/.pm2/logs` or `/home/user/.pm2/logs`

4. **Agent Not Starting**
   - Check system logs: `sudo journalctl -u datadog-agent`
   - Validate configuration: `sudo datadog-agent configcheck`

### Validation Commands

```bash
# Check agent status
sudo datadog-agent status

# Validate configuration
sudo datadog-agent configcheck

# Test connectivity
sudo datadog-agent diagnose

# View logs
sudo tail -f /var/log/datadog/agent.log
```

## 📁 Generated Files & Locations

### Configuration Files
- `/etc/datadog-agent/datadog.yaml` - Main configuration
- `/etc/datadog-agent/conf.d/apm.yaml` - APM settings
- `/etc/datadog-agent/conf.d/logs.yaml` - Log collection config

### Log Files
- `/var/log/datadog/agent.log` - Agent logs
- `/var/log/datadog/trace-agent.log` - APM trace logs

## 🔄 Uninstallation

To remove Datadog Agent:

### Ubuntu
```bash
sudo apt-get remove datadog-agent
sudo rm -rf /etc/datadog-agent
sudo rm -rf /var/log/datadog
```

### macOS
```bash
sudo launchctl unload -w /Library/LaunchDaemons/com.datadoghq.agent.plist
sudo rm -rf /opt/datadog-agent
sudo rm -rf /usr/local/bin/datadog-agent
sudo rm /Library/LaunchDaemons/com.datadoghq.agent.plist
```

## 📜 License

This script is provided as-is for Datadog Agent installation and configuration. Please refer to Datadog's official documentation and terms of service.

## 🤝 Contributing

For issues or improvements, please:
1. Check existing Datadog documentation
2. Test changes on supported platforms
3. Follow shell scripting best practices
4. Include appropriate error handling

## 📚 Additional Resources

- [Datadog Agent Documentation](https://docs.datadoghq.com/agent/)
- [APM for Node.js](https://docs.datadoghq.com/tracing/setup_overview/setup/nodejs/)
- [Log Collection](https://docs.datadoghq.com/logs/log_collection/)
- [PM2 Integration](https://docs.datadoghq.com/integrations/pm2/)
