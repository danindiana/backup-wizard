#!/usr/bin/env bash
# lib/common.sh — shared constants, colors, logging, and utility functions
# Sourced by backup-wizard.sh and all lib/* scripts.

# ---------------------------------------------------------------------------
# Terminal colors (disabled automatically when not a tty)
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
    RED='\033[0;31m';    YELLOW='\033[1;33m'; GREEN='\033[0;32m'
    CYAN='\033[0;36m';   BOLD='\033[1m';      RESET='\033[0m'
    BLUE='\033[0;34m';   MAGENTA='\033[0;35m'
else
    RED=''; YELLOW=''; GREEN=''; CYAN=''; BOLD=''; RESET=''; BLUE=''; MAGENTA=''
fi

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
WIZARD_CONFIG_DIR="${HOME}/.config/backup-wizard"
WIZARD_CONFIG_FILE="${WIZARD_CONFIG_DIR}/config"
RESTIC_PASS_FILE="${WIZARD_CONFIG_DIR}/restic_password"
STATUS_LOG="/var/log/backup-wizard/last_run.log"
STATUS_LOG_DIR="/var/log/backup-wizard"

# Default backup sources and destinations (worlock-specific)
DEFAULT_AIML_SRC="/home/jeb/Documents/AI-ML_Papers"
DEFAULT_AIML_DST="/mnt/hitachi_2tb/AI-ML_Papers_backup"
DEFAULT_CS_SRC="/home/jeb/Documents/computer science"
DEFAULT_CS_DST="/mnt/hitachi_2tb/computer_science_backup"
DEFAULT_COMPUTERS_SRC="/home/jeb/Documents/computers"
DEFAULT_COMPUTERS_DST="/mnt/hitachi_2tb/computers_backup"
DEFAULT_PDF_SRC="/mnt/raid0"
DEFAULT_PDF_DST="/mnt/pdf_backup"
DEFAULT_RESTIC_REPO_BASE="/mnt/hitachi_2tb/restic_repos"
# Per-archive restic repo paths (overridable via config file)
DEFAULT_RESTIC_REPO_AIML="/mnt/hitachi_2tb/restic_repos/ai-ml-papers"
DEFAULT_RESTIC_REPO_CS="/mnt/hitachi_2tb/restic_repos/computer-science"
DEFAULT_RESTIC_REPO_COMPUTERS="/mnt/hitachi_2tb/restic_repos/computers"
PDF_BACKUP_SCRIPT="/home/jeb/Documents/claude_creations/2026-03-27_220258_pdf-backup/pdf-backup.sh"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log_info()    { echo -e "${GREEN}[INFO]${RESET}  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
log_header()  { echo -e "\n${BOLD}${CYAN}$*${RESET}"; echo -e "${CYAN}$(printf '─%.0s' {1..60})${RESET}"; }
log_ok()      { echo -e "${GREEN}✓${RESET} $*"; }
log_fail()    { echo -e "${RED}✗${RESET} $*"; }

# Write a status entry to the shared log (used by MOTD script)
# Usage: write_status_entry <tag> <message>
write_status_entry() {
    local tag="$1"; shift
    local msg="$*"
    sudo mkdir -p "$STATUS_LOG_DIR" 2>/dev/null || mkdir -p "$STATUS_LOG_DIR" 2>/dev/null || true
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    local entry="${ts}  [${tag}]  ${msg}"
    # Update or append the line for this tag
    if [[ -w "$STATUS_LOG" ]] || sudo test -w "$STATUS_LOG" 2>/dev/null; then
        # Remove old entry for this tag and append new one
        sudo sed -i "/\[${tag}\]/d" "$STATUS_LOG" 2>/dev/null || \
            sed -i "/\[${tag}\]/d" "$STATUS_LOG" 2>/dev/null || true
        echo "$entry" | sudo tee -a "$STATUS_LOG" >/dev/null 2>/dev/null || \
            echo "$entry" >> "$STATUS_LOG" 2>/dev/null || true
    else
        sudo mkdir -p "$STATUS_LOG_DIR" 2>/dev/null || true
        echo "$entry" | sudo tee -a "$STATUS_LOG" >/dev/null 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# Mount-point guard: verify a path is actually mounted
# ---------------------------------------------------------------------------
require_mount() {
    local path="$1"
    if ! mountpoint -q "$path" 2>/dev/null; then
        log_error "'${path}' is not mounted. Aborting."
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Disk space check — warn if destination has < N GB free
# ---------------------------------------------------------------------------
check_free_space() {
    local path="$1"
    local min_gb="${2:-10}"
    local free_gb
    free_gb=$(df -BG "$path" 2>/dev/null | awk 'NR==2{gsub("G","",$4); print $4}')
    if [[ -z "$free_gb" ]] || [[ "$free_gb" -lt "$min_gb" ]]; then
        log_warn "Low free space on ${path}: ${free_gb:-unknown}G free (min recommended: ${min_gb}G)"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Config helpers
# ---------------------------------------------------------------------------
ensure_config_dir() {
    mkdir -p "$WIZARD_CONFIG_DIR"
    chmod 700 "$WIZARD_CONFIG_DIR"
}

load_config() {
    if [[ -f "$WIZARD_CONFIG_FILE" ]]; then
        source "$WIZARD_CONFIG_FILE"
    fi
}

save_config_value() {
    local key="$1" val="$2"
    ensure_config_dir
    touch "$WIZARD_CONFIG_FILE"
    # Update or append
    if grep -q "^${key}=" "$WIZARD_CONFIG_FILE" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$WIZARD_CONFIG_FILE"
    else
        echo "${key}=${val}" >> "$WIZARD_CONFIG_FILE"
    fi
}

# ---------------------------------------------------------------------------
# Prompt helpers
# ---------------------------------------------------------------------------

# Prompt with a default: prompt_default "Label" "default_value" -> result in $REPLY
prompt_default() {
    local label="$1" default="$2"
    read -r -p "$(echo -e "${CYAN}${label}${RESET} [${default}]: ")" REPLY
    REPLY="${REPLY:-$default}"
}

# Yes/no prompt — returns 0 for yes, 1 for no
confirm() {
    local prompt="${1:-Continue?} [y/N] "
    local ans
    read -r -p "$(echo -e "${YELLOW}${prompt}${RESET}")" ans
    [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

# Press enter to continue
pause() {
    read -r -p "$(echo -e "${CYAN}Press Enter to continue...${RESET}")"
}
