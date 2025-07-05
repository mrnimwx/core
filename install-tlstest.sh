#!/bin/bash

# Throughput Tester Installation Script
# Auto-detects SSL certificates and installs the service

echo "🚀 Throughput Tester Installation Script"
echo "==========================================="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root"
   exit 1
fi

# Auto-detect domain from certificate directory
DOMAIN=""
if [ -d "/root/cert" ]; then
    for cert_dir in /root/cert/*/; do
        if [ -d "$cert_dir" ]; then
            domain_name=$(basename "$cert_dir")
            if [ -f "$cert_dir/fullchain.pem" ] && [ -f "$cert_dir/privkey.pem" ]; then
                DOMAIN="$domain_name"
                echo "✅ Found domain: $DOMAIN"
                break
            fi
        fi
    done
fi

if [ -z "$DOMAIN" ]; then
    echo "❌ No valid SSL certificates found in /root/cert/"
    echo "Please ensure your certificates are in /root/cert/yourdomain.com/ format"
    exit 1
fi

# Create temporary directory for downloads
TEMP_DIR="/tmp/tlstest-install"
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

echo "📁 Downloading files..."

# Download all required files from GitHub
curl -sSL "https://raw.githubusercontent.com/mrnimwx/core/main/throughput_test.py" -o throughput_test.py
curl -sSL "https://raw.githubusercontent.com/mrnimwx/core/main/throughput-test.service" -o throughput-test.service

# Check if downloads were successful
if [ ! -f "throughput_test.py" ] || [ ! -f "throughput-test.service" ]; then
    echo "❌ Failed to download required files"
    exit 1
fi

echo "📁 Installing files..."

# Install Python script
cp throughput_test.py /root/
chmod +x /root/throughput_test.py

# Install systemd service
cp throughput-test.service /etc/systemd/system/
chmod 644 /etc/systemd/system/throughput-test.service

echo "🔄 Configuring systemd service..."

# Reload systemd and enable service
systemctl daemon-reload
systemctl enable throughput-test.service

echo "▶️  Starting throughput-test service..."

# Start the service
if systemctl start throughput-test.service; then
    echo "✅ Service started successfully!"
    echo "🌐 Server is running on port 2020"
    echo "📋 Domain: $DOMAIN"
    echo ""
    echo "📊 Check status with: systemctl status throughput-test"
    echo "📝 View logs with: journalctl -u throughput-test -f"
else
    echo "❌ Failed to start throughput-test service"
    echo "🔍 Check logs with: journalctl -u throughput-test -n 20"
    exit 1
fi

# Cleanup
rm -rf "$TEMP_DIR"

echo "🎉 Installation completed successfully!" 