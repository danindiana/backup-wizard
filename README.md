# backup-wizard

Interactive CLI backup wizard for **worlock** — wraps `rsync` and `restic` with a menu-driven interface, MOTD health integration, and non-interactive flags for scripting and cron.

## Features

- **Rsync backups** — resume-safe incremental sync to local drives
- **Restic backups** — encrypted, deduplicated, zstd-compressed snapshots with full version history
- **AI-ML Papers preset** — one command to back up `/home/jeb/Documents/AI-ML_Papers` (16GB, 5937 PDFs)
- **PDF archive preset** — delegates to `pdf-backup.sh` for the 4.7T RAID-0 → WD 4TB transfer
- **Custom jobs** — interactive prompts for arbitrary source/dest pairs
- **MOTD integration** — backup status and mount health shown at every login
- **Status log** — `/var/log/backup-wizard/last_run.log` updated after every job

## Quick Start

```bash
# Install system-wide
cd ~/Documents/claude_creations/2026-04-02_backup-wizard
sudo ./install.sh

# Interactive wizard
backup-wizard

# Quick rsync of AI-ML papers
backup-wizard --aiml

# Compressed restic snapshot
backup-wizard --aiml-restic

# Status report
backup-wizard --status
```

## Documentation

| File | Topic |
|------|-------|
| [docs/01-architecture.md](docs/01-architecture.md) | System layout, drive map, component overview |
| [docs/02-rsync-backups.md](docs/02-rsync-backups.md) | Rsync flags, presets, resume behavior, scheduling |
| [docs/03-restic-backups.md](docs/03-restic-backups.md) | Restic compression, snapshots, restore, prune |
| [docs/04-wizard-reference.md](docs/04-wizard-reference.md) | Full CLI reference, menus, MOTD, config, cron |

## Requirements

- bash 4+, rsync, restic 0.14+ (for `--compression`)
- All three are present on worlock

## Backup Matrix

| Source | Tool | Destination |
|--------|------|-------------|
| `~/Documents/AI-ML_Papers` | rsync | `/mnt/hitachi_2tb/AI-ML_Papers_backup` |
| `~/Documents/AI-ML_Papers` | restic | `/mnt/hitachi_2tb/restic_repos/ai-ml-papers` |
| `/mnt/raid0` (PDF archive) | rsync | `/mnt/pdf_backup` |
| Custom (interactive) | rsync or restic | User-defined |

## System

Tested on: Ubuntu 22.04 LTS · Linux 6.8.12 · worlock (dual NVIDIA, SATA RAID-0)
