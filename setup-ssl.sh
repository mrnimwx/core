#!/bin/bash

# Easy SSL Setup Script with Let's Encrypt
# Automatically sets up SSL certificates for throughput testing

echo "🔐 Easy SSL Setup with Let's Encrypt"
echo "===================================="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root"
   exit 1
fi

# Function to detect OS
detect_os() {
    if [[ -f /etc/debian_version ]]; then
        OS="debian"
        PKG_MANAGER="apt-get"
    elif [[ -f /etc/redhat-release ]]; then
        OS="redhat"
        PKG_MANAGER="yum"
    elif [[ -f /etc/arch-release ]]; then
        OS="arch"
        PKG_MANAGER="pacman"
    else
        echo "❌ Unsupported operating system"
        exit 1
    fi
    echo "✅ Detected OS: $OS"
}

# Function to install certbot
install_certbot() {
    echo "📦 Installing Certbot..."
    
    case $OS in
        debian)
            apt-get update
            apt-get install -y certbot python3-certbot-nginx snapd
            # Try snap installation as fallback
            if ! command -v certbot &> /dev/null; then
                snap install --classic certbot
                ln -sf /snap/bin/certbot /usr/bin/certbot
            fi
            ;;
        redhat)
            yum install -y epel-release
            yum install -y certbot python3-certbot-nginx snapd
            # Try snap installation as fallback
            if ! command -v certbot &> /dev/null; then
                snap install --classic certbot
                ln -sf /snap/bin/certbot /usr/bin/certbot
            fi
            ;;
        arch)
            pacman -Sy --noconfirm certbot certbot-nginx
            ;;
    esac
    
    if command -v certbot &> /dev/null; then
        echo "✅ Certbot installed successfully"
    else
        echo "❌ Failed to install Certbot"
        exit 1
    fi
}

# Function to validate domain
validate_domain() {
    local domain=$1
    
    # Basic domain validation - simplified and more permissive
    if [[ ! $domain =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] || [[ $domain =~ \.\. ]] || [[ $domain =~ ^[.-] ]] || [[ $domain =~ [.-]$ ]]; then
        echo "❌ Invalid domain format"
        echo "ℹ️  Domain should be in format: example.com or subdomain.example.com"
        echo "ℹ️  Your domain: $domain"
        return 1
    fi
    
    # Check if domain resolves to this server
    echo "🔍 Checking if domain points to this server..."
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || curl -s icanhazip.com 2>/dev/null)
    DOMAIN_IP=$(dig +short $domain 2>/dev/null | tail -n1)
    
    if [[ -z "$SERVER_IP" ]]; then
        echo "⚠️  Warning: Could not detect server IP"
        read -p "Continue anyway? [y/N]: " CONTINUE
        if [[ ! $CONTINUE =~ ^[Yy]$ ]]; then
            return 1
        fi
    elif [[ "$SERVER_IP" != "$DOMAIN_IP" ]]; then
        echo "⚠️  Warning: Domain ($DOMAIN_IP) doesn't point to this server ($SERVER_IP)"
        read -p "Continue anyway? [y/N]: " CONTINUE
        if [[ ! $CONTINUE =~ ^[Yy]$ ]]; then
            return 1
        fi
    else
        echo "✅ Domain correctly points to this server"
    fi
    
    return 0
}

# Function to setup nginx for certificate validation
setup_nginx() {
    local domain=$1
    
    echo "🌐 Setting up Nginx for certificate validation..."
    
    # Install nginx if not present
    case $OS in
        debian)
            if ! command -v nginx &> /dev/null; then
                apt-get install -y nginx
            fi
            ;;
        redhat)
            if ! command -v nginx &> /dev/null; then
                yum install -y nginx
            fi
            ;;
        arch)
            if ! command -v nginx &> /dev/null; then
                pacman -Sy --noconfirm nginx
            fi
            ;;
    esac
    
    # Create minimal nginx config
    cat > /etc/nginx/sites-available/$domain <<EOF
server {
    listen 80;
    server_name $domain;
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}
EOF
    
    # Enable site
    if [[ -d /etc/nginx/sites-enabled ]]; then
        ln -sf /etc/nginx/sites-available/$domain /etc/nginx/sites-enabled/
    fi
    
    # Test nginx config
    nginx -t
    if [[ $? -eq 0 ]]; then
        systemctl restart nginx
        systemctl enable nginx
        echo "✅ Nginx configured successfully"
    else
        echo "❌ Nginx configuration error"
        return 1
    fi
}

# Function to obtain SSL certificate
obtain_certificate() {
    local domain=$1
    local email=$2
    
    echo "🔐 Obtaining SSL certificate for $domain..."
    
    # Create webroot directory
    mkdir -p /var/www/html
    
    # Obtain certificate using webroot method
    certbot certonly \
        --webroot \
        --webroot-path=/var/www/html \
        --email "$email" \
        --agree-tos \
        --no-eff-email \
        --domains "$domain" \
        --non-interactive
    
    if [[ $? -eq 0 ]]; then
        echo "✅ SSL certificate obtained successfully"
        return 0
    else
        echo "❌ Failed to obtain SSL certificate"
        echo "🔄 Trying standalone method..."
        
        # Stop nginx temporarily for standalone method
        systemctl stop nginx
        
        # Try standalone method
        certbot certonly \
            --standalone \
            --email "$email" \
            --agree-tos \
            --no-eff-email \
            --domains "$domain" \
            --non-interactive
        
        # Restart nginx
        systemctl start nginx
        
        if [[ $? -eq 0 ]]; then
            echo "✅ SSL certificate obtained successfully (standalone method)"
            return 0
        else
            echo "❌ Failed to obtain SSL certificate with both methods"
            return 1
        fi
    fi
}

# Function to setup certificate directory structure
setup_cert_structure() {
    local domain=$1
    
    echo "📁 Setting up certificate directory structure..."
    
    # Create cert directory
    mkdir -p /root/cert/$domain
    
    # Copy certificates to our structure
    cp /etc/letsencrypt/live/$domain/fullchain.pem /root/cert/$domain/
    cp /etc/letsencrypt/live/$domain/privkey.pem /root/cert/$domain/
    
    # Set proper permissions
    chmod 600 /root/cert/$domain/privkey.pem
    chmod 644 /root/cert/$domain/fullchain.pem
    
    echo "✅ Certificate structure setup complete"
    echo "📋 Certificates available at: /root/cert/$domain/"
}

# Function to setup auto-renewal
setup_auto_renewal() {
    echo "🔄 Setting up automatic certificate renewal..."
    
    # Create renewal script
    cat > /root/renew-certs.sh <<'EOF'
#!/bin/bash

# Certificate renewal script
echo "🔄 Renewing SSL certificates..."

# Renew certificates
certbot renew --quiet

# Copy renewed certificates to our structure
for cert_dir in /etc/letsencrypt/live/*/; do
    if [[ -d "$cert_dir" ]]; then
        domain=$(basename "$cert_dir")
        if [[ -d "/root/cert/$domain" ]]; then
            cp "$cert_dir/fullchain.pem" "/root/cert/$domain/"
            cp "$cert_dir/privkey.pem" "/root/cert/$domain/"
            chmod 600 "/root/cert/$domain/privkey.pem"
            chmod 644 "/root/cert/$domain/fullchain.pem"
            echo "✅ Updated certificates for $domain"
        fi
    fi
done

# Restart services that use certificates
systemctl restart throughput-test.service 2>/dev/null
systemctl restart nginx 2>/dev/null

echo "🎉 Certificate renewal completed"
EOF
    
    chmod +x /root/renew-certs.sh
    
    # Add to crontab
    (crontab -l 2>/dev/null; echo "0 3 * * * /root/renew-certs.sh >> /var/log/cert-renewal.log 2>&1") | crontab -
    
    echo "✅ Auto-renewal setup complete"
    echo "📋 Certificates will be renewed automatically at 3 AM daily"
}

# Function to test certificate
test_certificate() {
    local domain=$1
    
    echo "🧪 Testing SSL certificate..."
    
    # Test with openssl
    echo | openssl s_client -connect $domain:443 -servername $domain 2>/dev/null | openssl x509 -noout -dates
    
    if [[ $? -eq 0 ]]; then
        echo "✅ SSL certificate test passed"
    else
        echo "⚠️  SSL certificate test failed (this is normal if nginx is not configured for HTTPS)"
    fi
}

# Main function
main() {
    detect_os
    
    echo ""
    echo "📋 This script will:"
    echo "1. Install Certbot (Let's Encrypt client)"
    echo "2. Setup Nginx for certificate validation"
    echo "3. Obtain SSL certificate for your domain"
    echo "4. Setup certificate directory structure"
    echo "5. Configure automatic renewal"
    echo ""
    
    # Get domain
    read -p "🌐 Enter your domain name (e.g., example.com): " DOMAIN
    
    if [[ -z "$DOMAIN" ]]; then
        echo "❌ Domain cannot be empty"
        exit 1
    fi
    
    # Validate domain
    if ! validate_domain "$DOMAIN"; then
        echo "❌ Domain validation failed"
        exit 1
    fi
    
    # Get email
    read -p "📧 Enter your email address for Let's Encrypt: " EMAIL
    
    if [[ -z "$EMAIL" ]]; then
        echo "❌ Email cannot be empty"
        exit 1
    fi
    
    # Confirm setup
    echo ""
    echo "📋 Setup Summary:"
    echo "Domain: $DOMAIN"
    echo "Email: $EMAIL"
    echo ""
    read -p "Proceed with SSL setup? [y/N]: " CONFIRM
    
    if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
        echo "❌ Setup cancelled"
        exit 1
    fi
    
    echo ""
    echo "🚀 Starting SSL setup..."
    
    # Install certbot
    install_certbot
    
    # Setup nginx
    setup_nginx "$DOMAIN"
    
    # Obtain certificate
    if obtain_certificate "$DOMAIN" "$EMAIL"; then
        # Setup certificate structure
        setup_cert_structure "$DOMAIN"
        
        # Setup auto-renewal
        setup_auto_renewal
        
        # Test certificate
        test_certificate "$DOMAIN"
        
        echo ""
        echo "🎉 SSL Setup Complete!"
        echo "================================"
        echo "✅ SSL certificate obtained for: $DOMAIN"
        echo "📁 Certificates stored in: /root/cert/$DOMAIN/"
        echo "🔄 Auto-renewal configured"
        echo "🌐 Your domain is now ready for HTTPS"
        echo ""
        echo "📋 Next steps:"
        echo "1. Install throughput test: bash <(curl -sSL https://raw.githubusercontent.com/mrnimwx/core/main/install-tlstest.sh)"
        echo "2. Test your setup: https://$DOMAIN:2020/"
        echo ""
    else
        echo "❌ SSL setup failed"
        exit 1
    fi
}

# Run main function
main 