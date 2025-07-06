#!/usr/bin/env python3
"""
Simple Connection Monitor Dashboard
==================================
Shows HAProxy status, connections, and TLS configuration
with password protection
"""

import ssl
import os
import sys
import json
import subprocess
import time
import hashlib
import base64
from urllib.parse import urlparse, parse_qs
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn
from datetime import datetime

# Configuration
MONITOR_PASSWORD = "admin123"  # Default password, can be changed via environment
MONITOR_PORT = 2020

class ConnectionMonitorHandler(BaseHTTPRequestHandler):
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
            expected_password = os.environ.get('MONITOR_PASSWORD', MONITOR_PASSWORD)
            return password == expected_password
        except:
            return False
    
    def _request_auth(self):
        """Request HTTP Basic Authentication"""
        self.send_response(401)
        self.send_header('WWW-Authenticate', 'Basic realm="Connection Monitor"')
        self.send_header('Content-Type', 'text/html')
        self.end_headers()
        
        html = '''
        <!DOCTYPE html>
        <html>
        <head>
            <title>Authentication Required</title>
            <style>
                body { font-family: Arial, sans-serif; text-align: center; margin-top: 100px; }
                .auth-box { max-width: 400px; margin: 0 auto; padding: 20px; border: 1px solid #ddd; border-radius: 8px; }
            </style>
        </head>
        <body>
            <div class="auth-box">
                <h2>🔒 Authentication Required</h2>
                <p>Please enter your credentials to access the Connection Monitor Dashboard.</p>
                <p><strong>Default Password:</strong> admin123</p>
            </div>
        </body>
        </html>
        '''
        self.wfile.write(html.encode())
    
    def _serve_dashboard(self):
        """Serve the main dashboard HTML"""
        html = self._get_dashboard_html()
        self.send_header('Content-Type', 'text/html')
        self.send_header('Content-Length', str(len(html)))
        self.end_headers()
        self.wfile.write(html.encode())
    
    def _serve_api_status(self):
        """Serve general system status"""
        try:
            status = {
                'timestamp': datetime.now().isoformat(),
                'server_time': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
                'uptime': self._get_uptime(),
                'load_average': self._get_load_average(),
                'tls_info': self._get_tls_info()
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
                'active_sessions': self._get_active_sessions()
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
                'listened_ports': self._get_listened_ports(),
                'backends': self._get_backend_status()
            }
            self._send_json(haproxy_info)
        except Exception as e:
            self._send_json({'error': str(e)})
    
    def _send_json(self, data):
        """Send JSON response"""
        json_data = json.dumps(data, indent=2)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(json_data)))
        self.end_headers()
        self.wfile.write(json_data.encode())
    
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
        ports = [8080, 8082, 8083, 8084, 8085, 8086, 2020]
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
            2020: "Connection Monitor"
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
    
    def _get_haproxy_status(self):
        """Get HAProxy service status"""
        try:
            result = subprocess.run(['systemctl', 'is-active', 'haproxy'], 
                                  capture_output=True, text=True, timeout=5)
            active = result.stdout.strip() == 'active'
            
            if active:
                # Get detailed status
                status_result = subprocess.run(['systemctl', 'status', 'haproxy', '--no-pager'], 
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
    
    def _get_backend_status(self):
        """Get backend server status"""
        # This would typically require HAProxy stats socket
        # For now, return basic info from config
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
        """Generate the dashboard HTML"""
        return '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Connection Monitor Dashboard</title>
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
            max-width: 1400px;
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
                Connection Monitor Dashboard
            </h1>
            <p>Real-time monitoring of HAProxy, connections, and TLS configuration</p>
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
                        <div class="card-title">System Info</div>
                    </div>
                    <div id="system-content">
                        <div class="loading">Loading...</div>
                    </div>
                </div>
            </div>
            
            <!-- Port Status Grid -->
            <div class="card">
                <div class="card-header">
                    <div class="card-icon connections">
                        <i class="fas fa-ethernet"></i>
                    </div>
                    <div class="card-title">Port Status</div>
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
                ${tls.certificates?.map(cert => `
                    <div class="metric">
                        <span class="metric-label">${cert.domain}</span>
                        <span class="metric-value">${cert.files.length} files</span>
                    </div>
                `).join('') || ''}
            `;
        }
        
        async function updateSystemInfo() {
            const data = await fetchData('/api/status');
            const content = document.getElementById('system-content');
            
            if (data.error) {
                content.innerHTML = `<div class="error-message">Error: ${data.error}</div>`;
                return;
            }
            
            const load = data.load_average || {};
            
            content.innerHTML = `
                <div class="metric">
                    <span class="metric-label">Server Time</span>
                    <span class="metric-value">${data.server_time || 'Unknown'}</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Uptime</span>
                    <span class="metric-value">${data.uptime || 'Unknown'}</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Load Average</span>
                    <span class="metric-value">${load['1min'] || 'N/A'}</span>
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
    context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
    
    # Look for certificates in common locations
    cert_paths = []
    key_paths = []
    
    # Check /root/cert directory structure
    if os.path.exists('/root/cert'):
        for item in os.listdir('/root/cert'):
            item_path = os.path.join('/root/cert', item)
            if os.path.isdir(item_path):
                # Check for fullchain.pem and privkey.pem (Let's Encrypt format)
                cert_file = os.path.join(item_path, 'fullchain.pem')
                key_file = os.path.join(item_path, 'privkey.pem')
                if os.path.exists(cert_file) and os.path.exists(key_file):
                    cert_paths.append(cert_file)
                    key_paths.append(key_file)
                    break
    
    # Fallback paths
    fallback_certs = ['/root/cert/server.crt', '/root/cert/server.pem']
    fallback_keys = ['/root/cert/server.key', '/root/cert/private.key']
    
    cert_paths.extend(fallback_certs)
    key_paths.extend(fallback_keys)
    
    # Find working certificate pair
    for cert_path in cert_paths:
        for key_path in key_paths:
            if os.path.exists(cert_path) and os.path.exists(key_path):
                try:
                    context.load_cert_chain(cert_path, key_path)
                    print(f"✅ Using SSL certificate: {cert_path}")
                    return context
                except Exception as e:
                    print(f"⚠️  Failed to load {cert_path}: {e}")
                    continue
    
    return None

def main():
    """Main server function"""
    print("🚀 Starting Connection Monitor Dashboard...")
    
    # Get configuration from environment
    port = int(os.environ.get('MONITOR_PORT', MONITOR_PORT))
    password = os.environ.get('MONITOR_PASSWORD', MONITOR_PASSWORD)
    
    print(f"📊 Dashboard will be available on port {port}")
    print(f"🔒 Authentication required (password: {password})")
    
    # Check for SSL certificates
    ssl_context = create_ssl_context()
    use_ssl = ssl_context is not None
    
    # Create and configure server
    server = ThreadedHTTPServer(('0.0.0.0', port), ConnectionMonitorHandler)
    
    if use_ssl:
        server.socket = ssl_context.wrap_socket(server.socket, server_side=True)
        print(f"🔒 HTTPS server running on port {port}")
        print(f"🌐 Dashboard URL: https://your-domain.com:{port}/")
    else:
        print(f"🌐 HTTP server running on port {port}")
        print(f"🌐 Dashboard URL: http://your-server-ip:{port}/")
        print("⚠️  No SSL certificate found - running in HTTP mode")
    
    print(f"🔑 Default credentials: any-username / {password}")
    print("ℹ️  Auto-refresh every 30 seconds")
    print("🔄 Press Ctrl+C to stop")
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n🛑 Shutting down Connection Monitor Dashboard...")
        server.shutdown()
        print("✅ Dashboard stopped")

if __name__ == '__main__':
    main() 