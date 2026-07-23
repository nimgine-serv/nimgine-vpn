# File: /root/nimgine-install/01-core-setup.sh
# Purpose: Bootstraps the environment idempotently.

#!/bin/bash
source /opt/nimgine/lib/installer_utils.sh

log_event "INFO" "Starting Phase 1: Core Infrastructure Setup"

# 1. Scaffolding Directories safely
safe_create_dir "/opt/nimgine/bin"
safe_create_dir "/opt/nimgine/core/keys"
safe_create_dir "/opt/nimgine/lib"
safe_create_dir "/opt/nimgine/logs"
safe_create_dir "/opt/nimgine/services/monitor"

# 2. Idempotent Dependency Installation
PACKAGES=(
    "curl" "wget" "git" "cron" "iptables" "lsof" "tar" "unzip" 
    "uuid-runtime" "ca-certificates" "openssl" "sqlite3" "bzip2"
    "dropbear" "stunnel4" "dante-server" "python3" "vnstat"
)

log_event "INFO" "Verifying core dependencies..."
DEBIAN_FRONTEND=noninteractive apt-get update -y > /dev/null 2>&1
# Network Optimizations (TCP BBR)
cat <<EOF > /etc/sysctl.d/99-nimgine-bbr.conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.ip_forward=1
EOF
sysctl --system >/dev/null 2>&1
for pkg in "${PACKAGES[@]}"; do
    ensure_package "$pkg"
done

log_event "INFO" "Whitelisting VPN user shell for Dropbear..."
if ! grep -qxF '/bin/false' /etc/shells; then
    echo "/bin/false" >> /etc/shells
fi

# 3. Safe Configuration Generation
CONF_FILE="/opt/nimgine/core/nimgine.conf"
if [ ! -f "$CONF_FILE" ]; then
    log_event "INFO" "Configuration file missing. Initiating interactive setup."
    
    read -p "Primary VPN Domain (e.g., vpn.nimgine.online): " DOMAIN
    read -p "Nameserver Domain (e.g., ns-vpn.nimgine.online): " NS_DOMAIN
    
    cat <<EOF > "$CONF_FILE"
# nimgine GLOBAL CONFIGURATION
BASE_DIR="/opt/nimgine"
PRIMARY_DOMAIN="$DOMAIN"
NS_DOMAIN="$NS_DOMAIN"
MAX_LOGINS_DEFAULT=2
PORT_SSH=22
PORT_DROPBEAR=109
PORT_DROPBEAR_ALT=143
PORT_WS_HTTP=80
PORT_WS_HTTPS=443
PORT_SOCKS=1080
EOF

    log_event "INFO" "Configuration saved to $CONF_FILE."
else
    log_event "INFO" "Existing configuration found. Sourcing values."
    source "$CONF_FILE"
fi

# 4. Safe Database Initialization
# (Calls the function we wrote in Phase 2)
source /opt/nimgine/lib/db.sh
init_database

log_event "INFO" "Configuring automatic UI dashboard on root login..."
if ! grep -qx "menu" /root/.bashrc; then
    echo -e "\n# Auto-start Nimgine™ Dashboard" >> /root/.bashrc
    echo '[[ $- == *i* ]] && menu' >> /root/.bashrc
fi

# Setup Log Rotation
cat <<EOF > /etc/logrotate.d/nimgine
/opt/nimgine/logs/nimgine.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    copytruncate
}
EOF

# --- Fix SSH Port Override & Ubuntu Socket Conflict ---
rm -f /etc/ssh/sshd_config.d/*

sed -i 's/^#*Port.*/Port 22/' /etc/ssh/sshd_config
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

systemctl stop ssh.socket 2>/dev/null || true
systemctl disable ssh.socket 2>/dev/null || true
systemctl enable ssh
systemctl restart ssh

log_event "INFO" "Phase 1 Complete."

