# Hostalika cPanel Backup System

Automated cPanel backup system with Telegram notifications.

## Features
- Full cPanel account backups using pkgacct
- Automatic transfer to dedicated backup server via rsync over SSH
- Per-account transfer and immediate local delete (minimal disk usage)
- Configurable backup retention (default: 3 copies)
- Telegram bot for remote control and notifications
- Multi-user Telegram support
- Automatic stale temp folder cleanup

## Installation

Run this single command on your cPanel server as root:

```bash
bash <(curl -s https://raw.githubusercontent.com/Hostalika/cpanel-backup/main/install.sh)
```

The installer will:
1. Install required packages (curl, rsync, python3)
2. Download and configure all scripts
3. Generate SSH key for server-to-server authentication
4. Ask for your configuration (backup server IP, Telegram credentials, schedule)
5. Set up Telegram bot as a systemd service
6. Add the cron job

## Management Commands

```bash
hbm-status     # Show system status
hbm-update     # Update to latest version
hbm-logs       # View recent logs
hbm-restart    # Restart Telegram bot
hbm-uninstall  # Remove everything
```

## Telegram Bot Commands

```
/backup  - Start a full backup now
/status  - Show last backup report
/logs    - Show last 20 log lines
/disk    - Show disk usage on backup server
/list    - List available backups
/users   - Show authorized users
/help    - Show all commands
```

## Requirements

**cPanel Server (source):**
- cPanel / WHM installed
- AlmaLinux 8 / CloudLinux
- root access
- curl, rsync, python3

**Backup Server:**
- Any Linux distro
- rsync installed
- SSH access
- Sufficient disk space (2x total accounts size recommended)
