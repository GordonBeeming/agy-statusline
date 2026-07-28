#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${HOME}/.gemini/antigravity-cli/scripts"
REPO_URL="https://raw.githubusercontent.com/GordonBeeming/agy-statusline/main/statusline.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Antigravity Statusline Installer ==="
echo ""

# --- Install statusline.sh ---
echo "Installing statusline.sh to ${INSTALL_DIR}..."
mkdir -p "$INSTALL_DIR"

if [[ -f "${SCRIPT_DIR}/statusline.sh" ]]; then
  cp "${SCRIPT_DIR}/statusline.sh" "${INSTALL_DIR}/statusline.sh"
  chmod +x "${INSTALL_DIR}/statusline.sh"
  echo "  Installed from local copy."
else
  tmp=$(mktemp)
  if curl -f -sSL "$REPO_URL" -o "$tmp"; then
    cp "$tmp" "${INSTALL_DIR}/statusline.sh"
    chmod +x "${INSTALL_DIR}/statusline.sh"
    echo "  Installed from remote successfully."
  else
    echo "  ERROR: Failed to download and no local statusline.sh found."
    exit 1
  fi
  rm -f "$tmp"
fi

# Write initial update marker
echo "$(date +%s)" > "${INSTALL_DIR}/.statusline-last-update"

# Auto-configure settings.json with absolute path if file exists
SETTINGS_FILE="${HOME}/.gemini/antigravity-cli/settings.json"
TARGET_CMD="${INSTALL_DIR}/statusline.sh"

if [[ -f "$SETTINGS_FILE" ]]; then
  if command -v jq &>/dev/null; then
    tmp_settings=$(mktemp)
    jq --arg cmd "$TARGET_CMD" '.statusLine = {"type": "command", "command": $cmd, "enabled": true}' "$SETTINGS_FILE" > "$tmp_settings" && mv "$tmp_settings" "$SETTINGS_FILE"
    echo "  Updated statusLine configuration in ${SETTINGS_FILE} automatically."
  fi
fi

echo ""
echo "=== Installation complete ==="
echo ""
echo "Ensure your ~/.gemini/antigravity-cli/settings.json contains:"
echo ""
echo '  "statusLine": {'
echo '    "type": "command",'
echo "    \"command\": \"${TARGET_CMD}\","
echo '    "enabled": true'
echo '  }'
echo ""
echo "The script will auto-update from main once per day."
