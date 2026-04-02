# 04 — Wizard CLI Reference

## Installation

```bash
cd ~/Documents/claude_creations/2026-04-02_backup-wizard
sudo ./install.sh
```

This:
1. Symlinks `backup-wizard.sh` → `/usr/local/bin/backup-wizard`
2. Installs `motd/94-backup-status` → `/etc/update-motd.d/94-backup-status`
3. Creates `/var/log/backup-wizard/` (world-writable sticky bit so jeb can write without sudo)

After install, `backup-wizard` is available system-wide.

## Non-Interactive Flags

All flags exit after completing their task — suitable for cron, scripts, and pipelines.

```
backup-wizard [FLAG]

  (none)           Launch interactive menu
  --help           Show usage summary
  --status         Print last runs + disk usage + mount health, then exit
  --aiml           Rsync AI-ML Papers → /mnt/hitachi_2tb/AI-ML_Papers_backup
  --aiml-restic    Restic (max compression) backup of AI-ML Papers
  --pdf            PDF archive rsync via pdf-backup.sh (requires sudo)
```

### Examples

```bash
# Quick status check
backup-wizard --status

# Rsync AI-ML papers (fast incremental, < 60s typically)
backup-wizard --aiml

# Compressed snapshot (first run initializes repo and prompts for password)
backup-wizard --aiml-restic

# Full PDF archive (4.7T, long-running — run in tmux/screen)
sudo backup-wizard --pdf
```

## Interactive Menu

Launch with no arguments:

```
backup-wizard
```

### Main Menu

```
  1) Rsync backups
  2) Restic backups  (compressed, deduplicated snapshots)
  3) Backup status   (last runs, disk usage)
  4) Configuration
  q) Quit
```

### Rsync Submenu (1)

```
  1) AI-ML Papers  →  /mnt/hitachi_2tb/AI-ML_Papers_backup
  2) PDF Archive   →  /mnt/pdf_backup  (via pdf-backup.sh)
  3) Custom source/destination
  b) Back
```

All options offer a dry-run before committing.

### Restic Submenu (2)

```
  1) AI-ML Papers  →  restic repo (max compression)
  2) Custom source →  restic repo
  3) List snapshots
  4) Restore from snapshot
  5) Prune old snapshots
  6) Initialize new repository
  b) Back
```

### Configuration Submenu (4)

Overrides are saved to `~/.config/backup-wizard/config` and persist across sessions.

```
  1) Set AI-ML source path          (default: /home/jeb/Documents/AI-ML_Papers)
  2) Set AI-ML rsync destination    (default: /mnt/hitachi_2tb/AI-ML_Papers_backup)
  3) Set restic repo path for AI-ML (default: /mnt/hitachi_2tb/restic_repos/ai-ml-papers)
  4) Change restic password
  b) Back
```

## MOTD Output

After install, every SSH/console login shows:

```
━━━━  Backup System  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Last backup runs:
  ✓  [RSYNC:AI-ML-Papers]    2026-04-02 14:30:00   OK — /home/jeb/...
  ✓  [RESTIC:AI-ML-Papers]   2026-04-02 14:32:00   OK — ...

Backup destinations:
  ✓  /mnt/hitachi_2tb  Hitachi 2TB   — free: 1.0T  used: 42%
  ✗  /mnt/pdf_backup   SDA ext4      — NOT MOUNTED
  ✓  /mnt/raid0        RAID0         — free: 7.3T  used: 39%

  backup-wizard              interactive menu
  backup-wizard --aiml       rsync AI-ML papers now
  backup-wizard --aiml-restic  compressed snapshot now
  backup-wizard --status     status report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

The MOTD reads `/var/log/backup-wizard/last_run.log` only — no rsync or restic runs at login.

To test the MOTD fragment independently:

```bash
sudo run-parts /etc/update-motd.d/
# or just the backup fragment:
sudo /etc/update-motd.d/94-backup-status
```

## Configuration File

`~/.config/backup-wizard/config` — plain key=value, sourced by bash:

```bash
AIML_SRC=/home/jeb/Documents/AI-ML_Papers
AIML_DST=/mnt/hitachi_2tb/AI-ML_Papers_backup
RESTIC_REPO_AIML=/mnt/hitachi_2tb/restic_repos/ai-ml-papers
```

Edit directly or use Configuration menu (option 4).

## Status Log Format

`/var/log/backup-wizard/last_run.log` — one line per named job, updated in-place:

```
2026-04-02 14:30:00  [RSYNC:AI-ML-Papers]  OK — /home/jeb/Documents/AI-ML_Papers → /mnt/hitachi_2tb/AI-ML_Papers_backup
2026-04-02 14:32:00  [RESTIC:AI-ML-Papers]  OK — /home/jeb/Documents/AI-ML_Papers → /mnt/hitachi_2tb/restic_repos/ai-ml-papers (compression=max)
```

## Cron Integration

```bash
# Edit root crontab
sudo crontab -e

# Nightly AI-ML rsync at 2:00am
0 2 * * * /usr/local/bin/backup-wizard --aiml >> /var/log/backup-wizard/cron.log 2>&1

# Weekly restic snapshot Sundays at 3:00am
0 3 * * 0 /usr/local/bin/backup-wizard --aiml-restic >> /var/log/backup-wizard/cron.log 2>&1
```

## Extending the Wizard

To add a new preset job:

1. Add a function in `lib/rsync_ops.sh` or `lib/restic_ops.sh`
2. Call `write_status_entry "TAG" "message"` at completion
3. Add a menu entry in `backup-wizard.sh` (rsync or restic submenu)
4. Add a `--flag` case in `handle_cli_flags()` if non-interactive access is needed
5. Update `motd/94-backup-status` if the job warrants MOTD visibility

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `not mounted` in MOTD | Drive not spinning / cable | Check `lsblk`, reseat SATA cable, `sudo mount /mnt/...` |
| `restic: wrong password` | Password file mismatch | `backup-wizard` → Config → Change restic password |
| rsync exits 23 | Permission denied on some source files | Run with sudo or fix source permissions |
| `pdf-backup.sh not found` | Path in `common.sh` outdated | Edit `PDF_BACKUP_SCRIPT` in `lib/common.sh` |
| MOTD not showing | Fragment not executable | `sudo chmod +x /etc/update-motd.d/94-backup-status` |
