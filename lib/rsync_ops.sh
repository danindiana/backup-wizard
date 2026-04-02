#!/usr/bin/env bash
# lib/rsync_ops.sh — rsync-based backup operations
# Sourced by backup-wizard.sh; requires lib/common.sh already sourced.

# ---------------------------------------------------------------------------
# Core rsync runner
# Supports --dry-run, --delete, resume-safe (--partial --append-verify)
# ---------------------------------------------------------------------------
run_rsync() {
    local src="$1"
    local dst="$2"
    local label="${3:-backup}"
    local dry_run="${4:-0}"
    local do_delete="${5:-0}"

    log_header "Rsync: ${label}"
    log_info "Source : ${src}"
    log_info "Dest   : ${dst}"
    [[ "$dry_run"   == "1" ]] && log_warn "DRY RUN — no files will be written"
    [[ "$do_delete" == "1" ]] && log_warn "DELETE enabled — files removed from dest if absent from source"

    # Verify source exists
    if [[ ! -d "$src" ]]; then
        log_error "Source directory does not exist: ${src}"
        return 1
    fi

    # Verify destination mount
    local dst_base
    dst_base="$(df "$dst" 2>/dev/null | awk 'NR==2{print $6}' || echo "")"
    if [[ -z "$dst_base" ]]; then
        # Destination may not exist yet — check parent
        dst_base="$(df "$(dirname "$dst")" 2>/dev/null | awk 'NR==2{print $6}' || echo "")"
    fi
    if [[ -z "$dst_base" ]]; then
        log_error "Cannot determine filesystem for destination: ${dst}"
        return 1
    fi

    mkdir -p "$dst"

    check_free_space "$dst_base" 5 || true   # warn only, don't abort

    local flags=(
        --archive           # -rlptgoD: recursive, links, perms, times, group, owner, devices
        --partial           # keep partial files on interruption (resume-safe)
        --append-verify     # on resume: append + full checksum verification
        --human-readable
        --progress
        --stats
        --exclude="*.tmp"
        --exclude=".Trash*"
        --exclude=".DS_Store"
    )

    [[ "$dry_run"   == "1" ]] && flags+=(--dry-run)
    [[ "$do_delete" == "1" ]] && flags+=(--delete --delete-excluded)

    echo ""
    rsync "${flags[@]}" "${src}/" "${dst}/"
    local rc=$?

    if [[ $rc -eq 0 ]]; then
        log_ok "Rsync completed successfully."
        write_status_entry "RSYNC:${label}" "OK — ${src} → ${dst}"
    elif [[ $rc -eq 24 ]]; then
        log_warn "Rsync finished with warnings (rc=24: some source files vanished during transfer — normal for live dirs)."
        write_status_entry "RSYNC:${label}" "WARN(24) — ${src} → ${dst}"
    else
        log_error "Rsync failed (exit code ${rc})."
        write_status_entry "RSYNC:${label}" "FAILED(${rc}) — ${src} → ${dst}"
        return $rc
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Preset: AI-ML Papers backup
# ---------------------------------------------------------------------------
backup_aiml_papers() {
    local dry_run="${1:-0}"
    local src="${AIML_SRC:-$DEFAULT_AIML_SRC}"
    local dst="${AIML_DST:-$DEFAULT_AIML_DST}"

    require_mount "/mnt/hitachi_2tb" || return 1
    run_rsync "$src" "$dst" "AI-ML-Papers" "$dry_run" "0"
}

# ---------------------------------------------------------------------------
# Preset: PDF Archive (delegates to the existing pdf-backup.sh if available,
# otherwise runs rsync directly)
# ---------------------------------------------------------------------------
backup_pdf_archive() {
    local dry_run="${1:-0}"

    require_mount "/mnt/raid0"    || { log_error "/mnt/raid0 (RAID0 source) not mounted."; return 1; }
    require_mount "/mnt/pdf_backup" || { log_error "/mnt/pdf_backup (destination) not mounted."; return 1; }

    if [[ -x "$PDF_BACKUP_SCRIPT" ]]; then
        log_header "PDF Archive Backup (via pdf-backup.sh)"
        log_info "Delegating to: ${PDF_BACKUP_SCRIPT}"
        if [[ "$dry_run" == "1" ]]; then
            sudo "$PDF_BACKUP_SCRIPT" --dry-run
        else
            sudo "$PDF_BACKUP_SCRIPT"
        fi
        local rc=$?
        if [[ $rc -eq 0 ]]; then
            write_status_entry "RSYNC:PDF-Archive" "OK — delegated to pdf-backup.sh"
        else
            write_status_entry "RSYNC:PDF-Archive" "FAILED(${rc}) — delegated to pdf-backup.sh"
        fi
        return $rc
    else
        log_warn "pdf-backup.sh not found or not executable at: ${PDF_BACKUP_SCRIPT}"
        log_info "Falling back to direct rsync..."
        run_rsync "$DEFAULT_PDF_SRC" "$DEFAULT_PDF_DST" "PDF-Archive" "$dry_run" "0"
    fi
}

# ---------------------------------------------------------------------------
# Custom rsync: interactively prompt for source + destination
# ---------------------------------------------------------------------------
backup_custom_rsync() {
    log_header "Custom Rsync Backup"

    prompt_default "Source directory" "/home/jeb/Documents"
    local src="$REPLY"

    prompt_default "Destination directory" "/mnt/hitachi_2tb/custom_backup"
    local dst="$REPLY"

    local do_delete=0
    if confirm "Enable --delete (mirror source exactly, removing files in dest not in source)?"; then
        do_delete=1
    fi

    local dry_run=0
    if confirm "Dry run first (recommended)?"; then
        dry_run=1
        run_rsync "$src" "$dst" "Custom" "$dry_run" "$do_delete"
        echo ""
        if confirm "Dry run complete. Proceed with real backup?"; then
            dry_run=0
            run_rsync "$src" "$dst" "Custom" "$dry_run" "$do_delete"
        else
            log_info "Backup cancelled after dry run."
        fi
    else
        run_rsync "$src" "$dst" "Custom" "$dry_run" "$do_delete"
    fi
}
