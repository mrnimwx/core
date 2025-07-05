# Network Proxy & TLS Testing Suite

A comprehensive network infrastructure tool that provides HAProxy load balancing, HTTPS throughput testing, and X-UI panel management capabilities.

## Features

### HAProxy Load Balancer
- TCP proxy configuration for ports 8080-8086
- Automatic backend server routing
- Easy installation and configuration

### TLS Throughput Tester
- HTTPS server for bandwidth testing
- SSL certificate auto-detection
- Configurable data sizes for testing
- CORS-enabled for web-based testing

### X-UI Panel (3x-ui)
- Web-based Xray management panel
- Automated installation with version 2.3.5
- Pre-configured with optimized settings
- Username/password: nimwx/nimwx
- Runs on port 80

### Network Dashboard
- Real-time monitoring web interface
- Service status monitoring (HAProxy, TLS Tester, X-UI)
- Traffic statistics for proxy ports 8080-8086
- Auto-refresh every 30 seconds
- Runs on port 3030

## Quick Installation

### Complete Suite (Recommended)
```bash
sudo ./install-all.sh
```

### Individual Components

#### HAProxy Setup
```bash
sudo ./install-haproxy.sh
```

#### TLS Tester Setup
```bash
sudo ./install-tlstest.sh
```

#### X-UI Panel Setup
```bash
sudo ./install-xui.sh
```

#### X-UI Interactive Setup
```bash
sudo ./install-xui-interactive.sh
```

#### Network Dashboard
```bash
sudo ./install-dashboard.sh
```

## Manual Installation

1. Clone this repository
2. Run the appropriate installation script for your needs
3. Configure as needed

## Usage

- **HAProxy**: Listens on ports 8080-8086 and forwards to configured backends
- **TLS Tester**: Runs on port 2020, access via `https://yourdomain.com:2020/?size=<bytes>`
- **X-UI Panel**: Web interface on port 80, login with `nimwx/nimwx`
- **Dashboard**: Monitoring interface on port 3030, access via `http://your-server-ip:3030/`

## Management

### Service Status
- HAProxy: `systemctl status haproxy`
- TLS Tester: `systemctl status throughput-test`
- X-UI Panel: `systemctl status x-ui`
- Dashboard: `systemctl status dashboard`

### View Logs
- HAProxy: `journalctl -u haproxy -f`
- TLS Tester: `journalctl -u throughput-test -f`
- X-UI Panel: `journalctl -u x-ui -f`
- Dashboard: `journalctl -u dashboard -f`

### X-UI Management
- Access panel: `http://your-server-ip:80/`
- Management menu: `x-ui`
- Start/Stop: `x-ui start` / `x-ui stop`

## Uninstallation

- TLS Tester: `./uninstall-tlstest.sh`
- X-UI Panel: `./uninstall-xui.sh`
- Dashboard: `./uninstall-dashboard.sh` 