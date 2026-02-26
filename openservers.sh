#!/bin/bash

# OpenServers - Turn Your Mobile Into a Global Server
# Compatible with Termux (Android) and Linux

set -e

# ─── Paths ────────────────────────────────────────────────────────────────────
export OPENSERVERS_DIR="$HOME/.openservers"
export SERVERS_DIR="$OPENSERVERS_DIR/servers"
export CONFIG_FILE="$OPENSERVERS_DIR/config.json"
export TUNNEL_LOG="$OPENSERVERS_DIR/tunnel.log"

# Initialize directories
mkdir -p "$OPENSERVERS_DIR" "$SERVERS_DIR"

# ─── Load Modules ─────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

source "$LIB_DIR/colors.sh"
source "$LIB_DIR/ui.sh"
source "$LIB_DIR/environment.sh"
source "$LIB_DIR/server_types.sh"
source "$LIB_DIR/server_process.sh"
source "$LIB_DIR/server_manager.sh"
source "$LIB_DIR/port_tunnel.sh"
source "$LIB_DIR/settings.sh"
source "$LIB_DIR/menu.sh"

# ─── Boot ─────────────────────────────────────────────────────────────────────
clear
show_banner
echo -e "${CYAN}🌍 Welcome to OpenServers!${NC}"
echo -e "${YELLOW}Transform your device into a globally accessible server${NC}\n"

check_environment
check_dependencies
install_cloudflared
main_menu