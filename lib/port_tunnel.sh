#!/bin/bash

# lib/port_tunnel.sh — Expose any local port through a Cloudflare tunnel
#
# KEY FEATURE: Auto-detects services bound only to 127.0.0.1 (e.g. llama.cpp)
# and transparently bridges them to 0.0.0.0 via a Python TCP proxy so
# cloudflared can reach them — no restart of the original service required.
#
# State per tunnel ($OPENSERVERS_DIR/port-tunnels/<n>/):
#   config.json   – name, port, loopback flag, created timestamp
#   tunnel.log    – cloudflared stdout/stderr
#   tunnel.pid    – cloudflared PID
#   tunnel.url    – resolved public URL
#   proxy.pid     – python bridge PID  (only in loopback mode)
#   proxy.port    – bridge listen port (only in loopback mode)
#   proxy.py      – the bridge script  (only in loopback mode)
#
# Sourced by openservers.sh

PORT_TUNNELS_DIR="$OPENSERVERS_DIR/port-tunnels"
mkdir -p "$PORT_TUNNELS_DIR"

# ─── Config helpers ───────────────────────────────────────────────────────────

_pt_dir()        { echo "$PORT_TUNNELS_DIR/$1"; }
_pt_port()       { grep -oP '"port":\s*\K\d+'              "$(_pt_dir "$1")/config.json" 2>/dev/null; }
_pt_created()    { grep -oP '"created":\s*"\K[^"]+'         "$(_pt_dir "$1")/config.json" 2>/dev/null; }
_pt_loopback()   { grep -oP '"loopback":\s*\K(true|false)' "$(_pt_dir "$1")/config.json" 2>/dev/null; }
_pt_proxy_port() { cat "$(_pt_dir "$1")/proxy.port" 2>/dev/null; }

_pt_save_config() {
    local name="$1" port="$2" loopback="${3:-false}"
    cat > "$(_pt_dir "$name")/config.json" << EOF
{
    "name": "$name",
    "port": $port,
    "loopback": $loopback,
    "created": "$(date)"
}
EOF
}

# ─── Status helpers ───────────────────────────────────────────────────────────

_pt_is_alive() {
    local pid_file="$(_pt_dir "$1")/tunnel.pid"
    [ -f "$pid_file" ] || return 1
    ps -p "$(cat "$pid_file")" > /dev/null 2>&1
}

_pt_proxy_alive() {
    local pid_file="$(_pt_dir "$1")/proxy.pid"
    [ -f "$pid_file" ] || return 1
    ps -p "$(cat "$pid_file")" > /dev/null 2>&1
}

_pt_list_all() {
    if [ ! "$(ls -A "$PORT_TUNNELS_DIR" 2>/dev/null)" ]; then
        echo -e "${YELLOW}No port tunnels found${NC}"
        return 1
    fi
    for d in "$PORT_TUNNELS_DIR"/*/; do
        [ -d "$d" ] || continue
        local name port label
        name=$(basename "$d")
        port=$(_pt_port "$name")
        _pt_is_alive "$name" && label="${GREEN}●${NC}" || label="${RED}○${NC}"
        local url_hint=""
        [ -f "$d/tunnel.url" ] && url_hint=" → $(cat "$d/tunnel.url")"
        echo -e "  $label $name  (port ${port:-?})${url_hint}"
    done
    return 0
}

_pt_pick() {
    local prompt="${1:-Tunnel name}"
    _pt_list_all || return 1
    echo ""
    echo -ne "${YELLOW}${prompt} (or 'cancel'): ${NC}"
    read picked
    [ "$picked" = "cancel" ] || [ -z "$picked" ] && return 1
    if [ ! -d "$(_pt_dir "$picked")" ]; then
        echo -e "\n${RED}✗ Tunnel '$picked' not found${NC}"; sleep 2; return 1
    fi
    echo "$picked"
}

# ─── Loopback detection ───────────────────────────────────────────────────────
# Returns 0 (true) if the port is ONLY bound to 127.0.0.1 — not 0.0.0.0 / ::

_pt_is_loopback_only() {
    local port="$1"

    if command -v ss &>/dev/null; then
        local bindings
        bindings=$(ss -tln 2>/dev/null | grep ":${port} ")
        [ -z "$bindings" ] && return 1   # nothing listening
        echo "$bindings" | grep -qE '0\.0\.0\.0:|::' && return 1  # already global
        return 0   # only loopback lines found
    fi

    if command -v netstat &>/dev/null; then
        local bindings
        bindings=$(netstat -tln 2>/dev/null | grep ":${port} ")
        [ -z "$bindings" ] && return 1
        echo "$bindings" | grep -qE '0\.0\.0\.0:|:::' && return 1
        return 0
    fi

    return 1   # can't tell — assume accessible
}

# ─── Python TCP proxy ─────────────────────────────────────────────────────────
# Bridges 0.0.0.0:PROXY_PORT → 127.0.0.1:TARGET_PORT
# Writes proxy.pid and proxy.port; returns the proxy port number on stdout.

_pt_start_proxy() {
    local dir="$1"
    local target_port="$2"

    # Choose a free proxy port
    local proxy_port=$(( target_port + 10000 ))
    if ss -tln 2>/dev/null | grep -q ":${proxy_port} " || \
       netstat -tln 2>/dev/null | grep -q ":${proxy_port} " 2>/dev/null; then
        proxy_port=$(( RANDOM % 10000 + 40000 ))
    fi

    cat > "$dir/proxy.py" << PYEOF
import socket, threading, sys

TARGET_HOST = '127.0.0.1'
TARGET_PORT = int(sys.argv[1])
LISTEN_PORT = int(sys.argv[2])

def forward(src, dst):
    try:
        while True:
            data = src.recv(4096)
            if not data:
                break
            dst.sendall(data)
    except Exception:
        pass
    finally:
        try: src.close()
        except: pass
        try: dst.close()
        except: pass

def handle(client):
    try:
        remote = socket.create_connection((TARGET_HOST, TARGET_PORT), timeout=10)
        t1 = threading.Thread(target=forward, args=(client, remote), daemon=True)
        t2 = threading.Thread(target=forward, args=(remote, client), daemon=True)
        t1.start(); t2.start()
        t1.join(); t2.join()
    except Exception:
        try: client.close()
        except: pass

srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(('0.0.0.0', LISTEN_PORT))
srv.listen(64)
print(f'Proxy ready: 0.0.0.0:{LISTEN_PORT} -> 127.0.0.1:{TARGET_PORT}', flush=True)
while True:
    client, _ = srv.accept()
    threading.Thread(target=handle, args=(client,), daemon=True).start()
PYEOF

    nohup python3 "$dir/proxy.py" "$target_port" "$proxy_port" \
        > "$dir/proxy.log" 2>&1 &
    echo $! > "$dir/proxy.pid"
    echo "$proxy_port" > "$dir/proxy.port"

    # Wait for the proxy to print its ready line
    local i
    for i in {1..10}; do
        sleep 0.5
        grep -q "Proxy ready" "$dir/proxy.log" 2>/dev/null && break
    done

    echo "$proxy_port"
}

_pt_stop_proxy() {
    local dir="$1"
    local pid_file="$dir/proxy.pid"
    [ -f "$pid_file" ] || return 0
    local pid; pid=$(cat "$pid_file")
    ps -p "$pid" > /dev/null 2>&1 && kill "$pid" 2>/dev/null
    rm -f "$pid_file" "$dir/proxy.port" "$dir/proxy.py" "$dir/proxy.log"
}

# ─── URL extraction ───────────────────────────────────────────────────────────

_pt_extract_url_from_log() {
    local dir="$1"
    local log="$dir/tunnel.log"
    local url=""

    url=$(grep -oE 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' "$log" 2>/dev/null | head -1)
    [ -z "$url" ] && url=$(grep -oP '(?<=url=)https://\S+trycloudflare\.com' "$log" 2>/dev/null | head -1)
    [ -z "$url" ] && url=$(grep -oP 'https://\S+trycloudflare\.com' "$log" 2>/dev/null | head -1)
    if [ -z "$url" ]; then
        local host
        host=$(grep -oP '[a-zA-Z0-9-]+\.trycloudflare\.com' "$log" 2>/dev/null | head -1)
        [ -n "$host" ] && url="https://$host"
    fi

    if [ -n "$url" ]; then
        echo "$url" > "$dir/tunnel.url"
        TUNNEL_URL="$url"
        return 0
    fi
    TUNNEL_URL=""; return 1
}

_pt_wait_for_url() {
    local dir="$1"
    echo -n "  Waiting for public URL"
    local i
    for i in {1..30}; do
        sleep 1; echo -n "."
        _pt_extract_url_from_log "$dir" 2>/dev/null && break
    done
    echo ""
    if [ -n "$TUNNEL_URL" ]; then
        echo -e "  ${GREEN}✓ Public URL:${NC} ${GREEN}${TUNNEL_URL}${NC}"
    else
        echo -e "  ${YELLOW}⚠ URL not captured yet — use option 3 'Show URL' to retry${NC}"
    fi
}

# ─── CREATE ───────────────────────────────────────────────────────────────────

port_tunnel_create() {
    clear
    section_header "🌐 Expose Local Port to Internet"

    echo -e "${BLUE}Share ANY port running on this device globally.${NC}"
    echo -e "${BLUE}Works even for services bound to 127.0.0.1 (like llama.cpp).${NC}\n"

    # Name
    echo -ne "${YELLOW}Tunnel name (e.g. llama, react-dev): ${NC}"
    read tname
    [ -z "$tname" ] && { echo -e "${RED}Name cannot be empty${NC}"; press_enter; return; }
    tname="${tname// /-}"
    if [ -d "$(_pt_dir "$tname")" ]; then
        echo -e "${RED}A tunnel named '$tname' already exists${NC}"; press_enter; return
    fi

    # Port
    echo -ne "${YELLOW}Local port to expose (e.g. 8080, 3130): ${NC}"
    read tport
    if ! [[ "$tport" =~ ^[0-9]+$ ]] || [ "$tport" -lt 1 ] || [ "$tport" -gt 65535 ]; then
        echo -e "${RED}Invalid port number${NC}"; press_enter; return
    fi

    # Protocol
    echo -e "\n${BLUE}Protocol:${NC}"
    echo "  1. HTTP  (web apps, APIs, LLMs — most common)"
    echo "  2. HTTPS (only if your app already uses TLS)"
    echo ""
    echo -ne "${YELLOW}Choice (1-2, default 1): ${NC}"
    read proto_choice
    local scheme="http"
    [ "$proto_choice" = "2" ] && scheme="https"

    # Loopback check
    echo -e "\n${CYAN}─────────────────────────────────────${NC}"
    echo -e "${BLUE}Checking port $tport binding...${NC}"

    local needs_proxy=false
    local effective_port="$tport"
    local loopback_flag="false"

    if _pt_is_loopback_only "$tport"; then
        needs_proxy=true
        loopback_flag="true"
        echo -e "${YELLOW}⚠ Detected: port $tport is bound to 127.0.0.1 only.${NC}"
        echo -e "${YELLOW}  This is common with llama.cpp, some dev servers, etc.${NC}"
        echo -e "${YELLOW}  Cloudflare cannot reach 127.0.0.1 directly.${NC}\n"
        echo -e "${CYAN}Fix: OpenServers will auto-start a TCP bridge:${NC}"
        echo -e "  ${GREEN}Internet → Cloudflare → 0.0.0.0:auto → 127.0.0.1:${tport}${NC}"
        echo -e "  ${GREEN}Your app needs zero changes.${NC}"
    else
        local listening=false
        if command -v ss &>/dev/null; then
            ss -tln 2>/dev/null | grep -q ":${tport} " && listening=true
        elif command -v netstat &>/dev/null; then
            netstat -tln 2>/dev/null | grep -q ":${tport} " && listening=true
        fi
        if $listening; then
            echo -e "${GREEN}✓ Port $tport is reachable (bound to 0.0.0.0)${NC}"
        else
            echo -e "${YELLOW}⚠ Nothing detected on port $tport yet.${NC}"
            echo -e "${YELLOW}  Tunnel will be created — start your app before using the URL.${NC}"
        fi
    fi

    echo -e "${CYAN}─────────────────────────────────────${NC}"
    echo -ne "\n${YELLOW}Start tunnel now? (y/n): ${NC}"
    read confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { press_enter; return; }

    local dir
    dir="$(_pt_dir "$tname")"
    mkdir -p "$dir"
    _pt_save_config "$tname" "$tport" "$loopback_flag"

    # Start proxy if needed
    if $needs_proxy; then
        echo -e "\n${BLUE}Starting TCP bridge proxy...${NC}"
        effective_port=$(_pt_start_proxy "$dir" "$tport")
        if _pt_proxy_alive "$tname"; then
            echo -e "${GREEN}✓ Bridge: 0.0.0.0:${effective_port} → 127.0.0.1:${tport}${NC}"
        else
            echo -e "${RED}✗ Bridge failed to start${NC}"
            cat "$dir/proxy.log" 2>/dev/null | tail -5 | sed 's/^/  /'
            rm -rf "$dir"; press_enter; return
        fi
    fi

    # Start cloudflared
    echo -e "\n${BLUE}Starting Cloudflare tunnel...${NC}"
    cloudflared tunnel --url "${scheme}://localhost:${effective_port}" \
        > "$dir/tunnel.log" 2>&1 &
    echo $! > "$dir/tunnel.pid"

    _pt_wait_for_url "$dir"

    echo -e "\n${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${GREEN}🌍 Tunnel '$tname' is LIVE!${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    if $needs_proxy; then
        echo -e "${YELLOW}Bridge:${NC}       127.0.0.1:${tport} ↔ 0.0.0.0:${effective_port}"
    fi
    echo -e "${YELLOW}Local target:${NC} ${scheme}://localhost:${tport}"
    if [ -f "$dir/tunnel.url" ]; then
        echo -e "${YELLOW}Public URL:${NC}   ${GREEN}$(cat "$dir/tunnel.url")${NC}"
        echo -e "\n${BLUE}Anyone can now reach your port ${tport} via the URL above.${NC}"
    fi

    press_enter
}

# ─── LIST ─────────────────────────────────────────────────────────────────────

port_tunnel_list() {
    clear
    section_header "🌐 Port Tunnels"

    if [ ! "$(ls -A "$PORT_TUNNELS_DIR" 2>/dev/null)" ]; then
        echo -e "${YELLOW}No port tunnels found.${NC}"
        echo -e "${BLUE}Use 'Expose Local Port' to create one.${NC}"
        press_enter; return
    fi

    for d in "$PORT_TUNNELS_DIR"/*/; do
        [ -d "$d" ] || continue
        local name port created
        name=$(basename "$d")
        port=$(_pt_port "$name")
        created=$(_pt_created "$name")

        # Recover URL from log if tunnel.url is missing
        [ ! -f "$d/tunnel.url" ] && [ -f "$d/tunnel.log" ] && \
            _pt_extract_url_from_log "$d" 2>/dev/null || true

        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${YELLOW}Name:${NC}    $name"

        if _pt_is_alive "$name"; then
            echo -e "${YELLOW}Status:${NC}  ${GREEN}● Active${NC}  (PID: $(cat "$d/tunnel.pid"))"
        else
            echo -e "${YELLOW}Status:${NC}  ${RED}○ Stopped${NC}"
        fi

        echo -e "${YELLOW}Port:${NC}    ${port:-N/A}"

        if [ "$(_pt_loopback "$name")" = "true" ]; then
            if _pt_proxy_alive "$name"; then
                local pp; pp=$(_pt_proxy_port "$name")
                echo -e "${YELLOW}Bridge:${NC}  ${GREEN}● Active${NC}  (0.0.0.0:${pp} → 127.0.0.1:${port})"
            else
                echo -e "${YELLOW}Bridge:${NC}  ${RED}○ Stopped${NC}  (loopback mode — restart to fix)"
            fi
        fi

        echo -e "${YELLOW}Created:${NC} ${created:-unknown}"

        if [ -f "$d/tunnel.url" ]; then
            echo -e "${YELLOW}URL:${NC}     ${GREEN}$(cat "$d/tunnel.url")${NC}"
        elif _pt_is_alive "$name"; then
            echo -e "${YELLOW}URL:${NC}     ${YELLOW}⚠ Not captured — use option 3 'Show URL'${NC}"
        else
            echo -e "${YELLOW}URL:${NC}     ${RED}—${NC}"
        fi
        echo ""
    done

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    press_enter
}

# ─── SHOW URL ─────────────────────────────────────────────────────────────────

port_tunnel_show_url() {
    clear
    section_header "🔗 Show Tunnel URL"

    local tname
    tname=$(_pt_pick "Tunnel name") || { press_enter; return; }
    local dir; dir="$(_pt_dir "$tname")"

    if ! _pt_is_alive "$tname"; then
        echo -e "\n${RED}✗ Tunnel '$tname' is not running.${NC}"
        echo -e "${YELLOW}  Use option 4 'Restart' to start it.${NC}"
        press_enter; return
    fi

    echo -e "\n${BLUE}Scanning log for public URL...${NC}"

    if _pt_extract_url_from_log "$dir" && [ -n "$TUNNEL_URL" ]; then
        echo -e "\n${CYAN}═══════════════════════════════════════${NC}"
        echo -e "${GREEN}🌍 $tname is live!${NC}"
        echo -e "${CYAN}═══════════════════════════════════════${NC}"
        echo -e "${YELLOW}Public URL:${NC}  ${GREEN}${TUNNEL_URL}${NC}"
        echo -e "${YELLOW}Local port:${NC}  $(_pt_port "$tname")"
    else
        echo -e "${YELLOW}Not in log yet — watching for 15s...${NC}"
        local i
        for i in {1..15}; do
            sleep 1; echo -n "."
            _pt_extract_url_from_log "$dir" && [ -n "$TUNNEL_URL" ] && break
        done
        echo ""
        if [ -n "$TUNNEL_URL" ]; then
            echo -e "\n${GREEN}✓ Public URL:${NC} ${GREEN}${TUNNEL_URL}${NC}"
        else
            echo -e "\n${YELLOW}⚠ Could not find URL. Raw tunnel log (last 20 lines):${NC}"
            echo -e "${CYAN}─────────────────────────────────────${NC}"
            tail -20 "$dir/tunnel.log" | sed 's/^/  /'
            echo -e "${CYAN}─────────────────────────────────────${NC}"
            echo -e "${YELLOW}Tip: use option 4 'Restart' to get a fresh tunnel.${NC}"
        fi
    fi

    press_enter
}

# ─── RESTART ──────────────────────────────────────────────────────────────────

port_tunnel_restart() {
    clear
    section_header "🔄 Restart Port Tunnel"

    local tname
    tname=$(_pt_pick "Tunnel name to restart") || { press_enter; return; }
    local dir port loopback
    dir="$(_pt_dir "$tname")"
    port=$(_pt_port "$tname")
    loopback=$(_pt_loopback "$tname")

    [ -z "$port" ] && { echo -e "\n${RED}✗ Cannot read config${NC}"; press_enter; return; }

    # Stop tunnel
    if [ -f "$dir/tunnel.pid" ]; then
        local pid; pid=$(cat "$dir/tunnel.pid")
        ps -p "$pid" > /dev/null 2>&1 && kill "$pid" 2>/dev/null
        sleep 1; rm -f "$dir/tunnel.pid"
    fi
    rm -f "$dir/tunnel.url"

    # Stop existing proxy
    _pt_stop_proxy "$dir"

    echo -e "\n${BLUE}Restarting '$tname'...${NC}"

    local effective_port="$port"

    # Restart proxy for loopback-bound services
    if [ "$loopback" = "true" ] || _pt_is_loopback_only "$port"; then
        _pt_save_config "$tname" "$port" "true"
        echo -e "${BLUE}Starting TCP bridge...${NC}"
        effective_port=$(_pt_start_proxy "$dir" "$port")
        if _pt_proxy_alive "$tname"; then
            echo -e "${GREEN}✓ Bridge: 0.0.0.0:${effective_port} → 127.0.0.1:${port}${NC}"
        else
            echo -e "${RED}✗ Bridge failed${NC}"; press_enter; return
        fi
    fi

    cloudflared tunnel --url "http://localhost:${effective_port}" \
        > "$dir/tunnel.log" 2>&1 &
    echo $! > "$dir/tunnel.pid"

    _pt_wait_for_url "$dir"

    echo -e "\n${GREEN}✓ '$tname' restarted.${NC}"
    [ -f "$dir/tunnel.url" ] && \
        echo -e "${YELLOW}New public URL:${NC} ${GREEN}$(cat "$dir/tunnel.url")${NC}"

    press_enter
}

# ─── STOP ─────────────────────────────────────────────────────────────────────

port_tunnel_stop() {
    clear
    section_header "⏹  Stop Port Tunnel"

    local tname
    tname=$(_pt_pick "Tunnel name to stop") || { press_enter; return; }
    local dir; dir="$(_pt_dir "$tname")"

    if [ -f "$dir/tunnel.pid" ] && ps -p "$(cat "$dir/tunnel.pid")" > /dev/null 2>&1; then
        local pid; pid=$(cat "$dir/tunnel.pid")
        echo -ne "\n${YELLOW}Stopping tunnel (PID: $pid)...${NC} "
        kill "$pid" 2>/dev/null; sleep 1
        ps -p "$pid" > /dev/null 2>&1 && kill -9 "$pid" 2>/dev/null
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "\n${YELLOW}⚠ Tunnel '$tname' was not running.${NC}"
    fi
    rm -f "$dir/tunnel.pid"

    if _pt_proxy_alive "$tname"; then
        echo -ne "${YELLOW}Stopping TCP bridge...${NC} "
        _pt_stop_proxy "$dir"
        echo -e "${GREEN}✓${NC}"
    fi

    echo -e "\n${GREEN}✓ '$tname' stopped.${NC}"
    press_enter
}

# ─── DELETE ───────────────────────────────────────────────────────────────────

port_tunnel_delete() {
    clear
    section_header "🗑  Delete Port Tunnel"

    local tname
    tname=$(_pt_pick "Tunnel name to delete") || { press_enter; return; }
    local dir; dir="$(_pt_dir "$tname")"

    echo -e "\n${RED}⚠ Permanently removes '$tname' and all state.${NC}"
    echo -ne "${RED}Type 'yes' to confirm: ${NC}"
    read confirm
    [ "$confirm" != "yes" ] && { echo -e "${YELLOW}Cancelled.${NC}"; press_enter; return; }

    [ -f "$dir/tunnel.pid" ] && kill -9 "$(cat "$dir/tunnel.pid")" 2>/dev/null
    _pt_stop_proxy "$dir"
    rm -rf "$dir"

    echo -e "\n${GREEN}✓ '$tname' deleted.${NC}"
    press_enter
}

# ─── SUB-MENU ─────────────────────────────────────────────────────────────────

port_tunnel_menu() {
    while true; do
        clear
        section_header "🌐 Port Tunnel Manager"

        echo -e "${BLUE}Expose any local port to the internet via Cloudflare.${NC}"
        echo -e "${BLUE}Auto-bridges 127.0.0.1-only services (llama.cpp, etc.)${NC}\n"

        echo "  1. 🚀 Expose a local port    (create & start)"
        echo "  2. 📋 List all tunnels"
        echo "  3. 🔗 Show URL               (recover URL from running tunnel)"
        echo "  4. 🔄 Restart a tunnel       (get a fresh public URL)"
        echo "  5. ⏹  Stop a tunnel"
        echo "  6. 🗑  Delete a tunnel"
        echo "  7. ⬅  Back to Main Menu"
        echo ""
        echo -ne "${YELLOW}Choice (1-7): ${NC}"
        read choice

        case $choice in
            1) port_tunnel_create   ;;
            2) port_tunnel_list     ;;
            3) port_tunnel_show_url ;;
            4) port_tunnel_restart  ;;
            5) port_tunnel_stop     ;;
            6) port_tunnel_delete   ;;
            7) return ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}