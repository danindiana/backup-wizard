# 03 — Restic Backups (Compressed Snapshots)

## Why restic in Addition to rsync

| Feature | rsync | restic |
|---------|-------|--------|
| Destination is browsable without tools | ✓ | ✗ (content-addressed) |
| Deduplication across snapshots | ✗ | ✓ |
| Encryption at rest | ✗ | ✓ (AES-256-CTR + Poly1305) |
| Compression | ✗ | ✓ (zstd, up to `--compression max`) |
| Point-in-time snapshots / history | ✗ (only latest) | ✓ |
| Incremental by default | ✓ | ✓ (pack-based dedup) |

Use **rsync** when you want a plain browsable mirror. Use **restic** when you want versioned, encrypted, deduplicated, compressed snapshots with restore-to-any-point capability.

## Restic on worlock

- **Binary:** `/usr/local/bin/restic`
- **Version:** 0.14.0 (supports `--compression`)
- **Repo base:** `/mnt/hitachi_2tb/restic_repos/`
- **Password file:** `~/.config/backup-wizard/restic_password` (chmod 600)

## Repository Initialization

A restic repository must be initialized once before first use:

```bash
restic init --repo /mnt/hitachi_2tb/restic_repos/ai-ml-papers
```

The wizard handles this automatically on first backup — if the repo directory doesn't exist, `restic_init_repo()` is called before proceeding.

Each repo is independently encrypted. The password is stored in `~/.config/backup-wizard/restic_password` and passed via `RESTIC_PASSWORD_FILE`. On first run the wizard prompts you to set and confirm the password.

**Do not lose this password** — restic repos cannot be decrypted without it.

## Compression

Restic 0.14+ uses zstd compression. Three levels:

| Flag | Meaning | Use When |
|------|---------|---------|
| `--compression off` | No compression | Source is already compressed (JPEG, MP4, zip) |
| `--compression auto` | Balanced (default) | Mixed content |
| `--compression max` | Maximum zstd | Text, PDFs, code — typical 30-60% size reduction |

AI-ML papers (PDFs) compress well. `--compression max` is the default for all wizard presets.

## Running a Backup

```bash
# Via wizard
backup-wizard --aiml-restic

# Direct restic equivalent
RESTIC_PASSWORD_FILE=~/.config/backup-wizard/restic_password \
restic backup \
  --repo /mnt/hitachi_2tb/restic_repos/ai-ml-papers \
  --compression max \
  --tag AI-ML-Papers \
  --exclude-caches \
  --exclude="*.tmp" \
  /home/jeb/Documents/AI-ML_Papers
```

## Listing Snapshots

```bash
RESTIC_PASSWORD_FILE=~/.config/backup-wizard/restic_password \
restic -r /mnt/hitachi_2tb/restic_repos/ai-ml-papers snapshots
```

Output example:
```
ID        Time                 Host     Tags            Paths
────────────────────────────────────────────────────────────────
a1b2c3d4  2026-04-02 14:30:00  worlock  AI-ML-Papers    /home/jeb/Documents/AI-ML_Papers
────────────────────────────────────────────────────────────────
1 snapshots
```

## Restoring

```bash
# Restore latest snapshot to /tmp/restore
RESTIC_PASSWORD_FILE=~/.config/backup-wizard/restic_password \
restic -r /mnt/hitachi_2tb/restic_repos/ai-ml-papers \
  restore latest --target /tmp/restore

# Restore a specific snapshot
restic -r /path/to/repo restore a1b2c3d4 --target /tmp/restore

# Restore only a subdirectory
restic -r /path/to/repo restore latest \
  --target /tmp/restore \
  --include "/home/jeb/Documents/AI-ML_Papers/agents"
```

The wizard's **Restore** option (menu 2 → 4) guides through repo selection, snapshot ID, and target directory interactively.

## Pruning Old Snapshots

Without pruning, every backup run creates a new snapshot and the repo grows indefinitely. The default retention policy:

```
--keep-daily   7     # one per day, last 7 days
--keep-weekly  4     # one per week, last 4 weeks
--keep-monthly 12    # one per month, last 12 months
```

Run from the wizard (menu 2 → 5) or directly:

```bash
RESTIC_PASSWORD_FILE=~/.config/backup-wizard/restic_password \
restic -r /path/to/repo forget \
  --keep-daily 7 --keep-weekly 4 --keep-monthly 12 \
  --prune
```

`--prune` does the actual data removal in the same pass. Without `--prune`, `forget` only removes the snapshot references; `restic prune` must then be run separately.

## Exit Codes Reference

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Fatal error |
| 3 | Incomplete backup (some files unreadable — warning) |

## Repo Health Check

```bash
# Verify all pack files are intact
RESTIC_PASSWORD_FILE=~/.config/backup-wizard/restic_password \
restic -r /path/to/repo check

# Full verification (reads all data — slow but thorough)
restic -r /path/to/repo check --read-data
```

## Storage Estimate

For a 16GB PDF collection at `--compression max`:
- First backup: ~7-10GB on disk (PDFs typically compress 40-60% with zstd)
- Each subsequent incremental: only changed/new files, further deduplicated
- After 30 daily snapshots with low churn: ~10-12GB total (dedup handles unchanged packs)

## Extending to Remote Backends

To back up to an S3-compatible store (e.g., Backblaze B2, AWS S3, MinIO):

```bash
restic init --repo s3:s3.amazonaws.com/bucket-name/ai-ml-papers
```

Restic supports: local, SFTP, REST server, S3, B2, Azure, GCS, rclone (any rclone remote). The wizard's custom backup prompt accepts any valid restic repo URI.
