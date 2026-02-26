#!/bin/bash

# lib/environment.sh — Environment detection, dependency checks, cloudflared install
# Sourced by openservers.sh

# ─── Detect Termux vs Linux ───────────────────────────────────────────────────
check_environment() {
    if [ -d "/data/data/com.termux" ]; then
        echo -e "${GREEN}✓ Termux detected${NC}"
        export ENV="termux"
    else
        echo -e "${GREEN}✓ Linux detected${NC}"
        export ENV="linux"
    fi
}

# ─── Verify required tools are present ───────────────────────────────────────
check_dependencies() {
    echo -e "\n${BLUE}Checking dependencies...${NC}"

    local missing=""

    if ! command -v python3 &> /dev/null; then
        missing="$missing python"
    else
        echo -e "${GREEN}✓ Python installed${NC}"
    fi

    if ! command -v curl &> /dev/null; then
        missing="$missing curl"
    else
        echo -e "${GREEN}✓ curl installed${NC}"
    fi

    if [ -n "$missing" ]; then
        echo -e "\n${RED}❌ Missing dependencies:${NC}$missing"
        echo -e "\n${YELLOW}Install them:${NC}"
        if [ "$ENV" = "termux" ]; then
            echo "  pkg install$missing"
        else
            echo "  sudo apt install$missing"
        fi
        exit 1
    fi
}

# ─── Install cloudflared (if not already present) ─────────────────────────────
install_cloudflared() {
    if command -v cloudflared &> /dev/null; then
        echo -e "${GREEN}✓ cloudflared already installed${NC}"
        return
    fi

    echo -e "\n${BLUE}Installing Cloudflare Tunnel...${NC}"

    if [ "$ENV" = "termux" ]; then
        pkg install cloudflared -y
    else
        mkdir -p "$HOME/.local/bin"

        # Kill stale instances that might lock the binary
        pkill -f cloudflared 2>/dev/null || true
        sleep 1

        local arch url temp_file
        arch=$(uname -m)
        if [ "$arch" = "aarch64" ] || [ "$arch" = "arm64" ]; then
            url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
        else
            url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
        fi

        temp_file=$(mktemp)
        if curl -L "$url" -o "$temp_file" 2>/dev/null; then
            mv -f "$temp_file" "$HOME/.local/bin/cloudflared"
            chmod +x "$HOME/.local/bin/cloudflared"
        else
            echo -e "${RED}Failed to download cloudflared${NC}"
            rm -f "$temp_file"
            exit 1
        fi

        export PATH="$HOME/.local/bin:$PATH"
    fi

    echo -e "${GREEN}✓ cloudflared installed${NC}"
}   