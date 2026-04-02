#!/usr/bin/env bash
# backup-wizard.sh — interactive CLI backup wizard for worlock
#
# Usage:
#   ./backup-wizard.sh              # interactive menu
#   ./backup-wizard.sh --status     # print status and exit
#   ./backup-wizard.sh --aiml       # non-interactive AI-ML Papers rsync
#   ./backup-wizard.sh --aiml-restic # non-interactive AI-ML Papers restic
#   ./backup-wizard.sh --help       # show usage
#
# Requires: rsync, restic (0.14+), bash 4+

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# Source libraries
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/rsync_ops.sh"
source "${SCRIPT_DIR}/lib/restic_ops.sh"

# Load saved config (overrides defaults)
load_config

# ---------------------------------------------------------------------------
# Non-interactive / CLI flags
# ---------------------------------------------------------------------------
handle_cli_flags() {
    case "${1:-}" in
        --help|-h)
            cat <<EOF
backup-wizard — worlock backup system

USAGE
  ./backup-wizard.sh [FLAG]

FLAGS
  (none)              Launch interactive menu
  --status            Print last backup status and disk usage, then exit
  --aiml              Rsync AI-ML Papers → /mnt/hitachi_2tb/AI-ML_Papers_backup
  --cs                Rsync computer science → /mnt/hitachi_2tb/computer_science_backup
  --computers         Rsync computers → /mnt/hitachi_2tb/computers_backup
  --all-archives      Rsync all three paper archives in one shot
  --aiml-restic       Restic (compressed) backup of AI-ML Papers
  --cs-restic         Restic (compressed) backup of computer science
  --computers-restic  Restic (compressed) backup of computers
  --all-restic        Restic all three paper archives in one shot
  --pdf               PDF archive rsync via pdf-backup.sh (requires sudo)
  --help              Show this help

EXAMPLES
  ./backup-wizard.sh                    # interactive wizard
  ./backup-wizard.sh --all-archives     # rsync all three archives at once
  ./backup-wizard.sh --aiml             # quick rsync of AI-ML papers
  ./backup-wizard.sh --cs               # quick rsync of computer science
  ./backup-wizard.sh --computers        # quick rsync of computers
  ./backup-wizard.sh --aiml-restic      # compressed snapshot of AI-ML papers
  ./backup-wizard.sh --cs-restic        # compressed snapshot of computer science
  ./backup-wizard.sh --computers-restic # compressed snapshot of computers
  ./backup-wizard.sh --all-restic       # restic snapshot all three archives
  sudo ./backup-wizard.sh --pdf         # full PDF archive backup
EOF
            exit 0
            ;;
        --status)
            show_status
            exit 0
            ;;
        --aiml)
            backup_aiml_papers 0
            exit $?
            ;;
        --cs)
            backup_computer_science 0
            exit $?
            ;;
        --computers)
            backup_computers 0
            exit $?
            ;;
        --all-archives)
            backup_all_archives 0
            exit $?
            ;;
        --aiml-restic)
            restic_backup_aiml 0
            exit $?
            ;;
        --cs-restic)
            restic_backup_cs 0
            exit $?
            ;;
        --computers-restic)
            restic_backup_computers 0
            exit $?
            ;;
        --all-restic)
            restic_backup_all_archives 0
            exit $?
            ;;
        --pdf)
            backup_pdf_archive 0
            exit $?
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Status display (used by --status flag and menu option)
# ---------------------------------------------------------------------------
show_status() {
    log_header "Backup Status"

    # Last run log
    if [[ -f "$STATUS_LOG" ]]; then
        echo -e "${BOLD}Last operations:${RESET}"
        sort "$STATUS_LOG" | while IFS= read -r line; do
            echo "  $line"
        done
    else
        echo -e "  ${YELLOW}No backup operations recorded yet.${RESET}"
    fi

    echo ""
    echo -e "${BOLD}Disk usage — backup destinations:${RESET}"

    local mounts=("/mnt/hitachi_2tb" "/mnt/pdf_backup" "/mnt/raid0" "/mnt/wd_storage")
    for m in "${mounts[@]}"; do
        if mountpoint -q "$m" 2>/dev/null; then
            local info
            info=$(df -h "$m" | awk 'NR==2{printf "%-12s  used=%-6s  free=%-6s  (%s)", $6, $3, $4, $5}')
            echo -e "  ${GREEN}✓${RESET}  ${info}"
        else
            echo -e "  ${RED}✗${RESET}  ${m}  (not mounted)"
        fi
    done

    echo ""
    echo -e "${BOLD}AI-ML Papers source:${RESET}"
    local src="${AIML_SRC:-$DEFAULT_AIML_SRC}"
    if [[ -d "$src" ]]; then
        local sz
        sz=$(du -sh "$src" 2>/dev/null | cut -f1)
        echo -e "  ${GREEN}✓${RESET}  ${src}  (${sz})"
    else
        echo -e "  ${RED}✗${RESET}  ${src}  (not found)"
    fi

    echo ""
    echo -e "${BOLD}Restic repos:${RESET}"
    if [[ -d "$DEFAULT_RESTIC_REPO_BASE" ]]; then
        local found=0
        while IFS= read -r -d '' d; do
            local rsize
            rsize=$(du -sh "$d" 2>/dev/null | cut -f1)
            echo -e "  ${CYAN}→${RESET}  ${d}  (${rsize})"
            found=1
        done < <(find "$DEFAULT_RESTIC_REPO_BASE" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
        [[ $found -eq 0 ]] && echo "  (no repos yet)"
    else
        echo "  (base dir not created yet)"
    fi
}

# ---------------------------------------------------------------------------
# Menu: Rsync submenu
# ---------------------------------------------------------------------------
menu_rsync() {
    while true; do
        echo ""
        echo -e "${BOLD}${BLUE}── Rsync Backups ──────────────────────────────────────${RESET}"
        echo "  1) ALL archives  (AI-ML Papers + computer science + computers)"
        echo "  2) AI-ML Papers      →  /mnt/hitachi_2tb/AI-ML_Papers_backup"
        echo "  3) computer science  →  /mnt/hitachi_2tb/computer_science_backup"
        echo "  4) computers         →  /mnt/hitachi_2tb/computers_backup"
        echo "  5) PDF Archive       →  /mnt/pdf_backup  (via pdf-backup.sh)"
        echo "  6) Custom source/destination"
        echo "  b) Back"
        echo ""
        read -r -p "$(echo -e "${CYAN}Select: ${RESET}")" choice
        case "$choice" in
            1)
                local dry=0
                confirm "Dry run first?" && dry=1
                backup_all_archives "$dry"
                [[ "$dry" == "1" ]] && confirm "Proceed with real backup?" && backup_all_archives 0
                pause
                ;;
            2)
                local dry=0
                confirm "Dry run first?" && dry=1
                backup_aiml_papers "$dry"
                [[ "$dry" == "1" ]] && confirm "Proceed with real backup?" && backup_aiml_papers 0
                pause
                ;;
            3)
                local dry=0
                confirm "Dry run first?" && dry=1
                backup_computer_science "$dry"
                [[ "$dry" == "1" ]] && confirm "Proceed with real backup?" && backup_computer_science 0
                pause
                ;;
            4)
                local dry=0
                confirm "Dry run first?" && dry=1
                backup_computers "$dry"
                [[ "$dry" == "1" ]] && confirm "Proceed with real backup?" && backup_computers 0
                pause
                ;;
            5)
                if [[ $EUID -ne 0 ]]; then
                    log_warn "PDF archive backup requires root. Re-running with sudo..."
                    sudo bash "$0" --pdf
                else
                    backup_pdf_archive 0
                fi
                pause
                ;;
            6)
                backup_custom_rsync
                pause
                ;;
            b|B) return ;;
            *) log_warn "Invalid choice." ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Menu: Restic submenu
# ---------------------------------------------------------------------------
menu_restic() {
    while true; do
        echo ""
        echo -e "${BOLD}${MAGENTA}── Restic (Compressed) Backups ────────────────────────${RESET}"
        echo "  1) ALL archives  (AI-ML Papers + computer science + computers)"
        echo "  2) AI-ML Papers      →  restic repo (max compression)"
        echo "  3) computer science  →  restic repo (max compression)"
        echo "  4) computers         →  restic repo (max compression)"
        echo "  5) Custom source →  restic repo"
        echo "  6) List snapshots"
        echo "  7) Restore from snapshot"
        echo "  8) Prune old snapshots"
        echo "  9) Initialize new repository"
        echo "  b) Back"
        echo ""
        read -r -p "$(echo -e "${CYAN}Select: ${RESET}")" choice
        case "$choice" in
            1)
                local dry=0
                confirm "Dry run first?" && dry=1
                restic_backup_all_archives "$dry"
                [[ "$dry" == "1" ]] && confirm "Proceed with real backup?" && restic_backup_all_archives 0
                pause
                ;;
            2)
                local dry=0
                confirm "Dry run first?" && dry=1
                restic_backup_aiml "$dry"
                [[ "$dry" == "1" ]] && confirm "Proceed with real backup?" && restic_backup_aiml 0
                pause
                ;;
            3)
                local dry=0
                confirm "Dry run first?" && dry=1
                restic_backup_cs "$dry"
                [[ "$dry" == "1" ]] && confirm "Proceed with real backup?" && restic_backup_cs 0
                pause
                ;;
            4)
                local dry=0
                confirm "Dry run first?" && dry=1
                restic_backup_computers "$dry"
                [[ "$dry" == "1" ]] && confirm "Proceed with real backup?" && restic_backup_computers 0
                pause
                ;;
            5)
                restic_backup_custom
                pause
                ;;
            6)
                restic_list_snapshots
                pause
                ;;
            7)
                restic_restore
                pause
                ;;
            8)
                restic_prune
                pause
                ;;
            9)
                prompt_default "New repo path" "${DEFAULT_RESTIC_REPO_BASE}/new-repo"
                restic_init_repo "$REPLY"
                pause
                ;;
            b|B) return ;;
            *) log_warn "Invalid choice." ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Menu: Configuration submenu
# ---------------------------------------------------------------------------
menu_config() {
    while true; do
        echo ""
        echo -e "${BOLD}── Configuration ──────────────────────────────────────${RESET}"
        echo "  Current values:"
        echo -e "    AIML_SRC  = ${AIML_SRC:-${DEFAULT_AIML_SRC}  ${YELLOW}(default)${RESET}}"
        echo -e "    AIML_DST  = ${AIML_DST:-${DEFAULT_AIML_DST}  ${YELLOW}(default)${RESET}}"
        echo -e "    RESTIC_REPO_AIML = ${RESTIC_REPO_AIML:-${DEFAULT_RESTIC_REPO_BASE}/ai-ml-papers  ${YELLOW}(default)${RESET}}"
        echo ""
        echo "  1) Set AI-ML source path"
        echo "  2) Set AI-ML rsync destination path"
        echo "  3) Set restic repo path for AI-ML"
        echo "  4) Change restic password"
        echo "  b) Back"
        echo ""
        read -r -p "$(echo -e "${CYAN}Select: ${RESET}")" choice
        case "$choice" in
            1)
                prompt_default "AI-ML source" "${AIML_SRC:-$DEFAULT_AIML_SRC}"
                AIML_SRC="$REPLY"; save_config_value "AIML_SRC" "$AIML_SRC"
                log_ok "Saved AIML_SRC=${AIML_SRC}"
                ;;
            2)
                prompt_default "AI-ML rsync destination" "${AIML_DST:-$DEFAULT_AIML_DST}"
                AIML_DST="$REPLY"; save_config_value "AIML_DST" "$AIML_DST"
                log_ok "Saved AIML_DST=${AIML_DST}"
                ;;
            3)
                prompt_default "Restic repo for AI-ML" "${RESTIC_REPO_AIML:-${DEFAULT_RESTIC_REPO_BASE}/ai-ml-papers}"
                RESTIC_REPO_AIML="$REPLY"; save_config_value "RESTIC_REPO_AIML" "$RESTIC_REPO_AIML"
                log_ok "Saved RESTIC_REPO_AIML=${RESTIC_REPO_AIML}"
                ;;
            4)
                rm -f "$RESTIC_PASS_FILE"
                ensure_restic_password
                ;;
            b|B) return ;;
            *) log_warn "Invalid choice." ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Main menu
# ---------------------------------------------------------------------------
main_menu() {
    while true; do
        clear
        echo -e "${BOLD}${CYAN}"
        cat <<'BANNER'
  ╔══════════════════════════════════════════════════════╗
  ║           worlock  backup-wizard  v1.0               ║
  ║     rsync · restic · AI-ML · PDF archive             ║
  ╚══════════════════════════════════════════════════════╝
BANNER
        echo -e "${RESET}"
        echo -e "${BOLD}Main Menu${RESET}"
        echo "  1) Rsync backups"
        echo "  2) Restic backups  (compressed, deduplicated snapshots)"
        echo "  3) Backup status   (last runs, disk usage)"
        echo "  4) Configuration"
        echo "  q) Quit"
        echo ""
        read -r -p "$(echo -e "${CYAN}Select: ${RESET}")" choice
        case "$choice" in
            1) menu_rsync ;;
            2) menu_restic ;;
            3) show_status; echo ""; pause ;;
            4) menu_config ;;
            q|Q) log_info "Goodbye."; exit 0 ;;
            *) log_warn "Invalid choice." ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
[[ $# -gt 0 ]] && handle_cli_flags "$@"
main_menu
