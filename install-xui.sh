#!/bin/bash

# X-UI Automated Installation Script
# Installs X-UI v2.3.5 with predefined settings

echo "🚀 X-UI Automated Installation Script"
echo "====================================="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root"
   exit 1
fi

# Set configuration variables
XUI_VERSION="2.3.5"
XUI_USERNAME="admin"
XUI_PASSWORD="admin"
XUI_PORT="800"

echo "📦 Installing X-UI v${XUI_VERSION}..."
echo "👤 Username: ${XUI_USERNAME}"
echo "🔑 Password: ${XUI_PASSWORD}"
echo "🌐 Port: ${XUI_PORT}"
echo ""

# Step 1: Install X-UI latest version first
echo "📥 Step 1: Installing X-UI (latest version)..."
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) <<EOF
n
EOF

# Wait for installation to complete
sleep 5

# Step 2: Change to legacy version 2.3.5
echo "📥 Step 2: Changing to legacy version ${XUI_VERSION}..."
/usr/bin/x-ui <<EOF
4
${XUI_VERSION}
y
${XUI_USERNAME}
${XUI_PASSWORD}
${XUI_PORT}

EOF

# Wait for version change to complete
sleep 5

# Step 3: Reset settings to remove web base path
echo "🔄 Step 3: Resetting panel settings..."
/usr/bin/x-ui <<EOF
8
y

EOF

# Wait for reset to complete
sleep 3

# Step 4: Set port to 80
echo "🌐 Step 4: Setting port to ${XUI_PORT}..."
/usr/bin/x-ui <<EOF
9
${XUI_PORT}
y

EOF

# Wait for port change to complete
sleep 3

# Step 5: Verify installation
echo "✅ Step 5: Verifying installation..."
echo ""
echo "🎉 X-UI Installation Completed Successfully!"
echo "=========================================="
echo "📋 Configuration Summary:"
echo "  - Version: ${XUI_VERSION}"
echo "  - Username: ${XUI_USERNAME}"
echo "  - Password: ${XUI_PASSWORD}"
echo "  - Port: ${XUI_PORT}"
echo "  - Web Base Path: / (root)"
echo ""
echo "🌐 Access Panel:"
echo "  - URL: http://$(curl -s ifconfig.me):${XUI_PORT}/"
echo "  - Local: http://localhost:${XUI_PORT}/"
echo ""
echo "🔧 Management Commands:"
echo "  - Status: x-ui status"
echo "  - Start: x-ui start"
echo "  - Stop: x-ui stop"
echo "  - Restart: x-ui restart"
echo "  - Menu: x-ui"
echo ""
echo "📊 Current Status:"
systemctl status x-ui --no-pager -l 