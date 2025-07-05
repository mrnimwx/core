#!/bin/bash

echo "🗑️  Uninstalling Throughput Tester..."

# Stop and disable service
systemctl stop throughput-test.service 2>/dev/null
systemctl disable throughput-test.service 2>/dev/null

# Remove files
rm -f /etc/systemd/system/throughput-test.service
rm -f /root/throughput_test.py

# Reload systemd
systemctl daemon-reload

echo "✅ Uninstallation completed!" 