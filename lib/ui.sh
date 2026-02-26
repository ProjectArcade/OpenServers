#!/bin/bash

# lib/ui.sh — Shared UI helpers (banners, section headers, prompts)
# Sourced by openservers.sh

# ─── Main ASCII Banner ────────────────────────────────────────────────────────
show_banner() {
    cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   ██████╗ ██████╗ ███████╗███╗   ██╗                      ║
║  ██╔═══██╗██╔══██╗██╔════╝████╗  ██║                      ║
║  ██║   ██║██████╔╝█████╗  ██╔██╗ ██║                      ║
║  ██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║                      ║
║  ╚██████╔╝██║     ███████╗██║ ╚████║                      ║
║   ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝                      ║
║                                                           ║
║      ███████╗███████╗██████╗ ██╗   ██╗███████╗██████╗     ║
║      ██╔════╝██╔════╝██╔══██╗██║   ██║██╔════╝██╔══██╗    ║
║      ███████╗█████╗  ██████╔╝██║   ██║█████╗  ██████╔╝    ║
║      ╚════██║██╔══╝  ██╔══██╗╚██╗ ██╔╝██╔══╝  ██╔══██╗    ║
║      ███████║███████╗██║  ██║ ╚████╔╝ ███████╗██║  ██║    ║
║      ╚══════╝╚══════╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝    ║
║                                                           ║
║         Turn Your Devices Into a Global Server            ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

EOF
}

# ─── Reusable Section Header ──────────────────────────────────────────────────
# Usage: section_header "🚀 Create New Server"
section_header() {
    local title="$1"
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     $title${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}\n"
}

# ─── Divider ──────────────────────────────────────────────────────────────────
divider() {
    echo -e "${CYAN}─────────────────────────────────────${NC}"
}

# ─── Pause prompt ─────────────────────────────────────────────────────────────
press_enter() {
    echo -e "\n${YELLOW}Press Enter to continue...${NC}"
    read
}

# ─── Server status badge ──────────────────────────────────────────────────────
# Usage: server_status_label "$server_dir"
# Prints a colored status string and sets $SERVER_STATUS_RUNNING (true/false)
server_status_label() {
    local dir="$1"
    SERVER_STATUS_RUNNING=false

    if [ -f "$dir/server.pid" ]; then
        local pid
        pid=$(cat "$dir/server.pid")
        if ps -p "$pid" > /dev/null 2>&1; then
            echo -e "${GREEN}● Running${NC}"
            SERVER_STATUS_RUNNING=true
            return
        fi
    fi
    echo -e "${RED}○ Stopped${NC}"
}