#!/usr/bin/env python3
"""
Robust Throughput Test Server
============================
Features:
- TCP and HTTP/HTTPS support
- Data loss detection
- Ping measurement
- Concurrent user support
- Comprehensive metrics
"""

import asyncio
import json
import ssl
import os
import sys
import time
import random
import string
import hashlib
import threading
from datetime import datetime
from urllib.parse import urlparse, parse_qs
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn
import socket
import struct

# Global stats
STATS = {
    'active_connections': 0,
    'total_connections': 0,
    'total_bytes_sent': 0,
    'start_time': time.time(),
    'tcp_connections': 0,
    'http_connections': 0
}

class ThroughputStats:
    def __init__(self):
        self.lock = threading.Lock()
        self.reset_stats()
    
    def reset_stats(self):
        with self.lock:
            STATS['active_connections'] = 0
            STATS['total_connections'] = 0
            STATS['total_bytes_sent'] = 0
            STATS['start_time'] = time.time()
            STATS['tcp_connections'] = 0
            STATS['http_connections'] = 0
    
    def increment_connection(self, protocol='http'):
        with self.lock:
            STATS['active_connections'] += 1
            STATS['total_connections'] += 1
            if protocol == 'tcp':
                STATS['tcp_connections'] += 1
            else:
                STATS['http_connections'] += 1
    
    def decrement_connection(self):
        with self.lock:
            STATS['active_connections'] = max(0, STATS['active_connections'] - 1)
    
    def add_bytes(self, bytes_count):
        with self.lock:
            STATS['total_bytes_sent'] += bytes_count
    
    def get_stats(self):
        with self.lock:
            uptime = time.time() - STATS['start_time']
            return {
                **STATS,
                'uptime': uptime,
                'avg_bytes_per_second': STATS['total_bytes_sent'] / uptime if uptime > 0 else 0
            }

stats_manager = ThroughputStats()

class RobustThroughputHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Custom logging with timestamp
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        print(f"[{timestamp}] [{self.address_string()}] {format % args}")
    
    def do_GET(self):
        stats_manager.increment_connection('http')
        try:
            self._handle_get()
        finally:
            stats_manager.decrement_connection()
    
    def do_POST(self):
        stats_manager.increment_connection('http')
        try:
            self._handle_post()
        finally:
            stats_manager.decrement_connection()
    
    def _handle_get(self):
        parsed_url = urlparse(self.path)
        path = parsed_url.path
        query_params = parse_qs(parsed_url.query)
        
        # Set CORS headers
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', '*')
        
        if path == '/stats':
            self._handle_stats()
        elif path == '/ping':
            self._handle_ping()
        elif path == '/test' or path == '/':
            self._handle_throughput_test(query_params)
        else:
            self.send_error(404, "Not Found")
    
    def _handle_post(self):
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length)
        
        try:
            data = json.loads(post_data.decode('utf-8'))
            test_type = data.get('type', 'throughput')
            
            if test_type == 'ping':
                self._handle_ping_test(data)
            elif test_type == 'upload':
                self._handle_upload_test(data)
            elif test_type == 'data_integrity':
                self._handle_data_integrity_test(data)
            else:
                self._handle_throughput_test_post(data)
        except json.JSONDecodeError:
            self.send_error(400, "Invalid JSON")
    
    def _handle_stats(self):
        """Return server statistics"""
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        
        stats = stats_manager.get_stats()
        self.wfile.write(json.dumps(stats, indent=2).encode('utf-8'))
    
    def _handle_ping(self):
        """Handle ping test"""
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        
        response = {
            'timestamp': time.time(),
            'server_time': datetime.now().isoformat(),
            'status': 'pong'
        }
        
        self.wfile.write(json.dumps(response).encode('utf-8'))
    
    def _handle_ping_test(self, data):
        """Handle detailed ping test with client timestamp"""
        client_timestamp = data.get('timestamp', time.time())
        server_timestamp = time.time()
        
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        
        response = {
            'client_timestamp': client_timestamp,
            'server_timestamp': server_timestamp,
            'server_time': datetime.now().isoformat(),
            'round_trip_start': client_timestamp,
            'status': 'pong'
        }
        
        self.wfile.write(json.dumps(response).encode('utf-8'))
    
    def _handle_upload_test(self, data):
        """Handle upload speed test"""
        upload_data = data.get('data', '')
        size = len(upload_data)
        
        # Calculate hash for data integrity
        data_hash = hashlib.sha256(upload_data.encode()).hexdigest()
        
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        
        response = {
            'received_bytes': size,
            'data_hash': data_hash,
            'timestamp': time.time(),
            'status': 'received'
        }
        
        stats_manager.add_bytes(size)
        self.wfile.write(json.dumps(response).encode('utf-8'))
    
    def _handle_data_integrity_test(self, data):
        """Handle data integrity test"""
        test_data = data.get('data', '')
        expected_hash = data.get('hash', '')
        
        # Calculate actual hash
        actual_hash = hashlib.sha256(test_data.encode()).hexdigest()
        
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        
        response = {
            'expected_hash': expected_hash,
            'actual_hash': actual_hash,
            'data_integrity': expected_hash == actual_hash,
            'received_bytes': len(test_data),
            'timestamp': time.time()
        }
        
        self.wfile.write(json.dumps(response).encode('utf-8'))
    
    def _handle_throughput_test(self, query_params):
        """Handle throughput test with data loss detection"""
        # Get parameters
        size = int(query_params.get('size', ['2097152'])[0])  # 2MB default
        chunk_size = int(query_params.get('chunk_size', ['8192'])[0])  # 8KB default
        test_type = query_params.get('type', ['download'])[0]
        include_hash = query_params.get('hash', ['false'])[0].lower() == 'true'
        
        # Generate test data
        if test_type == 'pattern':
            # Generate patterned data for loss detection
            data = self._generate_pattern_data(size)
        else:
            # Generate random data
            data = os.urandom(size)
        
        # Calculate hash if requested
        data_hash = hashlib.sha256(data).hexdigest() if include_hash else None
        
        # Send headers
        self.send_header('Content-Type', 'application/octet-stream')
        self.send_header('Content-Length', str(size))
        self.send_header('X-Test-Type', test_type)
        if data_hash:
            self.send_header('X-Data-Hash', data_hash)
        self.send_header('X-Chunk-Size', str(chunk_size))
        self.send_header('X-Server-Time', str(time.time()))
        self.end_headers()
        
        # Send data in chunks
        bytes_sent = 0
        try:
            for i in range(0, len(data), chunk_size):
                chunk = data[i:i + chunk_size]
                self.wfile.write(chunk)
                bytes_sent += len(chunk)
                
                # Add small delay for large transfers to prevent overwhelming
                if bytes_sent > 1024 * 1024:  # 1MB
                    time.sleep(0.001)  # 1ms delay
            
            stats_manager.add_bytes(bytes_sent)
            
        except (ConnectionResetError, BrokenPipeError):
            # Client disconnected
            pass
    
    def _handle_throughput_test_post(self, data):
        """Handle POST-based throughput test"""
        size = data.get('size', 2097152)
        test_type = data.get('test_type', 'download')
        
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        
        # Generate test data
        if test_type == 'pattern':
            test_data = self._generate_pattern_data(size)
        else:
            test_data = os.urandom(size)
        
        # Calculate hash
        data_hash = hashlib.sha256(test_data).hexdigest()
        
        response = {
            'size': size,
            'hash': data_hash,
            'data': test_data.hex(),  # Send as hex string
            'timestamp': time.time(),
            'server_time': datetime.now().isoformat()
        }
        
        stats_manager.add_bytes(size)
        self.wfile.write(json.dumps(response).encode('utf-8'))
    
    def _generate_pattern_data(self, size):
        """Generate patterned data for loss detection"""
        pattern = b'THROUGHPUT_TEST_PATTERN_'
        pattern_len = len(pattern)
        
        # Calculate how many full patterns we need
        full_patterns = size // pattern_len
        remainder = size % pattern_len
        
        # Generate data
        data = pattern * full_patterns
        if remainder > 0:
            data += pattern[:remainder]
        
        return data
    
    def do_OPTIONS(self):
        """Handle CORS preflight requests"""
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.end_headers()

class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    """Multi-threaded HTTP server for concurrent connections"""
    daemon_threads = True
    allow_reuse_address = True

class TCPThroughputServer:
    """TCP-based throughput server for raw TCP testing"""
    
    def __init__(self, host='0.0.0.0', port=2021):
        self.host = host
        self.port = port
        self.running = False
        self.server_socket = None
    
    async def start(self):
        """Start the TCP server"""
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server_socket.bind((self.host, self.port))
        self.server_socket.listen(100)  # Support up to 100 concurrent connections
        
        self.running = True
        print(f"🚀 TCP Throughput Server listening on {self.host}:{self.port}")
        
        while self.running:
            try:
                client_socket, address = self.server_socket.accept()
                # Handle each client in a separate thread
                threading.Thread(
                    target=self._handle_tcp_client,
                    args=(client_socket, address),
                    daemon=True
                ).start()
            except Exception as e:
                if self.running:
                    print(f"❌ TCP Server error: {e}")
                break
    
    def _handle_tcp_client(self, client_socket, address):
        """Handle TCP client connection"""
        stats_manager.increment_connection('tcp')
        
        try:
            print(f"🔗 TCP connection from {address}")
            
            # Receive command
            command = client_socket.recv(1024).decode('utf-8').strip()
            
            if command.startswith('THROUGHPUT'):
                self._handle_tcp_throughput(client_socket, command)
            elif command.startswith('PING'):
                self._handle_tcp_ping(client_socket, command)
            elif command.startswith('UPLOAD'):
                self._handle_tcp_upload(client_socket, command)
            else:
                client_socket.send(b'ERROR: Unknown command\n')
                
        except Exception as e:
            print(f"❌ TCP client error: {e}")
        finally:
            client_socket.close()
            stats_manager.decrement_connection()
    
    def _handle_tcp_throughput(self, client_socket, command):
        """Handle TCP throughput test"""
        # Parse command: THROUGHPUT <size> [chunk_size]
        parts = command.split()
        size = int(parts[1]) if len(parts) > 1 else 2097152
        chunk_size = int(parts[2]) if len(parts) > 2 else 8192
        
        # Send response header
        header = f"THROUGHPUT_START {size} {chunk_size} {time.time()}\n"
        client_socket.send(header.encode('utf-8'))
        
        # Generate and send data
        data = os.urandom(size)
        data_hash = hashlib.sha256(data).hexdigest()
        
        # Send hash
        client_socket.send(f"HASH {data_hash}\n".encode('utf-8'))
        
        # Send data in chunks
        bytes_sent = 0
        for i in range(0, len(data), chunk_size):
            chunk = data[i:i + chunk_size]
            client_socket.send(chunk)
            bytes_sent += len(chunk)
        
        # Send completion marker
        client_socket.send(b"THROUGHPUT_END\n")
        
        stats_manager.add_bytes(bytes_sent)
        print(f"📊 TCP throughput test completed: {bytes_sent} bytes sent")
    
    def _handle_tcp_ping(self, client_socket, command):
        """Handle TCP ping test"""
        # Parse command: PING [timestamp]
        parts = command.split()
        client_timestamp = float(parts[1]) if len(parts) > 1 else time.time()
        server_timestamp = time.time()
        
        response = f"PONG {client_timestamp} {server_timestamp}\n"
        client_socket.send(response.encode('utf-8'))
    
    def _handle_tcp_upload(self, client_socket, command):
        """Handle TCP upload test"""
        # Parse command: UPLOAD <size>
        parts = command.split()
        expected_size = int(parts[1]) if len(parts) > 1 else 1024
        
        # Send ready signal
        client_socket.send(b"READY\n")
        
        # Receive data
        received_data = b""
        while len(received_data) < expected_size:
            chunk = client_socket.recv(min(8192, expected_size - len(received_data)))
            if not chunk:
                break
            received_data += chunk
        
        # Calculate hash and send response
        data_hash = hashlib.sha256(received_data).hexdigest()
        response = f"UPLOAD_COMPLETE {len(received_data)} {data_hash}\n"
        client_socket.send(response.encode('utf-8'))
        
        stats_manager.add_bytes(len(received_data))
        print(f"📤 TCP upload completed: {len(received_data)} bytes received")
    
    def stop(self):
        """Stop the TCP server"""
        self.running = False
        if self.server_socket:
            self.server_socket.close()

def find_certificates():
    """Auto-detect SSL certificates from /root/cert/ directory"""
    cert_base = "/root/cert"
    
    if not os.path.exists(cert_base):
        return None, None
    
    # Look for certificate directories
    for item in os.listdir(cert_base):
        cert_dir = os.path.join(cert_base, item)
        if os.path.isdir(cert_dir):
            fullchain = os.path.join(cert_dir, "fullchain.pem")
            privkey = os.path.join(cert_dir, "privkey.pem")
            
            if os.path.exists(fullchain) and os.path.exists(privkey):
                print(f"✅ Found certificates for domain: {item}")
                return fullchain, privkey
    
    return None, None

def main():
    HTTP_PORT = 2020
    TCP_PORT = 2021
    
    print("🚀 Starting Robust Throughput Test Server")
    print("==========================================")
    
    # Find SSL certificates
    cert_file, key_file = find_certificates()
    
    if not cert_file or not key_file:
        print("❌ No SSL certificates found in /root/cert/")
        print("Please run: bash <(curl -sSL https://raw.githubusercontent.com/mrnimwx/core/main/setup-ssl.sh)")
        sys.exit(1)
    
    print(f"📋 Certificate: {cert_file}")
    print(f"🔑 Private Key: {key_file}")
    
    # Start TCP server in background
    tcp_server = TCPThroughputServer('0.0.0.0', TCP_PORT)
    tcp_thread = threading.Thread(target=lambda: asyncio.run(tcp_server.start()), daemon=True)
    tcp_thread.start()
    
    # Create HTTP server
    try:
        httpd = ThreadedHTTPServer(("", HTTP_PORT), RobustThroughputHandler)
        
        # Configure SSL
        context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
        context.load_cert_chain(cert_file, key_file)
        httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
        
        print(f"✅ HTTPS Server running on port {HTTP_PORT}")
        print(f"✅ TCP Server running on port {TCP_PORT}")
        print(f"🌐 Access via: https://yourdomain.com:{HTTP_PORT}/")
        print(f"🔗 TCP test: telnet yourdomain.com {TCP_PORT}")
        print("")
        print("📋 Available endpoints:")
        print("  GET  /          - Download throughput test")
        print("  GET  /test      - Download throughput test with parameters")
        print("  GET  /ping      - Simple ping test")
        print("  GET  /stats     - Server statistics")
        print("  POST /          - Upload/integrity tests")
        print(f"  TCP  :{TCP_PORT} - Raw TCP throughput tests")
        print("")
        print("Press Ctrl+C to stop")
        
        httpd.serve_forever()
        
    except KeyboardInterrupt:
        print("\n🛑 Stopping servers...")
        tcp_server.stop()
        print("✅ Servers stopped")

if __name__ == "__main__":
    main() 