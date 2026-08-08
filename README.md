# Hostalika cPanel Backup System

Automated cPanel backup system with Telegram notifications and remote control.

## Features
- Full cPanel account backups using pkgacct
- Per-account transfer with immediate local delete (minimal disk usage)
- Configurable backup retention (default: 3 copies)
- Automatic cleanup of stale temp folders
- Telegram bot for remote control and notifications
- Multi-user Telegram support
- Full suite of management commands

## One-Command Installation

```bash
bash <(curl -s https://raw.githubusercontent.com/Hostalika/cpanel-backup/main/install.sh)
```

The installer will:
1. Install required packages (curl, rsync, python3)
2. Download and configure all scripts
3. Generate SSH key for server-to-server authentication
4. Prompt for configuration (backup server IP, Telegram credentials, schedule)
5. Set up Telegram bot as a systemd service
6. Add the cron job

## Management Commands

| Command | Description |
|---------|-------------|
| `hbm-status` | Show system status |
| `hbm-config` | Edit configuration interactively |
| `hbm-test` | Run full system diagnostics |
| `hbm-update` | Update to latest version |
| `hbm-logs` | View recent log entries |
| `hbm-disk` | Show disk usage on both servers |
| `hbm-list` | List available backups on backup server |
| `hbm-clean` | Remove stale temp folders |
| `hbm-backup-now` | Start a full backup immediately |
| `hbm-backup-account <user>` | Backup a single cPanel account |
| `hbm-restore <user> [date]` | Copy backup file for restore via WHM |
| `hbm-restart` | Restart Telegram bot service |
| `hbm-uninstall` | Remove everything |

## Telegram Bot Commands

| Command | Description |
|---------|-------------|
| `/backup` | Start a full backup now |
| `/status` | Show last backup report |
| `/logs` | Show last 20 log lines |
| `/disk` | Show disk usage on backup server |
| `/list` | List available backups |
| `/users` | Show authorized users |
| `/help` | Show all commands |

## Requirements

**cPanel Server (source):**
- cPanel / WHM installed
- Any cPanel-supported OS:
  - AlmaLinux 8 / 9
  - CloudLinux 8 / 9
  - Rocky Linux 8 / 9
  - Ubuntu 20.04 / 22.04
- root access
- curl, rsync, python3

**Backup Server:**
- Any Linux distro
- rsync installed
- SSH access
- Sufficient disk space (2x total accounts size recommended)

## Changelog

### v2.2.0
- Added hbm-test: full diagnostics command
- Added hbm-clean: remove stale temp folders
- Added hbm-disk: disk usage on both servers
- Added hbm-list: list available backups
- Added hbm-backup-now: trigger backup in background
- Added hbm-backup-account: backup single account
- Added hbm-restore: copy backup file for WHM restore
- Added hbm-config: interactive configuration editor
- Fixed PATH refresh issue after installation
- Improved uninstall to remove all commands

### v2.1.0
- Per-account transfer with immediate local delete
- Automatic stale temp folder cleanup
- Multi-user Telegram support
- Split long Telegram messages automatically

### v2.0.0
- Initial release
