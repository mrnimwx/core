#!/usr/bin/env python3
import http.server
import socketserver
import ssl
import os
import sys
import random
import string
from urllib.parse import urlparse, parse_qs

class ThroughputHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        # Parse query parameters
        parsed_url = urlparse(self.path)
        query_params = parse_qs(parsed_url.query)
        
        # Get size parameter (default 2MB)
        size = int(query_params.get('size', ['2097152'])[0])  # 2MB default
        
        # Set CORS headers
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.send_header('Content-Type', 'application/octet-stream')
        self.send_header('Content-Length', str(size))
        self.end_headers()
        
        # Generate and send random data
        chunk_size = 8192
        remaining = size
        
        while remaining > 0:
            current_chunk = min(chunk_size, remaining)
            data = os.urandom(current_chunk)
            self.wfile.write(data)
            remaining -= current_chunk
    
    def do_OPTIONS(self):
        # Handle preflight requests
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.end_headers()
    
    def log_message(self, format, *args):
        # Custom logging
        print(f"[{self.address_string()}] {format % args}")

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
    PORT = 2020
    
    print("🚀 Starting Throughput Test Server")
    print("==================================")
    
    # Find SSL certificates
    cert_file, key_file = find_certificates()
    
    if not cert_file or not key_file:
        print("❌ No SSL certificates found in /root/cert/")
        print("Please ensure certificates are in /root/cert/yourdomain.com/ format")
        sys.exit(1)
    
    # Create server
    with socketserver.TCPServer(("", PORT), ThroughputHandler) as httpd:
        # Configure SSL
        context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
        context.load_cert_chain(cert_file, key_file)
        httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
        
        print(f"✅ Server running on port {PORT}")
        print(f"📋 Certificate: {cert_file}")
        print(f"🔑 Private Key: {key_file}")
        print(f"🌐 Access via: https://yourdomain.com:{PORT}/")
        print("Press Ctrl+C to stop")
        
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n🛑 Server stopped")

if __name__ == "__main__":
    main() 