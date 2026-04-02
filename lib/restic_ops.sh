#!/usr/bin/env bash
# lib/restic_ops.sh — restic-based compressed backup operations
# Sourced by backup-wizard.sh; requires lib/common.sh already sourced.
#
# Restic overview:
#   • Content-addressed, deduplicated snapshot store
#   • --compression max (zstd) gives 30-60% size reduction on PDFs/text
#   • Each repo is password-protected; password stored in RESTIC_PASS_FILE
#   • Repos live under DEFAULT_RESTIC_REPO_BASE by default

RESTIC_BIN="${RESTIC_BIN:-restic}"

# ---------------------------------------------------------------------------
# Password management
# ---------------------------------------------------------------------------

# Ensure a restic password file exists; create it interactively if not.
ensure_restic_password() {
    ensure_config_dir
    if [[ -f "$RESTIC_PASS_FILE" ]]; then
        return 0
    fi

    log_warn "No restic password file found at: ${RESTIC_PASS_FILE}"
    echo -e "${CYAN}A password is required to encrypt your restic repository.${RESET}"
    echo "It will be stored at: ${RESTIC_PASS_FILE} (chmod 600)"
    echo ""

    local pass1 pass2
    while true; do
        read -r -s -p "Enter restic password: " pass1; echo
        read -r -s -p "Confirm password    : " pass2; echo
        if [[ "$pass1" == "$pass2" && -n "$pass1" ]]; then
            break
        fi
        log_error "Passwords do not match or are empty. Try again."
    done

    echo "$pass1" > "$RESTIC_PASS_FILE"
    chmod 600 "$RESTIC_PASS_FILE"
    log_ok "Password saved to ${RESTIC_PASS_FILE}"
}

# Export RESTIC_PASSWORD_FILE for all restic calls
set_restic_env() {
    export RESTIC_PASSWORD_FILE="$RESTIC_PASS_FILE"
}

# ---------------------------------------------------------------------------
# Repo initialization
# ---------------------------------------------------------------------------
restic_init_repo() {
    local repo="$1"

    log_header "Initialize Restic Repository"
    log_info "Repo path: ${repo}"

    if [[ -d "${repo}/config" ]] || $RESTIC_BIN -r "$repo" cat config &>/dev/null; then
        log_ok "Repository already initialized at ${repo}"
        return 0
    fi

    mkdir -p "$repo"
    ensure_restic_password
    set_restic_env

    $RESTIC_BIN init --repo "$repo"
    local rc=$?
    if [[ $rc -eq 0 ]]; then
        log_ok "Repository initialized: ${repo}"
        write_status_entry "RESTIC:init" "OK — ${repo}"
    else
        log_error "Failed to initialize repository (rc=${rc})"
        return $rc
    fi
}

# ---------------------------------------------------------------------------
# Core backup runner
# ---------------------------------------------------------------------------
run_restic_backup() {
    local src="$1"
    local repo="$2"
    local label="${3:-restic-backup}"
    local dry_run="${4:-0}"
    local compression="${5:-max}"   # off | auto | max

    log_header "Restic Backup: ${label}"
    log_info "Source      : ${src}"
    log_info "Repository  : ${repo}"
    log_info "Compression : ${compression}"
    [[ "$dry_run" == "1" ]] && log_warn "DRY RUN — nothing will be written"

    if [[ ! -d "$src" ]]; then
        log_error "Source does not exist: ${src}"
        return 1
    fi

    # Auto-init if repo doesn't exist yet
    if [[ ! -d "${repo}" ]]; then
        log_info "Repository not found — initializing..."
        restic_init_repo "$repo" || return 1
    else
        ensure_restic_password
        set_restic_env
        # Quick check that repo is accessible
        if ! $RESTIC_BIN -r "$repo" cat config &>/dev/null; then
            log_error "Repository exists but is not accessible (wrong password or corrupt): ${repo}"
            return 1
        fi
    fi

    set_restic_env

    local flags=(
        --repo "$repo"
        --compression "$compression"
        --tag "$label"
        --exclude-caches
        --exclude="*.tmp"
        --exclude=".Trash*"
        --exclude=".DS_Store"
    )

    [[ "$dry_run" == "1" ]] && flags+=(--dry-run --verbose)

    echo ""
    $RESTIC_BIN backup "${flags[@]}" "$src"
    local rc=$?

    if [[ $rc -eq 0 ]]; then
        log_ok "Restic backup completed: ${label}"
        write_status_entry "RESTIC:${label}" "OK — ${src} → ${repo} (compression=${compression})"
        # Show latest snapshot summary
        echo ""
        $RESTIC_BIN -r "$repo" snapshots --last 1 2>/dev/null || true
    elif [[ $rc -eq 3 ]]; then
        log_warn "Restic completed with warnings (rc=3: some source files could not be read — normal for live dirs)."
        write_status_entry "RESTIC:${label}" "WARN(3) — ${src} → ${repo}"
    else
        log_error "Restic backup failed (rc=${rc})"
        write_status_entry "RESTIC:${label}" "FAILED(${rc}) — ${src} → ${repo}"
        return $rc
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Preset: AI-ML Papers restic backup
# ---------------------------------------------------------------------------
restic_backup_aiml() {
    local dry_run="${1:-0}"
    local src="${AIML_SRC:-$DEFAULT_AIML_SRC}"
    local repo="${RESTIC_REPO_AIML:-${DEFAULT_RESTIC_REPO_BASE}/ai-ml-papers}"

    require_mount "/mnt/hitachi_2tb" || return 1
    run_restic_backup "$src" "$repo" "AI-ML-Papers" "$dry_run" "max"
}

# ---------------------------------------------------------------------------
# Preset: computer science restic backup
# ---------------------------------------------------------------------------
restic_backup_cs() {
    local dry_run="${1:-0}"
    local src="${CS_SRC:-$DEFAULT_CS_SRC}"
    local repo="${RESTIC_REPO_CS:-${DEFAULT_RESTIC_REPO_BASE}/computer-science}"

    require_mount "/mnt/hitachi_2tb" || return 1
    run_restic_backup "$src" "$repo" "computer-science" "$dry_run" "max"
}

# ---------------------------------------------------------------------------
# Preset: computers restic backup
# ---------------------------------------------------------------------------
restic_backup_computers() {
    local dry_run="${1:-0}"
    local src="${COMPUTERS_SRC:-$DEFAULT_COMPUTERS_SRC}"
    local repo="${RESTIC_REPO_COMPUTERS:-${DEFAULT_RESTIC_REPO_BASE}/computers}"

    require_mount "/mnt/hitachi_2tb" || return 1
    run_restic_backup "$src" "$repo" "computers" "$dry_run" "max"
}

# ---------------------------------------------------------------------------
# Convenience: restic snapshot all three paper archives in one shot
# ---------------------------------------------------------------------------
restic_backup_all_archives() {
    local dry_run="${1:-0}"
    log_header "Restic: All Archives (AI-ML Papers + computer science + computers)"
    restic_backup_aiml      "$dry_run"
    restic_backup_cs        "$dry_run"
    restic_backup_computers "$dry_run"
    log_ok "All restic archive backups complete."
}

# ---------------------------------------------------------------------------
# Preset: Custom source restic backup (interactive)
# ---------------------------------------------------------------------------
restic_backup_custom() {
    log_header "Custom Restic Backup"

    prompt_default "Source directory" "/home/jeb/Documents"
    local src="$REPLY"

    prompt_default "Repository path" "${DEFAULT_RESTIC_REPO_BASE}/custom"
    local repo="$REPLY"

    echo ""
    echo -e "${BOLD}Compression options:${RESET}"
    echo "  max  — maximum zstd compression (slower, smallest files)"
    echo "  auto — balanced compression (recommended for large mixed sets)"
    echo "  off  — no compression (fastest)"
    prompt_default "Compression level" "max"
    local compression="$REPLY"

    local dry_run=0
    if confirm "Dry run first (recommended)?"; then
        dry_run=1
        run_restic_backup "$src" "$repo" "custom" "$dry_run" "$compression"
        echo ""
        if confirm "Dry run complete. Proceed with real backup?"; then
            dry_run=0
            run_restic_backup "$src" "$repo" "custom" "$dry_run" "$compression"
        else
            log_info "Backup cancelled after dry run."
        fi
    else
        run_restic_backup "$src" "$repo" "custom" "$dry_run" "$compression"
    fi
}

# ---------------------------------------------------------------------------
# List snapshots for a repository
# ---------------------------------------------------------------------------
restic_list_snapshots() {
    log_header "Restic Snapshots"

    local repos=()
    # Enumerate known repos under the base dir
    if [[ -d "$DEFAULT_RESTIC_REPO_BASE" ]]; then
        while IFS= read -r -d '' d; do
            repos+=("$d")
        done < <(find "$DEFAULT_RESTIC_REPO_BASE" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
    fi

    if [[ ${#repos[@]} -eq 0 ]]; then
        log_warn "No restic repositories found under ${DEFAULT_RESTIC_REPO_BASE}"
        prompt_default "Enter repository path manually (or blank to cancel)" ""
        [[ -z "$REPLY" ]] && return 0
        repos=("$REPLY")
    fi

    ensure_restic_password
    set_restic_env

    for repo in "${repos[@]}"; do
        echo -e "\n${BOLD}Repository: ${repo}${RESET}"
        $RESTIC_BIN -r "$repo" snapshots 2>/dev/null || log_warn "Could not read snapshots from ${repo}"
    done
}

# ---------------------------------------------------------------------------
# Interactive restore from a restic repo
# ---------------------------------------------------------------------------
restic_restore() {
    log_header "Restic Restore"

    prompt_default "Repository path" "${DEFAULT_RESTIC_REPO_BASE}/ai-ml-papers"
    local repo="$REPLY"

    ensure_restic_password
    set_restic_env

    echo ""
    log_info "Available snapshots:"
    $RESTIC_BIN -r "$repo" snapshots || { log_error "Could not list snapshots."; return 1; }

    echo ""
    prompt_default "Snapshot ID to restore (or 'latest')" "latest"
    local snap="$REPLY"

    prompt_default "Restore target directory" "/tmp/restic_restore"
    local target="$REPLY"

    mkdir -p "$target"

    log_warn "This will restore snapshot '${snap}' into: ${target}"
    confirm "Proceed?" || { log_info "Restore cancelled."; return 0; }

    $RESTIC_BIN -r "$repo" restore "$snap" --target "$target"
    local rc=$?
    if [[ $rc -eq 0 ]]; then
        log_ok "Restore complete → ${target}"
    else
        log_error "Restore failed (rc=${rc})"
        return $rc
    fi
}

# ---------------------------------------------------------------------------
# Prune old snapshots (keep policy)
# ---------------------------------------------------------------------------
restic_prune() {
    log_header "Restic Prune / Forget"

    prompt_default "Repository path" "${DEFAULT_RESTIC_REPO_BASE}/ai-ml-papers"
    local repo="$REPLY"

    ensure_restic_password
    set_restic_env

    echo ""
    echo -e "${BOLD}Retention policy (defaults):${RESET}"
    echo "  Keep last 7 daily, 4 weekly, 12 monthly snapshots"
    confirm "Use default retention policy?" || {
        log_info "Edit lib/restic_ops.sh restic_prune() to customize retention."
        return 0
    }

    log_info "Running forget + prune with default policy..."
    $RESTIC_BIN -r "$repo" forget \
        --keep-daily 7 \
        --keep-weekly 4 \
        --keep-monthly 12 \
        --prune

    local rc=$?
    if [[ $rc -eq 0 ]]; then
        log_ok "Prune complete."
        write_status_entry "RESTIC:prune" "OK — ${repo}"
    else
        log_error "Prune failed (rc=${rc})"
    fi
}
