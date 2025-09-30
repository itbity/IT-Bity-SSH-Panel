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
NC='\033[0m'

# Variables
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

# Get server IP
SERVER_IP=$(hostname -I | awk '{print $1}')

echo -e "${GREEN}[1/12] Updating system...${NC}"
apt update && apt upgrade -y

echo -e "${GREEN}[2/12] Installing MariaDB...${NC}"
apt install -y mariadb-server mariadb-client

echo -e "${GREEN}[3/12] Starting MariaDB...${NC}"
systemctl start mariadb
systemctl enable mariadb

# Generate random MySQL password
DB_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 24)

echo -e "${GREEN}[4/12] Creating database and user...${NC}"
mysql -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "CREATE USER IF NOT EXISTS 'itbity'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO 'itbity'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

echo -e "${GREEN}[5/12] Installing Python and dependencies...${NC}"
apt install -y python3 python3-pip python3-venv python3-dev libmariadb-dev build-essential

echo -e "${GREEN}[6/12] Installing Nginx...${NC}"
apt install -y nginx

echo -e "${GREEN}[7/12] Setting up project directory...${NC}"
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

# Copy project files (assuming script runs from project root)
if [ -d "/tmp/itbity-ssh-panel" ]; then
    cp -r /tmp/itbity-ssh-panel/* $PROJECT_DIR/
else
    echo -e "${YELLOW}Warning: Project files should be in /tmp/itbity-ssh-panel${NC}"
fi

echo -e "${GREEN}[8/12] Creating virtual environment...${NC}"
python3 -m venv $VENV_DIR
source $VENV_DIR/bin/activate

echo -e "${GREEN}[9/12] Installing Python packages...${NC}"
pip install --upgrade pip
pip install -r requirements.txt

# Generate random secret key and panel path
SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
PANEL_PATH=$(python3 -c "import secrets; print(secrets.token_hex(16))")

echo -e "${GREEN}[10/12] Creating .env file...${NC}"
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

echo -e "${GREEN}[11/12] Initializing database...${NC}"
cd $PROJECT_DIR
source $VENV_DIR/bin/activate

# Initialize Flask-Migrate
export FLASK_APP=app.py
flask db init 2>/dev/null || true
flask db migrate -m "Initial migration" 2>/dev/null || true
flask db upgrade

# Create default admin user
python3 << PYTHON_SCRIPT
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
        print('Admin user created')
PYTHON_SCRIPT

echo -e "${GREEN}[12/12] Configuring Nginx...${NC}"
cat > /etc/nginx/sites-available/itbity-ssh-panel << NGINX_CONFIG
server {
    listen 80;
    server_name _;

    location /${PANEL_PATH}/ {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /${PANEL_PATH}/static/ {
        alias ${PROJECT_DIR}/static/;
    }
}
NGINX_CONFIG

ln -sf /etc/nginx/sites-available/itbity-ssh-panel /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

echo -e "${GREEN}Creating systemd service...${NC}"
cat > /etc/systemd/system/itbity-ssh-panel.service << SERVICE
[Unit]
Description=IT Bity SSH Panel
After=network.target mariadb.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=${PROJECT_DIR}
Environment="PATH=${VENV_DIR}/bin"
ExecStart=${VENV_DIR}/bin/gunicorn --workers 3 --bind 127.0.0.1:5000 app:app
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE

# Set permissions
chown -R www-data:www-data $PROJECT_DIR

systemctl daemon-reload
systemctl enable itbity-ssh-panel
systemctl start itbity-ssh-panel

# Configure firewall
echo -e "${GREEN}Configuring firewall...${NC}"
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable 2>/dev/null || true

echo ""
echo "========================================"
echo -e "${GREEN}Installation completed successfully!${NC}"
echo "========================================"
echo ""
echo -e "Panel URL: ${YELLOW}http://${SERVER_IP}/${PANEL_PATH}${NC}"
echo -e "Username: ${YELLOW}ITBity${NC}"
echo -e "Password: ${YELLOW}Admin${NC}"
echo ""
echo -e "${RED}⚠️  IMPORTANT:${NC}"
echo "1. Change admin password immediately"
echo "2. Save this URL (it's randomly generated)"
echo "3. Database password saved in: ${PROJECT_DIR}/.env"
echo ""
echo "Panel service: systemctl status itbity-ssh-panel"
echo "========================================"