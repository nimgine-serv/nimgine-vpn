#!/bin/bash
# File: /opt/nimgine/installers/02-deploy-routing.sh
# Purpose: Idempotent deployment of Dropbear, Stunnel, and the Async Proxy.

source /opt/nimgine/core/nimgine.conf
source /opt/nimgine/lib/installer_utils.sh

log_event "INFO" "Deploying Phase 2: Data Plane & Routing Engine"

safe_create_dir "/opt/nimgine/services/routing"

# --- 1. Configure Dropbear & OpenSSH ---
log_event "INFO" "Configuring Dropbear and OpenSSH..."

# Write the Premium Default Banner
cat <<'EOF' > /etc/issue.net
</strong> <p style="text-align:center"><b> <br>
<font color="#00aaaa">════════════════════════════</font><br>
<b><font color="#00ffff">NIMGINE™ LTD PREMIUM VPN</font><br>
<font color="#00aaaa">════════════════════════════</font><br>
<b><font color="#ff00ff">GET YOUR SUBSCRIPTION</font></b><br>
<font color="#ff00ff">Bot: t.me/Nimginebot</font><br>
<font color="#ff00ff">Channel: t.me/nimgine_tech</font><b><br>
<font color="#00aaaa">════════════════════════════</font><br>
<b><font color="#ff4444">TERMS OF SERVICE</font></b><br>
<font color="#ff8800">- No Abuse, Spam, Illegal -</font><br>
<font color="#ff8800">- Do Not Share Configs -</font><br>
<font color="#ff8800">- Violation = Termination -</font><br>
<font color="#00aaaa">════════════════════════════</font><br>
<font color="#00ffff">Powered by Nimgine™</font><br>
<font color="#aaaaaa">nimgine.online</font><br>
<font color="#00aaaa">════════════════════════════</font><br>
</b></p>
EOF

# Enforce banner globally (Ubuntu 20/22/24 & Debian 11/12 fix)
# 1. Fallback for older OS
sed -i 's/#Banner.*/Banner \/etc\/issue.net/g' /etc/ssh/sshd_config
if ! grep -q "^Banner /etc/issue.net" /etc/ssh/sshd_config; then
    echo "Banner /etc/issue.net" >> /etc/ssh/sshd_config
fi
sed -i 's/#MaxStartups.*/MaxStartups 1000:30:2000/g' /etc/ssh/sshd_config
if ! grep -q "^MaxStartups" /etc/ssh/sshd_config; then
    echo "MaxStartups 1000:30:2000" >> /etc/ssh/sshd_config
fi
sed -i 's/#ClientAliveInterval.*/ClientAliveInterval 60/g' /etc/ssh/sshd_config
if ! grep -q "^ClientAliveInterval" /etc/ssh/sshd_config; then
    echo "ClientAliveInterval 60" >> /etc/ssh/sshd_config
fi
sed -i 's/#ClientAliveCountMax.*/ClientAliveCountMax 3/g' /etc/ssh/sshd_config
if ! grep -q "^ClientAliveCountMax" /etc/ssh/sshd_config; then
    echo "ClientAliveCountMax 3" >> /etc/ssh/sshd_config
fi

# 2. Priority Drop-in for Modern OS (Ubuntu 24.04+)
mkdir -p /etc/ssh/sshd_config.d
echo "Banner /etc/issue.net" > /etc/ssh/sshd_config.d/99-nimgine-banner.conf
echo "MaxStartups 1000:30:2000" >> /etc/ssh/sshd_config.d/99-nimgine-banner.conf
echo "ClientAliveInterval 60" >> /etc/ssh/sshd_config.d/99-nimgine-banner.conf
echo "ClientAliveCountMax 3" >> /etc/ssh/sshd_config.d/99-nimgine-banner.conf

# 3. Reload Daemons (Including Ubuntu 24 Socket Activation)
systemctl daemon-reload
systemctl restart ssh >/dev/null 2>&1 || systemctl restart sshd >/dev/null 2>&1
systemctl restart ssh.socket >/dev/null 2>&1

# Configure Dropbear ports and explicitly force the banner flag (-b)
cat <<EOF > /etc/default/dropbear
NO_START=0
DROPBEAR_PORT=${PORT_DROPBEAR}
DROPBEAR_EXTRA_ARGS="-p ${PORT_DROPBEAR_ALT} -w -g -K 60 -I 0 -b /etc/issue.net"
DROPBEAR_RECEIVE_WINDOW=65536
EOF

systemctl daemon-reload
systemctl enable dropbear >/dev/null 2>&1
systemctl restart dropbear

# --- 2. The Async WebSocket Proxy ---
log_event "INFO" "Deploying Async WebSocket Multiplexer..."

# The master installer already placed the file here, just ensure it's executable
chmod +x /opt/nimgine/services/routing/ws-proxy.py

cat <<EOF > /tmp/nimgine-ws.service.tmp
[Unit]
Description=nimgine Async WS Multiplexer
After=network.target dropbear.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/nimgine/services/routing
ExecStart=/usr/bin/python3 /opt/nimgine/services/routing/ws-proxy.py
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

safe_deploy_systemd "nimgine-ws"

# --- 3. Stunnel (SSL Termination) ---
log_event "INFO" "Configuring Stunnel4 TLS Bridging..."

# Use our idempotent TLS generator
ensure_tls_cert "$PRIMARY_DOMAIN"

cat <<EOF > /etc/stunnel/stunnel.conf
pid = /var/run/stunnel.pid
cert = /opt/nimgine/core/keys/stunnel.pem
client = no
socket = a:SO_REUSEADDR=1
socket = a:SO_KEEPALIVE=1
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1

[ssh-ws-ssl]
accept = ${PORT_WS_HTTPS}
connect = 127.0.0.1:${PORT_WS_HTTP}

[dropbear-ssl-447]
accept = 447
connect = 127.0.0.1:${PORT_SSH}

[dropbear-ssl-777]
accept = 777
connect = 127.0.0.1:${PORT_SSH}
EOF

# Ensure Stunnel boot flag is enabled
sed -i 's/ENABLED=0/ENABLED=1/g' /etc/default/stunnel4

systemctl enable stunnel4 >/dev/null 2>&1
systemctl restart stunnel4

# --- Open All Service Ports & Save Persistently ---
echo iptables-persistent iptables-persistent/enable-ipv4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/enable-ipv6 boolean true | debconf-set-selections
apt-get update && apt-get install -y iptables-persistent netfilter-persistent

# Open Dashboard Ports
iptables -I INPUT -p tcp --dport 22 -j ACCEPT
iptables -I INPUT -p tcp --dport 109 -j ACCEPT
iptables -I INPUT -p tcp --dport 143 -j ACCEPT
iptables -I INPUT -p tcp --dport 447 -j ACCEPT
iptables -I INPUT -p tcp --dport 777 -j ACCEPT
iptables -I INPUT -p tcp --dport 80 -j ACCEPT
iptables -I INPUT -p tcp --dport 443 -j ACCEPT
iptables -I INPUT -p tcp --dport 8880 -j ACCEPT
iptables -I INPUT -p tcp --dport 1080 -j ACCEPT
iptables -I INPUT -p tcp --dport 53 -j ACCEPT
iptables -I INPUT -p udp --dport 53 -j ACCEPT
iptables -I INPUT -p tcp --dport 5300 -j ACCEPT
iptables -I INPUT -p udp --dport 5300 -j ACCEPT
iptables -I INPUT -p udp --dport 1:65535 -j ACCEPT

# Save rules so they survive server reboots
netfilter-persistent save
systemctl enable netfilter-persistent

log_event "INFO" "Routing Engine Deployed Successfully."
