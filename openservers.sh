#!/bin/bash

# OpenServers - Turn Your Mobile Into a Global Server
# Compatible with Termux (Android) and Linux

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Paths
OPENSERVERS_DIR="$HOME/.openservers"
SERVERS_DIR="$OPENSERVERS_DIR/servers"
CONFIG_FILE="$OPENSERVERS_DIR/config.json"
TUNNEL_LOG="$OPENSERVERS_DIR/tunnel.log"

# Initialize
mkdir -p "$OPENSERVERS_DIR" "$SERVERS_DIR"

clear

cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   ██████╗ ██████╗ ███████╗███╗   ██╗                     ║
║  ██╔═══██╗██╔══██╗██╔════╝████╗  ██║                     ║
║  ██║   ██║██████╔╝█████╗  ██╔██╗ ██║                     ║
║  ██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║                     ║
║  ╚██████╔╝██║     ███████╗██║ ╚████║                     ║
║   ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝                     ║
║                                                           ║
║      ███████╗███████╗██████╗ ██╗   ██╗███████╗██████╗    ║
║      ██╔════╝██╔════╝██╔══██╗██║   ██║██╔════╝██╔══██╗   ║
║      ███████╗█████╗  ██████╔╝██║   ██║█████╗  ██████╔╝   ║
║      ╚════██║██╔══╝  ██╔══██╗╚██╗ ██╔╝██╔══╝  ██╔══██╗   ║
║      ███████║███████╗██║  ██║ ╚████╔╝ ███████╗██║  ██║   ║
║      ╚══════╝╚══════╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝   ║
║                                                           ║
║         Turn Your Devices Into a Global Server            ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

EOF

echo -e "${CYAN}🌍 Welcome to OpenServers!${NC}"
echo -e "${YELLOW}Transform your device into a globally accessible server${NC}\n"

# Check if running on Termux
check_environment() {
    if [ -d "/data/data/com.termux" ]; then
        echo -e "${GREEN}✓ Termux detected${NC}"
        ENV="termux"
    else
        echo -e "${GREEN}✓ Linux detected${NC}"
        ENV="linux"
    fi
}

# Check dependencies
check_dependencies() {
    echo -e "\n${BLUE}Checking dependencies...${NC}"
    
    MISSING=""
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        MISSING="$MISSING python"
    else
        echo -e "${GREEN}✓ Python installed${NC}"
    fi
    
    # Check curl
    if ! command -v curl &> /dev/null; then
        MISSING="$MISSING curl"
    else
        echo -e "${GREEN}✓ curl installed${NC}"
    fi
    
    if [ ! -z "$MISSING" ]; then
        echo -e "\n${RED}❌ Missing dependencies:${NC}$MISSING"
        echo -e "\n${YELLOW}Install them:${NC}"
        if [ "$ENV" = "termux" ]; then
            echo "  pkg install$MISSING"
        else
            echo "  sudo apt install$MISSING"
        fi
        exit 1
    fi
}

# Install Cloudflare Tunnel
install_cloudflared() {
    if command -v cloudflared &> /dev/null; then
        echo -e "${GREEN}✓ cloudflared already installed${NC}"
        return
    fi
    
    echo -e "\n${BLUE}Installing Cloudflare Tunnel...${NC}"
    
    if [ "$ENV" = "termux" ]; then
        pkg install cloudflared -y
    else
        # Ensure .local/bin exists
        mkdir -p "$HOME/.local/bin"
        
        # Stop any running cloudflared processes that might lock the file
        pkill -f cloudflared 2>/dev/null || true
        sleep 1
        
        # Download cloudflared
        ARCH=$(uname -m)
        if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
            URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
        else
            URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
        fi
        
        # Download to temp file first, then move
        TEMP_FILE=$(mktemp)
        if curl -L "$URL" -o "$TEMP_FILE" 2>/dev/null; then
            mv -f "$TEMP_FILE" "$HOME/.local/bin/cloudflared"
            chmod +x "$HOME/.local/bin/cloudflared"
        else
            echo -e "${RED}Failed to download cloudflared${NC}"
            rm -f "$TEMP_FILE"
            exit 1
        fi
        
        export PATH="$HOME/.local/bin:$PATH"
    fi
    
    echo -e "${GREEN}✓ cloudflared installed${NC}"
}

# Main menu
main_menu() {
    while true; do
        echo -e "\n${CYAN}═══════════════════════════════════════${NC}"
        echo -e "${GREEN}Main Menu${NC}"
        echo -e "${CYAN}═══════════════════════════════════════${NC}"
        echo ""
        echo "  1. 🚀 Create New Server"
        echo "  2. 📋 List Running Servers"
        echo "  3. 🔍 View Server Details"
        echo "  4. ⏹  Stop Server"
        echo "  5. 🗑  Delete Server"
        echo "  6. ⚙️  Settings"
        echo "  7. 🚪 Exit"
        echo ""
        echo -ne "${YELLOW}Choose option (1-7): ${NC}"
        
        read choice
        
        case $choice in
            1) create_server ;;
            2) list_servers ;;
            3) view_server ;;
            4) stop_server ;;
            5) delete_server ;;
            6) settings ;;
            7) 
                echo -e "\n${GREEN}👋 Thanks for using OpenServers!${NC}\n"
                exit 0
                ;;
            *) echo -e "${RED}Invalid option${NC}" ;;
        esac
    done
}

# Create new server
create_server() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     🚀 Create New Server              ║${NC}"
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}\n"
    
    # Server name
    echo -ne "${YELLOW}Server name:${NC} "
    read server_name
    
    if [ -z "$server_name" ]; then
        echo -e "${RED}Server name cannot be empty${NC}"
        return
    fi
    
    # Check if exists
    if [ -d "$SERVERS_DIR/$server_name" ]; then
        echo -e "${RED}Server '$server_name' already exists${NC}"
        return
    fi
    
    # Choose server type
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
    
    # Create server directory
    SERVER_DIR="$SERVERS_DIR/$server_name"
    mkdir -p "$SERVER_DIR"
    
    # Create server files based on type
    case $server_type in
        1) create_python_server "$SERVER_DIR" "$port" ;;
        2) create_static_server "$SERVER_DIR" "$port" ;;
        3) create_node_server "$SERVER_DIR" "$port" ;;
        4) create_custom_server "$SERVER_DIR" "$port" ;;
        *) 
            echo -e "${RED}Invalid type${NC}"
            rm -rf "$SERVER_DIR"
            return
            ;;
    esac
    
    # Expose globally?
    echo -e "\n${BLUE}Do you want to expose this server globally?${NC}"
    echo "  1. Yes (via Cloudflare Tunnel - Free & Permanent URL)"
    echo "  2. No (localhost only)"
    echo ""
    echo -ne "${YELLOW}Choice (1-2): ${NC}"
    read expose
    
    # Start server
    echo -e "\n${BLUE}Starting server...${NC}"
    start_server_process "$server_name" "$SERVER_DIR" "$port" "$expose"
    
    echo -e "\n${GREEN}✓ Server '$server_name' created and started!${NC}"
    
    if [ "$expose" = "1" ]; then
        sleep 3
        TUNNEL_URL=$(cat "$SERVER_DIR/tunnel.url" 2>/dev/null || echo "")
        if [ ! -z "$TUNNEL_URL" ]; then
            echo -e "\n${CYAN}═══════════════════════════════════════${NC}"
            echo -e "${GREEN}🌍 Your server is LIVE globally!${NC}"
            echo -e "${CYAN}═══════════════════════════════════════${NC}"
            echo -e "\n${YELLOW}Public URL:${NC} ${GREEN}$TUNNEL_URL${NC}"
            echo -e "${YELLOW}Local URL:${NC}  http://localhost:$port"
            echo -e "\n${BLUE}Share this URL with anyone in the world!${NC}"
        fi
    else
        echo -e "\n${YELLOW}Local URL:${NC} http://localhost:$port"
    fi
    
    echo -e "\n${YELLOW}Press Enter to continue...${NC}"
    read
}

# Create Python server
create_python_server() {
    local dir=$1
    local port=$2
    
    cat > "$dir/server.py" << EOF
from flask import Flask, jsonify, request
from datetime import datetime

app = Flask(__name__)

@app.route('/')
def home():
    return '''
    <!DOCTYPE html>
    <html>
    <head>
        <title>OpenServers - Running</title>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body {
                font-family: system-ui, -apple-system, sans-serif;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                min-height: 100vh;
                display: flex;
                align-items: center;
                justify-content: center;
                color: white;
                padding: 20px;
            }
            .container {
                background: rgba(255, 255, 255, 0.1);
                backdrop-filter: blur(10px);
                border-radius: 20px;
                padding: 40px;
                max-width: 600px;
                text-align: center;
                box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3);
            }
            h1 { font-size: 2.5rem; margin-bottom: 1rem; }
            .status { 
                display: inline-block;
                background: #10b981;
                padding: 8px 20px;
                border-radius: 20px;
                font-weight: 600;
                margin: 20px 0;
            }
            .info {
                background: rgba(0, 0, 0, 0.2);
                padding: 20px;
                border-radius: 10px;
                margin: 20px 0;
            }
            .info p { margin: 10px 0; font-size: 1.1rem; }
            .badge {
                display: inline-block;
                background: rgba(255, 255, 255, 0.2);
                padding: 5px 15px;
                border-radius: 15px;
                margin: 5px;
                font-size: 0.9rem;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>🚀 OpenServers</h1>
            <div class="status">● Server Running</div>
            <div class="info">
                <p><strong>Your device is now a server!</strong></p>
                <p>This is running on your mobile/computer</p>
                <p>Powered by OpenServers</p>
            </div>
            <div>
                <span class="badge">Python</span>
                <span class="badge">Flask</span>
                <span class="badge">Port $port</span>
            </div>
        </div>
    </body>
    </html>
    '''

@app.route('/api/status')
def status():
    return jsonify({
        'status': 'running',
        'server': 'OpenServers',
        'timestamp': datetime.now().isoformat(),
        'message': 'Your device is serving this globally!'
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=$port)
EOF
    
    echo "flask" > "$dir/requirements.txt"
    
    # Install dependencies
    pip install flask --break-system-packages 2>/dev/null || pip install flask
}

# Create static server
create_static_server() {
    local dir=$1
    local port=$2
    
    cat > "$dir/index.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>OpenServers - Running</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: system-ui, -apple-system, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            padding: 20px;
        }
        .container {
            background: rgba(255, 255, 255, 0.1);
            backdrop-filter: blur(10px);
            border-radius: 20px;
            padding: 40px;
            max-width: 600px;
            text-align: center;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3);
        }
        h1 { font-size: 2.5rem; margin-bottom: 1rem; }
        .status { 
            display: inline-block;
            background: #10b981;
            padding: 8px 20px;
            border-radius: 20px;
            font-weight: 600;
            margin: 20px 0;
        }
        .info {
            background: rgba(0, 0, 0, 0.2);
            padding: 20px;
            border-radius: 10px;
            margin: 20px 0;
        }
        .info p { margin: 10px 0; font-size: 1.1rem; }
        .badge {
            display: inline-block;
            background: rgba(255, 255, 255, 0.2);
            padding: 5px 15px;
            border-radius: 15px;
            margin: 5px;
            font-size: 0.9rem;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 OpenServers</h1>
        <div class="status">● Server Running</div>
        <div class="info">
            <p><strong>Your device is now a server!</strong></p>
            <p>This static site is running on your mobile/computer</p>
            <p>Edit index.html to customize</p>
            <p>Powered by OpenServers</p>
        </div>
        <div>
            <span class="badge">HTML</span>
            <span class="badge">Static</span>
        </div>
    </div>
</body>
</html>
EOF
    
    # Create start script
    cat > "$dir/start.sh" << EOF
#!/bin/bash
python3 -m http.server $port
EOF
    chmod +x "$dir/start.sh"
}

# Create Node.js server
create_node_server() {
    local dir=$1
    local port=$2
    
    cat > "$dir/server.js" << EOF
const http = require('http');

const server = http.createServer((req, res) => {
    if (req.url === '/') {
        res.writeHead(200, { 'Content-Type': 'text/html' });
        res.end(\`
<!DOCTYPE html>
<html>
<head>
    <title>OpenServers - Running</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: system-ui, -apple-system, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            padding: 20px;
        }
        .container {
            background: rgba(255, 255, 255, 0.1);
            backdrop-filter: blur(10px);
            border-radius: 20px;
            padding: 40px;
            max-width: 600px;
            text-align: center;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3);
        }
        h1 { font-size: 2.5rem; margin-bottom: 1rem; }
        .status { 
            display: inline-block;
            background: #10b981;
            padding: 8px 20px;
            border-radius: 20px;
            font-weight: 600;
            margin: 20px 0;
        }
        .info {
            background: rgba(0, 0, 0, 0.2);
            padding: 20px;
            border-radius: 10px;
            margin: 20px 0;
        }
        .info p { margin: 10px 0; font-size: 1.1rem; }
        .badge {
            display: inline-block;
            background: rgba(255, 255, 255, 0.2);
            padding: 5px 15px;
            border-radius: 15px;
            margin: 5px;
            font-size: 0.9rem;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 OpenServers</h1>
        <div class="status">● Server Running</div>
        <div class="info">
            <p><strong>Your device is now a server!</strong></p>
            <p>This Node.js server is running on your mobile/computer</p>
            <p>Powered by OpenServers</p>
        </div>
        <div>
            <span class="badge">Node.js</span>
            <span class="badge">Port $port</span>
        </div>
    </div>
</body>
</html>
        \`);
    } else if (req.url === '/api/status') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
            status: 'running',
            server: 'OpenServers',
            timestamp: new Date().toISOString()
        }));
    } else {
        res.writeHead(404);
        res.end('Not Found');
    }
});

server.listen($port, '0.0.0.0', () => {
    console.log('Server running on port $port');
});
EOF
}

# Create custom server
create_custom_server() {
    local dir=$1
    local port=$2
    
    echo -e "\n${BLUE}Custom server setup:${NC}"
    echo "1. Git clone"
    echo "2. Manual (you'll add files later)"
    echo ""
    echo -ne "${YELLOW}Choice (1-2): ${NC}"
    read custom_choice
    
    if [ "$custom_choice" = "1" ]; then
        echo -ne "\n${YELLOW}Git repository URL: ${NC}"
        read git_url
        
        if [ ! -z "$git_url" ]; then
            git clone "$git_url" "$dir/code"
        fi
    else
        mkdir -p "$dir/code"
        echo -e "\n${YELLOW}Add your files to: $dir/code${NC}"
        echo -e "${YELLOW}Then create a start.sh script${NC}"
    fi
}

# Start server process
start_server_process() {
    local name=$1
    local dir=$2
    local port=$3
    local expose=$4
    
    # Start the actual server
    cd "$dir"
    
    if [ -f "server.py" ]; then
        nohup python3 server.py > "$dir/server.log" 2>&1 &
        echo $! > "$dir/server.pid"
    elif [ -f "server.js" ]; then
        nohup node server.js > "$dir/server.log" 2>&1 &
        echo $! > "$dir/server.pid"
    elif [ -f "start.sh" ]; then
        nohup ./start.sh > "$dir/server.log" 2>&1 &
        echo $! > "$dir/server.pid"
    fi
    
    sleep 2
    
    # Expose if requested
    if [ "$expose" = "1" ]; then
        echo -e "${BLUE}Creating global tunnel...${NC}"
        echo -e "${YELLOW}Please wait, this may take 10-15 seconds...${NC}"
        
        # Start cloudflared and capture output
        cloudflared tunnel --url "http://localhost:$port" > "$dir/tunnel.log" 2>&1 &
        echo $! > "$dir/tunnel.pid"
        
        # Wait for URL to appear in logs
        echo -n "Waiting for tunnel URL"
        for i in {1..30}; do
            sleep 1
            echo -n "."
            
            # Check if URL appeared
            if grep -q "trycloudflare.com" "$dir/tunnel.log" 2>/dev/null; then
                break
            fi
        done
        echo ""
        
        # Extract URL - try multiple patterns
        TUNNEL_URL=$(grep -oP 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' "$dir/tunnel.log" 2>/dev/null | head -1)
        
        # If not found, try alternative pattern
        if [ -z "$TUNNEL_URL" ]; then
            TUNNEL_URL=$(grep -oE 'https://[^[:space:]]+trycloudflare\.com' "$dir/tunnel.log" 2>/dev/null | head -1)
        fi
        
        if [ ! -z "$TUNNEL_URL" ]; then
            echo "$TUNNEL_URL" > "$dir/tunnel.url"
            echo -e "${GREEN}✓ Tunnel created successfully!${NC}"
        else
            echo -e "${YELLOW}⚠ Tunnel started but URL not captured yet${NC}"
            echo -e "${YELLOW}Check logs: cat $dir/tunnel.log${NC}"
        fi
    fi
    
    # Save config
    cat > "$dir/config.json" << EOF
{
    "name": "$name",
    "port": $port,
    "exposed": $([ "$expose" = "1" ] && echo "true" || echo "false"),
    "created": "$(date)"
}
EOF
}

# List servers
list_servers() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     📋 Running Servers                ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}\n"
    
    if [ ! "$(ls -A $SERVERS_DIR 2>/dev/null)" ]; then
        echo -e "${YELLOW}No servers found${NC}"
        echo -e "\n${YELLOW}Press Enter to continue...${NC}"
        read
        return
    fi
    
    for server_dir in "$SERVERS_DIR"/*; do
        if [ -d "$server_dir" ]; then
            server_name=$(basename "$server_dir")
            
            # Check if running
            if [ -f "$server_dir/server.pid" ]; then
                pid=$(cat "$server_dir/server.pid")
                if ps -p $pid > /dev/null 2>&1; then
                    status="${GREEN}● Running${NC}"
                else
                    status="${RED}○ Stopped${NC}"
                fi
            else
                status="${RED}○ Stopped${NC}"
            fi
            
            # Get port
            if [ -f "$server_dir/config.json" ]; then
                port=$(grep -oP '"port":\s*\K\d+' "$server_dir/config.json")
            else
                port="N/A"
            fi
            
            # Get URL
            if [ -f "$server_dir/tunnel.url" ]; then
                url=$(cat "$server_dir/tunnel.url")
                url_display="${GREEN}$url${NC}"
            else
                url_display="http://localhost:$port"
            fi
            
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${YELLOW}Server:${NC} $server_name"
            echo -e "${YELLOW}Status:${NC} $status"
            echo -e "${YELLOW}Port:${NC}   $port"
            echo -e "${YELLOW}URL:${NC}    $url_display"
            echo ""
        fi
    done
    
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "\n${YELLOW}Press Enter to continue...${NC}"
    read
}

# View server details
view_server() {
    echo -ne "\n${YELLOW}Server name: ${NC}"
    read server_name
    
    SERVER_DIR="$SERVERS_DIR/$server_name"
    
    if [ ! -d "$SERVER_DIR" ]; then
        echo -e "${RED}Server not found${NC}"
        return
    fi
    
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     🔍 Server Details                 ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}\n"
    
    # Show config
    if [ -f "$SERVER_DIR/config.json" ]; then
        cat "$SERVER_DIR/config.json"
    fi
    
    # Show URLs
    echo -e "\n${BLUE}Access URLs:${NC}"
    
    # Local URL
    if [ -f "$SERVER_DIR/config.json" ]; then
        port=$(grep -oP '"port":\s*\K\d+' "$SERVER_DIR/config.json")
        echo -e "${YELLOW}Local:${NC}  http://localhost:$port"
    fi
    
    # Public URL
    if [ -f "$SERVER_DIR/tunnel.url" ]; then
        tunnel_url=$(cat "$SERVER_DIR/tunnel.url")
        echo -e "${GREEN}Public:${NC} $tunnel_url"
    elif [ -f "$SERVER_DIR/tunnel.log" ]; then
        # Try to extract from logs
        tunnel_url=$(grep -oE 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' "$SERVER_DIR/tunnel.log" | head -1)
        if [ ! -z "$tunnel_url" ]; then
            echo -e "${GREEN}Public:${NC} $tunnel_url"
            echo "$tunnel_url" > "$SERVER_DIR/tunnel.url"
        else
            echo -e "${YELLOW}Public: Checking tunnel logs...${NC}"
            echo -e "${YELLOW}Run this to see tunnel URL:${NC}"
            echo -e "  grep 'trycloudflare' $SERVER_DIR/tunnel.log"
        fi
    fi
    
    echo -e "\n${BLUE}Recent server logs:${NC}"
    tail -20 "$SERVER_DIR/server.log" 2>/dev/null || echo "No logs"
    
    echo -e "\n${BLUE}Recent tunnel logs:${NC}"
    tail -10 "$SERVER_DIR/tunnel.log" 2>/dev/null || echo "No tunnel logs"
    
    echo -e "\n${YELLOW}Press Enter to continue...${NC}"
    read
}

# Stop server
stop_server() {
    echo -ne "\n${YELLOW}Server name to stop: ${NC}"
    read server_name
    
    SERVER_DIR="$SERVERS_DIR/$server_name"
    
    if [ ! -d "$SERVER_DIR" ]; then
        echo -e "${RED}Server not found${NC}"
        return
    fi
    
    # Stop server
    if [ -f "$SERVER_DIR/server.pid" ]; then
        pid=$(cat "$SERVER_DIR/server.pid")
        kill $pid 2>/dev/null
        rm "$SERVER_DIR/server.pid"
    fi
    
    # Stop tunnel
    if [ -f "$SERVER_DIR/tunnel.pid" ]; then
        pid=$(cat "$SERVER_DIR/tunnel.pid")
        kill $pid 2>/dev/null
        rm "$SERVER_DIR/tunnel.pid"
    fi
    
    echo -e "${GREEN}✓ Server stopped${NC}"
    sleep 2
}

# Delete server
delete_server() {
    echo -ne "\n${YELLOW}Server name to delete: ${NC}"
    read server_name
    
    SERVER_DIR="$SERVERS_DIR/$server_name"
    
    if [ ! -d "$SERVER_DIR" ]; then
        echo -e "${RED}Server not found${NC}"
        return
    fi
    
    echo -ne "${RED}Are you sure? (yes/no): ${NC}"
    read confirm
    
    if [ "$confirm" = "yes" ]; then
        # Stop first
        if [ -f "$SERVER_DIR/server.pid" ]; then
            pid=$(cat "$SERVER_DIR/server.pid")
            kill $pid 2>/dev/null
        fi
        
        if [ -f "$SERVER_DIR/tunnel.pid" ]; then
            pid=$(cat "$SERVER_DIR/tunnel.pid")
            kill $pid 2>/dev/null
        fi
        
        rm -rf "$SERVER_DIR"
        echo -e "${GREEN}✓ Server deleted${NC}"
    else
        echo -e "${YELLOW}Cancelled${NC}"
    fi
    
    sleep 2
}

# Settings
settings() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     ⚙️  Settings                      ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}\n"
    
    echo "1. View all server files"
    echo "2. Export configuration"
    echo "3. Back"
    echo ""
    echo -ne "${YELLOW}Choice: ${NC}"
    read choice
    
    case $choice in
        1)
            echo -e "\n${BLUE}Servers directory:${NC} $SERVERS_DIR"
            ls -la "$SERVERS_DIR"
            ;;
        2)
            tar -czf "$HOME/openservers-backup.tar.gz" "$OPENSERVERS_DIR"
            echo -e "\n${GREEN}✓ Backup created: ~/openservers-backup.tar.gz${NC}"
            ;;
    esac
    
    echo -e "\n${YELLOW}Press Enter to continue...${NC}"
    read
}

# Main execution
check_environment
check_dependencies
install_cloudflared
main_menu