#!/bin/bash

# =================================================================
# 🚀 Unified Network Infrastructure Installer
# =================================================================
# Interactive installer for HAProxy, X-UI, Connection Monitor, Dashboard
# Choose what you want to install with a simple menu interface
# =================================================================

set -e  # Exit on any error

# Colors for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Configuration variables
DOMAIN=""
MONITOR_PASSWORD="admin123"
XUI_USERNAME="admin"
XUI_PASSWORD="admin"
XUI_PORT="800"

# Installation flags
INSTALL_HAPROXY=false
INSTALL_XUI=false
INSTALL_CONNECTION_MONITOR=false
INSTALL_DASHBOARD=false
INSTALL_SSL_SETUP=false

# =================================================================
# Utility Functions
# =================================================================

print_banner() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║     🚀 Network Infrastructure Installer v2.0                    ║
║                                                                  ║
║     Interactive installer for modern proxy infrastructure       ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

print_section() {
    echo -e "\n${BLUE}▶ $1${NC}"
    echo "================================================================="
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        echo "Usage: sudo ./install.sh"
        exit 1
    fi
}

detect_system() {
    print_section "System Detection"
    
    # Detect OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VERSION=$VERSION_ID
    else
        print_error "Cannot detect operating system"
        exit 1
    fi
    
    print_info "Operating System: $OS $VERSION"
    
    # Check if Ubuntu/Debian
    if [[ "$OS" != *"Ubuntu"* ]] && [[ "$OS" != *"Debian"* ]]; then
        print_warning "This installer is optimized for Ubuntu/Debian"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # Check internet connection
    if ! ping -c 1 google.com &> /dev/null; then
        print_error "No internet connection detected"
        exit 1
    fi
    
    print_success "System check passed"
}

auto_detect_domain() {
    print_section "Domain Detection"
    
    # Auto-detect domain from certificate directory
    if [ -d "/root/cert" ]; then
        for cert_dir in /root/cert/*/; do
            if [ -d "$cert_dir" ]; then
                domain_name=$(basename "$cert_dir")
                if [ -f "$cert_dir/fullchain.pem" ] && [ -f "$cert_dir/privkey.pem" ]; then
                    DOMAIN="$domain_name"
                    print_success "Found SSL certificate for domain: $DOMAIN"
                    return
                fi
            fi
        done
    fi
    
    # Try to get from hostname
    if [ -z "$DOMAIN" ]; then
        hostname_domain=$(hostname -f 2>/dev/null || echo "")
        if [[ "$hostname_domain" =~ \. ]]; then
            DOMAIN="$hostname_domain"
            print_info "Using hostname as domain: $DOMAIN"
        fi
    fi
    
    if [ -z "$DOMAIN" ]; then
        print_warning "No domain auto-detected"
    fi
}

# =================================================================
# Interactive Menu Functions
# =================================================================

show_main_menu() {
    print_banner
    
    echo -e "${WHITE}Choose an option:${NC}\n"
    
    echo -e "  ${GREEN}1)${NC} HAProxy Load Balancer"
    echo -e "  ${GREEN}2)${NC} X-UI Panel"
    echo -e "  ${GREEN}3)${NC} Connection Monitor"
    echo -e "  ${GREEN}4)${NC} Network Dashboard"
    echo -e "  ${GREEN}5)${NC} SSL/TLS Setup"
    echo -e "  ${GREEN}6)${NC} Install All Components"
    echo -e "  ${GREEN}7)${NC} Custom Selection"
    echo
    echo -e "  ${RED}8)${NC} Uninstall Components"
    echo
    echo -e "  ${GREEN}0)${NC} Exit"
    echo
}

get_user_choice() {
    while true; do
        show_main_menu
        read -p "Enter your choice (0-8): " choice
        
        case $choice in
            1)
                INSTALL_HAPROXY=true
                confirm_and_install
                break
                ;;
            2)
                INSTALL_XUI=true
                confirm_and_install
                break
                ;;
            3)
                INSTALL_CONNECTION_MONITOR=true
                get_monitor_config
                confirm_and_install
                break
                ;;
            4)
                INSTALL_DASHBOARD=true
                confirm_and_install
                break
                ;;
            5)
                INSTALL_SSL_SETUP=true
                get_ssl_config
                confirm_and_install
                break
                ;;
            6)
                INSTALL_HAPROXY=true
                INSTALL_XUI=true
                INSTALL_CONNECTION_MONITOR=true
                INSTALL_DASHBOARD=true
                INSTALL_SSL_SETUP=true
                get_full_config
                confirm_and_install
                break
                ;;
            7)
                custom_selection
                break
                ;;
            8)
                show_uninstall_menu
                break
                ;;
            0)
                print_info "Operation cancelled"
                exit 0
                ;;
            *)
                print_error "Invalid choice. Please try again."
                sleep 2
                ;;
        esac
    done
}

custom_selection() {
    print_banner
    echo -e "${WHITE}Custom Component Selection${NC}\n"
    
    # HAProxy
    read -p "Install HAProxy Load Balancer? (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] && INSTALL_HAPROXY=true
    
    # X-UI
    read -p "Install X-UI Panel? (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] && INSTALL_XUI=true
    
    # Connection Monitor
    read -p "Install Connection Monitor? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        INSTALL_CONNECTION_MONITOR=true
        get_monitor_config
    fi
    
    # Dashboard
    read -p "Install Network Dashboard? (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] && INSTALL_DASHBOARD=true
    
    # SSL Setup
    read -p "Setup SSL/TLS certificates? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        INSTALL_SSL_SETUP=true
        get_ssl_config
    fi
    
    confirm_and_install
}

get_monitor_config() {
    echo
    print_section "Connection Monitor Configuration"
    
    # Get monitor password
    read -p "Enter password for connection monitor (default: admin123): " monitor_pass
    if [ -n "$monitor_pass" ]; then
        MONITOR_PASSWORD="$monitor_pass"
    fi
    
    print_info "Monitor password set to: $MONITOR_PASSWORD"
}

get_ssl_config() {
    echo
    print_section "SSL/TLS Configuration"
    
    if [ -z "$DOMAIN" ]; then
        read -p "Enter your domain name: " domain_input
        if [ -n "$domain_input" ]; then
            DOMAIN="$domain_input"
        else
            print_warning "No domain provided. SSL setup will be skipped."
            INSTALL_SSL_SETUP=false
            return
        fi
    fi
    
    print_info "SSL will be configured for domain: $DOMAIN"
}

get_full_config() {
    echo
    print_section "Full Installation Configuration"
    
    # Get monitor password
    read -p "Enter password for connection monitor (default: admin123): " monitor_pass
    if [ -n "$monitor_pass" ]; then
        MONITOR_PASSWORD="$monitor_pass"
    fi
    
    # Get domain for SSL
    if [ -z "$DOMAIN" ]; then
        read -p "Enter your domain name for SSL (optional): " domain_input
        if [ -n "$domain_input" ]; then
            DOMAIN="$domain_input"
        else
            print_warning "No domain provided. SSL setup will be skipped."
            INSTALL_SSL_SETUP=false
        fi
    fi
}

confirm_and_install() {
    print_banner
    echo -e "${WHITE}Installation Summary${NC}\n"
    
    echo "Components to install:"
    $INSTALL_HAPROXY && echo -e "  ${GREEN}✓${NC} HAProxy Load Balancer"
    $INSTALL_XUI && echo -e "  ${GREEN}✓${NC} X-UI Panel"
    $INSTALL_CONNECTION_MONITOR && echo -e "  ${GREEN}✓${NC} Connection Monitor (Password: $MONITOR_PASSWORD)"
    $INSTALL_DASHBOARD && echo -e "  ${GREEN}✓${NC} Network Dashboard"
    $INSTALL_SSL_SETUP && echo -e "  ${GREEN}✓${NC} SSL/TLS Setup (Domain: $DOMAIN)"
    
    echo
    echo -e "${YELLOW}This will install the selected components and configure your server.${NC}"
    echo -e "${YELLOW}The installation may take several minutes.${NC}"
    echo
    
    read -p "Proceed with installation? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        run_installation
    else
        print_info "Installation cancelled"
        exit 0
    fi
}

# =================================================================
# Uninstall Functions
# =================================================================

show_uninstall_menu() {
    print_banner
    
    echo -e "${WHITE}Choose components to uninstall:${NC}\n"
    
    echo -e "  ${RED}1)${NC} HAProxy Load Balancer"
    echo -e "  ${RED}2)${NC} X-UI Panel"
    echo -e "  ${RED}3)${NC} Connection Monitor"
    echo -e "  ${RED}4)${NC} Network Dashboard"
    echo -e "  ${RED}5)${NC} Remove SSL Certificates"
    echo -e "  ${RED}6)${NC} Uninstall All Components"
    echo -e "  ${RED}7)${NC} Custom Uninstall Selection"
    echo
    echo -e "  ${GREEN}0)${NC} Back to Main Menu"
    echo
    
    while true; do
        read -p "Enter your choice (0-7): " choice
        
        case $choice in
            1)
                uninstall_haproxy
                break
                ;;
            2)
                uninstall_xui
                break
                ;;
            3)
                uninstall_connection_monitor
                break
                ;;
            4)
                uninstall_dashboard
                break
                ;;
            5)
                remove_ssl_certificates
                break
                ;;
            6)
                uninstall_all_components
                break
                ;;
            7)
                custom_uninstall_selection
                break
                ;;
            0)
                get_user_choice
                break
                ;;
            *)
                print_error "Invalid choice. Please try again."
                sleep 2
                ;;
        esac
    done
}

uninstall_haproxy() {
    print_section "Uninstalling HAProxy"
    
    read -p "Are you sure you want to uninstall HAProxy? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "HAProxy uninstall cancelled"
        return
    fi
    
    print_info "Stopping HAProxy service..."
    systemctl stop haproxy 2>/dev/null || true
    systemctl disable haproxy 2>/dev/null || true
    
    print_info "Removing HAProxy package..."
    apt remove -y haproxy 2>/dev/null || true
    
    print_info "Removing configuration files..."
    rm -rf /etc/haproxy/ 2>/dev/null || true
    
    print_success "HAProxy uninstalled successfully"
    
    read -p "Press Enter to continue..."
    show_uninstall_menu
}

uninstall_xui() {
    print_section "Uninstalling X-UI Panel"
    
    read -p "Are you sure you want to uninstall X-UI Panel? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "X-UI uninstall cancelled"
        return
    fi
    
    print_info "Stopping X-UI service..."
    systemctl stop x-ui 2>/dev/null || true
    systemctl disable x-ui 2>/dev/null || true
    
    print_info "Removing X-UI files..."
    rm -rf /usr/local/x-ui/ 2>/dev/null || true
    rm -f /usr/bin/x-ui 2>/dev/null || true
    rm -f /etc/systemd/system/x-ui.service 2>/dev/null || true
    
    systemctl daemon-reload
    
    print_success "X-UI Panel uninstalled successfully"
    
    read -p "Press Enter to continue..."
    show_uninstall_menu
}

uninstall_connection_monitor() {
    print_section "Uninstalling Connection Monitor"
    
    read -p "Are you sure you want to uninstall Connection Monitor? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Connection Monitor uninstall cancelled"
        return
    fi
    
    print_info "Stopping Connection Monitor service..."
    systemctl stop connection-monitor 2>/dev/null || true
    systemctl disable connection-monitor 2>/dev/null || true
    
    print_info "Removing Connection Monitor files..."
    rm -f /root/connection_monitor.py 2>/dev/null || true
    rm -f /etc/systemd/system/connection-monitor.service 2>/dev/null || true
    
    systemctl daemon-reload
    
    print_success "Connection Monitor uninstalled successfully"
    
    read -p "Press Enter to continue..."
    show_uninstall_menu
}

uninstall_dashboard() {
    print_section "Uninstalling Network Dashboard"
    
    read -p "Are you sure you want to uninstall Network Dashboard? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Dashboard uninstall cancelled"
        return
    fi
    
    print_info "Stopping Dashboard service..."
    systemctl stop dashboard 2>/dev/null || true
    systemctl disable dashboard 2>/dev/null || true
    
    print_info "Removing Dashboard files..."
    rm -f /root/dashboard.py 2>/dev/null || true
    rm -f /etc/systemd/system/dashboard.service 2>/dev/null || true
    
    systemctl daemon-reload
    
    print_success "Network Dashboard uninstalled successfully"
    
    read -p "Press Enter to continue..."
    show_uninstall_menu
}

remove_ssl_certificates() {
    print_section "Removing SSL Certificates"
    
    read -p "Are you sure you want to remove SSL certificates? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "SSL certificate removal cancelled"
        return
    fi
    
    print_warning "This will remove certificates from /root/cert/"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "SSL certificate removal cancelled"
        return
    fi
    
    print_info "Removing SSL certificates..."
    rm -rf /root/cert/ 2>/dev/null || true
    
    print_success "SSL certificates removed successfully"
    
    read -p "Press Enter to continue..."
    show_uninstall_menu
}

uninstall_all_components() {
    print_section "Uninstalling All Components"
    
    print_warning "This will remove ALL installed components:"
    echo "  - HAProxy Load Balancer"
    echo "  - X-UI Panel"
    echo "  - Connection Monitor"
    echo "  - Network Dashboard"
    echo "  - SSL Certificates"
    echo
    
    read -p "Are you absolutely sure? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Complete uninstall cancelled"
        return
    fi
    
    print_info "Stopping all services..."
    systemctl stop haproxy x-ui connection-monitor dashboard 2>/dev/null || true
    systemctl disable haproxy x-ui connection-monitor dashboard 2>/dev/null || true
    
    print_info "Removing packages..."
    apt remove -y haproxy 2>/dev/null || true
    
    print_info "Removing files..."
    rm -rf /etc/haproxy/ 2>/dev/null || true
    rm -rf /usr/local/x-ui/ 2>/dev/null || true
    rm -f /usr/bin/x-ui 2>/dev/null || true
    rm -f /root/connection_monitor.py 2>/dev/null || true
    rm -f /root/dashboard.py 2>/dev/null || true
    rm -f /etc/systemd/system/x-ui.service 2>/dev/null || true
    rm -f /etc/systemd/system/connection-monitor.service 2>/dev/null || true
    rm -f /etc/systemd/system/dashboard.service 2>/dev/null || true
    rm -rf /root/cert/ 2>/dev/null || true
    
    systemctl daemon-reload
    
    print_success "All components uninstalled successfully"
    
    read -p "Press Enter to continue..."
    show_uninstall_menu
}

custom_uninstall_selection() {
    print_banner
    echo -e "${WHITE}Custom Uninstall Selection${NC}\n"
    
    # HAProxy
    read -p "Uninstall HAProxy Load Balancer? (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] && uninstall_haproxy
    
    # X-UI
    read -p "Uninstall X-UI Panel? (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] && uninstall_xui
    
    # Connection Monitor
    read -p "Uninstall Connection Monitor? (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] && uninstall_connection_monitor
    
    # Dashboard
    read -p "Uninstall Network Dashboard? (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] && uninstall_dashboard
    
    # SSL
    read -p "Remove SSL certificates? (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] && remove_ssl_certificates
    
    print_success "Custom uninstall completed"
    
    read -p "Press Enter to continue..."
    show_uninstall_menu
}

# =================================================================
# Installation Functions
# =================================================================

update_system() {
    print_section "System Update"
    
    print_info "Updating package lists..."
    apt update
    
    print_info "Installing essential packages..."
    apt install -y curl wget unzip python3 python3-pip net-tools
    
    print_success "System updated successfully"
}

install_haproxy() {
    print_section "Installing HAProxy"
    
    print_info "Installing HAProxy package..."
    apt install -y haproxy
    
    print_info "Configuring HAProxy..."
    
    # Create proper HAProxy configuration
    print_info "Creating HAProxy configuration..."
    
    # Ensure directory exists
    mkdir -p /etc/haproxy
    
    # Create the configuration file
    cat > /etc/haproxy/haproxy.cfg << 'EOF'
# HAProxy Configuration
global
    daemon
    user haproxy
    group haproxy
    log stdout local0

defaults
    mode tcp
    timeout connect 10s
    timeout client 1m
    timeout server 1m
    log global

frontend incoming
    bind *:8080
    bind *:8082
    bind *:8083
    bind *:8084
    bind *:8085
    bind *:8086

    use_backend sv6 if { dst_port 8080 }
    use_backend sv2 if { dst_port 8082 }
    use_backend sv3 if { dst_port 8083 }
    use_backend sv4 if { dst_port 8084 }
    use_backend sv5 if { dst_port 8085 }
    use_backend sv1 if { dst_port 8086 }

backend sv6
    server sv6 10.0.0.4:8080

backend sv2
    server sv2 10.0.0.5:8082

backend sv3
    server sv3 10.0.0.6:8083

backend sv4
    server sv4 10.0.0.7:8084

backend sv5
    server sv5 10.0.0.8:8085

backend sv1
    server sv1 10.0.0.9:8086
EOF
    
    # Set proper permissions
    chmod 644 /etc/haproxy/haproxy.cfg
    chown root:root /etc/haproxy/haproxy.cfg
    
    print_info "HAProxy configuration created successfully"
    
    # Test HAProxy configuration
    print_info "Testing HAProxy configuration..."
    if haproxy -c -f /etc/haproxy/haproxy.cfg; then
        print_success "HAProxy configuration is valid"
    else
        print_error "HAProxy configuration is invalid"
        return 1
    fi
    
    # Start and enable HAProxy
    systemctl enable haproxy
    systemctl restart haproxy
    
    # Verify HAProxy is running
    sleep 2
    if systemctl is-active --quiet haproxy; then
        print_success "HAProxy installed and started successfully"
        print_info "Listening on ports: 8080, 8082, 8083, 8084, 8085, 8086"
    else
        print_error "HAProxy failed to start"
        print_info "Check logs with: journalctl -u haproxy -f"
        return 1
    fi
}

install_xui() {
    print_section "Installing X-UI Panel"
    
    print_info "Downloading and installing X-UI..."
    
    # Install X-UI with automated responses
    bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) << EOF
n
EOF

    sleep 5
    
    print_info "Configuring X-UI to legacy version 2.3.5..."
    
    # Change to legacy version
    /usr/bin/x-ui << EOF
4
2.3.5
y
$XUI_USERNAME
$XUI_PASSWORD
$XUI_PORT

EOF

    sleep 5
    
    # Reset settings to remove web base path
    /usr/bin/x-ui << EOF
8
y

EOF

    sleep 3
    
    # Set port
    /usr/bin/x-ui << EOF
9
$XUI_PORT
y

EOF

    sleep 3
    
    print_success "X-UI Panel installed and configured"
    print_info "Access URL: http://$(curl -s ifconfig.me):$XUI_PORT/"
    print_info "Username: $XUI_USERNAME"
    print_info "Password: $XUI_PASSWORD"
}

install_connection_monitor() {
    print_section "Installing Connection Monitor"
    
    print_info "Installing connection monitor files..."
    
    # Copy connection monitor script
    if [ -f "connection_monitor.py" ]; then
        cp connection_monitor.py /root/
        chmod +x /root/connection_monitor.py
    else
        print_error "connection_monitor.py not found"
        return 1
    fi
    
    # Create systemd service
    cat > /etc/systemd/system/connection-monitor.service << EOF
[Unit]
Description=Connection Monitor Dashboard
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root
ExecStart=/usr/bin/python3 /root/connection_monitor.py
Restart=always
RestartSec=5
Environment=MONITOR_PASSWORD=$MONITOR_PASSWORD
Environment=MONITOR_PORT=2020

[Install]
WantedBy=multi-user.target
EOF
    
    # Start and enable service
    systemctl daemon-reload
    systemctl enable connection-monitor.service
    systemctl start connection-monitor.service
    
    print_success "Connection Monitor installed and started"
    print_info "Access URL: https://$(curl -s ifconfig.me):2020/"
    print_info "Password: $MONITOR_PASSWORD"
}

install_dashboard() {
    print_section "Installing Network Dashboard"
    
    print_info "Installing dashboard files..."
    
    # Copy dashboard script if available
    if [ -f "dashboard.py" ]; then
        cp dashboard.py /root/
        chmod +x /root/dashboard.py
        
        # Copy service file
        if [ -f "dashboard.service" ]; then
            cp dashboard.service /etc/systemd/system/
        else
            # Create default service file
            cat > /etc/systemd/system/dashboard.service << 'EOF'
[Unit]
Description=Network Infrastructure Dashboard
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root
ExecStart=/usr/bin/python3 /root/dashboard.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        fi
        
        # Start and enable service
        systemctl daemon-reload
        systemctl enable dashboard.service
        systemctl start dashboard.service
        
        print_success "Network Dashboard installed and started"
        print_info "Access URL: http://$(curl -s ifconfig.me):3030/"
    else
        print_warning "dashboard.py not found - skipping dashboard installation"
    fi
}

setup_ssl() {
    print_section "Setting up SSL/TLS"
    
    if [ -z "$DOMAIN" ]; then
        print_warning "No domain specified - skipping SSL setup"
        return
    fi
    
    print_info "Setting up SSL for domain: $DOMAIN"
    
    # Install certbot if not available
    if ! command -v certbot &> /dev/null; then
        print_info "Installing Certbot..."
        apt install -y certbot
    fi
    
    # Create certificate directory
    mkdir -p /root/cert/$DOMAIN
    
    print_info "SSL setup completed for $DOMAIN"
    print_warning "Note: You may need to manually configure certificates"
}

run_installation() {
    print_section "Starting Installation"
    
    # Update system first
    update_system
    
    # Install selected components
    $INSTALL_HAPROXY && install_haproxy
    $INSTALL_XUI && install_xui
    $INSTALL_CONNECTION_MONITOR && install_connection_monitor
    $INSTALL_DASHBOARD && install_dashboard
    $INSTALL_SSL_SETUP && setup_ssl
    
    show_installation_summary
}

show_installation_summary() {
    print_banner
    echo -e "${GREEN}🎉 Installation Completed Successfully!${NC}\n"
    
    echo -e "${WHITE}Service Status:${NC}"
    
    if $INSTALL_HAPROXY; then
        if systemctl is-active --quiet haproxy; then
            echo -e "  ${GREEN}✓${NC} HAProxy: Running"
        else
            echo -e "  ${RED}✗${NC} HAProxy: Stopped"
        fi
    fi
    
    if $INSTALL_XUI; then
        if systemctl is-active --quiet x-ui; then
            echo -e "  ${GREEN}✓${NC} X-UI Panel: Running"
        else
            echo -e "  ${RED}✗${NC} X-UI Panel: Stopped"
        fi
    fi
    
    if $INSTALL_CONNECTION_MONITOR; then
        if systemctl is-active --quiet connection-monitor; then
            echo -e "  ${GREEN}✓${NC} Connection Monitor: Running"
        else
            echo -e "  ${RED}✗${NC} Connection Monitor: Stopped"
        fi
    fi
    
    if $INSTALL_DASHBOARD; then
        if systemctl is-active --quiet dashboard; then
            echo -e "  ${GREEN}✓${NC} Network Dashboard: Running"
        else
            echo -e "  ${RED}✗${NC} Network Dashboard: Stopped"
        fi
    fi
    
    echo
    echo -e "${WHITE}Access URLs:${NC}"
    
    SERVER_IP=$(curl -s ifconfig.me)
    
    $INSTALL_XUI && echo -e "  ${CYAN}🌐${NC} X-UI Panel: http://$SERVER_IP:$XUI_PORT/"
    $INSTALL_CONNECTION_MONITOR && echo -e "  ${CYAN}📊${NC} Connection Monitor: https://$SERVER_IP:2020/"
    $INSTALL_DASHBOARD && echo -e "  ${CYAN}📈${NC} Network Dashboard: http://$SERVER_IP:3030/"
    $INSTALL_HAPROXY && echo -e "  ${CYAN}🔀${NC} HAProxy Ports: 8080, 8082, 8083, 8084, 8085, 8086"
    
    echo
    echo -e "${WHITE}Management Commands:${NC}"
    $INSTALL_HAPROXY && echo -e "  ${CYAN}▶${NC} HAProxy: systemctl status haproxy"
    $INSTALL_XUI && echo -e "  ${CYAN}▶${NC} X-UI: x-ui"
    $INSTALL_CONNECTION_MONITOR && echo -e "  ${CYAN}▶${NC} Connection Monitor: systemctl status connection-monitor"
    $INSTALL_DASHBOARD && echo -e "  ${CYAN}▶${NC} Dashboard: systemctl status dashboard"
    
    echo
    echo -e "${WHITE}Credentials:${NC}"
    $INSTALL_XUI && echo -e "  ${CYAN}🔑${NC} X-UI: $XUI_USERNAME / $XUI_PASSWORD"
    $INSTALL_CONNECTION_MONITOR && echo -e "  ${CYAN}🔑${NC} Connection Monitor: any-username / $MONITOR_PASSWORD"
    
    echo
    print_success "All selected components have been installed and configured!"
    echo -e "${YELLOW}📖 Save these URLs and credentials for future reference.${NC}"
}

# =================================================================
# Main Script
# =================================================================

main() {
    print_banner
    
    # Check requirements
    check_root
    detect_system
    auto_detect_domain
    
    # Show interactive menu
    get_user_choice
}

# Run the installer
main "$@" 