#!/bin/bash
# =============================================================================
#  Hostalika cPanel Backup System - Installer
#  Version: 2.1
#  Usage: bash <(curl -s https://raw.githubusercontent.com/Hostalika/cpanel-backup/main/install.sh)
# =============================================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
REPO_URL="https://raw.githubusercontent.com/Hostalika/cpanel-backup/main"
INSTALL_DIR="/opt/hostalika-backup"
VERSION_FILE="/opt/hostalika-backup/VERSION"

log()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
step() { echo -e "\n${BLUE}[====]${NC}  $1"; }

echo ""
echo "=============================================="
echo "   Hostalika cPanel Backup System Installer  "
echo "=============================================="
echo ""

# Check root
[ "$EUID" -ne 0 ] && err "Must be run as root"

# Check cPanel
[ ! -f /usr/local/cpanel/bin/pkgacct ] && err "cPanel not found on this server"

# Check OS
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
curl -fsSL "${REPO_URL}/VERSION"              -o "$VERSION_FILE"
chmod 700 /usr/local/bin/cpanel_backup.sh
chmod 700 /usr/local/bin/cpanel_backup_bot.py
log "Scripts downloaded"

step "Installing management commands..."
# hbm-update
cat > /usr/local/bin/hbm-update << 'EOF'
#!/bin/bash
REPO_URL="https://raw.githubusercontent.com/Hostalika/cpanel-backup/main"
echo "[Hostalika] Checking for updates..."
REMOTE_VER=$(curl -fsSL "${REPO_URL}/VERSION" 2>/dev/null)
LOCAL_VER=$(cat /opt/hostalika-backup/VERSION 2>/dev/null || echo "0.0.0")
if [ "$REMOTE_VER" = "$LOCAL_VER" ]; then
    echo "Already up to date (v${LOCAL_VER})"
    exit 0
fi
echo "Updating from v${LOCAL_VER} to v${REMOTE_VER}..."
curl -fsSL "${REPO_URL}/cpanel_backup.sh"     -o /usr/local/bin/cpanel_backup.sh
curl -fsSL "${REPO_URL}/cpanel_backup_bot.py" -o /usr/local/bin/cpanel_backup_bot.py
echo "$REMOTE_VER" > /opt/hostalika-backup/VERSION
chmod 700 /usr/local/bin/cpanel_backup.sh
chmod 700 /usr/local/bin/cpanel_backup_bot.py
systemctl restart cpanel-backup-bot 2>/dev/null || true
echo "Update complete - v${REMOTE_VER}"
EOF

# hbm-status
cat > /usr/local/bin/hbm-status << 'EOF'
#!/bin/bash
echo "=== Hostalika Backup System Status ==="
echo "Version   : $(cat /opt/hostalika-backup/VERSION 2>/dev/null || echo 'unknown')"
echo "Bot       : $(systemctl is-active cpanel-backup-bot 2>/dev/null || echo 'not installed')"
echo "Cron      : $(crontab -l 2>/dev/null | grep cpanel_backup || echo 'not set')"
echo "Keep      : $(grep '^KEEP_BACKUPS=' /usr/local/bin/cpanel_backup.sh | cut -d= -f2) backups"
echo "Last run  : $(grep 'Backup Report' /var/log/cpanel_backup.log 2>/dev/null | tail -1 || echo 'never')"
echo "Disk      : $(df -h /backup 2>/dev/null | awk 'NR==2 {print $3" used / "$2" total ("$5")"}')"
EOF

# hbm-logs
cat > /usr/local/bin/hbm-logs << 'EOF'
#!/bin/bash
tail -50 /var/log/cpanel_backup.log
EOF

# hbm-restart
cat > /usr/local/bin/hbm-restart << 'EOF'
#!/bin/bash
systemctl restart cpanel-backup-bot
systemctl status cpanel-backup-bot
EOF

# hbm-uninstall
cat > /usr/local/bin/hbm-uninstall << 'EOF'
#!/bin/bash
echo "Uninstalling Hostalika Backup System..."
systemctl stop cpanel-backup-bot 2>/dev/null || true
systemctl disable cpanel-backup-bot 2>/dev/null || true
rm -f /etc/systemd/system/cpanel-backup-bot.service
systemctl daemon-reload
crontab -l 2>/dev/null | grep -v cpanel_backup | crontab - 2>/dev/null || true
rm -f /usr/local/bin/cpanel_backup.sh
rm -f /usr/local/bin/cpanel_backup_bot.py
rm -f /usr/local/bin/hbm-update
rm -f /usr/local/bin/hbm-status
rm -f /usr/local/bin/hbm-logs
rm -f /usr/local/bin/hbm-restart
rm -f /usr/local/bin/hbm-uninstall
rm -rf /opt/hostalika-backup
echo "Uninstall complete."
echo "Note: /backup/temp_cpanel and SSH keys were NOT removed."
EOF

chmod +x /usr/local/bin/hbm-update
chmod +x /usr/local/bin/hbm-status
chmod +x /usr/local/bin/hbm-logs
chmod +x /usr/local/bin/hbm-restart
chmod +x /usr/local/bin/hbm-uninstall
log "Management commands installed"

step "Generating SSH key..."
if [ ! -f /root/.ssh/backup_key ]; then
    ssh-keygen -t ed25519 -C "hostalika-cpanel-backup" -f /root/.ssh/backup_key -N ""
    log "SSH key generated: /root/.ssh/backup_key"
else
    log "SSH key already exists"
fi

step "Configuration..."
echo ""
read -p "  Backup server IP          : " BACKUP_IP
read -p "  Backup server SSH user    : " BACKUP_USER
BACKUP_USER=${BACKUP_USER:-backupuser}
read -p "  Backup server SSH port    : " BACKUP_PORT
BACKUP_PORT=${BACKUP_PORT:-22}
read -p "  Telegram Bot Token        : " BOT_TOKEN
read -p "  Telegram Chat ID(s)       : " CHAT_IDS
read -p "  Keep N backups (default 3): " KEEP_N
KEEP_N=${KEEP_N:-3}
read -p "  Cron schedule (default: 0 5 * * 5 = every Friday 5AM): " CRON_SCHEDULE
CRON_SCHEDULE=${CRON_SCHEDULE:-"0 5 * * 5"}

# Apply settings to backup script
sed -i "s|REMOTE_HOST=\"YOUR_BACKUP_SERVER_IP\"|REMOTE_HOST=\"${BACKUP_IP}\"|" /usr/local/bin/cpanel_backup.sh
sed -i "s|REMOTE_USER=\"backupuser\"|REMOTE_USER=\"${BACKUP_USER}\"|" /usr/local/bin/cpanel_backup.sh
sed -i "s|REMOTE_PORT=\"22\"|REMOTE_PORT=\"${BACKUP_PORT}\"|" /usr/local/bin/cpanel_backup.sh
sed -i "s|TELEGRAM_BOT_TOKEN=\"YOUR_BOT_TOKEN_HERE\"|TELEGRAM_BOT_TOKEN=\"${BOT_TOKEN}\"|" /usr/local/bin/cpanel_backup.sh
sed -i "s|TELEGRAM_CHAT_IDS=\"YOUR_CHAT_ID_HERE\"|TELEGRAM_CHAT_IDS=\"${CHAT_IDS}\"|" /usr/local/bin/cpanel_backup.sh
sed -i "s|^KEEP_BACKUPS=3|KEEP_BACKUPS=${KEEP_N}|" /usr/local/bin/cpanel_backup.sh

# Apply settings to bot script
sed -i "s|BOT_TOKEN     = \"YOUR_BOT_TOKEN_HERE\"|BOT_TOKEN     = \"${BOT_TOKEN}\"|" /usr/local/bin/cpanel_backup_bot.py
sed -i "s|REMOTE_HOST   = \"YOUR_BACKUP_SERVER_IP\"|REMOTE_HOST   = \"${BACKUP_IP}\"|" /usr/local/bin/cpanel_backup_bot.py
FIRST_CHAT=$(echo $CHAT_IDS | awk '{print $1}')
sed -i "s|\"YOUR_CHAT_ID_HERE\"|\"${FIRST_CHAT}\"|" /usr/local/bin/cpanel_backup_bot.py

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

step "Copying SSH public key to backup server..."
echo ""
echo "  Public key to add on backup server (${BACKUP_IP}):"
echo "  -------------------------------------------------------"
cat /root/.ssh/backup_key.pub
echo "  -------------------------------------------------------"
echo ""
read -p "  Press Enter after adding the key to the backup server..."

step "Testing connection to backup server..."
if ssh -i /root/.ssh/backup_key -p "$BACKUP_PORT" \
   -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o BatchMode=yes \
   "${BACKUP_USER}@${BACKUP_IP}" "echo ok" &>/dev/null; then
    log "Connection to backup server successful"
else
    warn "Cannot connect to backup server - check SSH key setup manually"
fi

echo ""
echo "=============================================="
echo "   Installation Complete!"
echo "=============================================="
echo ""
echo "  Backup script : /usr/local/bin/cpanel_backup.sh"
echo "  Bot script    : /usr/local/bin/cpanel_backup_bot.py"
echo "  Log file      : /var/log/cpanel_backup.log"
echo "  SSH key       : /root/.ssh/backup_key"
echo ""
echo "  Management commands:"
echo "    hbm-status    - Show system status"
echo "    hbm-update    - Update to latest version"
echo "    hbm-logs      - View recent logs"
echo "    hbm-restart   - Restart Telegram bot"
echo "    hbm-uninstall - Remove everything"
echo ""
echo "  To run a manual backup:"
echo "    /usr/local/bin/cpanel_backup.sh"
echo ""
echo "  Or send /backup to your Telegram bot"
echo "=============================================="
