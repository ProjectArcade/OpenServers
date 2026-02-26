#!/bin/bash

# lib/server_types.sh — File scaffolding for each server type
# Sourced by openservers.sh

# ─── Shared inline CSS / HTML shell ───────────────────────────────────────────
# Avoids duplicating the same glassmorphism card across templates.
_card_css() {
    cat << 'STYLE'
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
STYLE
}

# ─── Python / Flask ───────────────────────────────────────────────────────────
create_python_server() {
    local dir=$1
    local port=$2

    cat > "$dir/server.py" << PYEOF
from flask import Flask, jsonify
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
$(_card_css)
        </style>
    </head>
    <body>
        <div class="container">
            <h1>🚀 OpenServers</h1>
            <div class="status">● Server Running</div>
            <div class="info">
                <p><strong>Your device is now a server!</strong></p>
                <p>This is running on your device</p>
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
PYEOF

    echo "flask" > "$dir/requirements.txt"
    pip install flask --break-system-packages 2>/dev/null || pip install flask
}

# ─── Static HTML ──────────────────────────────────────────────────────────────
create_static_server() {
    local dir=$1
    local port=$2

    cat > "$dir/index.html" << HTMLEOF
<!DOCTYPE html>
<html>
<head>
    <title>OpenServers - Running</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
$(_card_css)
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 OpenServers</h1>
        <div class="status">● Server Running</div>
        <div class="info">
            <p><strong>Your device is now a server!</strong></p>
            <p>This static site is running on your device</p>
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
HTMLEOF

    cat > "$dir/start.sh" << EOF
#!/bin/bash
python3 -m http.server $port
EOF
    chmod +x "$dir/start.sh"
}

# ─── Node.js ──────────────────────────────────────────────────────────────────
create_node_server() {
    local dir=$1
    local port=$2

    # Embed the CSS as a JS string so we don't need a separate file
    local css
    css=$(_card_css)

    cat > "$dir/server.js" << JSEOF
const http = require('http');

const HTML = \`
<!DOCTYPE html>
<html>
<head>
    <title>OpenServers - Running</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
${css}
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 OpenServers</h1>
        <div class="status">● Server Running</div>
        <div class="info">
            <p><strong>Your device is now a server!</strong></p>
            <p>This Node.js server is running on your device</p>
            <p>Powered by OpenServers</p>
        </div>
        <div>
            <span class="badge">Node.js</span>
            <span class="badge">Port $port</span>
        </div>
    </div>
</body>
</html>
\`;

const server = http.createServer((req, res) => {
    if (req.url === '/') {
        res.writeHead(200, { 'Content-Type': 'text/html' });
        res.end(HTML);
    } else if (req.url === '/api/status') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ status: 'running', server: 'OpenServers', timestamp: new Date().toISOString() }));
    } else {
        res.writeHead(404);
        res.end('Not Found');
    }
});

server.listen($port, '0.0.0.0', () => console.log('Server running on port $port'));
JSEOF
}

# ─── Custom ───────────────────────────────────────────────────────────────────
create_custom_server() {
    local dir=$1
    local port=$2

    echo -e "\n${BLUE}Custom server setup:${NC}"
    echo "  1. Git clone from repository"
    echo "  2. Create files manually (opens editor)"
    echo "  3. Use existing local directory"
    echo ""
    echo -ne "${YELLOW}Choice (1-3): ${NC}"
    read custom_choice

    case $custom_choice in
        1) _custom_git_clone "$dir" "$port" ;;
        2) _custom_create_files "$dir" "$port" ;;
        3) _custom_copy_dir "$dir" ;;
        *)
            echo -e "${RED}Invalid choice${NC}"
            return 1
            ;;
    esac

    if [ ! -f "$dir/start.sh" ]; then
        echo -e "\n${YELLOW}⚠ No start script created${NC}"
        echo -e "${YELLOW}You can add one later at: $dir/start.sh${NC}"
    fi
}

# ── Helpers for create_custom_server ─────────────────────────────────────────

_pick_editor() {
    for ed in nano vim vi; do
        if command -v "$ed" &> /dev/null; then
            echo "$ed"
            return
        fi
    done
    echo ""
}

_write_start_sh() {
    local dir=$1
    local code_dir=$2
    local cmd=$3
    cat > "$dir/start.sh" << EOF
#!/bin/bash
cd "$code_dir"
$cmd
EOF
    chmod +x "$dir/start.sh"
    echo -e "${GREEN}✓ Start script created${NC}"
}

_ask_start_command() {
    echo -e "\n${YELLOW}How should we start your server?${NC}"
    echo "Example: python app.py, node index.js, ./start.sh"
    echo -ne "${YELLOW}Start command: ${NC}"
    read start_cmd
    echo "$start_cmd"
}

_custom_git_clone() {
    local dir=$1 port=$2
    echo -ne "\n${YELLOW}Git repository URL: ${NC}"
    read git_url
    [ -z "$git_url" ] && return 1

    echo -e "${BLUE}Cloning repository...${NC}"
    if git clone "$git_url" "$dir/code" 2>/dev/null; then
        echo -e "${GREEN}✓ Repository cloned successfully${NC}"
        local cmd
        cmd=$(_ask_start_command)
        [ -n "$cmd" ] && _write_start_sh "$dir" "$dir/code" "$cmd"
    else
        echo -e "${RED}✗ Failed to clone repository${NC}"
        return 1
    fi
}

_custom_create_files() {
    local dir=$1 port=$2
    mkdir -p "$dir/code"

    local editor
    editor=$(_pick_editor)
    if [ -z "$editor" ]; then
        echo -e "${RED}No text editor found (nano/vim/vi)${NC}"
        return 1
    fi

    echo -e "\n${YELLOW}What language/framework will you use?${NC}"
    echo "  1. Python"
    echo "  2. Node.js"
    echo "  3. Shell script"
    echo "  4. Other"
    echo ""
    echo -ne "${YELLOW}Choice (1-4): ${NC}"
    read lang_choice

    case $lang_choice in
        1)
            cat > "$dir/code/app.py" << 'EOF'
# Your Python server code here
# from flask import Flask
# app = Flask(__name__)
# @app.route('/')
# def home(): return "Hello from OpenServers!"
# if __name__ == '__main__': app.run(host='0.0.0.0', port=8000)
EOF
            $editor "$dir/code/app.py"
            _write_start_sh "$dir" "$dir/code" "python3 app.py"
            ;;
        2)
            cat > "$dir/code/server.js" << 'EOF'
// Your Node.js server code here
// const http = require('http');
// const server = http.createServer((req, res) => { res.end('Hello!'); });
// server.listen(8000, '0.0.0.0');
EOF
            $editor "$dir/code/server.js"
            _write_start_sh "$dir" "$dir/code" "node server.js"
            ;;
        3)
            cat > "$dir/start.sh" << 'EOF'
#!/bin/bash
# Your startup commands here
# python3 -m http.server 8000
EOF
            $editor "$dir/start.sh"
            chmod +x "$dir/start.sh"
            ;;
        4)
            echo -ne "\n${YELLOW}Filename (e.g., main.go, index.php): ${NC}"
            read filename
            filename="${filename:-main.txt}"
            touch "$dir/code/$filename"
            $editor "$dir/code/$filename"
            local cmd
            cmd=$(_ask_start_command)
            [ -n "$cmd" ] && _write_start_sh "$dir" "$dir/code" "$cmd"
            ;;
    esac

    echo -e "\n${GREEN}✓ Custom server files created${NC}"
}

_custom_copy_dir() {
    local dir=$1
    echo -ne "\n${YELLOW}Path to existing directory: ${NC}"
    read source_dir

    if [ -d "$source_dir" ]; then
        echo -e "${BLUE}Copying files...${NC}"
        cp -r "$source_dir"/* "$dir/code/" 2>/dev/null
        echo -e "${GREEN}✓ Files copied${NC}"
        local cmd
        cmd=$(_ask_start_command)
        [ -n "$cmd" ] && _write_start_sh "$dir" "$dir/code" "$cmd"
    else
        echo -e "${RED}✗ Directory not found${NC}"
        return 1
    fi
}