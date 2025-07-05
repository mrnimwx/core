#!/usr/bin/env python3
import http.server
import socketserver
import json
import subprocess
import re
import time
import threading
from datetime import datetime
from urllib.parse import urlparse, parse_qs

class DashboardHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
    
    def do_GET(self):
        if self.path == '/':
            self.serve_dashboard()
        elif self.path == '/api/status':
            self.serve_api_status()
        elif self.path == '/api/traffic':
            self.serve_api_traffic()
        else:
            self.send_error(404)
    
    def serve_dashboard(self):
        html_content = self.get_dashboard_html()
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.send_header('Content-Length', str(len(html_content)))
        self.end_headers()
        self.wfile.write(html_content.encode())
    
    def serve_api_status(self):
        status_data = self.get_service_status()
        self.send_json_response(status_data)
    
    def serve_api_traffic(self):
        traffic_data = self.get_traffic_stats()
        self.send_json_response(traffic_data)
    
    def send_json_response(self, data):
        json_data = json.dumps(data, indent=2)
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Content-Length', str(len(json_data)))
        self.end_headers()
        self.wfile.write(json_data.encode())
    
    def get_service_status(self):
        services = ['haproxy', 'throughput-test', 'x-ui']
        status = {}
        
        for service in services:
            try:
                result = subprocess.run(['systemctl', 'is-active', service], 
                                      capture_output=True, text=True, timeout=5)
                is_active = result.stdout.strip() == 'active'
                
                if is_active:
                    # Get more detailed status
                    status_result = subprocess.run(['systemctl', 'status', service, '--no-pager'], 
                                                 capture_output=True, text=True, timeout=5)
                    status[service] = {
                        'status': 'running',
                        'active': True,
                        'details': self.parse_service_details(status_result.stdout)
                    }
                else:
                    status[service] = {
                        'status': 'stopped',
                        'active': False,
                        'details': {}
                    }
            except Exception as e:
                status[service] = {
                    'status': 'error',
                    'active': False,
                    'details': {'error': str(e)}
                }
        
        return status
    
    def parse_service_details(self, status_output):
        details = {}
        lines = status_output.split('\n')
        
        for line in lines:
            if 'Active:' in line:
                details['active_since'] = line.split('since')[-1].strip() if 'since' in line else 'unknown'
            elif 'Main PID:' in line:
                details['pid'] = line.split('Main PID:')[-1].split()[0] if 'Main PID:' in line else 'unknown'
            elif 'Memory:' in line:
                details['memory'] = line.split('Memory:')[-1].strip() if 'Memory:' in line else 'unknown'
        
        return details
    
    def get_traffic_stats(self):
        traffic = {}
        ports = [8080, 8082, 8083, 8084, 8085, 8086]
        
        for port in ports:
            traffic[str(port)] = self.get_port_traffic(port)
        
        return traffic
    
    def get_port_traffic(self, port):
        try:
            # Check if port is listening
            netstat_result = subprocess.run(['netstat', '-tuln'], 
                                          capture_output=True, text=True, timeout=5)
            is_listening = f':{port} ' in netstat_result.stdout
            
            # Get connection count
            ss_result = subprocess.run(['ss', '-tuln', f'sport = :{port}'], 
                                     capture_output=True, text=True, timeout=5)
            connections = len(ss_result.stdout.split('\n')) - 1  # Subtract header
            
            # Try to get HAProxy stats if available
            haproxy_stats = self.get_haproxy_stats(port)
            
            return {
                'listening': is_listening,
                'connections': max(0, connections),
                'haproxy_stats': haproxy_stats,
                'last_updated': datetime.now().isoformat()
            }
        except Exception as e:
            return {
                'listening': False,
                'connections': 0,
                'haproxy_stats': {},
                'error': str(e),
                'last_updated': datetime.now().isoformat()
            }
    
    def get_haproxy_stats(self, port):
        try:
            # Try to get HAProxy stats from stats socket or logs
            # This is a simplified version - in production you'd use HAProxy stats socket
            return {
                'backend_status': 'unknown',
                'total_requests': 0,
                'bytes_transferred': 0
            }
        except:
            return {}
    
    def get_dashboard_html(self):
        return '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Network Infrastructure Dashboard</title>
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
        }
        
        .container {
            max-width: 1200px;
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
        }
        
        .header p {
            font-size: 1.2em;
            opacity: 0.9;
        }
        
        .dashboard {
            padding: 30px;
        }
        
        .section {
            margin-bottom: 30px;
        }
        
        .section h2 {
            color: #2c3e50;
            margin-bottom: 20px;
            font-size: 1.8em;
            border-bottom: 3px solid #3498db;
            padding-bottom: 10px;
        }
        
        .services-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .service-card {
            background: white;
            border-radius: 10px;
            padding: 20px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
            border-left: 5px solid #3498db;
        }
        
        .service-card.running {
            border-left-color: #27ae60;
        }
        
        .service-card.stopped {
            border-left-color: #e74c3c;
        }
        
        .service-card.error {
            border-left-color: #f39c12;
        }
        
        .service-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 15px;
        }
        
        .service-name {
            font-size: 1.3em;
            font-weight: bold;
            color: #2c3e50;
        }
        
        .status-badge {
            padding: 5px 15px;
            border-radius: 20px;
            font-size: 0.9em;
            font-weight: bold;
            text-transform: uppercase;
        }
        
        .status-running {
            background: #27ae60;
            color: white;
        }
        
        .status-stopped {
            background: #e74c3c;
            color: white;
        }
        
        .status-error {
            background: #f39c12;
            color: white;
        }
        
        .traffic-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
        }
        
        .port-card {
            background: white;
            border-radius: 8px;
            padding: 15px;
            text-align: center;
            box-shadow: 0 3px 10px rgba(0,0,0,0.1);
        }
        
        .port-number {
            font-size: 1.5em;
            font-weight: bold;
            color: #3498db;
            margin-bottom: 10px;
        }
        
        .port-status {
            margin-bottom: 10px;
        }
        
        .listening {
            color: #27ae60;
            font-weight: bold;
        }
        
        .not-listening {
            color: #e74c3c;
            font-weight: bold;
        }
        
        .connections {
            font-size: 1.2em;
            color: #2c3e50;
        }
        
        .refresh-btn {
            background: #3498db;
            color: white;
            border: none;
            padding: 12px 25px;
            border-radius: 25px;
            cursor: pointer;
            font-size: 1em;
            margin: 20px 0;
            transition: background 0.3s;
        }
        
        .refresh-btn:hover {
            background: #2980b9;
        }
        
        .last-updated {
            text-align: center;
            color: #7f8c8d;
            font-style: italic;
            margin-top: 20px;
        }
        
        .loading {
            text-align: center;
            padding: 20px;
            color: #7f8c8d;
        }
        
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
        
        .spinner {
            display: inline-block;
            width: 20px;
            height: 20px;
            border: 3px solid #f3f3f3;
            border-top: 3px solid #3498db;
            border-radius: 50%;
            animation: spin 1s linear infinite;
            margin-right: 10px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 Network Infrastructure Dashboard</h1>
            <p>Real-time monitoring of HAProxy, TLS Tester, and X-UI services</p>
        </div>
        
        <div class="dashboard">
            <button class="refresh-btn" onclick="refreshData()">🔄 Refresh Data</button>
            
            <div class="section">
                <h2>📊 Service Status</h2>
                <div id="services-container" class="services-grid">
                    <div class="loading">
                        <div class="spinner"></div>
                        Loading service status...
                    </div>
                </div>
            </div>
            
            <div class="section">
                <h2>🌐 Proxy Traffic (Ports 8080-8086)</h2>
                <div id="traffic-container" class="traffic-grid">
                    <div class="loading">
                        <div class="spinner"></div>
                        Loading traffic data...
                    </div>
                </div>
            </div>
            
            <div class="last-updated" id="last-updated">
                Last updated: Loading...
            </div>
        </div>
    </div>

    <script>
        let refreshInterval;
        
        function refreshData() {
            loadServiceStatus();
            loadTrafficData();
            updateLastUpdated();
        }
        
        function loadServiceStatus() {
            document.getElementById('services-container').innerHTML = '<div class="loading"><div class="spinner"></div>Loading service status...</div>';
            
            fetch('/api/status')
                .then(response => response.json())
                .then(data => {
                    displayServiceStatus(data);
                })
                .catch(error => {
                    console.error('Error loading service status:', error);
                    document.getElementById('services-container').innerHTML = '<div class="loading">❌ Error loading service status</div>';
                });
        }
        
        function loadTrafficData() {
            document.getElementById('traffic-container').innerHTML = '<div class="loading"><div class="spinner"></div>Loading traffic data...</div>';
            
            fetch('/api/traffic')
                .then(response => response.json())
                .then(data => {
                    displayTrafficData(data);
                })
                .catch(error => {
                    console.error('Error loading traffic data:', error);
                    document.getElementById('traffic-container').innerHTML = '<div class="loading">❌ Error loading traffic data</div>';
                });
        }
        
        function displayServiceStatus(services) {
            const container = document.getElementById('services-container');
            container.innerHTML = '';
            
            for (const [serviceName, serviceData] of Object.entries(services)) {
                const card = document.createElement('div');
                card.className = `service-card ${serviceData.status}`;
                
                const statusClass = serviceData.active ? 'status-running' : 
                                  serviceData.status === 'error' ? 'status-error' : 'status-stopped';
                
                card.innerHTML = `
                    <div class="service-header">
                        <div class="service-name">${serviceName.toUpperCase()}</div>
                        <div class="status-badge ${statusClass}">${serviceData.status}</div>
                    </div>
                    <div class="service-details">
                        ${serviceData.details.active_since ? `<p><strong>Active since:</strong> ${serviceData.details.active_since}</p>` : ''}
                        ${serviceData.details.pid ? `<p><strong>PID:</strong> ${serviceData.details.pid}</p>` : ''}
                        ${serviceData.details.memory ? `<p><strong>Memory:</strong> ${serviceData.details.memory}</p>` : ''}
                        ${serviceData.details.error ? `<p><strong>Error:</strong> ${serviceData.details.error}</p>` : ''}
                    </div>
                `;
                
                container.appendChild(card);
            }
        }
        
        function displayTrafficData(traffic) {
            const container = document.getElementById('traffic-container');
            container.innerHTML = '';
            
            for (const [port, portData] of Object.entries(traffic)) {
                const card = document.createElement('div');
                card.className = 'port-card';
                
                card.innerHTML = `
                    <div class="port-number">Port ${port}</div>
                    <div class="port-status ${portData.listening ? 'listening' : 'not-listening'}">
                        ${portData.listening ? '🟢 Listening' : '🔴 Not Listening'}
                    </div>
                    <div class="connections">
                        ${portData.connections} connections
                    </div>
                    ${portData.error ? `<div style="color: #e74c3c; font-size: 0.9em; margin-top: 5px;">Error: ${portData.error}</div>` : ''}
                `;
                
                container.appendChild(card);
            }
        }
        
        function updateLastUpdated() {
            const now = new Date();
            document.getElementById('last-updated').textContent = `Last updated: ${now.toLocaleString()}`;
        }
        
        // Auto-refresh every 30 seconds
        function startAutoRefresh() {
            refreshInterval = setInterval(refreshData, 30000);
        }
        
        function stopAutoRefresh() {
            if (refreshInterval) {
                clearInterval(refreshInterval);
            }
        }
        
        // Initial load
        document.addEventListener('DOMContentLoaded', function() {
            refreshData();
            startAutoRefresh();
        });
        
        // Stop auto-refresh when page is hidden
        document.addEventListener('visibilitychange', function() {
            if (document.hidden) {
                stopAutoRefresh();
            } else {
                startAutoRefresh();
            }
        });
    </script>
</body>
</html>
        '''

def main():
    PORT = 3030
    
    print("🚀 Starting Network Infrastructure Dashboard")
    print("=" * 45)
    print(f"📊 Dashboard running on port {PORT}")
    print(f"🌐 Access via: http://localhost:{PORT}/")
    print(f"🔄 Auto-refresh every 30 seconds")
    print("Press Ctrl+C to stop")
    print()
    
    try:
        with socketserver.TCPServer(("", PORT), DashboardHandler) as httpd:
            print(f"✅ Dashboard server started successfully!")
            print(f"📋 Monitoring services: HAProxy, TLS Tester, X-UI")
            print(f"🌐 Monitoring ports: 8080-8086")
            print()
            httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n🛑 Dashboard server stopped")
    except Exception as e:
        print(f"❌ Error starting dashboard: {e}")

if __name__ == "__main__":
    main() 