#!/bin/bash

# Unified Uninstallation Script
# Combines dashboard, throughput test, and X-UI uninstallation

echo "🗑️  Network Infrastructure Uninstaller"
echo "======================================"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root"
   exit 1
fi

# Function to uninstall dashboard
uninstall_dashboard() {
    echo ""
    echo "🗑️  Uninstalling Network Infrastructure Dashboard..."
    echo "=================================================="
    
    # Stop and disable service
    echo "🛑 Stopping dashboard service..."
    systemctl stop dashboard.service 2>/dev/null
    systemctl disable dashboard.service 2>/dev/null
    
    # Remove service file
    echo "📁 Removing service file..."
    rm -f /etc/systemd/system/dashboard.service
    
    # Remove dashboard script
    echo "📁 Removing dashboard script..."
    rm -f /root/dashboard.py
    
    # Reload systemd
    echo "🔄 Reloading systemd..."
    systemctl daemon-reload
    
    echo "✅ Dashboard has been successfully uninstalled!"
}

# Function to uninstall throughput test
uninstall_throughput() {
    echo ""
    echo "🗑️  Uninstalling Throughput Tester..."
    echo "===================================="
    
    # Stop and disable service
    echo "🛑 Stopping throughput test service..."
    systemctl stop throughput-test.service 2>/dev/null
    systemctl disable throughput-test.service 2>/dev/null
    
    # Remove files
    echo "📁 Removing service files..."
    rm -f /etc/systemd/system/throughput-test.service
    rm -f /root/throughput_test.py
    
    # Reload systemd
    echo "🔄 Reloading systemd..."
    systemctl daemon-reload
    
    echo "✅ Throughput test has been successfully uninstalled!"
}

# Function to uninstall X-UI
uninstall_xui() {
    echo ""
    echo "🗑️  Uninstalling X-UI..."
    echo "======================="
    
    # Use X-UI's built-in uninstall function
    if command -v x-ui &> /dev/null; then
        echo "📋 Using X-UI built-in uninstaller..."
        /usr/bin/x-ui <<EOF
5
y
EOF
    else
        echo "⚠️  X-UI command not found, performing manual cleanup..."
        
        # Stop and disable service
        echo "🛑 Stopping X-UI service..."
        systemctl stop x-ui 2>/dev/null
        systemctl disable x-ui 2>/dev/null
        
        # Remove service file
        echo "📁 Removing service files..."
        rm -f /etc/systemd/system/x-ui.service
        
        # Remove X-UI files
        echo "📁 Removing X-UI files..."
        rm -rf /usr/local/x-ui
        rm -f /usr/bin/x-ui
        rm -f /usr/local/x-ui-linux-amd64.tar.gz
        
        # Reload systemd
        echo "🔄 Reloading systemd..."
        systemctl daemon-reload
        
        echo "✅ Manual cleanup completed"
    fi
    
    echo "✅ X-UI has been successfully uninstalled!"
}

# Function to uninstall HAProxy
uninstall_haproxy() {
    echo ""
    echo "🗑️  Uninstalling HAProxy..."
    echo "=========================="
    
    # Stop and disable service
    echo "🛑 Stopping HAProxy service..."
    systemctl stop haproxy 2>/dev/null
    systemctl disable haproxy 2>/dev/null
    
    # Remove HAProxy
    echo "📁 Removing HAProxy..."
    apt-get remove --purge haproxy -y 2>/dev/null || yum remove haproxy -y 2>/dev/null
    
    # Remove config files
    echo "📁 Removing configuration files..."
    rm -f /etc/haproxy/haproxy.cfg
    rm -f /root/haproxy.cfg
    
    echo "✅ HAProxy has been successfully uninstalled!"
}

# Function to clean certificates
clean_certificates() {
    echo ""
    echo "🗑️  Cleaning SSL Certificates..."
    echo "==============================="
    
    read -p "⚠️  This will remove all certificates in /root/cert/. Continue? [y/N]: " CONFIRM
    if [[ $CONFIRM =~ ^[Yy]$ ]]; then
        echo "📁 Removing certificates..."
        rm -rf /root/cert/
        echo "✅ Certificates cleaned!"
    else
        echo "❌ Certificate cleanup cancelled"
    fi
}

# Main menu
show_menu() {
    echo ""
    echo "📋 Select what to uninstall:"
    echo "1) Dashboard only"
    echo "2) Throughput Test only"
    echo "3) X-UI only"
    echo "4) HAProxy only"
    echo "5) Clean SSL Certificates"
    echo "6) Uninstall Everything"
    echo "7) Exit"
    echo ""
    read -p "Enter your choice [1-7]: " choice
    
    case $choice in
        1)
            read -p "⚠️  Are you sure you want to uninstall Dashboard? [y/N]: " CONFIRM
            if [[ $CONFIRM =~ ^[Yy]$ ]]; then
                uninstall_dashboard
            else
                echo "❌ Uninstallation cancelled"
            fi
            ;;
        2)
            read -p "⚠️  Are you sure you want to uninstall Throughput Test? [y/N]: " CONFIRM
            if [[ $CONFIRM =~ ^[Yy]$ ]]; then
                uninstall_throughput
            else
                echo "❌ Uninstallation cancelled"
            fi
            ;;
        3)
            read -p "⚠️  Are you sure you want to uninstall X-UI? [y/N]: " CONFIRM
            if [[ $CONFIRM =~ ^[Yy]$ ]]; then
                uninstall_xui
            else
                echo "❌ Uninstallation cancelled"
            fi
            ;;
        4)
            read -p "⚠️  Are you sure you want to uninstall HAProxy? [y/N]: " CONFIRM
            if [[ $CONFIRM =~ ^[Yy]$ ]]; then
                uninstall_haproxy
            else
                echo "❌ Uninstallation cancelled"
            fi
            ;;
        5)
            clean_certificates
            ;;
        6)
            echo ""
            echo "⚠️  WARNING: This will remove EVERYTHING!"
            echo "- Dashboard"
            echo "- Throughput Test"
            echo "- X-UI"
            echo "- HAProxy"
            echo "- SSL Certificates"
            echo ""
            read -p "Are you absolutely sure? [y/N]: " CONFIRM
            if [[ $CONFIRM =~ ^[Yy]$ ]]; then
                uninstall_dashboard
                uninstall_throughput
                uninstall_xui
                uninstall_haproxy
                clean_certificates
                echo ""
                echo "🎉 Complete uninstallation finished!"
                echo "🔄 You may want to reboot your system."
            else
                echo "❌ Uninstallation cancelled"
            fi
            ;;
        7)
            echo "👋 Goodbye!"
            exit 0
            ;;
        *)
            echo "❌ Invalid choice. Please try again."
            show_menu
            ;;
    esac
}

# Run main menu
show_menu

echo ""
echo "🔄 Uninstallation process completed!" 