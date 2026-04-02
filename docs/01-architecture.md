# 01 — Architecture & System Layout

## Overview

`backup-wizard` is a modular bash backup system for **worlock** (Ubuntu/Debian, dual NVIDIA GPU workstation). It wraps `rsync` and `restic` behind an interactive CLI wizard, with MOTD integration that surfaces backup health at every login.

## Physical Storage Layout

```
/mnt/raid0          ← RAID-0 (2× Seagate IronWolf 12TB, md0)
                       PDF archive source  ~4.7T used / 12T total
                       ⚠ sdg ran hot historically; smartd alerts at 43°C

/mnt/pdf_backup     ← sda (WD 4TB, ext4, -i 4096 inode density)
                       PDF archive backup destination

/mnt/hitachi_2tb    ← sdb1 (Hitachi 2TB)
                       ├── AI-ML_Papers_backup/   (rsync destination)
                       └── restic_repos/          (encrypted compressed snapshots)
                             └── ai-ml-papers/

/mnt/wd_storage     ← WD 4TB (WD4005FZBX)  standalone misc storage
/mnt/sdc1           ← sdc1  5.5T  — 1.46M PDFs in files/files/, 918G free

NVMe:
  /mnt/nvme0        ← camera recordings (Hikvision DS-2CD2742FWD-IZS MKV)
  / (root)          ← NVMe system drive
```

## Backup Matrix

| Source | Tool | Destination | Notes |
|--------|------|-------------|-------|
| `/home/jeb/Documents/AI-ML_Papers` | rsync | `/mnt/hitachi_2tb/AI-ML_Papers_backup` | 16GB, 5937 files, fast incremental |
| `/home/jeb/Documents/AI-ML_Papers` | restic | `/mnt/hitachi_2tb/restic_repos/ai-ml-papers` | compressed, versioned snapshots |
| `/mnt/raid0` (PDF archive) | rsync | `/mnt/pdf_backup` | 4.7T, delegated to `pdf-backup.sh` |
| Custom (interactive) | rsync or restic | User-defined | Wizard prompts source/dest |

## Component Map

```
backup-wizard/
├── backup-wizard.sh        ← entry point; interactive menu + CLI flags
├── lib/
│   ├── common.sh           ← colors, logging, config helpers, mount checks
│   ├── rsync_ops.sh        ← rsync runner + preset jobs (AI-ML, PDF, custom)
│   └── restic_ops.sh       ← restic init/backup/restore/prune + presets
├── motd/
│   └── 94-backup-status    ← MOTD fragment (login summary)
├── install.sh              ← system installer (symlink + MOTD + log dir)
└── docs/
    ├── 01-architecture.md  ← this file
    ├── 02-rsync-backups.md
    ├── 03-restic-backups.md
    └── 04-wizard-reference.md
```

## Dependencies

| Tool | Version | Purpose |
|------|---------|---------|
| `bash` | 4+ | All scripts |
| `rsync` | any modern | File sync / backup |
| `restic` | 0.14+ | `--compression` flag required |
| `mountpoint` | util-linux | Mount guard checks |
| `df`, `du` | coreutils | Disk space checks |

Check versions:
```bash
rsync --version | head -1
restic version
bash --version | head -1
```

## Runtime State

| Path | Purpose |
|------|---------|
| `~/.config/backup-wizard/config` | Persisted overrides (source/dest paths) |
| `~/.config/backup-wizard/restic_password` | Restic repo password (chmod 600) |
| `/var/log/backup-wizard/last_run.log` | Status entries written after each job |

## Network / Remote Considerations

Currently all backups are local disk-to-disk. The restic architecture supports remote backends (S3, B2, SFTP, rclone) by changing the `--repo` argument. The wizard's custom backup prompt accepts any valid restic repository URI.

## MOTD Integration

The script at `/etc/update-motd.d/94-backup-status` runs at every SSH/local login via `run-parts`. It reads `/var/log/backup-wizard/last_run.log` (written by the backup jobs) and renders a compact status table. It does **not** run rsync or restic at login — login is instant.

Placement at `94` slots it after `92-unattended-upgrades` and before `95-security-updates`, keeping it in the informational cluster without disrupting existing MOTD ordering.
