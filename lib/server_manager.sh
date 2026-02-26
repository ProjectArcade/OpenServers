#!/bin/bash

# lib/server_manager.sh — User-facing server lifecycle actions
# Sourced by openservers.sh

# ─── Helper: read port from config ───────────────────────────────────────────
_cfg_port()    { grep -oP '"port":\s*\K\d+'          "$1/config.json" 2>/dev/null; }
_cfg_exposed() { grep -oP '"exposed":\s*\K(true|false)' "$1/config.json" 2>/dev/null; }

# ─── Helper: list all server dirs with running status ────────────────────────
_list_all_servers() {
    if [ ! "$(ls -A "$SERVERS_DIR" 2>/dev/null)" ]; then
        echo -e "${YELLOW}No servers found${NC}"
        return 1
    fi

    for server_dir in "$SERVERS_DIR"/*; do
        [ -d "$server_dir" ] || continue
        local name port label status_str
        name=$(basename "$server_dir")
        port=$(_cfg_port "$server_dir")

        if [ -f "$server_dir/server.pid" ]; then
            local pid
            pid=$(cat "$server_dir/server.pid")
            if ps -p "$pid" > /dev/null 2>&1; then
                label="${GREEN}●${NC}"
                status_str="Running"
            else
                label="${RED}○${NC}"; status_str="Stopped"
            fi
        else
            label="${RED}○${NC}"; status_str="Stopped"
        fi

        echo -e "  $label $name (${status_str}, port ${port:-N/A})"
    done
    return 0
}

# ─── Helper: pick a server interactively ─────────────────────────────────────
_pick_server() {
    local prompt="${1:-Server name}"
    _list_all_servers || return 1
    echo ""
    echo -ne "${YELLOW}${prompt} (or 'cancel'): ${NC}"
    read picked
    if [ "$picked" = "cancel" ] || [ -z "$picked" ]; then
        return 1
    fi
    local dir="$SERVERS_DIR/$picked"
    if [ ! -d "$dir" ]; then
        echo -e "\n${RED}✗ Server '$picked' not found${NC}"
        sleep 2
        return 1
    fi
    echo "$picked"
}

# ─────────────────────────────────────────────────────────────────────────────
# CREATE
# ─────────────────────────────────────────────────────────────────────────────
create_server() {
    clear
    section_header "🚀 Create New Server"

    # Name
    echo -ne "${YELLOW}Server name:${NC} "
    read server_name
    if [ -z "$server_name" ]; then
        echo -e "${RED}Server name cannot be empty${NC}"; return
    fi
    if [ -d "$SERVERS_DIR/$server_name" ]; then
        echo -e "${RED}Server '$server_name' already exists${NC}"; return
    fi

    # Type
    echo -e "\n${BLUE}Choose server type:${NC}"
    echo "  1. Python (Flask/FastAPI)"
    echo "  2. Static HTML"
    echo "  3. Node.js"
    echo "  4. Custom (bring your code)"
    echo ""
    echo -ne "${YELLOW}Type (1-4): ${NC}"
    read server_type

    # Port
    echo -ne "\n${YELLOW}Port (default: 8000): ${NC}"
    read port
    port=${port:-8000}

    # Scaffold
    local SERVER_DIR="$SERVERS_DIR/$server_name"
    mkdir -p "$SERVER_DIR"

    case $server_type in
        1) create_python_server "$SERVER_DIR" "$port" ;;
        2) create_static_server "$SERVER_DIR" "$port" ;;
        3) create_node_server   "$SERVER_DIR" "$port" ;;
        4) create_custom_server "$SERVER_DIR" "$port" ;;
        *)
            echo -e "${RED}Invalid type${NC}"
            rm -rf "$SERVER_DIR"
            return
            ;;
    esac

    # Expose?
    echo -e "\n${BLUE}Expose this server globally?${NC}"
    echo "  1. Yes (via Cloudflare Tunnel - Free & Permanent URL)"
    echo "  2. No  (localhost only)"
    echo ""
    echo -ne "${YELLOW}Choice (1-2): ${NC}"
    read expose

    echo -e "\n${BLUE}Starting server...${NC}"
    start_server_process "$server_name" "$SERVER_DIR" "$port" "$expose"

    echo -e "\n${GREEN}✓ Server '$server_name' created and started!${NC}"

    if [ "$expose" = "1" ]; then
        sleep 3
        local url
        url=$(cat "$SERVER_DIR/tunnel.url" 2>/dev/null || echo "")
        if [ -n "$url" ]; then
            echo -e "\n${CYAN}═══════════════════════════════════════${NC}"
            echo -e "${GREEN}🌍 Your server is LIVE globally!${NC}"
            echo -e "${CYAN}═══════════════════════════════════════${NC}"
            echo -e "\n${YELLOW}Public URL:${NC} ${GREEN}$url${NC}"
            echo -e "${YELLOW}Local URL:${NC}  http://localhost:$port"
            echo -e "\n${BLUE}Share this URL with anyone in the world!${NC}"
        fi
    else
        echo -e "\n${YELLOW}Local URL:${NC} http://localhost:$port"
    fi

    press_enter
}

# ─────────────────────────────────────────────────────────────────────────────
# LIST
# ─────────────────────────────────────────────────────────────────────────────
list_servers() {
    clear
    section_header "📋 Running Servers"

    if [ ! "$(ls -A "$SERVERS_DIR" 2>/dev/null)" ]; then
        echo -e "${YELLOW}No servers found${NC}"
        press_enter; return
    fi

    for server_dir in "$SERVERS_DIR"/*; do
        [ -d "$server_dir" ] || continue
        local name port status url_display
        name=$(basename "$server_dir")
        port=$(_cfg_port "$server_dir")

        status=$(server_status_label "$server_dir")

        if [ -f "$server_dir/tunnel.url" ]; then
            url_display="${GREEN}$(cat "$server_dir/tunnel.url")${NC}"
        else
            url_display="http://localhost:${port:-?}"
        fi

        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${YELLOW}Server:${NC} $name"
        echo -e "${YELLOW}Status:${NC} $status"
        echo -e "${YELLOW}Port:${NC}   ${port:-N/A}"
        echo -e "${YELLOW}URL:${NC}    $url_display"
        echo ""
    done

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    press_enter
}

# ─────────────────────────────────────────────────────────────────────────────
# START
# ─────────────────────────────────────────────────────────────────────────────
start_server() {
    clear
    section_header "▶️  Start Server"

    local server_name
    server_name=$(_pick_server "Server name to start") || { press_enter; return; }

    local SERVER_DIR="$SERVERS_DIR/$server_name"

    # Already running?
    if [ -f "$SERVER_DIR/server.pid" ]; then
        local pid
        pid=$(cat "$SERVER_DIR/server.pid")
        if ps -p "$pid" > /dev/null 2>&1; then
            echo -e "\n${YELLOW}⚠ '$server_name' is already running (PID: $pid)${NC}"
            press_enter; return
        fi
    fi

    local port exposed
    port=$(_cfg_port "$SERVER_DIR")
    exposed=$(_cfg_exposed "$SERVER_DIR")

    if [ -z "$port" ]; then
        echo -e "\n${RED}✗ Configuration file not found${NC}"
        sleep 2; return
    fi

    echo -e "\n${BLUE}Starting '$server_name'...${NC}"
    start_app_process "$SERVER_DIR"
    sleep 2

    # Verify start
    if [ -f "$SERVER_DIR/server.pid" ]; then
        local pid
        pid=$(cat "$SERVER_DIR/server.pid")
        if ps -p "$pid" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Server started (PID: $pid)${NC}"
        else
            echo -e "${RED}✗ Server failed to start${NC}"
            echo -e "${YELLOW}  Check logs: cat $SERVER_DIR/server.log${NC}"
            sleep 2; return
        fi
    fi

    # Tunnel
    if [ "$exposed" = "true" ]; then
        start_tunnel "$SERVER_DIR" "$port"
    fi

    echo -e "\n${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${GREEN}✓ '$server_name' is now running!${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "\n${YELLOW}Local URL:${NC}  http://localhost:$port"

    if [ "$exposed" = "true" ] && [ -f "$SERVER_DIR/tunnel.url" ]; then
        echo -e "${YELLOW}Public URL:${NC} ${GREEN}$(cat "$SERVER_DIR/tunnel.url")${NC}"
    fi

    press_enter
}

# ─────────────────────────────────────────────────────────────────────────────
# VIEW
# ─────────────────────────────────────────────────────────────────────────────
view_server() {
    clear
    section_header "🔍 View Server Details"

    local server_name
    server_name=$(_pick_server "Server name") || { press_enter; return; }

    local SERVER_DIR="$SERVERS_DIR/$server_name"

    clear
    section_header "Server: $server_name"

    # Status
    local status_str
    status_str=$(server_status_label "$SERVER_DIR")
    if [ -f "$SERVER_DIR/server.pid" ]; then
        echo -e "$status_str (PID: $(cat "$SERVER_DIR/server.pid"))"
    else
        echo -e "$status_str"
    fi

    # Config
    local port exposed created
    port=$(_cfg_port "$SERVER_DIR")
    exposed=$(_cfg_exposed "$SERVER_DIR")
    created=$(grep -oP '"created":\s*"\K[^"]+' "$SERVER_DIR/config.json" 2>/dev/null)

    echo -e "${BLUE}Port:${NC}    ${port:-N/A}"
    echo -e "${BLUE}Created:${NC} ${created:-unknown}"
    echo -e "${BLUE}Exposed:${NC} $([ "$exposed" = "true" ] && echo "Yes (Global tunnel)" || echo "No (Localhost only)")"

    # URLs
    echo -e "\n$(divider)"
    echo -e "${YELLOW}Access URLs:${NC}"
    divider

    if [ "$SERVER_STATUS_RUNNING" = true ]; then
        echo -e "${GREEN}✓${NC} Local:  http://localhost:${port:-?}"
    else
        echo -e "${RED}✗${NC} Local:  http://localhost:${port:-?} (server stopped)"
    fi

    if [ -f "$SERVER_DIR/tunnel.url" ]; then
        local tunnel_url
        tunnel_url=$(cat "$SERVER_DIR/tunnel.url")
        if [ -f "$SERVER_DIR/tunnel.pid" ] && ps -p "$(cat "$SERVER_DIR/tunnel.pid")" > /dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} Public: $tunnel_url"
        else
            echo -e "${RED}✗${NC} Public: $tunnel_url (tunnel stopped)"
        fi
    fi

    # Server logs
    echo -e "\n$(divider)"
    echo -e "${YELLOW}Recent Server Logs:${NC}"
    divider
    if [ -f "$SERVER_DIR/server.log" ]; then
        tail -15 "$SERVER_DIR/server.log" | sed 's/^/  /'
    else
        echo -e "${YELLOW}  No logs available${NC}"
    fi

    # Tunnel logs
    if [ -f "$SERVER_DIR/tunnel.log" ]; then
        echo -e "\n$(divider)"
        echo -e "${YELLOW}Recent Tunnel Logs:${NC}"
        divider
        tail -8 "$SERVER_DIR/tunnel.log" | sed 's/^/  /'
    fi

    echo -e "\n$(divider)"
    press_enter
}

# ─────────────────────────────────────────────────────────────────────────────
# STOP
# ─────────────────────────────────────────────────────────────────────────────
stop_server() {
    clear
    section_header "⏹  Stop Server"

    local server_name
    server_name=$(_pick_server "Server name to stop") || { press_enter; return; }

    local SERVER_DIR="$SERVERS_DIR/$server_name"

    echo -e "\n${BLUE}Stopping '$server_name'...${NC}"

    local stopped_something=false
    stop_app_process "$SERVER_DIR" && stopped_something=true
    stop_tunnel "$SERVER_DIR"      && stopped_something=true

    if [ "$stopped_something" = true ]; then
        echo -e "\n${GREEN}✓ '$server_name' stopped successfully${NC}"
    else
        echo -e "\n${YELLOW}⚠ '$server_name' was not running${NC}"
    fi

    echo -e "\n${BLUE}What would you like to do?${NC}"
    echo "  1. Return to main menu"
    echo "  2. Exit OpenServers"
    echo ""
    echo -ne "${YELLOW}Choice (1-2): ${NC}"
    read exit_choice

    if [ "$exit_choice" = "2" ]; then
        echo -e "\n${GREEN}👋 Thanks for using OpenServers!${NC}\n"
        exit 0
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# DELETE
# ─────────────────────────────────────────────────────────────────────────────
delete_server() {
    clear
    section_header "🗑  Delete Server"

    local server_name
    server_name=$(_pick_server "Server name to delete") || { press_enter; return; }

    local SERVER_DIR="$SERVERS_DIR/$server_name"

    echo -e "\n${RED}⚠  WARNING: This will permanently delete the server!${NC}"
    echo -e "${YELLOW}   Server: $server_name${NC}"
    echo -e "${YELLOW}   Path:   $SERVER_DIR${NC}"
    echo ""
    echo -ne "${RED}Type 'yes' to confirm deletion: ${NC}"
    read confirm

    if [ "$confirm" = "yes" ]; then
        echo -e "\n${BLUE}Deleting '$server_name'...${NC}"

        stop_app_process "$SERVER_DIR" 2>/dev/null || true
        stop_tunnel      "$SERVER_DIR" 2>/dev/null || true

        echo -ne "${YELLOW}  Removing files...${NC} "
        rm -rf "$SERVER_DIR"
        echo -e "${GREEN}✓${NC}"
        echo -e "\n${GREEN}✓ '$server_name' deleted successfully${NC}"
    else
        echo -e "\n${YELLOW}Deletion cancelled${NC}"
    fi

    press_enter
}