#!/bin/bash

# Dashboard Installation Script

echo "📊 Installing Network Infrastructure Dashboard..."
echo "==============================================="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root"
   exit 1
fi

# Create temporary directory and download required files
echo "📥 Downloading required files..."
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Download necessary files from GitHub
curl -sSLO https://raw.githubusercontent.com/mrnimwx/core/main/dashboard.py
curl -sSLO https://raw.githubusercontent.com/mrnimwx/core/main/dashboard.service

if [ ! -f "dashboard.py" ] || [ ! -f "dashboard.service" ]; then
    echo "❌ Failed to download required files"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "✅ Files downloaded successfully"

# Install Python3 if not already installed
echo "📦 Checking Python3 installation..."
if ! command -v python3 &> /dev/null; then
    echo "Installing Python3..."
    apt update
    apt install -y python3 python3-pip
else
    echo "✅ Python3 is already installed"
fi

# Install dashboard files
echo "📁 Installing dashboard files..."

# Copy dashboard script
cp dashboard.py /root/
chmod +x /root/dashboard.py
echo "✅ Dashboard script installed"

# Copy systemd service
cp dashboard.service /etc/systemd/system/
chmod 644 /etc/systemd/system/dashboard.service
echo "✅ Dashboard service file installed"

# Clean up temporary directory
cd /root
rm -rf "$TEMP_DIR"

# Configure systemd service
echo "🔄 Configuring systemd service..."
systemctl daemon-reload
systemctl enable dashboard.service

# Start the service
echo "▶️  Starting dashboard service..."
if systemctl start dashboard.service; then
    echo "✅ Dashboard service started successfully!"
    echo ""
    echo "🌐 Dashboard Access Information:"
    echo "================================"
    echo "📊 Local URL: http://localhost:3030/"
    echo "🌍 External URL: http://$(curl -s ifconfig.me):3030/"
    echo ""
    echo "📋 Service Management:"
    echo "  - Status: systemctl status dashboard"
    echo "  - Start: systemctl start dashboard"
    echo "  - Stop: systemctl stop dashboard"
    echo "  - Restart: systemctl restart dashboard"
    echo "  - Logs: journalctl -u dashboard -f"
    echo ""
    echo "🔄 The dashboard auto-refreshes every 30 seconds"
    echo "📊 Monitors: HAProxy, TLS Tester, X-UI, and proxy ports 8080-8086"
else
    echo "❌ Failed to start dashboard service"
    echo "🔍 Check logs with: journalctl -u dashboard -n 20"
    exit 1
fi

echo ""
echo "🎉 Dashboard installation completed successfully!" 