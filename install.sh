#!/bin/bash

# =================================================================
# 🚀 Unified Network Infrastructure Installer
# =================================================================
# Interactive installer for HAProxy, X-UI, Unified Dashboard
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
USE_HTTPS=false
AVAILABLE_DOMAINS=()
MONITOR_PASSWORD="admin"
XUI_USERNAME="admin"
XUI_PASSWORD="admin"
XUI_PORT="800"

# Installation flags
INSTALL_HAPROXY=false
INSTALL_XUI=false
INSTALL_UNIFIED_DASHBOARD=false
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

check_existing_certificates() {
    print_section "Certificate Detection"
    
    # Check for existing certificates
    AVAILABLE_DOMAINS=()
    if [ -d "/root/cert" ]; then
        for cert_dir in /root/cert/*/; do
            if [ -d "$cert_dir" ]; then
                domain_name=$(basename "$cert_dir")
                # Check if both certificate files exist and are not empty
                if [ -f "$cert_dir/fullchain.pem" ] && [ -f "$cert_dir/privkey.pem" ] && 
                   [ -s "$cert_dir/fullchain.pem" ] && [ -s "$cert_dir/privkey.pem" ]; then
                    # Verify the certificate files are valid
                    if openssl x509 -in "$cert_dir/fullchain.pem" -noout -text >/dev/null 2>&1; then
                        AVAILABLE_DOMAINS+=("$domain_name")
                        print_info "✓ Valid certificate found for: $domain_name"
                    else
                        print_warning "⚠ Invalid certificate for: $domain_name"
                    fi
                else
                    print_warning "⚠ Incomplete certificate files for: $domain_name"
                fi
            fi
        done
    fi
    
    if [ ${#AVAILABLE_DOMAINS[@]} -gt 0 ]; then
        echo
        print_success "Found ${#AVAILABLE_DOMAINS[@]} valid SSL certificate(s)"
        return 0
    else
        print_warning "No valid SSL certificates found in /root/cert/"
        return 1
    fi
}

select_domain_interactive() {
    if check_existing_certificates; then
        echo
        read -p "Do you want to use HTTPS with an existing certificate? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if [ ${#AVAILABLE_DOMAINS[@]} -eq 1 ]; then
                DOMAIN="${AVAILABLE_DOMAINS[0]}"
                USE_HTTPS=true
                print_success "Selected domain: $DOMAIN"
            else
                echo "Select a domain:"
                for i in "${!AVAILABLE_DOMAINS[@]}"; do
                    echo "  $((i+1))) ${AVAILABLE_DOMAINS[i]}"
                done
                echo "  0) Cancel"
                echo
                
                while true; do
                    read -p "Enter your choice (0-${#AVAILABLE_DOMAINS[@]}): " choice
                    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 0 ] && [ "$choice" -le ${#AVAILABLE_DOMAINS[@]} ]; then
                        if [ "$choice" -eq 0 ]; then
                            print_info "HTTPS setup cancelled"
                            USE_HTTPS=false
                            DOMAIN=""
                            break
                        else
                            DOMAIN="${AVAILABLE_DOMAINS[$((choice-1))]}"
                            USE_HTTPS=true
                            print_success "Selected domain: $DOMAIN"
                            break
                        fi
                    else
                        print_error "Invalid choice. Please try again."
                    fi
                done
            fi
        else
            USE_HTTPS=false
            DOMAIN=""
            print_info "Will use HTTP mode"
        fi
    else
        echo
        read -p "Do you want to set up SSL/TLS certificates? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            read -p "Enter your domain name: " domain_input
            if [ -n "$domain_input" ]; then
                DOMAIN="$domain_input"
                USE_HTTPS=true
                INSTALL_SSL_SETUP=true
                print_info "Will set up SSL for domain: $DOMAIN"
            else
                USE_HTTPS=false
                DOMAIN=""
                print_warning "No domain provided. Will use HTTP mode."
            fi
        else
            USE_HTTPS=false
            DOMAIN=""
            print_info "Will use HTTP mode"
        fi
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
    echo -e "  ${GREEN}3)${NC} Unified Dashboard"
    echo -e "  ${GREEN}4)${NC} SSL/TLS Setup"
    echo -e "  ${GREEN}5)${NC} Install All Components"
    echo -e "  ${GREEN}6)${NC} Custom Selection"
    echo -e "  ${CYAN}7)${NC} Add SSL to Existing Dashboard"
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
                INSTALL_UNIFIED_DASHBOARD=true
                select_domain_interactive
                get_dashboard_config
                confirm_and_install
                break
                ;;
            4)
                INSTALL_SSL_SETUP=true
                get_ssl_config
                confirm_and_install
                break
                ;;
            5)
                INSTALL_HAPROXY=true
                INSTALL_XUI=true
                INSTALL_UNIFIED_DASHBOARD=true
                INSTALL_SSL_SETUP=true
                select_domain_interactive
                get_full_config
                confirm_and_install
                break
                ;;
            6)
                custom_selection
                break
                ;;
            7)
                add_ssl_to_dashboard
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
    
    # Unified Dashboard
    read -p "Install Unified Dashboard? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        INSTALL_UNIFIED_DASHBOARD=true
        select_domain_interactive
        get_dashboard_config
    fi
    
    # SSL Setup
    read -p "Setup SSL/TLS certificates? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        INSTALL_SSL_SETUP=true
        get_ssl_config
    fi
    
    confirm_and_install
}

get_dashboard_config() {
    echo
    print_section "Unified Dashboard Configuration"
    
    # Get dashboard password
    read -p "Enter password for unified dashboard (default: admin): " dashboard_pass
    if [ -n "$dashboard_pass" ]; then
        MONITOR_PASSWORD="$dashboard_pass"
    fi
    
    print_info "Dashboard password set to: $MONITOR_PASSWORD"
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
    
    # Get dashboard password
    read -p "Enter password for unified dashboard (default: admin): " dashboard_pass
    if [ -n "$dashboard_pass" ]; then
        MONITOR_PASSWORD="$dashboard_pass"
    fi
    
    # SSL setup is handled by select_domain_interactive
    if [ "$USE_HTTPS" = false ] && [ -z "$DOMAIN" ]; then
        print_info "SSL setup will be skipped (HTTP mode selected)"
        INSTALL_SSL_SETUP=false
    fi
}

add_ssl_to_dashboard() {
    print_banner
    echo -e "${WHITE}Add SSL to Existing Dashboard${NC}\n"
    
    # Check if dashboard is running
    if ! systemctl is-active --quiet unified-dashboard; then
        print_error "Unified Dashboard is not running. Please install it first."
        echo
        read -p "Press Enter to return to main menu..."
        return
    fi
    
    print_info "Current dashboard is running in HTTP mode"
    echo
    
    # Check for existing certificates and let user choose
    select_domain_interactive
    
    if [ "$USE_HTTPS" = true ] && [ -n "$DOMAIN" ]; then
        print_section "Configuring SSL for Dashboard"
        
        # Check if certificates exist, if not, set them up
        if [ ! -f "/root/cert/$DOMAIN/fullchain.pem" ] || [ ! -f "/root/cert/$DOMAIN/privkey.pem" ]; then
            print_info "SSL certificates not found. Setting up certificates..."
            INSTALL_SSL_SETUP=true
            setup_ssl
        fi
        
        # Check again if certificates exist after setup
        if [ -f "/root/cert/$DOMAIN/fullchain.pem" ] && [ -f "/root/cert/$DOMAIN/privkey.pem" ]; then
            print_info "SSL certificates found. Restarting dashboard to enable HTTPS..."
            systemctl restart unified-dashboard
            
            sleep 3
            
            if systemctl is-active --quiet unified-dashboard; then
                print_success "Dashboard updated successfully!"
                echo
                print_info "🔒 Dashboard is now available at: https://$DOMAIN:2020/"
                # Get password from service environment
                CURRENT_PASSWORD=$(systemctl show unified-dashboard -p Environment --value | grep DASHBOARD_PASSWORD | cut -d'=' -f2)
                if [ -z "$CURRENT_PASSWORD" ]; then
                    CURRENT_PASSWORD="admin"
                fi
                print_info "🔑 Password: $CURRENT_PASSWORD"
                echo
                print_info "The dashboard automatically detects SSL certificates and enables HTTPS"
            else
                print_error "Failed to restart dashboard. Check logs: journalctl -u unified-dashboard -f"
            fi
        else
            print_warning "SSL certificates not found or setup failed."
            print_info "Dashboard remains in HTTP mode."
            echo
            print_info "To manually add certificates, place them in:"
            print_info "  Certificate: /root/cert/$DOMAIN/fullchain.pem"
            print_info "  Private Key: /root/cert/$DOMAIN/privkey.pem"
            print_info "Then restart the dashboard: systemctl restart unified-dashboard"
        fi
    else
        print_info "No SSL configuration selected. Dashboard remains in HTTP mode."
    fi
    
    echo
    read -p "Press Enter to return to main menu..."
}

confirm_and_install() {
    print_banner
    echo -e "${WHITE}Installation Summary${NC}\n"
    
    echo "Components to install:"
    $INSTALL_HAPROXY && echo -e "  ${GREEN}✓${NC} HAProxy Load Balancer"
    $INSTALL_XUI && echo -e "  ${GREEN}✓${NC} X-UI Panel"
    if $INSTALL_UNIFIED_DASHBOARD; then
        if [ "$USE_HTTPS" = true ] && [ -n "$DOMAIN" ]; then
            echo -e "  ${GREEN}✓${NC} Unified Dashboard (HTTPS: $DOMAIN, Password: $MONITOR_PASSWORD)"
        else
            echo -e "  ${GREEN}✓${NC} Unified Dashboard (HTTP mode, Password: $MONITOR_PASSWORD)"
        fi
    fi
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

install_unified_dashboard() {
    print_section "Installing Unified Dashboard"
    
    print_info "Installing unified dashboard files..."
    
    # Copy unified dashboard script
    if [ -f "unified_dashboard.py" ]; then
        # Only copy if it's different or doesn't exist
        if [ ! -f "/root/unified_dashboard.py" ] || ! cmp -s "unified_dashboard.py" "/root/unified_dashboard.py"; then
            cp unified_dashboard.py /root/
            chmod +x /root/unified_dashboard.py
            print_info "Dashboard script updated"
        else
            print_info "Dashboard script already up to date"
        fi
    else
        print_error "unified_dashboard.py not found"
        return 1
    fi
    
    # Copy service file
    if [ -f "unified-dashboard.service" ]; then
        cp unified-dashboard.service /etc/systemd/system/
    else
        # Create default service file
        cat > /etc/systemd/system/unified-dashboard.service << EOF
[Unit]
Description=Unified Network Dashboard
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root
ExecStart=/usr/bin/python3 /root/unified_dashboard.py
Restart=always
RestartSec=5
Environment=DASHBOARD_PASSWORD=$MONITOR_PASSWORD
Environment=DASHBOARD_PORT=2020

[Install]
WantedBy=multi-user.target
EOF
    fi
    
    # Stop and remove old services if they exist
    print_info "Cleaning up legacy services..."
    LEGACY_SERVICES=("connection-monitor" "dashboard" "throughput-test" "legacy-panel")
    
    for service in "${LEGACY_SERVICES[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            print_info "Stopping legacy service: $service"
            systemctl stop "$service" 2>/dev/null || true
        fi
        
        if systemctl is-enabled --quiet "$service" 2>/dev/null; then
            print_info "Disabling legacy service: $service"
            systemctl disable "$service" 2>/dev/null || true
        fi
        
        # Remove service file if it exists
        if [ -f "/etc/systemd/system/$service.service" ]; then
            print_info "Removing legacy service file: $service.service"
            rm -f "/etc/systemd/system/$service.service"
        fi
    done
    
    systemctl daemon-reload
    
    # Start and enable unified service
    systemctl daemon-reload
    systemctl enable unified-dashboard.service
    systemctl start unified-dashboard.service
    
    # Verify service is running
    sleep 2
    if systemctl is-active --quiet unified-dashboard; then
        print_success "Unified Dashboard installed and started successfully"
        
            # Show appropriate URL based on HTTPS selection
    if [ "$USE_HTTPS" = true ] && [ -n "$DOMAIN" ]; then
        print_info "Access URL: https://$DOMAIN:2020/"
        print_info "Mode: HTTPS with SSL certificate"
    else
        SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "your-server-ip")
        print_info "Access URL: http://$SERVER_IP:2020/"
        print_info "Mode: HTTP (no SSL)"
        print_info "💡 You can add SSL later by selecting option 7 from the main menu"
    fi
        print_info "Password: $MONITOR_PASSWORD"
    else
        print_error "Unified Dashboard failed to start"
        print_info "Check logs with: journalctl -u unified-dashboard -f"
        return 1
    fi
}

setup_ssl() {
    print_section "Setting up SSL/TLS"
    
    if [ -z "$DOMAIN" ]; then
        print_warning "No domain specified - skipping SSL setup"
        return
    fi
    
    print_info "Setting up SSL for domain: $DOMAIN"
    
    # Check if certificates already exist
    if [ -d "/root/cert/$DOMAIN" ] && [ -f "/root/cert/$DOMAIN/fullchain.pem" ] && [ -f "/root/cert/$DOMAIN/privkey.pem" ]; then
        print_success "SSL certificates already exist for $DOMAIN"
        return
    fi
    
    # Install certbot if not available
    if ! command -v certbot &> /dev/null; then
        print_info "Installing Certbot..."
        apt update
        apt install -y certbot
    fi
    
    # Create certificate directory
    mkdir -p /root/cert/$DOMAIN
    
    echo
    print_info "SSL Certificate Setup Options:"
    echo "1) Use Certbot (automatic with Let's Encrypt)"
    echo "2) Manual certificate placement"
    echo "3) Skip SSL setup"
    echo
    
    read -p "Choose option (1-3): " ssl_choice
    
    case $ssl_choice in
        1)
            print_info "Setting up Let's Encrypt certificate..."
            echo
            print_warning "Make sure your domain $DOMAIN points to this server's IP address"
            echo
            read -p "Continue with automatic certificate generation? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                # Stop services that might use port 80
                systemctl stop nginx apache2 2>/dev/null || true
                
                # Generate certificate
                certbot certonly --standalone --non-interactive --agree-tos --register-unsafely-without-email -d "$DOMAIN"
                
                # Copy certificates to our directory
                if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
                    cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "/root/cert/$DOMAIN/"
                    cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "/root/cert/$DOMAIN/"
                    chmod 600 "/root/cert/$DOMAIN/privkey.pem"
                    print_success "SSL certificate generated and installed for $DOMAIN"
                else
                    print_error "Failed to generate SSL certificate"
                    print_info "Please check that your domain points to this server"
                fi
            else
                print_info "SSL certificate generation skipped"
            fi
            ;;
        2)
            print_info "Manual certificate setup selected"
            echo
            print_info "Please place your SSL certificate files in:"
            print_info "  Certificate: /root/cert/$DOMAIN/fullchain.pem"
            print_info "  Private Key: /root/cert/$DOMAIN/privkey.pem"
            echo
            print_info "The dashboard will automatically detect and use these certificates"
            ;;
        3)
            print_info "SSL setup skipped"
            ;;
        *)
            print_warning "Invalid choice. SSL setup skipped"
            ;;
    esac
}

run_installation() {
    print_section "Starting Installation"
    
    # Update system first
    update_system
    
    # Install selected components
    $INSTALL_HAPROXY && install_haproxy
    $INSTALL_XUI && install_xui
    $INSTALL_UNIFIED_DASHBOARD && install_unified_dashboard
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
    
    if $INSTALL_UNIFIED_DASHBOARD; then
        if systemctl is-active --quiet unified-dashboard; then
            echo -e "  ${GREEN}✓${NC} Unified Dashboard: Running"
        else
            echo -e "  ${RED}✗${NC} Unified Dashboard: Stopped"
        fi
    fi
    
    echo
    echo -e "${WHITE}Access URLs:${NC}"
    
    # Get server info - prefer domain over IP
    if [ -n "$DOMAIN" ]; then
        SERVER_DISPLAY="$DOMAIN"
        PROTOCOL="https"
    else
        SERVER_DISPLAY=$(curl -s ifconfig.me)
        PROTOCOL="http"
    fi
    
    $INSTALL_XUI && echo -e "  ${CYAN}🌐${NC} X-UI Panel: http://$SERVER_DISPLAY:$XUI_PORT/"
    $INSTALL_UNIFIED_DASHBOARD && echo -e "  ${CYAN}📊${NC} Unified Dashboard: $PROTOCOL://$SERVER_DISPLAY:2020/"
    $INSTALL_HAPROXY && echo -e "  ${CYAN}🔀${NC} HAProxy Ports: 8080, 8082, 8083, 8084, 8085, 8086"
    
    echo
    echo -e "${WHITE}Management Commands:${NC}"
    $INSTALL_HAPROXY && echo -e "  ${CYAN}▶${NC} HAProxy: systemctl status haproxy"
    $INSTALL_XUI && echo -e "  ${CYAN}▶${NC} X-UI: x-ui"
    $INSTALL_UNIFIED_DASHBOARD && echo -e "  ${CYAN}▶${NC} Unified Dashboard: systemctl status unified-dashboard"
    
    echo
    echo -e "${WHITE}Credentials:${NC}"
    $INSTALL_XUI && echo -e "  ${CYAN}🔑${NC} X-UI: $XUI_USERNAME / $XUI_PASSWORD"
    $INSTALL_UNIFIED_DASHBOARD && echo -e "  ${CYAN}🔑${NC} Unified Dashboard: any-username / $MONITOR_PASSWORD"
    
    echo
    print_success "All selected components have been installed and configured!"
    echo -e "${YELLOW}📖 Save these URLs and credentials for future reference.${NC}"
}

# =================================================================
# Main Script
# =================================================================

main() {
    print_banner
    
    # Always organize files into proper directory structure
    if [ "$(basename "$PWD")" != "core" ]; then
        print_info "Setting up proper directory structure..."
        
        # Create core directory if it doesn't exist
        if [ ! -d "core" ]; then
            mkdir core
        fi
        
        # If files exist in current directory, move them to core
        if [ -f "unified_dashboard.py" ] || [ -f "haproxy.cfg" ]; then
            print_info "Moving existing files to core directory..."
            
            # Move all relevant files to core directory
            for file in *.py *.cfg *.sh *.service *.md; do
                if [ -f "$file" ] && [ "$file" != "install.sh" ]; then
                    mv "$file" core/ 2>/dev/null || true
                fi
            done
            
            # Copy install.sh to core as well
            if [ -f "install.sh" ]; then
                cp "install.sh" core/
            fi
            
            print_success "Files moved to core directory"
        else
            # Download if no files exist
            print_info "Downloading latest version from GitHub..."
            
            # Remove existing core directory
            if [ -d "core" ]; then
                rm -rf core
            fi
            
            # Clone repository
            git clone https://github.com/mrnimwx/core.git
            
            if [ ! -d "core" ]; then
                print_error "Failed to download repository"
                exit 1
            fi
            
            print_success "Downloaded successfully"
        fi
        
        print_info "Entering core directory..."
        cd core
        
        # Clean up the parent directory (remove the moved files)
        print_info "Cleaning up parent directory..."
        cd ..
        for file in *.py *.cfg *.sh *.service *.md; do
            if [ -f "$file" ] && [ "$file" != "install.sh" ]; then
                rm -f "$file" 2>/dev/null || true
            fi
        done
        cd core
    fi
    
    # Verify we have the required files
    if [ ! -f "unified_dashboard.py" ] || [ ! -f "haproxy.cfg" ]; then
        print_error "Required files not found. Please check the installation."
        exit 1
    fi
    
    # Check requirements
    check_root
    detect_system
    
    # Show interactive menu
    get_user_choice
}

# Run the installer
main "$@" 