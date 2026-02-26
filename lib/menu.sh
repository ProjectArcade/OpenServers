#!/bin/bash

# lib/menu.sh — Main navigation loop
# Sourced by openservers.sh

main_menu() {
    while true; do
        clear
        show_banner

        echo -e "\n${CYAN}═══════════════════════════════════════${NC}"
        echo -e "${GREEN}Main Menu${NC}"
        echo -e "${CYAN}═══════════════════════════════════════${NC}"
        echo ""
        echo "  1. 🚀 Create New Server"
        echo "  2. 📋 List Running Servers"
        echo "  3. ▶️  Start Server"
        echo "  4. 🔍 View Server Details"
        echo "  5. ⏹  Stop Server"
        echo "  6. 🗑  Delete Server"
        echo "  7. ⚙️  Settings"
        echo "  ──────────────────────────────────────"
        echo "  8. 🌐 Port Tunnel  (expose any port)"
        echo "  ──────────────────────────────────────"
        echo "  9. 🚪 Exit"
        echo ""
        echo -ne "${YELLOW}Choose option (1-9): ${NC}"
        read choice

        case $choice in
            1) create_server     ;;
            2) list_servers      ;;
            3) start_server      ;;
            4) view_server       ;;
            5) stop_server       ;;
            6) delete_server     ;;
            7) settings          ;;
            8) port_tunnel_menu  ;;
            9)
                echo -e "\n${GREEN}👋 Thanks for using OpenServers!${NC}\n"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                sleep 1
                ;;
        esac
    done
}