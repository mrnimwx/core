#!/bin/bash

# X-UI Interactive Installation Script
# Allows customization of X-UI installation settings

echo "🚀 X-UI Interactive Installation Script"
echo "======================================="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root"
   exit 1
fi

# Get user preferences
echo "📋 Configuration Setup:"
echo ""

# Get version
read -p "Enter X-UI version [default: 2.3.5]: " XUI_VERSION
XUI_VERSION=${XUI_VERSION:-2.3.5}

# Get username
read -p "Enter username [default: nimwx]: " XUI_USERNAME
XUI_USERNAME=${XUI_USERNAME:-nimwx}

# Get password
read -p "Enter password [default: nimwx]: " XUI_PASSWORD
XUI_PASSWORD=${XUI_PASSWORD:-nimwx}

# Get port
read -p "Enter port [default: 80]: " XUI_PORT
XUI_PORT=${XUI_PORT:-80}

# Confirm settings
echo ""
echo "📋 Configuration Summary:"
echo "  - Version: ${XUI_VERSION}"
echo "  - Username: ${XUI_USERNAME}"
echo "  - Password: ${XUI_PASSWORD}"
echo "  - Port: ${XUI_PORT}"
echo ""

read -p "Proceed with installation? [y/N]: " CONFIRM
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo "❌ Installation cancelled"
    exit 1
fi

echo ""
echo "🚀 Starting installation..."

# Step 1: Install X-UI latest version first
echo "📥 Step 1: Installing X-UI (latest version)..."
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) <<EOF
n
EOF

# Wait for installation to complete
sleep 5

# Step 2: Change to specified version
echo "📥 Step 2: Changing to version ${XUI_VERSION}..."
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

# Step 4: Set port
echo "🌐 Step 4: Setting port to ${XUI_PORT}..."
/usr/bin/x-ui <<EOF
9
${XUI_PORT}
y

EOF

# Wait for port change to complete
sleep 3

# Step 5: Final verification
echo "✅ Step 5: Installation verification..."
echo ""
echo "🎉 X-UI Installation Completed Successfully!"
echo "=========================================="
echo "📋 Final Configuration:"
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