#!/bin/bash
# =============================================================================
#  Hostalika cPanel Backup System - Installer
#  Version: 2.2.0
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
echo "   Hostalika cPanel Backup System v2.2.0    "
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
curl -fsSL "${REPO_URL}/VERSION"              -o "${INSTALL_DIR}/VERSION"
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
curl -fsSL "${REPO_URL}/hbm-config.sh"        -o /usr/local/bin/hbm-config
curl -fsSL "${REPO_URL}/hbm-test.sh"          -o /usr/local/bin/hbm-test
curl -fsSL "${REPO_URL}/hbm-clean.sh"         -o /usr/local/bin/hbm-clean
curl -fsSL "${REPO_URL}/hbm-disk.sh"          -o /usr/local/bin/hbm-disk
curl -fsSL "${REPO_URL}/hbm-list.sh"          -o /usr/local/bin/hbm-list
curl -fsSL "${REPO_URL}/hbm-backup-now.sh"    -o /usr/local/bin/hbm-backup-now
curl -fsSL "${REPO_URL}/hbm-backup-account.sh" -o /usr/local/bin/hbm-backup-account
curl -fsSL "${REPO_URL}/hbm-restore.sh"       -o /usr/local/bin/hbm-restore
chmod +x /usr/local/bin/hbm-*
echo "$REMOTE_VER" > /opt/hostalika-backup/VERSION
systemctl restart cpanel-backup-bot 2>/dev/null || true
echo "Update complete - v${REMOTE_VER}"
EOF

# hbm-status
cat > /usr/local/bin/hbm-status << 'EOF'
#!/bin/bash
SCRIPT="/usr/local/bin/cpanel_backup.sh"
echo "=============================================="
echo "   Hostalika Backup System Status"
echo "=============================================="
echo "Version      : $(cat /opt/hostalika-backup/VERSION 2>/dev/null || echo 'unknown')"
echo "Bot service  : $(systemctl is-active cpanel-backup-bot 2>/dev/null || echo 'not installed')"
echo "Cron         : $(crontab -l 2>/dev/null | grep cpanel_backup | awk '{print $1,$2,$3,$4,$5}' || echo 'not set')"
echo "Backup server: $(grep '^REMOTE_HOST=' $SCRIPT | cut -d'"' -f2)"
echo "SSH user     : $(grep '^REMOTE_USER=' $SCRIPT | cut -d'"' -f2)"
echo "Keep backups : $(grep '^KEEP_BACKUPS=' $SCRIPT | cut -d'=' -f2)"
echo "Last run     : $(grep 'Backup Report' /var/log/cpanel_backup.log 2>/dev/null | tail -1 | awk '{print $1,$2}' || echo 'never')"
echo "Last status  : $(grep 'Backup Report' /var/log/cpanel_backup.log 2>/dev/null | tail -1 | grep -oP '(?<=- ).*' || echo 'N/A')"
echo "Disk (local) : $(df -h /backup 2>/dev/null | awk 'NR==2 {print $3" used / "$2" total ("$5")"}')"
echo "=============================================="
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
read -p "Are you sure you want to uninstall? (yes/no): " confirm
[ "$confirm" != "yes" ] && echo "Aborted." && exit 0
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
rm -f /usr/local/bin/hbm-config
rm -f /usr/local/bin/hbm-test
rm -f /usr/local/bin/hbm-clean
rm -f /usr/local/bin/hbm-disk
rm -f /usr/local/bin/hbm-list
rm -f /usr/local/bin/hbm-backup-now
rm -f /usr/local/bin/hbm-backup-account
rm -f /usr/local/bin/hbm-restore
rm -rf /opt/hostalika-backup
echo "Uninstall complete."
echo "Note: /backup/temp_cpanel and SSH keys were NOT removed."
EOF

# hbm-config
cat > /usr/local/bin/hbm-config << 'EOF'
#!/bin/bash
SCRIPT="/usr/local/bin/cpanel_backup.sh"
BOT="/usr/local/bin/cpanel_backup_bot.py"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; RED='\033[0;31m'; NC='\033[0m'

echo -e "\n${BLUE}Current Configuration:${NC}"
echo "----------------------------------------"
grep -E "^REMOTE_HOST=|^REMOTE_USER=|^REMOTE_PORT=|^KEEP_BACKUPS=|^TELEGRAM_BOT_TOKEN=|^TELEGRAM_CHAT_IDS=" "$SCRIPT"
echo "Cron: $(crontab -l 2>/dev/null | grep cpanel_backup | awk '{print $1,$2,$3,$4,$5}' || echo 'not set')"
echo "----------------------------------------"
echo -e "\n${YELLOW}Leave blank to keep current value${NC}\n"

read -p "  Backup server IP       [$(grep '^REMOTE_HOST=' $SCRIPT | cut -d'"' -f2)]: " v
[ -n "$v" ] && { sed -i "s|^REMOTE_HOST=.*|REMOTE_HOST=\"${v}\"|" "$SCRIPT"; sed -i "s|REMOTE_HOST   = .*|REMOTE_HOST   = \"${v}\"|" "$BOT"; }

read -p "  Backup server SSH user [$(grep '^REMOTE_USER=' $SCRIPT | cut -d'"' -f2)]: " v
[ -n "$v" ] && { sed -i "s|^REMOTE_USER=.*|REMOTE_USER=\"${v}\"|" "$SCRIPT"; sed -i "s|REMOTE_USER   = .*|REMOTE_USER   = \"${v}\"|" "$BOT"; }

read -p "  Backup server SSH port [$(grep '^REMOTE_PORT=' $SCRIPT | cut -d'"' -f2)]: " v
[ -n "$v" ] && sed -i "s|^REMOTE_PORT=.*|REMOTE_PORT=\"${v}\"|" "$SCRIPT"

read -p "  Keep N backups         [$(grep '^KEEP_BACKUPS=' $SCRIPT | cut -d'=' -f2)]: " v
[ -n "$v" ] && sed -i "s|^KEEP_BACKUPS=.*|KEEP_BACKUPS=${v}|" "$SCRIPT"

read -p "  Telegram Bot Token     [$(grep '^TELEGRAM_BOT_TOKEN=' $SCRIPT | cut -d'"' -f2)]: " v
[ -n "$v" ] && { sed -i "s|^TELEGRAM_BOT_TOKEN=.*|TELEGRAM_BOT_TOKEN=\"${v}\"|" "$SCRIPT"; sed -i "s|BOT_TOKEN     = .*|BOT_TOKEN     = \"${v}\"|" "$BOT"; }

read -p "  Telegram Chat ID(s)    [$(grep '^TELEGRAM_CHAT_IDS=' $SCRIPT | cut -d'"' -f2)]: " v
[ -n "$v" ] && sed -i "s|^TELEGRAM_CHAT_IDS=.*|TELEGRAM_CHAT_IDS=\"${v}\"|" "$SCRIPT"

read -p "  Cron schedule          [$(crontab -l 2>/dev/null | grep cpanel_backup | awk '{print $1,$2,$3,$4,$5}')]: " v
if [ -n "$v" ]; then
    (crontab -l 2>/dev/null | grep -v cpanel_backup; \
     echo "${v} /usr/local/bin/cpanel_backup.sh >> /var/log/cpanel_backup.log 2>&1") | crontab -
fi

echo -e "\n${GREEN}Configuration updated.${NC}"
systemctl restart cpanel-backup-bot 2>/dev/null && echo "Bot restarted." || true

echo -e "\n${BLUE}Testing SSH connection...${NC}"
RHOST=$(grep '^REMOTE_HOST=' "$SCRIPT" | cut -d'"' -f2)
RUSER=$(grep '^REMOTE_USER=' "$SCRIPT" | cut -d'"' -f2)
RPORT=$(grep '^REMOTE_PORT=' "$SCRIPT" | cut -d'"' -f2)
SKEY=$(grep '^SSH_KEY=' "$SCRIPT" | cut -d'"' -f2)
if ssh -i "$SKEY" -p "$RPORT" -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
   -o BatchMode=yes "${RUSER}@${RHOST}" "echo ok" &>/dev/null; then
    echo -e "${GREEN}Connection successful!${NC}"
else
    echo -e "${RED}Connection failed. Add this key to ${RHOST}:${NC}"
    cat "${SKEY}.pub"
fi
EOF

# hbm-test
cat > /usr/local/bin/hbm-test << 'EOF'
#!/bin/bash
SCRIPT="/usr/local/bin/cpanel_backup.sh"
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}[OK]${NC}    $1"; }
fail() { echo -e "  ${RED}[FAIL]${NC}  $1"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC}  $1"; }

RHOST=$(grep '^REMOTE_HOST=' "$SCRIPT" | cut -d'"' -f2)
RUSER=$(grep '^REMOTE_USER=' "$SCRIPT" | cut -d'"' -f2)
RPORT=$(grep '^REMOTE_PORT=' "$SCRIPT" | cut -d'"' -f2)
SKEY=$(grep '^SSH_KEY=' "$SCRIPT" | cut -d'"' -f2)
BOT_TOKEN=$(grep '^TELEGRAM_BOT_TOKEN=' "$SCRIPT" | cut -d'"' -f2)
CHAT_IDS=$(grep '^TELEGRAM_CHAT_IDS=' "$SCRIPT" | cut -d'"' -f2)

echo -e "\n${BLUE}====== Hostalika Backup System - Full Test ======${NC}\n"

# 1. cPanel
[ -f /usr/local/cpanel/bin/pkgacct ] && ok "cPanel found" || fail "cPanel not found"

# 2. Required packages
command -v curl  &>/dev/null && ok "curl installed"  || fail "curl not installed"
command -v rsync &>/dev/null && ok "rsync installed" || fail "rsync not installed"
command -v python3 &>/dev/null && ok "python3 installed" || fail "python3 not installed"

# 3. SSH key
[ -f "$SKEY" ] && ok "SSH key exists: $SKEY" || fail "SSH key missing: $SKEY"

# 4. SSH connection
if ssh -i "$SKEY" -p "$RPORT" -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
   -o BatchMode=yes "${RUSER}@${RHOST}" "echo ok" &>/dev/null; then
    ok "SSH connection to ${RHOST} successful"
else
    fail "SSH connection to ${RHOST} failed"
fi

# 5. rsync test
if rsync -e "ssh -i ${SKEY} -p ${RPORT} -o StrictHostKeyChecking=no" \
   --dry-run /etc/hostname "${RUSER}@${RHOST}:/tmp/" &>/dev/null; then
    ok "rsync transfer works"
else
    fail "rsync transfer failed"
fi

# 6. Disk space
FREE=$(df -BG /backup 2>/dev/null | awk 'NR==2 {print $4}' | tr -d 'G')
if [ -n "$FREE" ] && [ "$FREE" -gt 20 ]; then
    ok "Local disk space: ${FREE}GB free"
elif [ -n "$FREE" ]; then
    warn "Local disk space low: ${FREE}GB free"
else
    warn "Could not check local disk space"
fi

# 7. Remote disk space
RDISK=$(ssh -i "$SKEY" -p "$RPORT" -o StrictHostKeyChecking=no \
    "${RUSER}@${RHOST}" "df -h /backup 2>/dev/null | awk 'NR==2 {print \$4}'" 2>/dev/null)
[ -n "$RDISK" ] && ok "Backup server disk free: ${RDISK}" || warn "Could not check backup server disk"

# 8. Telegram
TG_RESP=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getMe" 2>/dev/null)
echo "$TG_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('ok',''))" 2>/dev/null | grep -q "True" \
    && ok "Telegram bot token valid" || fail "Telegram bot token invalid"

# 9. Bot service
systemctl is-active cpanel-backup-bot &>/dev/null && ok "Telegram bot service running" || warn "Telegram bot service not running"

# 10. Cron
crontab -l 2>/dev/null | grep -q cpanel_backup \
    && ok "Cron job set: $(crontab -l 2>/dev/null | grep cpanel_backup | awk '{print $1,$2,$3,$4,$5}')" \
    || warn "Cron job not set"

echo -e "\n${BLUE}=================================================${NC}\n"
EOF

# hbm-clean
cat > /usr/local/bin/hbm-clean << 'EOF'
#!/bin/bash
TEMP_DIR="/backup/temp_cpanel"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
echo "Checking for stale temp folders in ${TEMP_DIR}..."
count=0
for d in "${TEMP_DIR}"/????-??-??_??-??; do
    [ -d "$d" ] || continue
    sz=$(du -sh "$d" | cut -f1)
    rm -rf "$d"
    echo -e "  ${YELLOW}[REMOVED]${NC} $(basename $d) ($sz)"
    ((count++))
done
if [ $count -eq 0 ]; then
    echo -e "  ${GREEN}No stale folders found. Everything is clean.${NC}"
else
    echo -e "\n  ${GREEN}Removed $count stale folder(s).${NC}"
fi
echo "Current usage: $(du -sh ${TEMP_DIR} 2>/dev/null | cut -f1)"
EOF

# hbm-disk
cat > /usr/local/bin/hbm-disk << 'EOF'
#!/bin/bash
SCRIPT="/usr/local/bin/cpanel_backup.sh"
RHOST=$(grep '^REMOTE_HOST=' "$SCRIPT" | cut -d'"' -f2)
RUSER=$(grep '^REMOTE_USER=' "$SCRIPT" | cut -d'"' -f2)
RPORT=$(grep '^REMOTE_PORT=' "$SCRIPT" | cut -d'"' -f2)
SKEY=$(grep '^SSH_KEY=' "$SCRIPT" | cut -d'"' -f2)
echo "=== Local Server Disk Usage ==="
df -h /backup
echo ""
echo "=== Backup Server (${RHOST}) Disk Usage ==="
ssh -i "$SKEY" -p "$RPORT" -o StrictHostKeyChecking=no "${RUSER}@${RHOST}" "df -h /backup"
echo ""
echo "=== Backup Copies on ${RHOST} ==="
ssh -i "$SKEY" -p "$RPORT" -o StrictHostKeyChecking=no "${RUSER}@${RHOST}" \
    "ls -lht /backup/cpanel/ 2>/dev/null | grep -v total || echo 'No backups found'"
EOF

# hbm-list
cat > /usr/local/bin/hbm-list << 'EOF'
#!/bin/bash
SCRIPT="/usr/local/bin/cpanel_backup.sh"
RHOST=$(grep '^REMOTE_HOST=' "$SCRIPT" | cut -d'"' -f2)
RUSER=$(grep '^REMOTE_USER=' "$SCRIPT" | cut -d'"' -f2)
RPORT=$(grep '^REMOTE_PORT=' "$SCRIPT" | cut -d'"' -f2)
SKEY=$(grep '^SSH_KEY=' "$SCRIPT" | cut -d'"' -f2)
RDIR=$(grep '^REMOTE_DIR=' "$SCRIPT" | cut -d'"' -f2)
echo "=== Available Backups on ${RHOST} ==="
ssh -i "$SKEY" -p "$RPORT" -o StrictHostKeyChecking=no "${RUSER}@${RHOST}" "
for d in \$(ls -dt ${RDIR}/????-??-??_??-?? 2>/dev/null); do
    count=\$(ls \$d/*.tar.gz \$d/*.tar 2>/dev/null | wc -l)
    size=\$(du -sh \$d | cut -f1)
    echo \"  \$(basename \$d)  |  \${count} accounts  |  \${size}\"
done
" 2>/dev/null || echo "No backups found"
EOF

# hbm-backup-now
cat > /usr/local/bin/hbm-backup-now << 'EOF'
#!/bin/bash
echo "Starting manual backup in background..."
echo "Monitor progress with: hbm-logs"
nohup /usr/local/bin/cpanel_backup.sh >> /var/log/cpanel_backup.log 2>&1 &
echo "Backup started with PID: $!"
EOF

# hbm-backup-account
cat > /usr/local/bin/hbm-backup-account << 'EOF'
#!/bin/bash
SCRIPT="/usr/local/bin/cpanel_backup.sh"
[ -z "$1" ] && echo "Usage: hbm-backup-account <username>" && exit 1
USERNAME="$1"
[ ! -d "/var/cpanel/users/${USERNAME}" ] && echo "Account not found: ${USERNAME}" && exit 1

RHOST=$(grep '^REMOTE_HOST=' "$SCRIPT" | cut -d'"' -f2)
RUSER=$(grep '^REMOTE_USER=' "$SCRIPT" | cut -d'"' -f2)
RPORT=$(grep '^REMOTE_PORT=' "$SCRIPT" | cut -d'"' -f2)
SKEY=$(grep '^SSH_KEY=' "$SCRIPT" | cut -d'"' -f2)
RDIR=$(grep '^REMOTE_DIR=' "$SCRIPT" | cut -d'"' -f2)
DATE=$(date +"%Y-%m-%d_%H-%M")
TMPDIR="/backup/temp_cpanel/single-${DATE}"

echo "Backing up account: ${USERNAME}"
mkdir -p "$TMPDIR"
/usr/local/cpanel/bin/pkgacct "$USERNAME" "$TMPDIR"

FILE=$(ls "${TMPDIR}/cpmove-${USERNAME}.tar.gz" 2>/dev/null || ls "${TMPDIR}/cpmove-${USERNAME}.tar" 2>/dev/null)
if [ -n "$FILE" ] && [ -f "$FILE" ]; then
    echo "Transferring to backup server..."
    ssh -i "$SKEY" -p "$RPORT" -o StrictHostKeyChecking=no "${RUSER}@${RHOST}" "mkdir -p ${RDIR}/single-accounts"
    rsync -avz -e "ssh -i ${SKEY} -p ${RPORT} -o StrictHostKeyChecking=no" \
        "$FILE" "${RUSER}@${RHOST}:${RDIR}/single-accounts/"
    rm -rf "$TMPDIR"
    echo "Done: ${USERNAME} backed up to ${RHOST}:${RDIR}/single-accounts/"
else
    echo "Backup failed for: ${USERNAME}"
    rm -rf "$TMPDIR"
    exit 1
fi
EOF

# hbm-restore
cat > /usr/local/bin/hbm-restore << 'EOF'
#!/bin/bash
SCRIPT="/usr/local/bin/cpanel_backup.sh"
if [ -z "$1" ]; then
    echo "Usage: hbm-restore <username> [backup-date]"
    echo "       hbm-restore john"
    echo "       hbm-restore john 2026-08-08_02-00"
    echo ""
    echo "Available backups:"
    hbm-list
    exit 1
fi

USERNAME="$1"
RHOST=$(grep '^REMOTE_HOST=' "$SCRIPT" | cut -d'"' -f2)
RUSER=$(grep '^REMOTE_USER=' "$SCRIPT" | cut -d'"' -f2)
RPORT=$(grep '^REMOTE_PORT=' "$SCRIPT" | cut -d'"' -f2)
SKEY=$(grep '^SSH_KEY=' "$SCRIPT" | cut -d'"' -f2)
RDIR=$(grep '^REMOTE_DIR=' "$SCRIPT" | cut -d'"' -f2)

if [ -n "$2" ]; then
    BACKUP_PATH="${RDIR}/${2}/cpmove-${USERNAME}.tar.gz"
else
    BACKUP_PATH=$(ssh -i "$SKEY" -p "$RPORT" -o StrictHostKeyChecking=no "${RUSER}@${RHOST}" \
        "ls -t ${RDIR}/????-??-??_??-??/cpmove-${USERNAME}.tar.gz 2>/dev/null | head -1")
fi

if [ -z "$BACKUP_PATH" ]; then
    echo "No backup found for account: ${USERNAME}"
    exit 1
fi

echo "Restoring: ${USERNAME}"
echo "Source   : ${RHOST}:${BACKUP_PATH}"
echo "Target   : /home/"
echo ""
scp -i "$SKEY" -P "$RPORT" -o StrictHostKeyChecking=no \
    "${RUSER}@${RHOST}:${BACKUP_PATH}" /home/
echo ""
echo "File copied to /home/$(basename $BACKUP_PATH)"
echo "To restore via WHM: Transfers > Restore a Full Backup/cpmove File"
EOF

chmod +x /usr/local/bin/hbm-update
chmod +x /usr/local/bin/hbm-status
chmod +x /usr/local/bin/hbm-logs
chmod +x /usr/local/bin/hbm-restart
chmod +x /usr/local/bin/hbm-uninstall
chmod +x /usr/local/bin/hbm-config
chmod +x /usr/local/bin/hbm-test
chmod +x /usr/local/bin/hbm-clean
chmod +x /usr/local/bin/hbm-disk
chmod +x /usr/local/bin/hbm-list
chmod +x /usr/local/bin/hbm-backup-now
chmod +x /usr/local/bin/hbm-backup-account
chmod +x /usr/local/bin/hbm-restore

log "Management commands installed"

step "Generating SSH key..."
if [ ! -f /root/.ssh/backup_key ]; then
    ssh-keygen -t ed25519 -C "hostalika-cpanel-backup" -f /root/.ssh/backup_key -N ""
    log "SSH key generated"
else
    log "SSH key already exists"
fi

step "Configuration..."
echo ""
read -p "  Backup server IP                         : " BACKUP_IP
read -p "  Backup server SSH user (default: backupuser): " BACKUP_USER
BACKUP_USER=${BACKUP_USER:-backupuser}
read -p "  Backup server SSH port (default: 22)     : " BACKUP_PORT
BACKUP_PORT=${BACKUP_PORT:-22}
read -p "  Telegram Bot Token                       : " BOT_TOKEN
read -p "  Telegram Chat ID(s)                      : " CHAT_IDS
read -p "  Keep N backups (default: 3)              : " KEEP_N
KEEP_N=${KEEP_N:-3}
read -p "  Cron schedule (default: 0 5 * * 5)      : " CRON_SCHEDULE
CRON_SCHEDULE=${CRON_SCHEDULE:-"0 5 * * 5"}

sed -i "s|REMOTE_HOST=\"YOUR_BACKUP_SERVER_IP\"|REMOTE_HOST=\"${BACKUP_IP}\"|"       /usr/local/bin/cpanel_backup.sh
sed -i "s|REMOTE_USER=\"backupuser\"|REMOTE_USER=\"${BACKUP_USER}\"|"                /usr/local/bin/cpanel_backup.sh
sed -i "s|REMOTE_PORT=\"22\"|REMOTE_PORT=\"${BACKUP_PORT}\"|"                        /usr/local/bin/cpanel_backup.sh
sed -i "s|TELEGRAM_BOT_TOKEN=\"YOUR_BOT_TOKEN_HERE\"|TELEGRAM_BOT_TOKEN=\"${BOT_TOKEN}\"|" /usr/local/bin/cpanel_backup.sh
sed -i "s|TELEGRAM_CHAT_IDS=\"YOUR_CHAT_ID_HERE\"|TELEGRAM_CHAT_IDS=\"${CHAT_IDS}\"|"     /usr/local/bin/cpanel_backup.sh
sed -i "s|^KEEP_BACKUPS=3|KEEP_BACKUPS=${KEEP_N}|"                                  /usr/local/bin/cpanel_backup.sh
sed -i "s|BOT_TOKEN     = \"YOUR_BOT_TOKEN_HERE\"|BOT_TOKEN     = \"${BOT_TOKEN}\"|"      /usr/local/bin/cpanel_backup_bot.py
sed -i "s|REMOTE_HOST   = \"YOUR_BACKUP_SERVER_IP\"|REMOTE_HOST   = \"${BACKUP_IP}\"|"   /usr/local/bin/cpanel_backup_bot.py
sed -i "s|REMOTE_USER   = \"backupuser\"|REMOTE_USER   = \"${BACKUP_USER}\"|"            /usr/local/bin/cpanel_backup_bot.py
FIRST_CHAT=$(echo $CHAT_IDS | awk '{print $1}')
sed -i "s|\"YOUR_CHAT_ID_HERE\"|\"${FIRST_CHAT}\"|"                                  /usr/local/bin/cpanel_backup_bot.py

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
log "Cron job added"

step "SSH key setup..."
echo ""
echo "  Add this public key to your backup server (${BACKUP_IP}):"
echo "  -------------------------------------------------------"
cat /root/.ssh/backup_key.pub
echo "  -------------------------------------------------------"
echo ""
echo "  Run on backup server:"
echo "  echo \"$(cat /root/.ssh/backup_key.pub)\" >> /home/${BACKUP_USER}/.ssh/authorized_keys"
echo ""
read -p "  Press Enter after adding the key..."

step "Testing connection..."
if ssh -i /root/.ssh/backup_key -p "$BACKUP_PORT" \
   -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o BatchMode=yes \
   "${BACKUP_USER}@${BACKUP_IP}" "echo ok" &>/dev/null; then
    log "Connection to backup server successful"
else
    warn "Cannot connect - run 'hbm-test' after fixing SSH key"
fi

hash -r 2>/dev/null || true

echo ""
echo "=============================================="
echo "   Hostalika Backup System v2.2.0 Installed!"
echo "=============================================="
echo ""
echo "  Management commands:"
echo "    hbm-status          - System status"
echo "    hbm-config          - Edit configuration"
echo "    hbm-test            - Full system test"
echo "    hbm-update          - Update to latest"
echo "    hbm-logs            - View logs"
echo "    hbm-disk            - Disk usage"
echo "    hbm-list            - List backups"
echo "    hbm-clean           - Remove stale temp files"
echo "    hbm-backup-now      - Start backup now"
echo "    hbm-backup-account  - Backup single account"
echo "    hbm-restore         - Restore account"
echo "    hbm-restart         - Restart bot"
echo "    hbm-uninstall       - Remove everything"
echo "=============================================="
