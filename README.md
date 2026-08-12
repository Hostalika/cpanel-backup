# Hostalika cPanel Backup System

Automated cPanel backup system with Telegram notifications and remote control.

## One-Command Installation

```bash
bash <(curl -s https://raw.githubusercontent.com/Hostalika/cpanel-backup/main/install.sh)
```

## Usage

All management is done through the `hbm` command:

```
hbm <command> [options]
```

## Commands

### System
```bash
hbm install          # Install the backup system
hbm update           # Update to latest version
hbm remove           # Uninstall everything
hbm version          # Show current and latest version
hbm status           # Show system status
hbm config           # Edit configuration interactively
hbm test             # Run full diagnostics
```

### Backup
```bash
hbm backup                    # Start a full backup now (background)
hbm backup <username>         # Backup a single cPanel account
hbm restore <username>        # Restore latest backup of an account
hbm restore <username> <date> # Restore from specific date
```

### Info
```bash
hbm logs             # Show last 50 log lines
hbm logs live        # Follow log in real-time
hbm list             # List available backups with sizes
hbm disk             # Show disk usage on both servers
```

### Maintenance
```bash
hbm clean            # Remove stale temp folders
hbm restart          # Restart Telegram bot
```

## Backup Schedule (hbm config)

When setting the backup schedule, you will be asked to choose:

```
Backup schedule:
  1) Daily
  2) Every 2 days
  3) Every 3 days
  4) Weekly (every Friday)
  5) Custom (cron expression)

At what hour? (0-23)
```

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

## Features
- Full cPanel account backups using pkgacct
- Per-account transfer with immediate local delete (minimal disk usage)
- Configurable backup retention (default: 3 copies)
- Automatic cleanup of stale temp folders
- Telegram bot for remote control and notifications
- Multi-user Telegram support
- Simple schedule selection (no cron knowledge needed)

## Requirements

**cPanel Server (source):**
- cPanel / WHM installed
- Any cPanel-supported OS (AlmaLinux, CloudLinux, Rocky Linux, Ubuntu)
- root access
- curl, rsync, python3

**Backup Server:**
- Any Linux distro
- rsync installed
- SSH access
- Sufficient disk space
