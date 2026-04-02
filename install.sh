#!/usr/bin/env bash
# install.sh — install backup-wizard system-wide on worlock
#
# What this does:
#   1. Symlinks backup-wizard.sh → /usr/local/bin/backup-wizard
#   2. Copies motd/94-backup-status → /etc/update-motd.d/94-backup-status
#   3. Creates /var/log/backup-wizard/ with correct permissions
#   4. Prints a test invocation
#
# Run once as root or with sudo:
#   sudo ./install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_LINK="/usr/local/bin/backup-wizard"
MOTD_DEST="/etc/update-motd.d/94-backup-status"
LOG_DIR="/var/log/backup-wizard"

if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Please run as root: sudo ./install.sh" >&2
    exit 1
fi

echo "[1/4] Making scripts executable..."
chmod +x "${SCRIPT_DIR}/backup-wizard.sh"
chmod +x "${SCRIPT_DIR}/lib/"*.sh
chmod +x "${SCRIPT_DIR}/motd/94-backup-status"

echo "[2/4] Installing backup-wizard to ${BIN_LINK}..."
if [[ -L "$BIN_LINK" || -f "$BIN_LINK" ]]; then
    echo "      (removing old link/file)"
    rm -f "$BIN_LINK"
fi
ln -s "${SCRIPT_DIR}/backup-wizard.sh" "$BIN_LINK"
echo "      → ${BIN_LINK}"

echo "[3/4] Installing MOTD fragment..."
cp "${SCRIPT_DIR}/motd/94-backup-status" "$MOTD_DEST"
chmod +x "$MOTD_DEST"
echo "      → ${MOTD_DEST}"

echo "[4/4] Creating log directory ${LOG_DIR}..."
mkdir -p "$LOG_DIR"
# Allow the invoking user (jeb) to write status entries without sudo
chmod 1777 "$LOG_DIR"
touch "${LOG_DIR}/last_run.log"
chmod 666 "${LOG_DIR}/last_run.log"

echo ""
echo "Installation complete."
echo ""
echo "Test the wizard:   backup-wizard --help"
echo "Test MOTD:         run-parts /etc/update-motd.d/"
echo "Interactive:       backup-wizard"
