#!/bin/bash

# lib/settings.sh — Settings & management sub-menu
# Sourced by openservers.sh

settings() {
    while true; do
        clear
        section_header "⚙️  Settings & Management"

        echo "  1. 📁 View Server Directory"
        echo "  2. 💾 Export Backup"
        echo "  3. 📊 System Information"
        echo "  4. 🧹 Clean Up Old Logs"
        echo "  5. ⬅  Back to Main Menu"
        echo ""
        echo -ne "${YELLOW}Choice (1-5): ${NC}"
        read choice

        case $choice in
            1) _settings_view_dir ;;
            2) _settings_backup   ;;
            3) _settings_sysinfo  ;;
            4) _settings_cleanlogs ;;
            5) return ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

# ─── Sub-actions ──────────────────────────────────────────────────────────────

_settings_view_dir() {
    echo -e "\n$(divider)"
    echo -e "${BLUE}Servers Directory:${NC} $SERVERS_DIR"
    divider
    echo ""
    if [ "$(ls -A "$SERVERS_DIR" 2>/dev/null)" ]; then
        ls -lh "$SERVERS_DIR" | tail -n +2
    else
        echo -e "${YELLOW}No servers found${NC}"
    fi
    press_enter
}

_settings_backup() {
    echo -e "\n${BLUE}Creating backup...${NC}"
    local backup_file="$HOME/openservers-backup-$(date +%Y%m%d-%H%M%S).tar.gz"

    if tar -czf "$backup_file" -C "$HOME" ".openservers" 2>/dev/null; then
        local size
        size=$(du -h "$backup_file" | cut -f1)
        echo -e "${GREEN}✓ Backup created successfully!${NC}"
        echo -e "\n${BLUE}Location:${NC} $backup_file"
        echo -e "${BLUE}Size:${NC}     $size"
    else
        echo -e "${RED}✗ Backup failed${NC}"
    fi
    press_enter
}

_settings_sysinfo() {
    echo -e "\n$(divider)"
    echo -e "${YELLOW}System Information${NC}"
    divider

    echo -e "${BLUE}Environment:${NC}     $ENV"
    echo -e "${BLUE}Hostname:${NC}        $(hostname)"
    echo -e "${BLUE}User:${NC}            $USER"
    echo -e "${BLUE}Home:${NC}            $HOME"
    echo -e "${BLUE}Architecture:${NC}    $(uname -m)"
    echo -e "${BLUE}Python:${NC}          $(python3 --version 2>&1 | cut -d' ' -f2)"

    if command -v cloudflared &> /dev/null; then
        echo -e "${BLUE}Cloudflared:${NC}     $(cloudflared --version 2>&1 | head -1)"
    else
        echo -e "${BLUE}Cloudflared:${NC}     Not installed"
    fi

    # Count servers
    local total running stopped
    total=$(find "$SERVERS_DIR" -maxdepth 1 -type d 2>/dev/null | wc -l)
    total=$((total - 1))   # subtract the parent dir itself
    running=0

    if [ -d "$SERVERS_DIR" ]; then
        for dir in "$SERVERS_DIR"/*; do
            [ -f "$dir/server.pid" ] || continue
            local pid
            pid=$(cat "$dir/server.pid")
            ps -p "$pid" > /dev/null 2>&1 && running=$((running + 1))
        done
    fi

    stopped=$((total - running))
    echo -e "\n${BLUE}Total Servers:${NC}   $total"
    echo -e "${BLUE}Running:${NC}         $running"
    echo -e "${BLUE}Stopped:${NC}         $stopped"

    press_enter
}

_settings_cleanlogs() {
    echo -e "\n${BLUE}Cleaning up old logs...${NC}"
    local cleaned=0

    for dir in "$SERVERS_DIR"/*; do
        [ -d "$dir" ] || continue
        for logfile in "$dir/server.log" "$dir/tunnel.log"; do
            [ -f "$logfile" ] || continue
            local lines
            lines=$(wc -l < "$logfile" 2>/dev/null || echo 0)
            if [ "$lines" -gt 1000 ]; then
                tail -500 "$logfile" > "$logfile.tmp"
                mv "$logfile.tmp" "$logfile"
                cleaned=$((cleaned + 1))
            fi
        done
    done

    if [ "$cleaned" -gt 0 ]; then
        echo -e "${GREEN}✓ Cleaned $cleaned log file(s)${NC}"
    else
        echo -e "${YELLOW}No log files needed cleaning${NC}"
    fi

    press_enter
}