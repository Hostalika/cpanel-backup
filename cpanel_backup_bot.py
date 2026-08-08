#!/usr/bin/env python3
# =============================================================================
#  Telegram Bot Listener - cPanel Backup Controller
#  Version: 2.0 | Hostalika LLC | Multi-user support
# =============================================================================
#
#  SETTINGS - Edit these values before running
# =============================================================================

BOT_TOKEN     = "YOUR_BOT_TOKEN_HERE"
BACKUP_SCRIPT = "/usr/local/bin/cpanel_backup.sh"
LOG_FILE      = "/var/log/cpanel_backup.log"
REMOTE_USER   = "backupuser"
REMOTE_HOST   = "YOUR_BACKUP_SERVER_IP"
SSH_KEY       = "/root/.ssh/backup_key"
POLL_INTERVAL = 3

# Add/remove Chat IDs here
AUTHORIZED_USERS = [
    "YOUR_CHAT_ID_HERE",
    # "111222333",
]

# =============================================================================
#  DO NOT EDIT BELOW THIS LINE
# =============================================================================

import urllib.request
import urllib.parse
import json
import subprocess
import time
import logging

logging.basicConfig(
    filename="/var/log/cpanel_backup_bot.log",
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)

def api_request(method, params=None):
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/{method}"
    data = urllib.parse.urlencode(params).encode() if params else None
    req = urllib.request.Request(url, data=data)
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.loads(r.read().decode())
    except Exception as e:
        logging.error(f"API request failed: {e}")
        return None

def send_message(chat_id, text):
    api_request("sendMessage", {
        "chat_id": chat_id,
        "text": text,
        "parse_mode": "HTML"
    })

def broadcast(text):
    for uid in AUTHORIZED_USERS:
        send_message(uid, text)

def get_updates(offset=None):
    params = {"timeout": 2, "allowed_updates": ["message"]}
    if offset:
        params["offset"] = offset
    return api_request("getUpdates", params)

def is_authorized(message):
    return str(message.get("chat", {}).get("id", "")) in AUTHORIZED_USERS

backup_running = False

def handle_backup(chat_id):
    global backup_running
    if backup_running:
        send_message(chat_id, "<b>[Hostalika]</b> A backup is already running. Please wait.")
        return
    backup_running = True
    broadcast("<b>[Hostalika]</b> Manual backup started.
A report will be sent when finished.")
    logging.info(f"Manual backup triggered by chat_id: {chat_id}")
    try:
        subprocess.Popen(
            ["bash", BACKUP_SCRIPT],
            stdout=open(LOG_FILE, "a"),
            stderr=open(LOG_FILE, "a")
        )
    except Exception as e:
        broadcast(f"<b>[Hostalika]</b> Failed to start backup:\n<code>{e}</code>")
        logging.error(f"Failed to start backup: {e}")
    finally:
        time.sleep(5)
        backup_running = False

def handle_status(chat_id):
    try:
        with open(LOG_FILE, "r") as f:
            lines = f.readlines()
        report_lines = [l.strip() for l in lines if any(
            k in l for k in ["Backup Report", "Status", "Succeeded", "Failed", "Duration", "Backup size"]
        )]
        last_report = report_lines[-10:] if report_lines else ["No report found yet."]
        send_message(chat_id, "<b>[Hostalika] Last Backup Status</b>\n<code>" + "\n".join(last_report) + "</code>")
    except Exception as e:
        send_message(chat_id, f"<b>[Hostalika]</b> Could not read status:\n<code>{e}</code>")

def handle_logs(chat_id):
    try:
        with open(LOG_FILE, "r") as f:
            lines = f.readlines()
        last_lines = [l.strip() for l in lines[-20:]]
        send_message(chat_id, "<b>[Hostalika] Last 20 log lines</b>\n<code>" + "\n".join(last_lines) + "</code>")
    except Exception as e:
        send_message(chat_id, f"<b>[Hostalika]</b> Could not read log:\n<code>{e}</code>")

def handle_disk(chat_id):
    try:
        result = subprocess.run(
            ["ssh", "-i", SSH_KEY, "-o", "StrictHostKeyChecking=no",
             f"{REMOTE_USER}@{REMOTE_HOST}", "df -h /backup"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
        )
        send_message(chat_id, f"<b>[Hostalika] Backup Server Disk Usage</b>\n<code>{result.stdout.decode('utf-8').strip()}</code>")
    except Exception as e:
        send_message(chat_id, f"<b>[Hostalika]</b> Could not get disk info:\n<code>{e}</code>")

def handle_list(chat_id):
    try:
        result = subprocess.run(
            ["ssh", "-i", SSH_KEY, "-o", "StrictHostKeyChecking=no",
             f"{REMOTE_USER}@{REMOTE_HOST}",
             "ls -lht /backup/cpanel/ | grep -v total"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
        )
        output = result.stdout.decode("utf-8").strip() or "No backups found."
        send_message(chat_id, f"<b>[Hostalika] Available Backups on {REMOTE_HOST}</b>\n<code>{output}</code>")
    except Exception as e:
        send_message(chat_id, f"<b>[Hostalika]</b> Could not list backups:\n<code>{e}</code>")

def handle_users(chat_id):
    msg = "<b>[Hostalika] Authorized Users</b>\n"
    for i, uid in enumerate(AUTHORIZED_USERS, 1):
        msg += f"{i}. <code>{uid}</code>\n"
    send_message(chat_id, msg)

def handle_help(chat_id):
    send_message(chat_id, """<b>[Hostalika] Backup Bot - Available Commands</b>

/backup - Start a full cPanel backup now
/status - Show last backup result
/logs   - Show last 20 lines of backup log
/disk   - Show disk usage on backup server
/list   - List available backups on backup server
/users  - Show authorized users list
/help   - Show this message""")

def main():
    logging.info("Telegram backup bot started - multi-user mode")
    broadcast("<b>[Hostalika]</b> Backup bot is online.\nType /help to see available commands.")
    offset = None
    while True:
        try:
            result = get_updates(offset)
            if result and result.get("ok"):
                for update in result.get("result", []):
                    offset = update["update_id"] + 1
                    message = update.get("message", {})
                    chat_id = str(message.get("chat", {}).get("id", ""))
                    if not is_authorized(message):
                        logging.warning(f"Unauthorized access from chat_id: {chat_id}")
                        continue
                    text = message.get("text", "").strip().lower()
                    cmd  = text.split("@")[0]
                    logging.info(f"Command: {cmd} from {chat_id}")
                    if cmd == "/backup":              handle_backup(chat_id)
                    elif cmd == "/status":            handle_status(chat_id)
                    elif cmd == "/logs":              handle_logs(chat_id)
                    elif cmd == "/disk":              handle_disk(chat_id)
                    elif cmd == "/list":              handle_list(chat_id)
                    elif cmd == "/users":             handle_users(chat_id)
                    elif cmd in ["/help", "/start"]:  handle_help(chat_id)
                    else: send_message(chat_id, "Unknown command. Type /help to see available commands.")
        except Exception as e:
            logging.error(f"Main loop error: {e}")
        time.sleep(POLL_INTERVAL)

if __name__ == "__main__":
    main()
