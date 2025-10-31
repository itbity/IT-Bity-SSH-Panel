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

echo -e "${GREEN}[1/14] Updating system...${NC}"
apt update && apt upgrade -y

echo -e "${GREEN}[2/14] Installing MariaDB...${NC}"
apt install -y mariadb-server mariadb-client

echo -e "${GREEN}[3/14] Starting MariaDB...${NC}"
systemctl start mariadb
systemctl enable mariadb

# Generate random MySQL password
DB_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 24)

echo -e "${GREEN}[4/14] Creating database and user...${NC}"

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

echo -e "${GREEN}[5/14] Installing Python and dependencies...${NC}"
apt install -y python3 python3-pip python3-venv python3-dev libmariadb-dev build-essential pkg-config libssl-dev libffi-dev

echo -e "${GREEN}[5.1/14] Installing network monitoring tools...${NC}"

export DEBIAN_FRONTEND=noninteractive
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections

# Install all monitoring tools non-interactively
apt install -y nethogs vnstat iftop conntrack iptables-persistent

# Enable vnstat service (for interface traffic persistence)
systemctl enable vnstat
systemctl start vnstat

# Verify installation
for cmd in nethogs vnstat iftop conntrack; do
    if command -v $cmd >/dev/null 2>&1; then
        echo -e "${GREEN}✓ $cmd installed successfully${NC}"
    else
        echo -e "${RED}✗ $cmd installation failed${NC}"
    fi
done

# ✅ Add sudo permission for traffic tools
echo -e "${GREEN}Granting sudo permissions for www-data...${NC}"
if ! grep -q "www-data ALL=(ALL) NOPASSWD: /usr/sbin/nethogs, /usr/sbin/conntrack" /etc/sudoers; then
    echo "www-data ALL=(ALL) NOPASSWD: /usr/sbin/nethogs, /usr/sbin/conntrack" >> /etc/sudoers
fi

echo -e "${GREEN}[6/14] Installing Nginx...${NC}"
apt install -y nginx

echo -e "${GREEN}[6.1/14] Configuring sudo permissions for www-data...${NC}"

cat > /etc/sudoers.d/itbity-panel <<'EOF'
# ITBity Panel restricted sudo permissions for www-data
www-data ALL=(ALL) NOPASSWD: \
    /usr/sbin/useradd, \
    /usr/sbin/userdel, \
    /usr/sbin/usermod, \
    /usr/sbin/chpasswd, \
    /usr/bin/systemctl reload ssh, \
    /usr/bin/systemctl reload sshd, \
    /usr/bin/tee -a /etc/ssh/sshd_config, \
    /usr/bin/rm -f /tmp/ssh_user_*.conf, \
    /usr/bin/pkill -KILL -u *
EOF

chmod 440 /etc/sudoers.d/itbity-panel

if visudo -c >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Sudoers file validated successfully${NC}"
else
    echo -e "${RED}✗ Invalid sudoers file! Aborting installation.${NC}"
    rm -f /etc/sudoers.d/itbity-panel
    exit 1
fi

echo -e "${GREEN}[6.2/14] Configuring PAM for connection limits...${NC}"

# Backup original sshd PAM file
if [ ! -f /etc/pam.d/sshd.backup ]; then
    cp /etc/pam.d/sshd /etc/pam.d/sshd.backup
    echo -e "${GREEN}✓ Backup created: /etc/pam.d/sshd.backup${NC}"
fi

# Check if our line already exists
if grep -q "check_user_limit.py" /etc/pam.d/sshd; then
    echo -e "${YELLOW}⚠ PAM already configured, skipping...${NC}"
else
    # Create the connection limit check script
    cat > /usr/local/bin/check_user_limit.py << 'LIMIT_SCRIPT'
#!/usr/bin/env python3

import os
import sys
import subprocess
from datetime import datetime

LOG_FILE = '/var/log/ssh_connection_limits.log'
ENV_FILE = '/var/www/itbity-ssh-panel/.env'

def log_message(message):
    try:
        with open(LOG_FILE, 'a') as f:
            f.write(f"[{datetime.now()}] {message}\n")
    except:
        pass

def load_env():
    env_vars = {}
    try:
        with open(ENV_FILE, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    env_vars[key.strip()] = value.strip().strip("'\"")
        return env_vars
    except Exception as e:
        log_message(f"ERROR: Failed to load .env: {e}")
        return None

def get_user_limit(username):
    env = load_env()
    if not env:
        return None
    
    try:
        import pymysql
        
        conn = pymysql.connect(
            host=env.get('DB_HOST', 'localhost'),
            user=env.get('DB_USER'),
            password=env.get('DB_PASSWORD'),
            database=env.get('DB_NAME'),
            charset='utf8mb4'
        )
        
        with conn.cursor() as cursor:
            query = """
                SELECT ul.max_connections 
                FROM users u 
                JOIN user_limits ul ON u.id = ul.user_id 
                WHERE u.username = %s AND u.is_active = 1
            """
            cursor.execute(query, (username,))
            result = cursor.fetchone()
            
            conn.close()
            
            if result:
                return result[0]
            return None
            
    except Exception as e:
        log_message(f"ERROR: Database query failed: {e}")
        return None

def count_user_sessions(username):
    try:
        result = subprocess.run(['who'], capture_output=True, text=True, timeout=5)
        if result.returncode != 0:
            return 0
        
        sessions = [line for line in result.stdout.split('\n') if line.startswith(username)]
        return len(sessions)
    except Exception as e:
        log_message(f"ERROR: Failed to count sessions: {e}")
        return 0

def main():
    username = os.environ.get('PAM_USER')
    
    if not username:
        log_message("ERROR: PAM_USER not found")
        sys.exit(0)
    
    max_connections = get_user_limit(username)
    
    if max_connections is None:
        log_message(f"INFO: No limit configured for user '{username}', allowing login")
        sys.exit(0)
    
    current_sessions = count_user_sessions(username)
    
    log_message(f"USER: {username}, CURRENT: {current_sessions}, MAX: {max_connections}")
    
    if current_sessions >= max_connections:
        print("=" * 70)
        print("CONNECTION LIMIT REACHED!")
        print(f"Maximum connections allowed: {max_connections}")
        print(f"Current active connections: {current_sessions}")
        print("Please disconnect one session or contact your administrator.")
        print("=" * 70)
        log_message(f"DENIED: {username} reached limit ({current_sessions}/{max_connections})")
        sys.exit(1)
    else:
        log_message(f"ALLOWED: {username} connection ({current_sessions + 1}/{max_connections})")
        sys.exit(0)

if __name__ == '__main__':
    main()
LIMIT_SCRIPT

    chmod +x /usr/local/bin/check_user_limit.py
    chown root:root /usr/local/bin/check_user_limit.py
    
    touch /var/log/ssh_connection_limits.log
    chmod 666 /var/log/ssh_connection_limits.log
    
    echo -e "${GREEN}✓ Connection limit script created${NC}"
    
    sed -i '/^@include common-account/a # ITBity Panel - Check user connection limit\naccount    required     pam_exec.so /usr/local/bin/check_user_limit.py' /etc/pam.d/sshd
    
    if grep -q "check_user_limit.py" /etc/pam.d/sshd; then
        echo -e "${GREEN}✓ PAM configured successfully${NC}"
    else
        echo -e "${RED}✗ Failed to configure PAM${NC}"
        echo -e "${YELLOW}Restoring backup...${NC}"
        cp /etc/pam.d/sshd.backup /etc/pam.d/sshd
        exit 1
    fi
fi

echo -e "${GREEN}[7/14] Setting up project directory...${NC}"
mkdir -p $PROJECT_DIR
echo "Copying files from $SCRIPT_DIR to $PROJECT_DIR..."
rsync -av --exclude='venv' --exclude='__pycache__' --exclude='*.pyc' --exclude='.git' --exclude='migrations' "$SCRIPT_DIR/" "$PROJECT_DIR/"

cd $PROJECT_DIR

echo -e "${GREEN}[8/14] Creating virtual environment...${NC}"
python3 -m venv $VENV_DIR
source $VENV_DIR/bin/activate

echo -e "${GREEN}[9/14] Installing Python packages...${NC}"
pip install --upgrade pip setuptools wheel
pip install --no-cache-dir -r $PROJECT_DIR/requirements.txt

# Install gunicorn
pip install gunicorn

# Generate random secret key and panel path
SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
PANEL_PATH=$(python3 -c "import secrets; print(secrets.token_hex(16))")

echo -e "${GREEN}[10/14] Creating .env file...${NC}"
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

echo -e "${GREEN}[11/14] Creating WSGI entry point...${NC}"

# Create wsgi.py file
cat > $PROJECT_DIR/wsgi.py << 'WSGI_PY'
from app import create_app, db
from app.models import User

# Create Flask application instance
application = create_app()
app = application

@app.cli.command()
def init_db():
    """Initialize database with default admin user"""
    db.create_all()
    
    admin = User.query.filter_by(username='ITBity').first()
    if not admin:
        admin = User(username='ITBity', user_type='admin')
        admin.set_password('Admin')
        db.session.add(admin)
        db.session.commit()
        print('Default admin user created: ITBity / Admin')
    else:
        print('Admin user already exists')

if __name__ == '__main__':
    with app.app_context():
        db.create_all()
    app.run(
        host=app.config.get('HOST', '127.0.0.1'),
        port=app.config.get('PORT', 5000),
        debug=app.config.get('DEBUG', False)
    )
WSGI_PY

chmod +x $PROJECT_DIR/wsgi.py
echo -e "${GREEN}✓ wsgi.py created${NC}"

echo -e "${GREEN}[12/14] Testing application structure...${NC}"
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

# Test 3: Try to import app module
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

# Test 5: Check if wsgi.py works
echo -e "${BLUE}Testing wsgi.py...${NC}"
if ! $VENV_DIR/bin/python3 -c "import wsgi; print('✓ wsgi.py works')" 2>&1; then
    echo -e "${RED}✗ wsgi.py import failed!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All application tests passed${NC}"

echo -e "${GREEN}[13/14] Initializing database...${NC}"
source $VENV_DIR/bin/activate
export FLASK_APP=wsgi.py

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

echo -e "${GREEN}[14/14] Configuring services...${NC}"

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
        proxy_redirect off;
    }

    # Static files - without panel path prefix
    location /static {
        alias /var/www/itbity-ssh-panel/static/;
        expires 30d;
        access_log off;
        add_header Cache-Control "public, immutable";
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
echo -e "${BLUE}Creating systemd service...${NC}"
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
ExecStart=/var/www/itbity-ssh-panel/venv/bin/gunicorn --workers 3 --bind 127.0.0.1:5000 --timeout 120 --access-logfile /var/log/itbity-panel-access.log --error-logfile /var/log/itbity-panel-error.log wsgi:app
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE

# Set proper permissions
chown -R www-data:www-data $PROJECT_DIR
chmod +x $PROJECT_DIR/wsgi.py
[ -f "$PROJECT_DIR/app.py" ] && chmod +x $PROJECT_DIR/app.py

# Create log files with proper permissions
touch /var/log/itbity-panel-access.log /var/log/itbity-panel-error.log
chown www-data:www-data /var/log/itbity-panel-access.log /var/log/itbity-panel-error.log

# Final test: Run gunicorn as www-data for 3 seconds
echo -e "${BLUE}Testing Gunicorn with wsgi.py...${NC}"
sudo -u www-data $VENV_DIR/bin/gunicorn --bind 127.0.0.1:5001 --timeout 5 wsgi:app --daemon --pid /tmp/test-gunicorn.pid
sleep 3

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
echo -e "${BLUE}Starting panel service...${NC}"
systemctl daemon-reload
systemctl enable itbity-ssh-panel
systemctl start itbity-ssh-panel

# Wait for service to start
sleep 5

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
    echo -e "${BLUE}Setting up firewall rules...${NC}"
    ufw allow 22/tcp       # SSH - CRITICAL!
    ufw allow 80/tcp       # HTTP
    ufw allow 443/tcp      # HTTPS
    ufw --force enable 2>/dev/null || true
    echo -e "${GREEN}✓ Firewall configured (SSH, HTTP, HTTPS allowed)${NC}"
    ufw status numbered
else
    echo -e "${YELLOW}⚠ UFW not found, skipping firewall configuration${NC}"
fi

echo ""
echo "========================================"
echo -e "${GREEN}✓✓✓ Installation Completed! ✓✓✓${NC}"
echo "========================================"
echo ""
echo -e "${BLUE}Panel Access Information:${NC}"
echo -e "  Panel URL: ${YELLOW}http://${SERVER_IP}/${PANEL_PATH}${NC}"
echo -e "  Default Username: ${YELLOW}ITBity${NC}"
echo -e "  Default Password: ${YELLOW}Admin${NC}"
echo ""
echo -e "${BLUE}Database Information:${NC}"
echo -e "  Database Name: ${YELLOW}${DB_NAME}${NC}"
echo -e "  Database User: ${YELLOW}itbity${NC}"
echo -e "  Database Password: ${YELLOW}${DB_PASSWORD}${NC}"
echo -e "  Database Host: ${YELLOW}localhost${NC}"
echo ""
echo -e "${BLUE}Configuration File:${NC}"
echo -e "  Location: ${YELLOW}${PROJECT_DIR}/.env${NC}"
echo -e "  View credentials: ${YELLOW}cat ${PROJECT_DIR}/.env${NC}"
echo ""
echo -e "${BLUE}SSH Connection Limits:${NC}"
echo -e "  Limit script: ${YELLOW}/usr/local/bin/check_user_limit.py${NC}"
echo -e "  Limit logs:   ${YELLOW}tail -f /var/log/ssh_connection_limits.log${NC}"
echo -e "  PAM config:   ${YELLOW}/etc/pam.d/sshd${NC}"
echo -e "  PAM backup:   ${YELLOW}/etc/pam.d/sshd.backup${NC}"
echo ""
echo -e "${RED}⚠️  CRITICAL SECURITY WARNINGS:${NC}"
echo "  1. Change admin password IMMEDIATELY after first login"
echo "  2. Save the panel URL (it's randomly generated and won't be shown again)"
echo "  3. Keep database credentials safe (stored in .env file)"
echo "  4. Database credentials are stored in: ${PROJECT_DIR}/.env"
echo ""
echo -e "${BLUE}Database Tables Created:${NC}"
echo -e "  ${GREEN}✓${NC} users (User accounts and authentication)"
echo -e "  ${GREEN}✓${NC} user_limits (Traffic limits and restrictions)"
echo ""
echo -e "${BLUE}Service Management:${NC}"
echo "  Status:  systemctl status itbity-ssh-panel"
echo "  Logs:    journalctl -u itbity-ssh-panel -f"
echo "  Errors:  tail -f /var/log/itbity-panel-error.log"
echo "  Restart: systemctl restart itbity-ssh-panel"
echo "  Stop:    systemctl stop itbity-ssh-panel"
echo ""
echo -e "${BLUE}Debug Commands:${NC}"
echo "  Test import: cd $PROJECT_DIR && sudo -u www-data ./venv/bin/python3 -c 'from app import create_app; app = create_app()'"
echo "  Manual run:  cd $PROJECT_DIR && sudo -u www-data ./venv/bin/gunicorn --bind 127.0.0.1:5000 wsgi:app"
echo "  View .env:   cat ${PROJECT_DIR}/.env"
echo ""
echo "========================================"
echo -e "${GREEN}Installation Summary:${NC}"
echo "========================================"
echo -e "${GREEN}✓${NC} MariaDB installed and configured"
echo -e "${GREEN}✓${NC} Database '${DB_NAME}' created"
echo -e "${GREEN}✓${NC} Database user 'itbity' created"
echo -e "${GREEN}✓${NC} Admin user 'ITBity' created in database"
echo -e "${GREEN}✓${NC} Python environment configured"
echo -e "${GREEN}✓${NC} Nginx reverse proxy configured"
echo -e "${GREEN}✓${NC} Systemd service running"
echo -e "${GREEN}✓${NC} Firewall configured (SSH, HTTP, HTTPS)"
echo -e "${GREEN}✓${NC} PAM connection limits configured"
echo ""
echo -e "${YELLOW}Save these credentials before closing this terminal!${NC}"
echo "========================================"