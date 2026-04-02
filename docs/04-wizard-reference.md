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

  (none)              Launch interactive menu
  --help              Show usage summary
  --status            Print last runs + disk usage + mount health, then exit

  Rsync:
  --aiml              Rsync AI-ML Papers → /mnt/hitachi_2tb/AI-ML_Papers_backup
  --cs                Rsync computer science → /mnt/hitachi_2tb/computer_science_backup
  --computers         Rsync computers → /mnt/hitachi_2tb/computers_backup
  --all-archives      Rsync all three paper archives in one shot
  --pdf               PDF archive rsync via pdf-backup.sh (requires sudo)

  Restic (encrypted, compressed snapshots):
  --aiml-restic       Restic backup of AI-ML Papers (max compression)
  --cs-restic         Restic backup of computer science (max compression)
  --computers-restic  Restic backup of computers (max compression)
  --all-restic        Restic all three paper archives in one shot
```

### Examples

```bash
# Full incremental backup of all three paper archives — both rsync + restic
backup-wizard --all-archives && backup-wizard --all-restic

# Individual targets
backup-wizard --aiml              # rsync AI-ML papers only
backup-wizard --cs-restic         # restic snapshot of computer science only

# PDF archive (4.7T, long-running — run in tmux/screen)
sudo backup-wizard --pdf

# Status report
backup-wizard --status
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
  1) ALL archives  (AI-ML Papers + computer science + computers)
  2) AI-ML Papers      →  /mnt/hitachi_2tb/AI-ML_Papers_backup
  3) computer science  →  /mnt/hitachi_2tb/computer_science_backup
  4) computers         →  /mnt/hitachi_2tb/computers_backup
  5) PDF Archive       →  /mnt/pdf_backup  (via pdf-backup.sh)
  6) Custom source/destination
  b) Back
```

### Restic Submenu (2)

```
  1) ALL archives  (AI-ML Papers + computer science + computers)
  2) AI-ML Papers      →  restic repo (max compression)
  3) computer science  →  restic repo (max compression)
  4) computers         →  restic repo (max compression)
  5) Custom source →  restic repo
  6) List snapshots
  7) Restore from snapshot
  8) Prune old snapshots
  9) Initialize new repository
  b) Back
```

All backup options offer a dry-run before committing.

### Configuration Submenu (4)

Overrides are saved to `~/.config/backup-wizard/config` and persist across sessions.

```
  1) Set AI-ML source path
  2) Set AI-ML rsync destination
  3) Set restic repo path for AI-ML
  4) Change restic password
  b) Back
```

## MOTD Output

After install, every SSH/console login shows a four-section block:

```
━━━━  Backup System (backup-wizard)  ━━━━━━━━━━━━━━━━━━━━━
  Rsync mirrors  (plain browsable copies)
    ✓  computers               2026-04-02 12:16:35
    ✓  computer-science        2026-04-02 12:16:18
    ✓  AI-ML-Papers            2026-04-02 11:40:29

  Restic snapshots  (encrypted · zstd · versioned)
    ✓  computers               2026-04-02 13:12:40
    ✓  computer-science        2026-04-02 13:10:55
    ✓  AI-ML-Papers            2026-04-02 13:09:38

  Restic repos  (/mnt/hitachi_2tb/restic_repos)
    →  ai-ml-papers            1 snapshot(s)  latest: 2026-04-02 13:03:23
    →  computers               1 snapshot(s)  latest: 2026-04-02 13:10:59
    →  computer-science        1 snapshot(s)  latest: 2026-04-02 13:09:42

  Backup destinations:
    ✓  /mnt/hitachi_2tb  Hitachi 2TB  rsync mirrors + restic repos  — free: 1006G  (43% used)
    ✓  /mnt/pdf_backup   SDA ext4     PDF archive rsync backup       — free: 575G   (83% used)
    ✓  /mnt/raid0        RAID0        PDF archive source (~4.7T)     — free: 1.4T   (88% used)

  Quick commands:
    backup-wizard                  interactive menu
    backup-wizard --all-archives   rsync all 3 paper archives
    backup-wizard --all-restic     restic snapshot all 3 archives
    backup-wizard --status         full status report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**What each section does:**
- **Rsync mirrors** — last successful rsync timestamp per archive (from status log)
- **Restic snapshots** — last successful restic timestamp per archive (from status log)
- **Restic repos** — live query: snapshot count + latest timestamp per repo (fast, ~1s per repo)
- **Backup destinations** — live `df` check: mount health + free space

The MOTD does **not** run rsync or restic at login. Init/prune housekeeping entries are filtered out — only backup operations are shown.

To test the MOTD fragment independently:

```bash
sudo /etc/update-motd.d/94-backup-status
# or run the full MOTD suite:
sudo run-parts /etc/update-motd.d/
```

**Note:** `$HOME` resolves to `/root` when run as sudo, so the restic password path is
hardcoded to `/home/jeb/.config/backup-wizard/restic_password` in the MOTD script.

## Restic Password

Generated 2026-04-02:
- Password: stored in `RESTIC_PASSWORD.txt` (repo root) and `~/.config/backup-wizard/restic_password`
- All three repos share the same password
- Without this password, no restic repo can be decrypted or restored

## Configuration File

`~/.config/backup-wizard/config` — plain key=value, sourced by bash:

```bash
AIML_SRC=/home/jeb/Documents/AI-ML_Papers
AIML_DST=/mnt/hitachi_2tb/AI-ML_Papers_backup
CS_SRC=/home/jeb/Documents/computer science
CS_DST=/mnt/hitachi_2tb/computer_science_backup
COMPUTERS_SRC=/home/jeb/Documents/computers
COMPUTERS_DST=/mnt/hitachi_2tb/computers_backup
RESTIC_REPO_AIML=/mnt/hitachi_2tb/restic_repos/ai-ml-papers
RESTIC_REPO_CS=/mnt/hitachi_2tb/restic_repos/computer-science
RESTIC_REPO_COMPUTERS=/mnt/hitachi_2tb/restic_repos/computers
```

Edit directly or use Configuration menu (option 4).

## Status Log Format

`/var/log/backup-wizard/last_run.log` — one line per named job tag, updated in-place on each run:

```
2026-04-02 11:40:29  [RSYNC:AI-ML-Papers]       OK — .../AI-ML_Papers → .../AI-ML_Papers_backup
2026-04-02 12:16:18  [RSYNC:computer-science]   OK — .../computer science → .../computer_science_backup
2026-04-02 12:16:35  [RSYNC:computers]          OK — .../computers → .../computers_backup
2026-04-02 13:09:38  [RESTIC:AI-ML-Papers]      OK — .../AI-ML_Papers → .../restic_repos/ai-ml-papers (compression=max)
2026-04-02 13:10:55  [RESTIC:computer-science]  OK — .../computer science → .../restic_repos/computer-science (compression=max)
2026-04-02 13:12:40  [RESTIC:computers]         OK — .../computers → .../restic_repos/computers (compression=max)
```

Tags starting with `RSYNC:` are rsync operations; `RESTIC:` are restic operations.
`init` and `prune` housekeeping tags are written to the log but filtered out of the MOTD display.

## Cron Integration

```bash
sudo crontab -e

# Nightly rsync of all paper archives at 2:00am
0 2 * * * /usr/local/bin/backup-wizard --all-archives >> /var/log/backup-wizard/cron.log 2>&1

# Weekly restic snapshots Sundays at 3:00am
0 3 * * 0 /usr/local/bin/backup-wizard --all-restic >> /var/log/backup-wizard/cron.log 2>&1

# Full PDF archive backup Saturdays at 1:00am (long-running)
0 1 * * 6 /usr/local/bin/backup-wizard --pdf >> /var/log/backup-wizard/cron.log 2>&1
```

## Extending the Wizard

To add a new preset job:

1. Add source/dest constants to `lib/common.sh`
2. Add a function in `lib/rsync_ops.sh` or `lib/restic_ops.sh`; call `write_status_entry "TAG" "message"` at completion
3. Add a menu entry in `backup-wizard.sh` (rsync or restic submenu)
4. Add a `--flag` case in `handle_cli_flags()`
5. The MOTD will pick it up automatically via the `RSYNC:`/`RESTIC:` prefix split in the status log

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `not mounted` in MOTD | Drive not spinning / cable | Check `lsblk`, reseat SATA cable, `sudo mount /mnt/...` |
| restic repos missing from MOTD | Password file not at `/home/jeb/.config/...` | Verify `~/.config/backup-wizard/restic_password` exists |
| `restic: wrong password` | Password file mismatch | `backup-wizard` → Config → Change restic password |
| rsync exits 23 | Permission denied on some source files | Run with sudo or fix source permissions |
| `pdf-backup.sh not found` | Path in `common.sh` outdated | Edit `PDF_BACKUP_SCRIPT` in `lib/common.sh` |
| MOTD not showing | Fragment not executable | `sudo chmod +x /etc/update-motd.d/94-backup-status` |
| New archive not in MOTD | Tag prefix wrong | Ensure function calls `write_status_entry "RSYNC:name"` or `"RESTIC:name"` |
