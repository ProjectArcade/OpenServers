#!/bin/bash

# lib/server_process.sh — Low-level process management and Cloudflare tunnel handling
# Sourced by openservers.sh

# ─── Start a server's background process ─────────────────────────────────────
# Usage: start_app_process "$server_dir"
# Sets SERVER_PID on success.
start_app_process() {
    local dir="$1"
    cd "$dir"

    local bin=""
    if   [ -f "server.py" ]; then bin="python3 server.py"
    elif [ -f "server.js" ]; then bin="node server.js"
    elif [ -f "start.sh"  ]; then bin="./start.sh"
    fi

    if [ -z "$bin" ]; then
        echo -e "${RED}✗ No server executable found (expected server.py / server.js / start.sh)${NC}"
        return 1
    fi

    nohup $bin > "$dir/server.log" 2>&1 &
    echo $! > "$dir/server.pid"
    SERVER_PID=$!
}

# ─── Stop a running server process ───────────────────────────────────────────
# Usage: stop_app_process "$server_dir"
# Returns 0 if a process was killed, 1 if nothing was running.
stop_app_process() {
    local dir="$1"
    local pid_file="$dir/server.pid"

    if [ ! -f "$pid_file" ]; then return 1; fi

    local pid
    pid=$(cat "$pid_file")

    if ps -p "$pid" > /dev/null 2>&1; then
        echo -ne "${YELLOW}  Stopping server (PID: $pid)...${NC} "
        kill "$pid" 2>/dev/null
        sleep 1
        ps -p "$pid" > /dev/null 2>&1 && kill -9 "$pid" 2>/dev/null
        echo -e "${GREEN}✓${NC}"
        rm -f "$pid_file"
        return 0
    fi

    rm -f "$pid_file"
    return 1
}

# ─── Start a Cloudflare tunnel ────────────────────────────────────────────────
# Usage: start_tunnel "$server_dir" "$port"
# Writes the public URL to "$server_dir/tunnel.url" when found.
start_tunnel() {
    local dir="$1"
    local port="$2"

    echo -e "${BLUE}Creating global tunnel...${NC}"
    echo -e "${YELLOW}Please wait, this may take 10-15 seconds...${NC}"

    cloudflared tunnel --url "http://localhost:$port" > "$dir/tunnel.log" 2>&1 &
    echo $! > "$dir/tunnel.pid"

    echo -n "Waiting for tunnel URL"
    local i
    for i in {1..30}; do
        sleep 1
        echo -n "."
        grep -q "trycloudflare.com" "$dir/tunnel.log" 2>/dev/null && break
    done
    echo ""

    _extract_tunnel_url "$dir"
}

# ─── Stop a running tunnel ────────────────────────────────────────────────────
stop_tunnel() {
    local dir="$1"
    local pid_file="$dir/tunnel.pid"

    if [ ! -f "$pid_file" ]; then return 1; fi

    local pid
    pid=$(cat "$pid_file")

    if ps -p "$pid" > /dev/null 2>&1; then
        echo -ne "${YELLOW}  Stopping Cloudflare tunnel (PID: $pid)...${NC} "
        kill "$pid" 2>/dev/null
        sleep 1
        ps -p "$pid" > /dev/null 2>&1 && kill -9 "$pid" 2>/dev/null
        echo -e "${GREEN}✓${NC}"
        rm -f "$pid_file"
        return 0
    fi

    rm -f "$pid_file"
    return 1
}

# ─── Extract tunnel URL from logs ────────────────────────────────────────────
# Writes to "$dir/tunnel.url" and exports TUNNEL_URL.
_extract_tunnel_url() {
    local dir="$1"
    TUNNEL_URL=""

    TUNNEL_URL=$(grep -oP 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' "$dir/tunnel.log" 2>/dev/null | head -1)
    if [ -z "$TUNNEL_URL" ]; then
        TUNNEL_URL=$(grep -oE 'https://[^[:space:]]+trycloudflare\.com' "$dir/tunnel.log" 2>/dev/null | head -1)
    fi

    if [ -n "$TUNNEL_URL" ]; then
        echo "$TUNNEL_URL" > "$dir/tunnel.url"
        echo -e "${GREEN}✓ Tunnel URL: $TUNNEL_URL${NC}"
    else
        echo -e "${YELLOW}⚠ Tunnel started but URL not captured yet${NC}"
        echo -e "${YELLOW}Check logs: cat $dir/tunnel.log${NC}"
    fi
}

# ─── Save server config JSON ─────────────────────────────────────────────────
save_server_config() {
    local name="$1"
    local dir="$2"
    local port="$3"
    local expose="$4"

    cat > "$dir/config.json" << EOF
{
    "name": "$name",
    "port": $port,
    "exposed": $([ "$expose" = "1" ] && echo "true" || echo "false"),
    "created": "$(date)"
}
EOF
}

# ─── Convenience: start app + optional tunnel ────────────────────────────────
start_server_process() {
    local name="$1"
    local dir="$2"
    local port="$3"
    local expose="$4"

    start_app_process "$dir"
    sleep 2

    if [ "$expose" = "1" ]; then
        start_tunnel "$dir" "$port"
    fi

    save_server_config "$name" "$dir" "$port" "$expose"
}