#!/bin/bash

# Show Panel Credentials


RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PROJECT_DIR="/var/www/itbity-ssh-panel"
ENV_FILE="$PROJECT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}Error: .env file not found!${NC}"
    echo "Panel may not be installed yet."
    exit 1
fi

# Read values from .env
PANEL_PATH=$(grep "^PANEL_PATH=" $ENV_FILE | cut -d "'" -f 2)
DB_NAME=$(grep "^DB_NAME=" $ENV_FILE | cut -d "'" -f 2)
DB_USER=$(grep "^DB_USER=" $ENV_FILE | cut -d "'" -f 2)
DB_PASSWORD=$(grep "^DB_PASSWORD=" $ENV_FILE | cut -d "'" -f 2)
DB_HOST=$(grep "^DB_HOST=" $ENV_FILE | cut -d "'" -f 2)

SERVER_IP=$(hostname -I | awk '{print $1}')

clear
echo ""
echo "========================================"
echo "  IT Bity SSH Panel - Credentials"
echo "========================================"
echo ""
echo -e "${BLUE}Panel Access:${NC}"
echo -e "  URL: ${YELLOW}http://${SERVER_IP}/${PANEL_PATH}${NC}"
echo -e "  Username: ${YELLOW}ITBity${NC}"
echo -e "  Password: ${YELLOW}Admin${NC}"
echo ""
echo -e "${BLUE}Database Credentials:${NC}"
echo -e "  Host: ${YELLOW}${DB_HOST}${NC}"
echo -e "  Database: ${YELLOW}${DB_NAME}${NC}"
echo -e "  Username: ${YELLOW}${DB_USER}${NC}"
echo -e "  Password: ${YELLOW}${DB_PASSWORD}${NC}"
echo ""
echo -e "${BLUE}MySQL Connection String:${NC}"
echo -e "  ${YELLOW}mysql -u ${DB_USER} -p'${DB_PASSWORD}' ${DB_NAME}${NC}"
echo ""
echo -e "${BLUE}Service Status:${NC}"

# Check service status
if systemctl is-active --quiet itbity-ssh-panel; then
    echo -e "  Panel Service: ${GREEN}Running ✓${NC}"
else
    echo -e "  Panel Service: ${RED}Stopped ✗${NC}"
fi

if systemctl is-active --quiet nginx; then
    echo -e "  Nginx: ${GREEN}Running ✓${NC}"
else
    echo -e "  Nginx: ${RED}Stopped ✗${NC}"
fi

if systemctl is-active --quiet mariadb; then
    echo -e "  MariaDB: ${GREEN}Running ✓${NC}"
else
    echo -e "  MariaDB: ${RED}Stopped ✗${NC}"
fi

echo ""
echo -e "${BLUE}Database Tables:${NC}"

# Check if tables exist
TABLES=$(mysql -u $DB_USER -p"$DB_PASSWORD" $DB_NAME -e "SHOW TABLES;" 2>/dev/null | tail -n +2)

if [ -z "$TABLES" ]; then
    echo -e "  ${RED}No tables found${NC}"
else
    echo "$TABLES" | while read table; do
        COUNT=$(mysql -u $DB_USER -p"$DB_PASSWORD" $DB_NAME -e "SELECT COUNT(*) FROM $table;" 2>/dev/null | tail -n 1)
        echo -e "  ${GREEN}✓${NC} $table (${COUNT} records)"
    done
fi

echo ""
echo -e "${BLUE}Admin User:${NC}"

# Check admin user
ADMIN_EXISTS=$(mysql -u $DB_USER -p"$DB_PASSWORD" $DB_NAME -e "SELECT COUNT(*) FROM users WHERE username='ITBity';" 2>/dev/null | tail -n 1)

if [ "$ADMIN_EXISTS" -eq "1" ]; then
    echo -e "  ${GREEN}✓${NC} Admin user 'ITBity' exists"
    
    # Get admin details
    ADMIN_ROLE=$(mysql -u $DB_USER -p"$DB_PASSWORD" $DB_NAME -e "SELECT role FROM users WHERE username='ITBity';" 2>/dev/null | tail -n 1)
    ADMIN_ACTIVE=$(mysql -u $DB_USER -p"$DB_PASSWORD" $DB_NAME -e "SELECT is_active FROM users WHERE username='ITBity';" 2>/dev/null | tail -n 1)
    
    echo -e "  Role: ${YELLOW}${ADMIN_ROLE}${NC}"
    echo -e "  Status: ${YELLOW}$([ "$ADMIN_ACTIVE" -eq "1" ] && echo "Active" || echo "Inactive")${NC}"
else
    echo -e "  ${RED}✗${NC} Admin user 'ITBity' not found!"
fi

echo ""
echo -e "${BLUE}Files & Directories:${NC}"
echo -e "  Config: ${YELLOW}${ENV_FILE}${NC}"
echo -e "  Logs: ${YELLOW}/var/log/itbity-panel-*.log${NC}"
echo -e "  Project: ${YELLOW}${PROJECT_DIR}${NC}"

echo ""
echo -e "${RED}⚠️  Security Reminder:${NC}"
echo "  - Change default admin password immediately"
echo "  - Keep these credentials safe"
echo "  - Never share your .env file"
echo ""
echo "========================================"
echo ""