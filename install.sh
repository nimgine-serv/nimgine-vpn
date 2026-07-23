#!/bin/bash
# File: install.sh
# Purpose: Master Orchestrator for Nimgine™ Services  Platform.

REPO_URL="https://raw.githubusercontent.com/nimgine-serv/nimgine-vpn/main"

# --- UI Colors ---
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
ORANGE='\033[0;33m'
NC='\033[0m'

clear
echo -e "${CYAN}======================================================${NC}"
echo -e "${GREEN}      NIMGINE™ SERVICES SCRIPT DEPLOYMENT PIPELINE        ${NC}"
echo -e "${CYAN}======================================================${NC}"

if [ "${EUID}" -ne 0 ]; then
    echo -e "${RED}[FATAL] Please run as root. (Type: sudo su -)${NC}"
    exit 1
fi

# Ensure basic fetch tools are present before we even start
apt-get update -y >/dev/null 2>&1
apt-get install -y curl wget >/dev/null 2>&1

# --- 1. System Scaffolding ---
echo -e "${CYAN}[*] Bootstrapping Base Architecture...${NC}"
mkdir -p /opt/nimgine/{bin,lib,logs,menus,services,core}
mkdir -p /opt/nimgine/core/keys
mkdir -p /opt/nimgine/services/{monitor,routing}
mkdir -p /root/nimgine-tmp
cd /root/nimgine-tmp

# --- 2. Secure Fetch Function ---
# This function guarantees we don't accidentally execute a 404 HTML page.
fetch_file() {
    local remote_path="$1"
    local local_path="$2"
    
    echo -e "  -> Fetching: ${remote_path}"
    curl -sS -L -o "$local_path" "${REPO_URL}/${remote_path}"
    
    # FIX: Use regex bracket so the file doesn't literally contain the 404 string
    if [ ! -s "$local_path" ] || grep -q "404: N[o]t Found" "$local_path"; then
        echo -e "${RED}[FATAL] Failed to download ${remote_path}. Halting to prevent system corruption.${NC}"
        exit 1
    fi
}

# --- 3. Stage Libraries & Core Files ---
echo -e "\n${CYAN}[*] Staging Core Libraries & APIs...${NC}"

# Fetching the libraries we built
fetch_file "lib/system.sh" "/opt/nimgine/lib/system.sh"
fetch_file "lib/installer_utils.sh" "/opt/nimgine/lib/installer_utils.sh"
fetch_file "lib/db.sh" "/opt/nimgine/lib/db.sh"
fetch_file "lib/users.sh" "/opt/nimgine/lib/users.sh"
fetch_file "lib/services.sh" "/opt/nimgine/lib/services.sh"

# Fetching the CLI router and Menu
fetch_file "bin/nimgine" "/opt/nimgine/bin/nimgine"
fetch_file "menus/main_menu.sh" "/opt/nimgine/menus/main_menu.sh"

# Apply execution permissions to bin/menus
chmod +x /opt/nimgine/bin/nimgine
chmod +x /opt/nimgine/menus/main_menu.sh

# Fetching the Python services
fetch_file "services/monitor/daemon.py" "/opt/nimgine/services/monitor/daemon.py"
fetch_file "services/routing/async-ws-proxy.py" "/opt/nimgine/services/routing/ws-proxy.py"

# --- 4. Fetch & Execute Deployment Phases ---
echo -e "\n${GREEN}[*] Initiating Deployment Phases...${NC}"

PHASES=(
    "01-core-setup.sh"
    "02-deploy-routing.sh"
    "03-deploy-sidecars.sh"
    "04-deploy-monitor.sh"
)

for PHASE in "${PHASES[@]}"; do
    fetch_file "installers/${PHASE}" "/root/nimgine-tmp/${PHASE}"
    chmod +x "/root/nimgine-tmp/${PHASE}"
    
    echo -e "\n${ORANGE}>>> Executing Phase: ${PHASE} <<<${NC}"
    /root/nimgine-tmp/"${PHASE}"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}[FATAL] Phase ${PHASE} failed. Halting installation to protect OS integrity.${NC}"
        exit 1
    fi
done

# --- 5. Symlink Global Commands ---
echo -e "\n${CYAN}[*] Binding Global CLI Interfaces...${NC}"

# Safely remove old hardcoded binaries if they exist from the v1 script
rm -f /usr/bin/menu /usr/local/sbin/menu /usr/local/bin/nimgine

# Symlink the new modular paths globally
ln -sf /opt/nimgine/menus/main_menu.sh /usr/local/sbin/menu
ln -sf /opt/nimgine/bin/nimgine /usr/local/bin/nimgine

# --- 6. Cleanup & Finalization ---
cd /root
rm -rf /root/nimgine-tmp

echo -e "\n${CYAN}======================================================${NC}"
echo -e "${GREEN}    NIMGINE™ VPN SCRIPT DEPLOYMENT COMPLETED                   ${NC}"
echo -e "${CYAN}======================================================${NC}"
echo -e "Your infrastructure is now running safely in ${ORANGE}/opt/nimgine${NC}"
echo -e "Type ${GREEN}menu${NC} to access the UI dashboard."
echo -e "Type ${GREEN}nimgine${NC} to access the headless API commands."

