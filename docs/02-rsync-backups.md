# 02 — Rsync Backups

## Why rsync

`rsync` is the standard for local disk-to-disk backup on Linux:

- **Incremental** — only transfers files that have changed (mtime + size by default; `--checksum` for byte-level)
- **Resume-safe** — `--partial --append-verify` keeps interrupted transfers intact and verifies on resume
- **Transparent** — destination is a plain directory tree, readable without any special tool
- **Fast** — on local SATA/NVMe, limited only by disk throughput

## Standard Flags Used

Every rsync job in `backup-wizard` uses this core set:

```bash
rsync \
  --archive           # -rlptgoD: recursive + preserve everything
  --partial           # keep partial files on interrupt
  --append-verify     # resume: append remaining bytes + full checksum
  --human-readable    # human-readable sizes in output
  --progress          # per-file transfer progress
  --stats             # summary at completion
  --exclude="*.tmp"   # skip temp files
  --exclude=".Trash*"
  --exclude=".DS_Store"
  SRC/  DEST/         # trailing slash on SRC = "contents of SRC"
```

The trailing `/` on the source is intentional: `rsync SRC/ DEST/` copies the *contents* of SRC into DEST. Without it, rsync would create `DEST/SRC/`.

## Preset: AI-ML Papers

**Source:** `/home/jeb/Documents/AI-ML_Papers`
**Destination:** `/mnt/hitachi_2tb/AI-ML_Papers_backup`

This is a 16GB collection of ~5,937 PDFs organized into topic subdirectories (agents, reasoning, transformers, BCI, nanobots, etc.). The backup runs in under a minute on a warm incremental — typically < 1 second if nothing changed.

```bash
# Via wizard
backup-wizard --aiml

# Direct rsync equivalent
rsync -av --partial --append-verify --progress --stats \
  /home/jeb/Documents/AI-ML_Papers/ \
  /mnt/hitachi_2tb/AI-ML_Papers_backup/
```

Exit code semantics:
- `0` — success
- `24` — some files vanished during transfer (normal for live directories, treated as warning)
- anything else — failure

## Preset: PDF Archive

**Source:** `/mnt/raid0` (RAID-0, 2× Seagate IronWolf 12TB, ~4.7T PDFs)
**Destination:** `/mnt/pdf_backup` (WD 4TB, ext4)

This delegates to the existing `pdf-backup.sh` toolkit at:
```
~/Documents/claude_creations/2026-03-27_220258_pdf-backup/pdf-backup.sh
```

That script adds:
- PID-file guard (only one instance)
- `--max-size` limit
- Suspend/resume via `stop.sh` / `status.sh`
- Dedicated logging

If `pdf-backup.sh` is not found, the wizard falls back to a direct rsync.

**Requires root** (source RAID mount permissions). The wizard auto-re-invokes with `sudo` if not already root.

```bash
sudo backup-wizard --pdf
```

## Custom Rsync

The wizard's interactive custom backup:

1. Prompts for source and destination
2. Offers `--delete` (mirror mode — removes files in dest absent from source)
3. Offers a dry-run first pass
4. Confirms before the real run

`--delete` is off by default because it's destructive. Use it only for true mirrors where you want the destination to exactly track the source.

## Resume Behavior

If a transfer is interrupted (power, Ctrl-C, network drop):

1. Partial files remain on the destination (not deleted)
2. Re-running the same command resumes from where it left off via `--append-verify`
3. `--append-verify` checksums the full file after appending — guarantees integrity

This means large transfers (e.g., the 4.7T PDF archive) can be safely interrupted and resumed without starting over.

## Exit Codes Reference

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Syntax or usage error |
| 11 | Error in file I/O |
| 23 | Partial transfer due to error |
| 24 | Partial transfer — some files vanished (warning, not failure) |
| 30 | Timeout |

## Scheduling (Optional)

To run the AI-ML backup nightly at 2am, add to root's crontab:

```bash
sudo crontab -e
# Add:
0 2 * * * /usr/local/bin/backup-wizard --aiml >> /var/log/backup-wizard/cron.log 2>&1
```
