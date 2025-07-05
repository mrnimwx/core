#!/bin/bash

# Dashboard Installation Script

echo "📊 Installing Network Infrastructure Dashboard..."
echo "==============================================="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root"
   exit 1
fi

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
if [ -f "dashboard.py" ]; then
    cp dashboard.py /root/
    chmod +x /root/dashboard.py
    echo "✅ Dashboard script installed"
else
    echo "❌ dashboard.py not found in current directory"
    exit 1
fi

# Copy systemd service
if [ -f "dashboard.service" ]; then
    cp dashboard.service /etc/systemd/system/
    chmod 644 /etc/systemd/system/dashboard.service
    echo "✅ Dashboard service file installed"
else
    echo "❌ dashboard.service not found in current directory"
    exit 1
fi

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