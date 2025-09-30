#!/bin/bash

#===========================================
# IT Bity SSH Panel - Auto Installer
# Ubuntu/Debian Only
#===========================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="/var/www/itbity-ssh-panel"
VENV_DIR="$PROJECT_DIR/venv"
DB_NAME="itbitysshpanel"

echo "========================================"
echo "  IT Bity SSH Panel - Installation"
echo "========================================"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Error: Please run as root (sudo ./install.sh)${NC}"
    exit 1
fi

# Check if requirements.txt exists
if [ ! -f "$SCRIPT_DIR/requirements.txt" ]; then
    echo -e "${RED}Error: requirements.txt not found in $SCRIPT_DIR${NC}"
    exit 1
fi

# Check if app directory exists
if [ ! -d "$SCRIPT_DIR/app" ]; then
    echo -e "${RED}Error: app/ directory not found in $SCRIPT_DIR${NC}"
    exit 1
fi

# Get server IP
SERVER_IP=$(hostname -I | awk '{print $1}')

echo -e "${GREEN}[1/13] Updating system...${NC}"
apt update && apt upgrade -y

echo -e "${GREEN}[2/13] Installing MariaDB...${NC}"
apt install -y mariadb-server mariadb-client

echo -e "${GREEN}[3/13] Starting MariaDB...${NC}"
systemctl start mariadb
systemctl enable mariadb

# Generate random MySQL password
DB_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 24)

echo -e "${GREEN}[4/13] Creating database and user...${NC}"

# Drop user if exists
mysql -e "DROP USER IF EXISTS 'itbity'@'localhost';" 2>/dev/null || true

# Create database
mysql -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

# Create user - MariaDB syntax
mysql -e "CREATE USER 'itbity'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';"

# Grant privileges
mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO 'itbity'@'localhost';"

# Flush privileges
mysql -e "FLUSH PRIVILEGES;"

# Test connection
echo "Testing database connection..."
if mysql -u itbity -p"${DB_PASSWORD}" -e "USE ${DB_NAME};" 2>/dev/null; then
    echo -e "${GREEN}✓ Database connection successful${NC}"
else
    echo -e "${RED}✗ Database connection failed!${NC}"
    exit 1
fi

echo -e "${GREEN}[5/13] Installing Python and dependencies...${NC}"
apt install -y python3 python3-pip python3-venv python3-dev libmariadb-dev build-essential pkg-config libssl-dev libffi-dev

echo -e "${GREEN}[6/13] Installing Nginx...${NC}"
apt install -y nginx

echo -e "${GREEN}[7/13] Setting up project directory...${NC}"
mkdir -p $PROJECT_DIR
echo "Copying files from $SCRIPT_DIR to $PROJECT_DIR..."
rsync -av --exclude='venv' --exclude='__pycache__' --exclude='*.pyc' --exclude='.git' --exclude='migrations' "$SCRIPT_DIR/" "$PROJECT_DIR/"

cd $PROJECT_DIR

echo -e "${GREEN}[8/13] Creating virtual environment...${NC}"
python3 -m venv $VENV_DIR
source $VENV_DIR/bin/activate

echo -e "${GREEN}[9/13] Installing Python packages...${NC}"
pip install --upgrade pip setuptools wheel
pip install --no-cache-dir -r $PROJECT_DIR/requirements.txt

# Install gunicorn
pip install gunicorn

# Generate random secret key and panel path
SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
PANEL_PATH=$(python3 -c "import secrets; print(secrets.token_hex(16))")

echo -e "${GREEN}[10/13] Creating .env file...${NC}"
cat > $PROJECT_DIR/.env << EOF
SECRET_KEY='$SECRET_KEY'
PANEL_PATH='$PANEL_PATH'

DB_HOST='localhost'
DB_USER='itbity'
DB_PASSWORD='$DB_PASSWORD'
DB_NAME='$DB_NAME'

HOST='127.0.0.1'
PORT=5000
DEBUG=False
EOF

chmod 600 $PROJECT_DIR/.env

echo -e "${GREEN}[11/13] Testing application structure...${NC}"
cd $PROJECT_DIR

# Test 1: Check if app package exists
if [ ! -f "$PROJECT_DIR/app/__init__.py" ]; then
    echo -e "${RED}✗ app/__init__.py not found!${NC}"
    exit 1
fi

# Test 2: Check if models exist
if [ ! -f "$PROJECT_DIR/app/models.py" ]; then
    echo -e "${RED}✗ app/models.py not found!${NC}"
    exit 1
fi

# Test 3: Try to import app
echo -e "${BLUE}Testing app import...${NC}"
if ! $VENV_DIR/bin/python3 -c "from app import create_app; print('Import successful')" 2>&1; then
    echo -e "${RED}✗ Failed to import app module!${NC}"
    echo -e "${YELLOW}Checking app structure:${NC}"
    ls -la $PROJECT_DIR/app/
    exit 1
fi

# Test 4: Try to create app instance
echo -e "${BLUE}Testing app creation...${NC}"
if ! $VENV_DIR/bin/python3 -c "from app import create_app; app = create_app(); print('App created successfully')" 2>&1; then
    echo -e "${RED}✗ Failed to create app instance!${NC}"
    exit 1
fi

# Test 5: Check if app.py has the app object
echo -e "${BLUE}Testing app.py structure...${NC}"
if ! $VENV_DIR/bin/python3 -c "import app as app_module; print(f'App object type: {type(app_module.app)}')" 2>&1; then
    echo -e "${RED}✗ app.py doesn't expose 'app' object correctly!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All application tests passed${NC}"

echo -e "${GREEN}[12/13] Initializing database...${NC}"
source $VENV_DIR/bin/activate
export FLASK_APP=app.py

if [ ! -d "$PROJECT_DIR/migrations" ]; then
    flask db init
fi

flask db migrate -m "Initial migration" 2>/dev/null || echo "Migration already exists"
flask db upgrade

# Create default admin user
$VENV_DIR/bin/python3 << 'PYTHON_SCRIPT'
from app import create_app, db
from app.models import User, UserLimit

app = create_app()
with app.app_context():
    admin = User.query.filter_by(username='ITBity').first()
    if not admin:
        admin = User(username='ITBity', role='admin', is_active=True)
        admin.set_password('Admin')
        db.session.add(admin)
        db.session.flush()
        
        admin_limits = UserLimit(
            user_id=admin.id,
            traffic_limit_gb=999999,
            max_connections=999,
            download_speed_mbps=0
        )
        db.session.add(admin_limits)
        db.session.commit()
        print('✓ Admin user created')
    else:
        print('✓ Admin user already exists')
PYTHON_SCRIPT

echo -e "${GREEN}[13/13] Configuring services...${NC}"

# Nginx configuration
cat > /etc/nginx/sites-available/itbity-ssh-panel << 'NGINX_CONFIG'
server {
    listen 80;
    server_name _;

    location /PANEL_PATH_PLACEHOLDER {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /PANEL_PATH_PLACEHOLDER/static {
        alias /var/www/itbity-ssh-panel/static/;
    }
}
NGINX_CONFIG

# Replace placeholder with actual panel path
sed -i "s|PANEL_PATH_PLACEHOLDER|${PANEL_PATH}|g" /etc/nginx/sites-available/itbity-ssh-panel

ln -sf /etc/nginx/sites-available/itbity-ssh-panel /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

if nginx -t 2>&1; then
    systemctl reload nginx
    echo -e "${GREEN}✓ Nginx configured successfully${NC}"
else
    echo -e "${RED}✗ Nginx configuration failed!${NC}"
    exit 1
fi

# Systemd service
cat > /etc/systemd/system/itbity-ssh-panel.service << 'SERVICE'
[Unit]
Description=IT Bity SSH Panel
After=network.target mariadb.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/var/www/itbity-ssh-panel
Environment="PATH=/var/www/itbity-ssh-panel/venv/bin"
ExecStart=/var/www/itbity-ssh-panel/venv/bin/gunicorn --workers 3 --bind 127.0.0.1:5000 --timeout 120 --access-logfile /var/log/itbity-panel-access.log --error-logfile /var/log/itbity-panel-error.log app:app
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE

# Set proper permissions
chown -R www-data:www-data $PROJECT_DIR
chmod +x $PROJECT_DIR/app.py

# Create log files with proper permissions
touch /var/log/itbity-panel-access.log /var/log/itbity-panel-error.log
chown www-data:www-data /var/log/itbity-panel-access.log /var/log/itbity-panel-error.log

# Final test: Run gunicorn as www-data for 2 seconds
echo -e "${BLUE}Testing Gunicorn startup...${NC}"
sudo -u www-data $VENV_DIR/bin/gunicorn --bind 127.0.0.1:5001 --timeout 5 app:app --daemon --pid /tmp/test-gunicorn.pid
sleep 2

if [ -f /tmp/test-gunicorn.pid ]; then
    TEST_PID=$(cat /tmp/test-gunicorn.pid)
    if ps -p $TEST_PID > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Gunicorn test successful${NC}"
        kill $TEST_PID 2>/dev/null || true
        rm -f /tmp/test-gunicorn.pid
    else
        echo -e "${RED}✗ Gunicorn test failed - process died${NC}"
        echo -e "${YELLOW}Check error log:${NC}"
        tail -n 20 /var/log/itbity-panel-error.log 2>/dev/null || echo "No error log"
        exit 1
    fi
else
    echo -e "${RED}✗ Gunicorn test failed - no PID file${NC}"
    exit 1
fi

# Start the actual service
systemctl daemon-reload
systemctl enable itbity-ssh-panel
systemctl start itbity-ssh-panel

# Wait for service to start
sleep 3

# Check service status
if systemctl is-active --quiet itbity-ssh-panel; then
    echo -e "${GREEN}✓ Panel service started successfully${NC}"
else
    echo -e "${RED}✗ Panel service failed to start${NC}"
    echo ""
    echo "=== Service Status ==="
    systemctl status itbity-ssh-panel --no-pager -l
    echo ""
    echo "=== Recent Logs ==="
    journalctl -u itbity-ssh-panel -n 50 --no-pager
    echo ""
    echo "=== Error Log ==="
    tail -n 30 /var/log/itbity-panel-error.log 2>/dev/null || echo "No error log yet"
    exit 1
fi

# Configure firewall
echo -e "${GREEN}Configuring firewall...${NC}"
if command -v ufw &> /dev/null; then
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw --force enable 2>/dev/null || true
fi

echo ""
echo "========================================"
echo -e "${GREEN}✓ Installation completed!${NC}"
echo "========================================"
echo ""
echo -e "Panel URL: ${YELLOW}http://${SERVER_IP}/${PANEL_PATH}${NC}"
echo -e "Username: ${YELLOW}ITBity${NC}"
echo -e "Password: ${YELLOW}Admin${NC}"
echo ""
echo -e "${RED}⚠️  IMPORTANT:${NC}"
echo "1. Change admin password immediately"
echo "2. Save this URL (it's randomly generated)"
echo "3. Database credentials: ${PROJECT_DIR}/.env"
echo ""
echo "Commands:"
echo "  Status: systemctl status itbity-ssh-panel"
echo "  Logs: journalctl -u itbity-ssh-panel -f"
echo "  Error log: tail -f /var/log/itbity-panel-error.log"
echo "  Restart: systemctl restart itbity-ssh-panel"
echo "  Stop: systemctl stop itbity-ssh-panel"
echo ""
echo "Debug commands:"
echo "  Test import: cd $PROJECT_DIR && sudo -u www-data ./venv/bin/python3 -c 'from app import create_app; app = create_app()'"
echo "  Manual run: cd $PROJECT_DIR && sudo -u www-data ./venv/bin/gunicorn --bind 127.0.0.1:5000 app:app"
echo "========================================"