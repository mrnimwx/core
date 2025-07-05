#!/usr/bin/env python3
"""
Simple Speed Test Server
========================
Just basic speed testing - nothing fancy
"""

import ssl
import os
import sys
import time
from urllib.parse import urlparse, parse_qs
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn

class SimpleSpeedHandler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    
    def log_message(self, format, *args):
        print(f"[{self.address_string()}] {format % args}")
    
    def do_GET(self):
        parsed_url = urlparse(self.path)
        path = parsed_url.path
        query_params = parse_qs(parsed_url.query)
        
        # Set CORS headers
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.send_header('Connection', 'keep-alive')
        
        if path == '/ping':
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"status":"ok","time":' + str(time.time()).encode() + b'}')
        elif path == '/test' or path == '/':
            self._handle_speed_test(query_params)
        else:
            self.send_error(404, "Not Found")
    
    def _handle_speed_test(self, query_params):
        """Simple speed test - just send data"""
        size = int(query_params.get('size', ['1048576'])[0])  # 1MB default
        
        # Send headers
        self.send_header('Content-Type', 'application/octet-stream')
        self.send_header('Content-Length', str(size))
        self.end_headers()
        
        # Send random data
        chunk_size = 8192
        bytes_sent = 0
        
        try:
            while bytes_sent < size:
                remaining = size - bytes_sent
                current_chunk = min(chunk_size, remaining)
                data = os.urandom(current_chunk)
                self.wfile.write(data)
                bytes_sent += current_chunk
        except (ConnectionResetError, BrokenPipeError):
            pass  # Client disconnected
    
    def do_OPTIONS(self):
        """Handle CORS preflight requests"""
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.end_headers()

class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    """Handle requests in a separate thread."""
    daemon_threads = True
    allow_reuse_address = True

def create_ssl_context():
    """Create SSL context for HTTPS"""
    context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
    
    # Look for certificates
    cert_paths = ['/root/cert/server.crt', '/root/cert/server.pem', 'server.crt']
    key_paths = ['/root/cert/server.key', '/root/cert/private.key', 'server.key']
    
    cert_file = key_file = None
    
    for cert_path in cert_paths:
        if os.path.exists(cert_path):
            cert_file = cert_path
            break
    
    for key_path in key_paths:
        if os.path.exists(key_path):
            key_file = key_path
            break
    
    if cert_file and key_file:
        context.load_cert_chain(cert_file, key_file)
        return context
    return None

def main():
    """Main server function"""
    print("Starting Simple Speed Test Server...")
    
    port = 2020
    if len(sys.argv) > 1:
        try:
            port = int(sys.argv[1])
        except ValueError:
            print(f"Invalid port: {sys.argv[1]}")
            sys.exit(1)
    
    # Check for SSL
    ssl_context = create_ssl_context()
    use_ssl = ssl_context is not None
    
    server = ThreadedHTTPServer(('0.0.0.0', port), SimpleSpeedHandler)
    
    if use_ssl:
        server.socket = ssl_context.wrap_socket(server.socket, server_side=True)
        print(f"HTTPS server running on port {port}")
    else:
        print(f"HTTP server running on port {port}")
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()

if __name__ == '__main__':
    main() 