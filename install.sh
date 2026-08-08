#!/bin/bash
# =============================================================================
#  Hostalika cPanel Backup System - Installer
#  Version: 2.3.0
#  Usage: bash <(curl -s https://raw.githubusercontent.com/Hostalika/cpanel-backup/main/install.sh)
# =============================================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
REPO_URL="https://raw.githubusercontent.com/Hostalika/cpanel-backup/main"
INSTALL_DIR="/opt/hostalika-backup"

log()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
step() { echo -e "\n${BLUE}[====]${NC}  $1"; }

echo ""
echo "=============================================="
echo "   Hostalika cPanel Backup System v2.3.0    "
echo "=============================================="
echo ""

[ "$EUID" -ne 0 ] && err "Must be run as root"
[ ! -f /usr/local/cpanel/bin/pkgacct ] && err "cPanel not found on this server"

if [ -f /etc/almalinux-release ] || [ -f /etc/centos-release ] || [ -f /etc/redhat-release ]; then
    PKG_MGR="yum"
elif [ -f /etc/debian_version ]; then
    PKG_MGR="apt-get"
else
    err "Unsupported OS"
fi

step "Installing required packages..."
if [ "$PKG_MGR" = "yum" ]; then
    yum install -y curl rsync python3 >> /dev/null 2>&1
else
    apt-get install -y curl rsync python3 >> /dev/null 2>&1
fi
log "Packages installed"

step "Creating directories..."
mkdir -p /backup/temp_cpanel
mkdir -p /root/.ssh
mkdir -p "$INSTALL_DIR"
log "Directories created"

step "Downloading scripts..."
curl -fsSL "${REPO_URL}/cpanel_backup.sh"     -o /usr/local/bin/cpanel_backup.sh
curl -fsSL "${REPO_URL}/cpanel_backup_bot.py" -o /usr/local/bin/cpanel_backup_bot.py
curl -fsSL "${REPO_URL}/hbm"                  -o /usr/local/bin/hbm
curl -fsSL "${REPO_URL}/VERSION"              -o "${INSTALL_DIR}/VERSION"
chmod 700 /usr/local/bin/cpanel_backup.sh
chmod 700 /usr/local/bin/cpanel_backup_bot.py
chmod +x  /usr/local/bin/hbm
log "Scripts downloaded"

step "Generating SSH key..."
if [ ! -f /root/.ssh/backup_key ]; then
    ssh-keygen -t ed25519 -C "hostalika-cpanel-backup" -f /root/.ssh/backup_key -N ""
    log "SSH key generated"
else
    log "SSH key already exists"
fi

step "Configuration..."
echo ""
read -p "  Backup server IP                              : " BACKUP_IP
read -p "  Backup server SSH user (default: backupuser) : " BACKUP_USER
BACKUP_USER=${BACKUP_USER:-backupuser}
read -p "  Backup server SSH port (default: 22)         : " BACKUP_PORT
BACKUP_PORT=${BACKUP_PORT:-22}
read -p "  Telegram Bot Token                            : " BOT_TOKEN
read -p "  Telegram Chat ID(s)                          : " CHAT_IDS
read -p "  Keep N backups (default: 3)                  : " KEEP_N
KEEP_N=${KEEP_N:-3}
read -p "  Cron schedule (default: 0 5 * * 5)           : " CRON_SCHEDULE
CRON_SCHEDULE=${CRON_SCHEDULE:-"0 5 * * 5"}

sed -i "s|REMOTE_HOST=\"YOUR_BACKUP_SERVER_IP\"|REMOTE_HOST=\"${BACKUP_IP}\"|"            /usr/local/bin/cpanel_backup.sh
sed -i "s|REMOTE_USER=\"backupuser\"|REMOTE_USER=\"${BACKUP_USER}\"|"                     /usr/local/bin/cpanel_backup.sh
sed -i "s|REMOTE_PORT=\"22\"|REMOTE_PORT=\"${BACKUP_PORT}\"|"                             /usr/local/bin/cpanel_backup.sh
sed -i "s|TELEGRAM_BOT_TOKEN=\"YOUR_BOT_TOKEN_HERE\"|TELEGRAM_BOT_TOKEN=\"${BOT_TOKEN}\"|" /usr/local/bin/cpanel_backup.sh
sed -i "s|TELEGRAM_CHAT_IDS=\"YOUR_CHAT_ID_HERE\"|TELEGRAM_CHAT_IDS=\"${CHAT_IDS}\"|"     /usr/local/bin/cpanel_backup.sh
sed -i "s|^KEEP_BACKUPS=3|KEEP_BACKUPS=${KEEP_N}|"                                        /usr/local/bin/cpanel_backup.sh
sed -i "s|BOT_TOKEN     = \"YOUR_BOT_TOKEN_HERE\"|BOT_TOKEN     = \"${BOT_TOKEN}\"|"       /usr/local/bin/cpanel_backup_bot.py
sed -i "s|REMOTE_HOST   = \"YOUR_BACKUP_SERVER_IP\"|REMOTE_HOST   = \"${BACKUP_IP}\"|"    /usr/local/bin/cpanel_backup_bot.py
sed -i "s|REMOTE_USER   = \"backupuser\"|REMOTE_USER   = \"${BACKUP_USER}\"|"             /usr/local/bin/cpanel_backup_bot.py
FIRST_CHAT=$(echo $CHAT_IDS | awk '{print $1}')
sed -i "s|\"YOUR_CHAT_ID_HERE\"|\"${FIRST_CHAT}\"|"                                        /usr/local/bin/cpanel_backup_bot.py
log "Configuration applied"

step "Installing Telegram bot as service..."
cat > /etc/systemd/system/cpanel-backup-bot.service << EOF
[Unit]
Description=cPanel Backup Telegram Bot - Hostalika
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/cpanel_backup_bot.py
Restart=always
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable cpanel-backup-bot >> /dev/null 2>&1
systemctl start cpanel-backup-bot
log "Bot service started"

step "Setting up cron job..."
(crontab -l 2>/dev/null | grep -v cpanel_backup; \
 echo "${CRON_SCHEDULE} /usr/local/bin/cpanel_backup.sh >> /var/log/cpanel_backup.log 2>&1") | crontab -
log "Cron job added: ${CRON_SCHEDULE}"

step "SSH key setup..."
echo ""
echo "  Add this public key to your backup server (${BACKUP_IP}):"
echo "  -------------------------------------------------------"
cat /root/.ssh/backup_key.pub
echo "  -------------------------------------------------------"
echo ""
echo "  Run on backup server (${BACKUP_USER}@${BACKUP_IP}):"
echo "  echo \"$(cat /root/.ssh/backup_key.pub)\" >> /home/${BACKUP_USER}/.ssh/authorized_keys"
echo ""
read -p "  Press Enter after adding the key..."

step "Testing connection..."
if ssh -i /root/.ssh/backup_key -p "$BACKUP_PORT" \
   -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o BatchMode=yes \
   "${BACKUP_USER}@${BACKUP_IP}" "echo ok" &>/dev/null; then
    log "Connection to backup server successful"
else
    warn "Cannot connect - run 'hbm test' after fixing SSH key"
fi

hash -r 2>/dev/null || true

echo ""
echo "=============================================="
echo "   Installation Complete! v2.3.0"
echo "=============================================="
echo ""
echo "  Usage: hbm <command>"
echo ""
echo "    hbm help       Show all commands"
echo "    hbm status     System status"
echo "    hbm test       Run diagnostics"
echo "    hbm backup     Start backup now"
echo "    hbm update     Update to latest"
echo "    hbm config     Edit configuration"
echo "=============================================="
