#!/bin/bash

echo "🚀 Network Proxy & TLS Testing Suite Installation"
echo "================================================="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root"
   exit 1
fi

echo "📦 Installing HAProxy..."
apt update && apt install -y haproxy

echo "🌐 Configuring HAProxy..."
# Use local haproxy.cfg if available, otherwise download
if [ -f "haproxy.cfg" ]; then
    cp haproxy.cfg /etc/haproxy/haproxy.cfg
else
    curl -o /etc/haproxy/haproxy.cfg https://raw.githubusercontent.com/mrnimwx/hareproxy/main/haproxy.cfg
fi

echo "🔄 Starting HAProxy..."
systemctl enable haproxy
systemctl restart haproxy

echo "✅ HAProxy is set up and listening on ports 8080–8086."

echo ""
echo "🚀 Installing Throughput Tester..."

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
    echo "⚠️  No valid SSL certificates found in /root/cert/"
    echo "   TLS Tester installation skipped"
    echo "   Please ensure your certificates are in /root/cert/yourdomain.com/ format"
    echo "   Then run: ./install-tlstest.sh"
else
    echo "📁 Installing TLS Tester files..."
    
    # Install Python script
    if [ -f "throughput_test.py" ]; then
        cp throughput_test.py /root/
    else
        curl -sSL "https://raw.githubusercontent.com/mrnimwx/tlstest/main/throughput_test.py" -o /root/throughput_test.py
    fi
    chmod +x /root/throughput_test.py
    
    # Install systemd service
    if [ -f "throughput-test.service" ]; then
        cp throughput-test.service /etc/systemd/system/
    else
        curl -sSL "https://raw.githubusercontent.com/mrnimwx/tlstest/main/throughput-test.service" -o /etc/systemd/system/throughput-test.service
    fi
    chmod 644 /etc/systemd/system/throughput-test.service
    
    echo "🔄 Configuring systemd service..."
    systemctl daemon-reload
    systemctl enable throughput-test.service
    
    echo "▶️  Starting throughput-test service..."
    if systemctl start throughput-test.service; then
        echo "✅ TLS Tester started successfully!"
        echo "🌐 Server is running on port 2020"
        echo "📋 Domain: $DOMAIN"
    else
        echo "❌ Failed to start throughput-test service"
        echo "🔍 Check logs with: journalctl -u throughput-test -n 20"
    fi
fi

echo ""
echo "🚀 Installing X-UI Panel..."

# Install X-UI with predefined settings
if [ -f "install-xui.sh" ]; then
    echo "📁 Using local X-UI installer..."
    ./install-xui.sh
else
    echo "📥 Downloading and running X-UI installer..."
    curl -sSL "https://raw.githubusercontent.com/yourusername/yourrepo/main/install-xui.sh" | bash
fi

echo ""
echo "📊 Installing Network Dashboard..."

# Install Dashboard
if [ -f "install-dashboard.sh" ]; then
    echo "📁 Using local dashboard installer..."
    ./install-dashboard.sh
else
    echo "📥 Downloading and running dashboard installer..."
    curl -sSL "https://raw.githubusercontent.com/yourusername/yourrepo/main/install-dashboard.sh" | bash
fi

echo ""
echo "🎉 Complete Installation Finished!"
echo "================================="
echo ""
echo "📊 Service Status:"
echo "  - HAProxy: systemctl status haproxy"
echo "  - TLS Tester: systemctl status throughput-test"
echo "  - X-UI Panel: systemctl status x-ui"
echo "  - Dashboard: systemctl status dashboard"
echo ""
echo "📝 View Logs:"
echo "  - HAProxy: journalctl -u haproxy -f"
echo "  - TLS Tester: journalctl -u throughput-test -f"
echo "  - X-UI Panel: journalctl -u x-ui -f"
echo "  - Dashboard: journalctl -u dashboard -f"
echo ""
echo "🌐 Access Points:"
echo "  - Dashboard: http://$(curl -s ifconfig.me):3030/"
echo "  - X-UI Panel: http://$(curl -s ifconfig.me):80/"
echo "  - TLS Tester: https://yourdomain.com:2020/"
echo ""
echo "📊 The dashboard provides real-time monitoring of all services!" 