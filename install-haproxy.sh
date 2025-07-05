#!/bin/bash

echo "📦 Installing HAProxy..."
apt update && apt install -y haproxy

echo "🌐 Downloading HAProxy config from GitHub..."
curl -o /etc/haproxy/haproxy.cfg https://raw.githubusercontent.com/mrnimwx/hareproxy/main/haproxy.cfg

echo "🔄 Restarting HAProxy..."
systemctl enable haproxy
systemctl restart haproxy

echo "✅ HAProxy is set up and listening on ports 8080–8086." 