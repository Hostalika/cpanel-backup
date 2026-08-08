#!/bin/bash
# =============================================================================
#  cPanel Automatic Backup Script
#  Version: 2.1 | Hostalika LLC
#  Notifications: Telegram
# =============================================================================
#
#  SETTINGS - Edit these values before running
# =============================================================================

REMOTE_HOST="YOUR_BACKUP_SERVER_IP"
REMOTE_USER="backupuser"
REMOTE_PORT="22"
REMOTE_DIR="/backup/cpanel"
SSH_KEY="/root/.ssh/backup_key"
LOCAL_TEMP_DIR="/backup/temp_cpanel"
KEEP_LOCAL_COPY=false
KEEP_BACKUPS=3

TELEGRAM_BOT_TOKEN="YOUR_BOT_TOKEN_HERE"
TELEGRAM_CHAT_IDS="YOUR_CHAT_ID_HERE"
# To add multiple users: TELEGRAM_CHAT_IDS="111111111 222222222 333333333"

LOG_FILE="/var/log/cpanel_backup.log"
LOG_MAX_SIZE=10

# =============================================================================
#  DO NOT EDIT BELOW THIS LINE
# =============================================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
BACKUP_DATE=$(date +"%Y-%m-%d_%H-%M")
BACKUP_SESSION_DIR="${LOCAL_TEMP_DIR}/${BACKUP_DATE}"
START_TIME=$(date +%s)
SUCCESS_COUNT=0; FAIL_COUNT=0; FAILED_ACCOUNTS=()

log() {
    local level="$1"; local message="$2"; local ts=$(date +"%Y-%m-%d %H:%M:%S")
    case "$level" in
        INFO)  echo -e "${GREEN}[INFO]${NC}  $ts - $message" | tee -a "$LOG_FILE" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC}  $ts - $message" | tee -a "$LOG_FILE" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $ts - $message" | tee -a "$LOG_FILE" ;;
        START) echo -e "${BLUE}[====]${NC}  $ts - $message" | tee -a "$LOG_FILE" ;;
    esac
}

send_telegram() {
    local message="$1"
    for tid in ${TELEGRAM_CHAT_IDS}; do
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d chat_id="${tid}" \
            -d text="${message}" \
            -d parse_mode="HTML" \
            >> "$LOG_FILE" 2>&1
    done
}

check_requirements() {
    log INFO "Checking requirements..."
    [ "$EUID" -ne 0 ] && { log ERROR "Script must be run as root"; exit 1; }
    [ ! -f /usr/local/cpanel/bin/pkgacct ] && { log ERROR "cPanel not found on this server"; exit 1; }
    [ ! -f "$SSH_KEY" ] && { log ERROR "SSH key not found: $SSH_KEY"; exit 1; }
    command -v curl  &>/dev/null || { log ERROR "curl not installed: yum install curl -y";  exit 1; }
    command -v rsync &>/dev/null || { log ERROR "rsync not installed: yum install rsync -y"; exit 1; }
    log INFO "Testing connection to backup server ${REMOTE_HOST} ..."
    if ! ssh -i "$SSH_KEY" -p "$REMOTE_PORT" -o ConnectTimeout=10 \
         -o StrictHostKeyChecking=no -o BatchMode=yes \
         "${REMOTE_USER}@${REMOTE_HOST}" "echo ok" &>/dev/null; then
        log ERROR "Connection to backup server failed!"
        send_telegram "<b>[Hostalika] Backup FAILED</b>
Cannot connect to backup server ${REMOTE_HOST}
Time: ${BACKUP_DATE}"
        exit 1
    fi
    log INFO "Connection to backup server OK"
}

get_all_accounts() {
    /usr/local/cpanel/bin/whmapi1 listaccts --output=json 2>/dev/null | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
for a in data.get('data',{}).get('acct',[]):
    print(a['user'])
" 2>/dev/null || ls /var/cpanel/users/ 2>/dev/null
}

backup_account() {
    local user="$1"; local outdir="$2"
    log INFO "  --> Backing up: $user"
    /usr/local/cpanel/bin/pkgacct "$user" "$outdir" >> "$LOG_FILE" 2>&1
    local ec=$?
    local f=$(ls "${outdir}/cpmove-${user}.tar.gz" 2>/dev/null || ls "${outdir}/cpmove-${user}.tar" 2>/dev/null)
    if [ $ec -eq 0 ] && [ -n "$f" ] && [ -f "$f" ]; then
        log INFO "  [OK] $user ($(du -sh "$f" | cut -f1))"; return 0
    else
        log ERROR "  [FAIL] $user"; return 1
    fi
}

# Transfer a single account file to the remote backup server
transfer_account_to_remote() {
    local file="$1"
    local rdest="${REMOTE_DIR}/${BACKUP_DATE}"
    rsync -avz \
        -e "ssh -i ${SSH_KEY} -p ${REMOTE_PORT} -o StrictHostKeyChecking=no" \
        "${file}" "${REMOTE_USER}@${REMOTE_HOST}:${rdest}/" 2>>"$LOG_FILE"
    return $?
}

transfer_to_remote() {
    local src="$1"; local rdest="${REMOTE_DIR}/${BACKUP_DATE}"
    log START "Transferring backup to ${REMOTE_HOST} ..."
    ssh -i "$SSH_KEY" -p "$REMOTE_PORT" -o StrictHostKeyChecking=no \
        "${REMOTE_USER}@${REMOTE_HOST}" "mkdir -p '${rdest}'" 2>>"$LOG_FILE" \
        || { log ERROR "Failed to create directory on backup server"; return 1; }
    rsync -avz --progress \
        -e "ssh -i ${SSH_KEY} -p ${REMOTE_PORT} -o StrictHostKeyChecking=no" \
        "${src}/" "${REMOTE_USER}@${REMOTE_HOST}:${rdest}/" 2>>"$LOG_FILE"
    if [ $? -eq 0 ]; then
        local sz=$(ssh -i "$SSH_KEY" -p "$REMOTE_PORT" -o StrictHostKeyChecking=no \
            "${REMOTE_USER}@${REMOTE_HOST}" "du -sh '${rdest}' | cut -f1" 2>/dev/null)
        log INFO "Transfer complete - Size on backup server: ${sz}"
        echo "$sz"; return 0
    else
        log ERROR "Transfer failed"; return 1
    fi
}

cleanup_old_backups() {
    log INFO "Cleaning up old backups on backup server..."
    local list=$(ssh -i "$SSH_KEY" -p "$REMOTE_PORT" -o StrictHostKeyChecking=no \
        "${REMOTE_USER}@${REMOTE_HOST}" \
        "ls -dt '${REMOTE_DIR}'/????-??-??_??-?? 2>/dev/null | sort" 2>/dev/null)
    local total=$(echo "$list" | grep -c . 2>/dev/null || echo 0)
    log INFO "Current backups: $total | Max allowed: $KEEP_BACKUPS"
    if [ "$total" -gt "$KEEP_BACKUPS" ]; then
        local to_del=$((total - KEEP_BACKUPS))
        log INFO "Deleting $to_del old backup(s)..."
        echo "$list" | head -n "$to_del" | while IFS= read -r old; do
            [ -z "$old" ] && continue
            local sz=$(ssh -i "$SSH_KEY" -p "$REMOTE_PORT" -o StrictHostKeyChecking=no \
                "${REMOTE_USER}@${REMOTE_HOST}" "du -sh '$old' | cut -f1" 2>/dev/null)
            ssh -i "$SSH_KEY" -p "$REMOTE_PORT" -o StrictHostKeyChecking=no \
                "${REMOTE_USER}@${REMOTE_HOST}" "rm -rf '$old'" 2>>"$LOG_FILE" \
                && log INFO "  [DELETED] $(basename $old) ($sz)" \
                || log WARN  "  [FAILED] Could not delete: $(basename $old)"
        done
    else
        log INFO "No old backups to delete"
    fi
}

# Remove any temp folders left from previous failed runs
cleanup_stale_temp() {
    log INFO "Checking for stale temp folders..."
    local stale_count=0
    for d in "${LOCAL_TEMP_DIR}"/????-??-??_??-??; do
        [ -d "$d" ] || continue
        rm -rf "$d"
        log INFO "  [REMOVED] Stale folder: $(basename $d)"
        ((stale_count++))
    done
    [ $stale_count -eq 0 ] && log INFO "No stale temp folders found" \
        || log INFO "Removed $stale_count stale folder(s)"
}

send_report() {
    local status="$1"; local transfer_size="$2"
    local dur=$(( $(date +%s) - START_TIME ))
    local dur_fmt=$(printf '%02d:%02d:%02d' $((dur/3600)) $((dur%3600/60)) $((dur%60)))
    log START "======================================"
    log START "  Backup Report - $status"
    log START "======================================"
    log INFO  "Duration  : $dur_fmt"
    log INFO  "Succeeded : $SUCCESS_COUNT account(s)"
    log INFO  "Failed    : $FAIL_COUNT account(s)"
    [ ${#FAILED_ACCOUNTS[@]} -gt 0 ] && log WARN "Failed accounts: ${FAILED_ACCOUNTS[*]}"
    log START "======================================"

    local summary_msg="<b>[Hostalika] Backup Report</b>
------------------------
<b>Status:</b> ${status}
<b>Date:</b> ${BACKUP_DATE}
<b>Duration:</b> ${dur_fmt}
------------------------
<b>Succeeded:</b> ${SUCCESS_COUNT} account(s)
<b>Failed:</b> ${FAIL_COUNT} account(s)
<b>Backup size:</b> ${transfer_size:-N/A}
<b>Backup server:</b> ${REMOTE_HOST}
------------------------
<b>Retention:</b> Last ${KEEP_BACKUPS} backup(s) kept"

    send_telegram "$summary_msg"

    if [ ${#FAILED_ACCOUNTS[@]} -gt 0 ]; then
        local chunk=""
        for acc in "${FAILED_ACCOUNTS[@]}"; do
            chunk+="- ${acc}\n"
            if [ ${#chunk} -gt 3800 ]; then
                send_telegram "<b>Failed accounts (continued):</b>\n${chunk}"
                chunk=""
            fi
        done
        [ -n "$chunk" ] && send_telegram "<b>Failed accounts:</b>\n${chunk}"
    fi
}

main() {
    [ -f "$LOG_FILE" ] && [ $(du -m "$LOG_FILE" | cut -f1) -gt $LOG_MAX_SIZE ] && mv "$LOG_FILE" "${LOG_FILE}.old"
    log START "======================================"
    log START "  cPanel Backup Started - $BACKUP_DATE"
    log START "======================================"
    cleanup_stale_temp

    send_telegram "<b>[Hostalika] Backup Started</b>
Date: ${BACKUP_DATE}
Source: $(hostname -I | awk '{print $1}')
Destination: ${REMOTE_HOST}"

    check_requirements
    mkdir -p "$BACKUP_SESSION_DIR"
    log INFO "Fetching cPanel accounts list..."
    mapfile -t ACCOUNTS < <(get_all_accounts)
    local total=${#ACCOUNTS[@]}
    [ "$total" -eq 0 ] && { log ERROR "No cPanel accounts found!"; send_report "FAILED" ""; exit 1; }
    log INFO "Total accounts: $total"

    # Create the remote session directory once before the loop
    ssh -i "$SSH_KEY" -p "$REMOTE_PORT" -o StrictHostKeyChecking=no \
        "${REMOTE_USER}@${REMOTE_HOST}" \
        "mkdir -p '${REMOTE_DIR}/${BACKUP_DATE}'" 2>>"$LOG_FILE" \
        || { log ERROR "Cannot create remote directory - aborting"; send_report "FAILED" ""; exit 1; }

    local cur=0
    for acc in "${ACCOUNTS[@]}"; do
        ((cur++))
        log INFO "[$cur/$total] Processing: $acc"

        if backup_account "$acc" "$BACKUP_SESSION_DIR"; then
            # Locate the backup file
            local acc_file="${BACKUP_SESSION_DIR}/cpmove-${acc}.tar.gz"
            [ ! -f "$acc_file" ] && acc_file="${BACKUP_SESSION_DIR}/cpmove-${acc}.tar"

            if [ -f "$acc_file" ]; then
                log INFO "  --> Transferring: $acc"
                if transfer_account_to_remote "$acc_file"; then
                    local fsz=$(du -sh "$acc_file" | cut -f1)
                    log INFO "  [SENT] $acc ($fsz) - removing local copy"
                    rm -f "$acc_file"
                    ((SUCCESS_COUNT++))
                else
                    log WARN "  [TRANSFER FAILED] Keeping local copy for: $acc"
                    ((FAIL_COUNT++))
                    FAILED_ACCOUNTS+=("$acc")
                fi
            fi
        else
            ((FAIL_COUNT++))
            FAILED_ACCOUNTS+=("$acc")
        fi

        # Log free disk space every 10 accounts
        if (( cur % 10 == 0 )); then
            local free=$(df -h "${LOCAL_TEMP_DIR}" | awk 'NR==2 {print $4}')
            log INFO "  [DISK] Free space on source server: ${free}"
        fi
    done

    log INFO "Backup done: $SUCCESS_COUNT succeeded / $FAIL_COUNT failed"

    # Remove session dir (should be empty at this point)
    rm -rf "$BACKUP_SESSION_DIR"
    log INFO "Local temp session folder removed"

    if [ "$SUCCESS_COUNT" -gt 0 ]; then
        local transfer_size=$(ssh -i "$SSH_KEY" -p "$REMOTE_PORT" \
            -o StrictHostKeyChecking=no \
            "${REMOTE_USER}@${REMOTE_HOST}" \
            "du -sh '${REMOTE_DIR}/${BACKUP_DATE}' | cut -f1" 2>/dev/null)
        log INFO "Total size on storage server: ${transfer_size}"
        cleanup_old_backups
        send_report "SUCCESS" "$transfer_size"
    else
        log ERROR "All backup operations failed"
        rm -rf "$BACKUP_SESSION_DIR"
        send_report "COMPLETE FAILURE" ""
        exit 1
    fi

    log INFO "All done successfully"
}

main "$@"
