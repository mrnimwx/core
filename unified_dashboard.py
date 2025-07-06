#!/usr/bin/env python3
"""
Unified Network Dashboard
========================
Combined Connection Monitor and Network Dashboard
Shows HAProxy status, connections, TLS info, and comprehensive system monitoring
with password protection on port 2020
"""

import ssl
import os
import sys
import json
import subprocess
import time
import hashlib
import base64
import threading
from urllib.parse import urlparse, parse_qs
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn
from datetime import datetime

# Configuration
DASHBOARD_PASSWORD = "admin"  # Default password, can be changed via environment
DASHBOARD_PORT = 2020

class UnifiedDashboardHandler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    
    def log_message(self, format, *args):
        print(f"[{self.address_string()}] {format % args}")
    
    def do_GET(self):
        parsed_url = urlparse(self.path)
        path = parsed_url.path
        query_params = parse_qs(parsed_url.query)
        
        # Check authentication
        if not self._check_auth():
            self._request_auth()
            return
        
        # Set common headers
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
        self.send_header('Pragma', 'no-cache')
        self.send_header('Expires', '0')
        
        if path == '/' or path == '/dashboard':
            self._serve_dashboard()
        elif path == '/api/status':
            self._serve_api_status()
        elif path == '/api/connections':
            self._serve_api_connections()
        elif path == '/api/haproxy':
            self._serve_api_haproxy()
        elif path == '/api/services':
            self._serve_api_services()
        elif path == '/api/system':
            self._serve_api_system()
        else:
            self.send_error(404, "Not Found")
    
    def _check_auth(self):
        """Check HTTP Basic Authentication"""
        auth_header = self.headers.get('Authorization')
        if not auth_header:
            return False
        
        try:
            auth_type, credentials = auth_header.split(' ', 1)
            if auth_type.lower() != 'basic':
                return False
            
            decoded = base64.b64decode(credentials).decode('utf-8')
            username, password = decoded.split(':', 1)
            
            # Simple authentication - username can be anything, check password
            expected_password = os.environ.get('DASHBOARD_PASSWORD', DASHBOARD_PASSWORD)
            return password == expected_password
        except:
            return False
    
    def _request_auth(self):
        """Request HTTP Basic Authentication"""
        self.send_response(401)
        self.send_header('WWW-Authenticate', 'Basic realm="Unified Network Dashboard"')
        self.send_header('Content-Type', 'text/html')
        self.end_headers()
        
        html = '''
        <!DOCTYPE html>
        <html>
        <head>
            <title>Authentication Required</title>
            <style>
                body { font-family: Arial, sans-serif; text-align: center; margin-top: 100px; background: #f5f7fa; }
                .auth-box { max-width: 400px; margin: 0 auto; padding: 30px; background: white; border-radius: 10px; box-shadow: 0 5px 15px rgba(0,0,0,0.1); }
                .icon { font-size: 3em; color: #3498db; margin-bottom: 20px; }
            </style>
        </head>
        <body>
            <div class="auth-box">
                <div class="icon">🔒</div>
                <h2>Authentication Required</h2>
                <p>Please enter your credentials to access the Unified Network Dashboard.</p>
                <p><strong>Default Password:</strong> admin</p>
            </div>
        </body>
        </html>
        '''
        self.wfile.write(html.encode())
    
    def _serve_dashboard(self):
        """Serve the unified dashboard HTML"""
        html = self._get_dashboard_html()
        self.send_header('Content-Type', 'text/html')
        self.send_header('Content-Length', str(len(html)))
        self.end_headers()
        self.wfile.write(html.encode())
    
    def _serve_api_status(self):
        """Serve general system status"""
        try:
            server_info = self._get_server_info()
            status = {
                'timestamp': datetime.now().isoformat(),
                'server_time': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
                'uptime': self._get_uptime(),
                'load_average': self._get_load_average(),
                'tls_info': self._get_tls_info(),
                'server_info': server_info,
                'server_ip': server_info.get('ip', server_info['display']),  # Keep for backward compatibility
                'server_domain': server_info.get('domain'),
                'server_display': server_info['display']
            }
            self._send_json(status)
        except Exception as e:
            self._send_json({'error': str(e)})
    
    def _serve_api_connections(self):
        """Serve connection statistics"""
        try:
            connections = {
                'total_connections': self._get_total_connections(),
                'port_details': self._get_port_connections(),
                'active_sessions': self._get_active_sessions(),
                'listening_ports': self._get_listened_ports()
            }
            self._send_json(connections)
        except Exception as e:
            self._send_json({'error': str(e)})
    
    def _serve_api_haproxy(self):
        """Serve HAProxy information"""
        try:
            haproxy_info = {
                'status': self._get_haproxy_status(),
                'configuration': self._get_haproxy_config(),
                'listened_ports': self._get_haproxy_ports(),
                'backends': self._get_backend_status()
            }
            self._send_json(haproxy_info)
        except Exception as e:
            self._send_json({'error': str(e)})
    
    def _serve_api_services(self):
        """Serve service information"""
        try:
            services = {
                'haproxy': self._get_service_status('haproxy'),
                'x-ui': self._get_service_status('x-ui'),
                'dashboard': self._get_service_status('dashboard'),
                'connection-monitor': self._get_service_status('connection-monitor')
            }
            self._send_json(services)
        except Exception as e:
            self._send_json({'error': str(e)})
    
    def _serve_api_system(self):
        """Serve system information"""
        try:
            system = {
                'cpu_usage': self._get_cpu_usage(),
                'memory_usage': self._get_memory_usage(),
                'disk_usage': self._get_disk_usage(),
                'network_stats': self._get_network_stats()
            }
            self._send_json(system)
        except Exception as e:
            self._send_json({'error': str(e)})
    
    def _send_json(self, data):
        """Send JSON response"""
        json_data = json.dumps(data, indent=2)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(json_data)))
        self.end_headers()
        self.wfile.write(json_data.encode())
    
    def _get_server_info(self):
        """Get server domain and IP address"""
        try:
            # Try to get domain from SSL certificates first
            domain = self._get_server_domain()
            if domain and domain != "Unknown":
                return {'domain': domain, 'display': domain}
            
            # Fallback to IP address
            result = subprocess.run(['curl', '-s', 'ifconfig.me'], capture_output=True, text=True, timeout=5)
            ip = result.stdout.strip()
            return {'domain': None, 'display': ip, 'ip': ip}
        except:
            return {'domain': None, 'display': "Unknown", 'ip': "Unknown"}
    
    def _get_server_domain(self):
        """Get server domain from SSL certificates"""
        try:
            # Check /root/cert directory for domain
            if os.path.exists('/root/cert'):
                for item in os.listdir('/root/cert'):
                    item_path = os.path.join('/root/cert', item)
                    if os.path.isdir(item_path):
                        # Check if it has SSL certificates
                        cert_file = os.path.join(item_path, 'fullchain.pem')
                        key_file = os.path.join(item_path, 'privkey.pem')
                        if os.path.exists(cert_file) and os.path.exists(key_file):
                            return item  # Return domain name
            
            # Try to get from hostname
            hostname = subprocess.run(['hostname', '-f'], capture_output=True, text=True, timeout=5)
            if hostname.returncode == 0 and '.' in hostname.stdout.strip():
                return hostname.stdout.strip()
                
            return "Unknown"
        except:
            return "Unknown"
    
    def _get_uptime(self):
        """Get system uptime"""
        try:
            with open('/proc/uptime', 'r') as f:
                uptime_seconds = float(f.readline().split()[0])
                days = int(uptime_seconds // 86400)
                hours = int((uptime_seconds % 86400) // 3600)
                minutes = int((uptime_seconds % 3600) // 60)
                return f"{days}d {hours}h {minutes}m"
        except:
            return "Unknown"
    
    def _get_load_average(self):
        """Get system load average"""
        try:
            with open('/proc/loadavg', 'r') as f:
                load = f.readline().split()[:3]
                return {'1min': load[0], '5min': load[1], '15min': load[2]}
        except:
            return {'1min': 'N/A', '5min': 'N/A', '15min': 'N/A'}
    
    def _get_cpu_usage(self):
        """Get CPU usage percentage"""
        try:
            result = subprocess.run(['top', '-bn1'], capture_output=True, text=True, timeout=5)
            for line in result.stdout.split('\n'):
                if 'Cpu(s):' in line:
                    parts = line.split()
                    for part in parts:
                        if 'us' in part:
                            return part.replace('%us,', '')
            return "0"
        except:
            return "Unknown"
    
    def _get_memory_usage(self):
        """Get memory usage"""
        try:
            with open('/proc/meminfo', 'r') as f:
                meminfo = f.read()
                
            total = int([line for line in meminfo.split('\n') if 'MemTotal:' in line][0].split()[1])
            available = int([line for line in meminfo.split('\n') if 'MemAvailable:' in line][0].split()[1])
            used = total - available
            
            return {
                'total': f"{total // 1024} MB",
                'used': f"{used // 1024} MB",
                'available': f"{available // 1024} MB",
                'percentage': f"{(used / total * 100):.1f}%"
            }
        except:
            return {'total': 'N/A', 'used': 'N/A', 'available': 'N/A', 'percentage': 'N/A'}
    
    def _get_disk_usage(self):
        """Get disk usage"""
        try:
            result = subprocess.run(['df', '-h', '/'], capture_output=True, text=True, timeout=5)
            lines = result.stdout.split('\n')
            if len(lines) > 1:
                parts = lines[1].split()
                return {
                    'total': parts[1],
                    'used': parts[2],
                    'available': parts[3],
                    'percentage': parts[4]
                }
        except:
            pass
        return {'total': 'N/A', 'used': 'N/A', 'available': 'N/A', 'percentage': 'N/A'}
    
    def _get_network_stats(self):
        """Get network statistics"""
        try:
            with open('/proc/net/dev', 'r') as f:
                lines = f.readlines()
            
            total_rx = 0
            total_tx = 0
            
            for line in lines[2:]:  # Skip header lines
                parts = line.split()
                if len(parts) >= 10:
                    rx_bytes = int(parts[1])
                    tx_bytes = int(parts[9])
                    total_rx += rx_bytes
                    total_tx += tx_bytes
            
            return {
                'rx_bytes': f"{total_rx // (1024*1024)} MB",
                'tx_bytes': f"{total_tx // (1024*1024)} MB"
            }
        except:
            return {'rx_bytes': 'N/A', 'tx_bytes': 'N/A'}
    
    def _get_tls_info(self):
        """Get TLS certificate information"""
        tls_info = {'certificates': [], 'paths': []}
        
        # Common certificate paths
        cert_paths = [
            '/root/cert',
            '/etc/ssl/certs',
            '/etc/letsencrypt/live'
        ]
        
        for path in cert_paths:
            if os.path.exists(path):
                tls_info['paths'].append(path)
                try:
                    for item in os.listdir(path):
                        item_path = os.path.join(path, item)
                        if os.path.isdir(item_path):
                            cert_files = []
                            for file in os.listdir(item_path):
                                if file.endswith(('.pem', '.crt', '.key')):
                                    cert_files.append(file)
                            if cert_files:
                                tls_info['certificates'].append({
                                    'domain': item,
                                    'path': item_path,
                                    'files': cert_files
                                })
                except:
                    pass
        
        return tls_info
    
    def _get_total_connections(self):
        """Get total number of connections"""
        try:
            result = subprocess.run(['ss', '-tuln'], capture_output=True, text=True, timeout=5)
            lines = result.stdout.split('\n')
            return len([line for line in lines if 'LISTEN' in line])
        except:
            return 0
    
    def _get_port_connections(self):
        """Get detailed port connection information"""
        ports = [8080, 8082, 8083, 8084, 8085, 8086, 2020, 3030, 800, 80, 443]
        port_info = {}
        
        for port in ports:
            try:
                # Check if port is listening
                result = subprocess.run(['ss', '-tuln', f'sport = :{port}'], 
                                      capture_output=True, text=True, timeout=5)
                listening = len(result.stdout.split('\n')) > 1
                
                # Get established connections
                result = subprocess.run(['ss', '-tun', f'sport = :{port}'], 
                                      capture_output=True, text=True, timeout=5)
                established = len([line for line in result.stdout.split('\n') if 'ESTAB' in line])
                
                port_info[str(port)] = {
                    'listening': listening,
                    'established_connections': established,
                    'description': self._get_port_description(port)
                }
            except:
                port_info[str(port)] = {
                    'listening': False,
                    'established_connections': 0,
                    'description': self._get_port_description(port)
                }
        
        return port_info
    
    def _get_port_description(self, port):
        """Get description for each port"""
        descriptions = {
            8080: "HAProxy Backend 1",
            8082: "HAProxy Backend 2", 
            8083: "HAProxy Backend 3",
            8084: "HAProxy Backend 4",
            8085: "HAProxy Backend 5",
            8086: "HAProxy Backend 6",
            2020: "Unified Dashboard",
            3030: "Legacy Dashboard",
            800: "X-UI Panel",
            80: "HTTP",
            443: "HTTPS"
        }
        return descriptions.get(port, f"Port {port}")
    
    def _get_active_sessions(self):
        """Get active session count"""
        try:
            result = subprocess.run(['ss', '-tun'], capture_output=True, text=True, timeout=5)
            established = len([line for line in result.stdout.split('\n') if 'ESTAB' in line])
            return established
        except:
            return 0
    
    def _get_listened_ports(self):
        """Get all listened ports"""
        try:
            result = subprocess.run(['ss', '-tuln'], capture_output=True, text=True, timeout=5)
            ports = []
            for line in result.stdout.split('\n'):
                if 'LISTEN' in line and ':' in line:
                    try:
                        # Extract port from address like *:8080 or 0.0.0.0:8080
                        parts = line.split()
                        for part in parts:
                            if ':' in part and not part.startswith('['):
                                port = part.split(':')[-1]
                                if port.isdigit():
                                    ports.append(int(port))
                    except:
                        continue
            return sorted(list(set(ports)))
        except:
            return []
    
    def _get_haproxy_status(self):
        """Get HAProxy service status"""
        return self._get_service_status('haproxy')
    
    def _get_service_status(self, service_name):
        """Get service status"""
        try:
            result = subprocess.run(['systemctl', 'is-active', service_name], 
                                  capture_output=True, text=True, timeout=5)
            active = result.stdout.strip() == 'active'
            
            if active:
                # Get detailed status
                status_result = subprocess.run(['systemctl', 'status', service_name, '--no-pager'], 
                                             capture_output=True, text=True, timeout=5)
                return {
                    'active': True,
                    'status': 'running',
                    'details': self._parse_systemctl_output(status_result.stdout)
                }
            else:
                return {'active': False, 'status': 'stopped', 'details': {}}
        except:
            return {'active': False, 'status': 'error', 'details': {}}
    
    def _get_haproxy_config(self):
        """Get HAProxy configuration summary"""
        config_path = '/etc/haproxy/haproxy.cfg'
        config_info = {'path': config_path, 'exists': False, 'frontends': [], 'backends': []}
        
        if os.path.exists(config_path):
            config_info['exists'] = True
            try:
                with open(config_path, 'r') as f:
                    content = f.read()
                    
                    # Parse frontends and backends
                    lines = content.split('\n')
                    for line in lines:
                        line = line.strip()
                        if line.startswith('frontend '):
                            config_info['frontends'].append(line.split()[1])
                        elif line.startswith('backend '):
                            config_info['backends'].append(line.split()[1])
                        elif line.startswith('bind '):
                            # Extract bind ports
                            if 'bind_ports' not in config_info:
                                config_info['bind_ports'] = []
                            if ':' in line:
                                port = line.split(':')[-1].strip()
                                if port.isdigit():
                                    config_info['bind_ports'].append(int(port))
            except:
                pass
        
        return config_info
    
    def _get_haproxy_ports(self):
        """Get HAProxy listening ports"""
        return [8080, 8082, 8083, 8084, 8085, 8086]
    
    def _get_backend_status(self):
        """Get backend server status"""
        config_info = self._get_haproxy_config()
        backends = {}
        
        for backend in config_info.get('backends', []):
            backends[backend] = {
                'status': 'unknown',
                'servers': [],
                'description': f"Backend {backend}"
            }
        
        return backends
    
    def _parse_systemctl_output(self, output):
        """Parse systemctl status output"""
        details = {}
        lines = output.split('\n')
        
        for line in lines:
            if 'Active:' in line:
                details['active_since'] = line.split('since')[-1].strip() if 'since' in line else 'unknown'
            elif 'Main PID:' in line:
                details['pid'] = line.split('Main PID:')[-1].split()[0] if 'Main PID:' in line else 'unknown'
            elif 'Memory:' in line:
                details['memory'] = line.split('Memory:')[-1].strip() if 'Memory:' in line else 'unknown'
        
        return details
    
    def _get_dashboard_html(self):
        """Generate the unified dashboard HTML"""
        return '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Unified Network Dashboard</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
            color: #333;
        }
        
        .container {
            max-width: 1600px;
            margin: 0 auto;
            background: rgba(255, 255, 255, 0.95);
            border-radius: 15px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            overflow: hidden;
        }
        
        .header {
            background: linear-gradient(45deg, #2c3e50, #3498db);
            color: white;
            padding: 30px;
            text-align: center;
        }
        
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 15px;
        }
        
        .header p {
            font-size: 1.2em;
            opacity: 0.9;
        }
        
        .time-display {
            font-size: 1.1em;
            margin-top: 10px;
            font-weight: 300;
        }
        
        .dashboard {
            padding: 30px;
        }
        
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .card {
            background: white;
            border-radius: 10px;
            padding: 20px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.08);
            border-left: 4px solid #3498db;
            transition: transform 0.2s ease;
        }
        
        .card:hover {
            transform: translateY(-2px);
        }
        
        .card.haproxy { border-left-color: #e74c3c; }
        .card.connections { border-left-color: #2ecc71; }
        .card.tls { border-left-color: #f39c12; }
        .card.system { border-left-color: #9b59b6; }
        .card.services { border-left-color: #1abc9c; }
        
        .card-header {
            display: flex;
            align-items: center;
            margin-bottom: 15px;
            gap: 10px;
        }
        
        .card-icon {
            font-size: 1.5em;
            padding: 10px;
            border-radius: 8px;
            color: white;
        }
        
        .card-icon.haproxy { background: #e74c3c; }
        .card-icon.connections { background: #2ecc71; }
        .card-icon.tls { background: #f39c12; }
        .card-icon.system { background: #9b59b6; }
        .card-icon.services { background: #1abc9c; }
        
        .card-title {
            font-size: 1.3em;
            font-weight: 600;
        }
        
        .status-badge {
            display: inline-block;
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 0.85em;
            font-weight: 500;
        }
        
        .status-running {
            background: #d4edda;
            color: #155724;
        }
        
        .status-stopped {
            background: #f8d7da;
            color: #721c24;
        }
        
        .status-unknown {
            background: #fff3cd;
            color: #856404;
        }
        
        .metric {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 8px 0;
            border-bottom: 1px solid #eee;
        }
        
        .metric:last-child {
            border-bottom: none;
        }
        
        .metric-label {
            font-weight: 500;
            color: #666;
        }
        
        .metric-value {
            font-weight: 600;
            color: #2c3e50;
        }
        
        .port-list {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
            gap: 10px;
            margin-top: 10px;
        }
        
        .port-item {
            background: #f8f9fa;
            padding: 10px;
            border-radius: 6px;
            text-align: center;
            border: 2px solid transparent;
        }
        
        .port-item.listening {
            border-color: #2ecc71;
            background: #d4edda;
        }
        
        .port-number {
            font-weight: 600;
            font-size: 1.1em;
        }
        
        .port-description {
            font-size: 0.85em;
            color: #666;
            margin-top: 2px;
        }
        
        .connections-count {
            font-size: 0.8em;
            color: #666;
        }
        
        .refresh-btn {
            background: #3498db;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 6px;
            cursor: pointer;
            font-size: 1em;
            transition: background 0.2s ease;
        }
        
        .refresh-btn:hover {
            background: #2980b9;
        }
        
        .loading {
            opacity: 0.6;
            pointer-events: none;
        }
        
        .error-message {
            color: #e74c3c;
            font-style: italic;
            padding: 10px;
            background: #f8d7da;
            border-radius: 4px;
            margin: 10px 0;
        }
        
        .wide-card {
            grid-column: 1 / -1;
        }
        
        @media (max-width: 768px) {
            .grid {
                grid-template-columns: 1fr;
            }
            
            .header h1 {
                font-size: 2em;
            }
            
            .port-list {
                grid-template-columns: repeat(auto-fit, minmax(100px, 1fr));
            }
        }
    </style>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>
                <i class="fas fa-network-wired"></i>
                Unified Network Dashboard
            </h1>
            <p>Complete monitoring of HAProxy, connections, services, and system resources</p>
            <div class="time-display" id="currentTime"></div>
        </div>
        
        <div class="dashboard">
            <div style="text-align: center; margin-bottom: 20px;">
                <button class="refresh-btn" onclick="refreshAll()">
                    <i class="fas fa-sync-alt"></i> Refresh All
                </button>
            </div>
            
            <div class="grid">
                <!-- HAProxy Status Card -->
                <div class="card haproxy">
                    <div class="card-header">
                        <div class="card-icon haproxy">
                            <i class="fas fa-server"></i>
                        </div>
                        <div class="card-title">HAProxy Status</div>
                    </div>
                    <div id="haproxy-content">
                        <div class="loading">Loading...</div>
                    </div>
                </div>
                
                <!-- Services Status Card -->
                <div class="card services">
                    <div class="card-header">
                        <div class="card-icon services">
                            <i class="fas fa-cogs"></i>
                        </div>
                        <div class="card-title">Services</div>
                    </div>
                    <div id="services-content">
                        <div class="loading">Loading...</div>
                    </div>
                </div>
                
                <!-- Connection Statistics Card -->
                <div class="card connections">
                    <div class="card-header">
                        <div class="card-icon connections">
                            <i class="fas fa-plug"></i>
                        </div>
                        <div class="card-title">Connections</div>
                    </div>
                    <div id="connections-content">
                        <div class="loading">Loading...</div>
                    </div>
                </div>
                
                <!-- TLS Configuration Card -->
                <div class="card tls">
                    <div class="card-header">
                        <div class="card-icon tls">
                            <i class="fas fa-lock"></i>
                        </div>
                        <div class="card-title">TLS Configuration</div>
                    </div>
                    <div id="tls-content">
                        <div class="loading">Loading...</div>
                    </div>
                </div>
                
                <!-- System Information Card -->
                <div class="card system">
                    <div class="card-header">
                        <div class="card-icon system">
                            <i class="fas fa-chart-line"></i>
                        </div>
                        <div class="card-title">System Resources</div>
                    </div>
                    <div id="system-content">
                        <div class="loading">Loading...</div>
                    </div>
                </div>
            </div>
            
            <!-- Port Status Grid -->
            <div class="card wide-card">
                <div class="card-header">
                    <div class="card-icon connections">
                        <i class="fas fa-ethernet"></i>
                    </div>
                    <div class="card-title">Port Status & Connections</div>
                </div>
                <div class="port-list" id="port-status">
                    <div class="loading">Loading ports...</div>
                </div>
            </div>
        </div>
    </div>

    <script>
        // Update current time
        function updateTime() {
            const now = new Date();
            document.getElementById('currentTime').textContent = 
                now.toLocaleString('en-US', {
                    timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
                    year: 'numeric',
                    month: 'long',
                    day: 'numeric',
                    hour: '2-digit',
                    minute: '2-digit',
                    second: '2-digit'
                });
        }
        
        // Fetch and display data
        async function fetchData(endpoint) {
            try {
                const response = await fetch(endpoint);
                if (!response.ok) throw new Error(`HTTP ${response.status}`);
                return await response.json();
            } catch (error) {
                console.error(`Error fetching ${endpoint}:`, error);
                return { error: error.message };
            }
        }
        
        async function updateHAProxyStatus() {
            const data = await fetchData('/api/haproxy');
            const content = document.getElementById('haproxy-content');
            
            if (data.error) {
                content.innerHTML = `<div class="error-message">Error: ${data.error}</div>`;
                return;
            }
            
            const status = data.status || {};
            const config = data.configuration || {};
            
            content.innerHTML = `
                <div class="metric">
                    <span class="metric-label">Service Status</span>
                    <span class="status-badge ${status.active ? 'status-running' : 'status-stopped'}">
                        ${status.active ? 'Running' : 'Stopped'}
                    </span>
                </div>
                <div class="metric">
                    <span class="metric-label">Configuration</span>
                    <span class="metric-value">${config.exists ? 'Found' : 'Missing'}</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Frontends</span>
                    <span class="metric-value">${config.frontends?.length || 0}</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Backends</span>
                    <span class="metric-value">${config.backends?.length || 0}</span>
                </div>
                ${status.details?.pid ? `
                <div class="metric">
                    <span class="metric-label">Process ID</span>
                    <span class="metric-value">${status.details.pid}</span>
                </div>` : ''}
            `;
        }
        
        async function updateServicesStatus() {
            const data = await fetchData('/api/services');
            const content = document.getElementById('services-content');
            
            if (data.error) {
                content.innerHTML = `<div class="error-message">Error: ${data.error}</div>`;
                return;
            }
            
            const services = ['haproxy', 'x-ui', 'dashboard', 'connection-monitor'];
            content.innerHTML = services.map(service => {
                const serviceData = data[service] || {};
                return `
                    <div class="metric">
                        <span class="metric-label">${service.toUpperCase()}</span>
                        <span class="status-badge ${serviceData.active ? 'status-running' : 'status-stopped'}">
                            ${serviceData.active ? 'Running' : 'Stopped'}
                        </span>
                    </div>
                `;
            }).join('');
        }
        
        async function updateConnections() {
            const data = await fetchData('/api/connections');
            const content = document.getElementById('connections-content');
            
            if (data.error) {
                content.innerHTML = `<div class="error-message">Error: ${data.error}</div>`;
                return;
            }
            
            content.innerHTML = `
                <div class="metric">
                    <span class="metric-label">Total Listening Ports</span>
                    <span class="metric-value">${data.total_connections || 0}</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Active Sessions</span>
                    <span class="metric-value">${data.active_sessions || 0}</span>
                </div>
                <div class="metric">
                    <span class="metric-label">All Listening Ports</span>
                    <span class="metric-value">${data.listening_ports?.length || 0}</span>
                </div>
            `;
        }
        
        async function updateTLSInfo() {
            const data = await fetchData('/api/status');
            const content = document.getElementById('tls-content');
            
            if (data.error) {
                content.innerHTML = `<div class="error-message">Error: ${data.error}</div>`;
                return;
            }
            
            const tls = data.tls_info || {};
            
            content.innerHTML = `
                <div class="metric">
                    <span class="metric-label">Certificate Paths</span>
                    <span class="metric-value">${tls.paths?.length || 0}</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Certificates Found</span>
                    <span class="metric-value">${tls.certificates?.length || 0}</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Server</span>
                    <span class="metric-value">${data.server_display || data.server_ip || 'Unknown'}</span>
                </div>
                ${tls.certificates?.map(cert => `
                    <div class="metric">
                        <span class="metric-label">${cert.domain}</span>
                        <span class="metric-value">${cert.files.length} files</span>
                    </div>
                `).join('') || ''}
            `;
        }
        
        async function updateSystemInfo() {
            const systemData = await fetchData('/api/system');
            const statusData = await fetchData('/api/status');
            const content = document.getElementById('system-content');
            
            if (systemData.error || statusData.error) {
                content.innerHTML = `<div class="error-message">Error loading system info</div>`;
                return;
            }
            
            const load = statusData.load_average || {};
            const memory = systemData.memory_usage || {};
            const disk = systemData.disk_usage || {};
            
            content.innerHTML = `
                <div class="metric">
                    <span class="metric-label">Uptime</span>
                    <span class="metric-value">${statusData.uptime || 'Unknown'}</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Load Average</span>
                    <span class="metric-value">${load['1min'] || 'N/A'}</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Memory Usage</span>
                    <span class="metric-value">${memory.percentage || 'N/A'}</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Disk Usage</span>
                    <span class="metric-value">${disk.percentage || 'N/A'}</span>
                </div>
            `;
        }
        
        async function updatePortStatus() {
            const data = await fetchData('/api/connections');
            const content = document.getElementById('port-status');
            
            if (data.error) {
                content.innerHTML = `<div class="error-message">Error: ${data.error}</div>`;
                return;
            }
            
            const ports = data.port_details || {};
            
            content.innerHTML = Object.entries(ports).map(([port, info]) => `
                <div class="port-item ${info.listening ? 'listening' : ''}">
                    <div class="port-number">${port}</div>
                    <div class="port-description">${info.description}</div>
                    <div class="connections-count">
                        ${info.listening ? 'Listening' : 'Not listening'}
                        ${info.established_connections ? ` • ${info.established_connections} conn` : ''}
                    </div>
                </div>
            `).join('');
        }
        
        function refreshAll() {
            const btn = document.querySelector('.refresh-btn');
            btn.classList.add('loading');
            btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Refreshing...';
            
            Promise.all([
                updateHAProxyStatus(),
                updateServicesStatus(),
                updateConnections(),
                updateTLSInfo(),
                updateSystemInfo(),
                updatePortStatus()
            ]).finally(() => {
                btn.classList.remove('loading');
                btn.innerHTML = '<i class="fas fa-sync-alt"></i> Refresh All';
            });
        }
        
        // Initialize
        updateTime();
        setInterval(updateTime, 1000);
        
        // Load initial data
        refreshAll();
        
        // Auto-refresh every 30 seconds
        setInterval(refreshAll, 30000);
    </script>
</body>
</html>
        '''

class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    """Handle requests in a separate thread."""
    daemon_threads = True
    allow_reuse_address = True

def create_ssl_context():
    """Create SSL context for HTTPS"""
    # Check /root/cert directory structure for valid certificates
    if os.path.exists('/root/cert'):
        for item in os.listdir('/root/cert'):
            item_path = os.path.join('/root/cert', item)
            if os.path.isdir(item_path):
                # Check for fullchain.pem and privkey.pem (Let's Encrypt format)
                cert_file = os.path.join(item_path, 'fullchain.pem')
                key_file = os.path.join(item_path, 'privkey.pem')
                
                if os.path.exists(cert_file) and os.path.exists(key_file):
                    try:
                        # Verify certificate files are valid
                        with open(cert_file, 'r') as f:
                            cert_content = f.read()
                        with open(key_file, 'r') as f:
                            key_content = f.read()
                        
                        # Check if files have content
                        if not cert_content.strip() or not key_content.strip():
                            print(f"⚠️  Empty certificate files in {item_path}")
                            continue
                        
                        # Create SSL context
                        context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
                        context.minimum_version = ssl.TLSVersion.TLSv1_2
                        
                        # Load certificate chain
                        context.load_cert_chain(cert_file, key_file)
                        
                        print(f"✅ Using SSL certificate: {cert_file}")
                        print(f"✅ Using SSL private key: {key_file}")
                        return context
                        
                    except ssl.SSLError as e:
                        print(f"⚠️  SSL error loading {cert_file}: {e}")
                        continue
                    except Exception as e:
                        print(f"⚠️  Failed to load {cert_file}: {e}")
                        continue
    
    print("⚠️  No valid SSL certificates found")
    return None

def main():
    """Main server function"""
    print("🚀 Starting Unified Network Dashboard...")
    
    # Get configuration from environment
    port = int(os.environ.get('DASHBOARD_PORT', DASHBOARD_PORT))
    password = os.environ.get('DASHBOARD_PASSWORD', DASHBOARD_PASSWORD)
    
    print(f"📊 Dashboard will be available on port {port}")
    print(f"🔒 Authentication required (password: {password})")
    
    # Check for SSL certificates
    ssl_context = create_ssl_context()
    use_ssl = ssl_context is not None
    
    # Create and configure server
    server = ThreadedHTTPServer(('0.0.0.0', port), UnifiedDashboardHandler)
    
    # Get server info for display
    def get_server_info_static():
        """Get server info without creating a handler instance"""
        try:
            # Try to get domain from certificate directory
            domain = None
            if os.path.exists('/root/cert'):
                for item in os.listdir('/root/cert'):
                    item_path = os.path.join('/root/cert', item)
                    if os.path.isdir(item_path):
                        if os.path.exists(os.path.join(item_path, 'fullchain.pem')):
                            domain = item
                            break
            
            if domain:
                return {'display': domain, 'domain': domain, 'ip': None}
            else:
                # Get server IP
                result = subprocess.run(['curl', '-s', 'ifconfig.me'], capture_output=True, text=True, timeout=5)
                server_ip = result.stdout.strip() if result.returncode == 0 else 'localhost'
                return {'display': server_ip, 'domain': None, 'ip': server_ip}
        except:
            return {'display': 'localhost', 'domain': None, 'ip': 'localhost'}
    
    server_info = get_server_info_static()
    server_display = server_info['display']
    
    if use_ssl:
        try:
            server.socket = ssl_context.wrap_socket(server.socket, server_side=True)
            print(f"🔒 HTTPS server running on port {port}")
            print(f"🌐 Dashboard URL: https://{server_display}:{port}/")
        except Exception as e:
            print(f"⚠️  Failed to enable SSL: {e}")
            print(f"🌐 Falling back to HTTP mode")
            print(f"🌐 Dashboard URL: http://{server_display}:{port}/")
            use_ssl = False
    else:
        print(f"🌐 HTTP server running on port {port}")
        print(f"🌐 Dashboard URL: http://{server_display}:{port}/")
        print("⚠️  No SSL certificate found - running in HTTP mode")
    
    print(f"🔑 Default credentials: any-username / {password}")
    print("ℹ️  Auto-refresh every 30 seconds")
    print("🔄 Press Ctrl+C to stop")
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n🛑 Shutting down Unified Network Dashboard...")
        server.shutdown()
        print("✅ Dashboard stopped")

if __name__ == '__main__':
    main() 