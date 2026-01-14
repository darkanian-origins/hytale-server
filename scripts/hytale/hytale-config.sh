#!/bin/sh
set -eu

# ------------------------------------------------------
#               Load Dependencies
# ------------------------------------------------------
. "$SCRIPTS_PATH/utils.sh"

CONFIG_FILE="/home/container/config.json"

log_section "Config Management"

# ------------------------------------------------------
#               Config File Generation
# ------------------------------------------------------
if [ ! -f "$CONFIG_FILE" ]; then
    log_step "Generating new config"
    cat <<EOF > "$CONFIG_FILE"
{
    "Version": 3,
    "ServerName": "Hytale Server",
    "MOTD": "",
    "Password": "",
    "MaxPlayers": 100,
    "MaxViewRadius": 32,
    "LocalCompressionEnabled": false,
    "Defaults": { "World": "default", "GameMode": "Adventure" },
    "ConnectionTimeouts": { "JoinTimeouts": {} },
    "RateLimit": {},
    "Modules": {},
    "LogLevels": {},
    "Mods": {},
    "DisplayTmpTagsInStrings": false,
    "PlayerStorage": { "Type": "Hytale" }
}
EOF
    log_success
else
    log_step "Updating existing config"
    log_success
fi

# ------------------------------------------------------
#               ENV Injection Helper
# ------------------------------------------------------
# Usage: apply_env ".JSON.PATH" "$ENV_VARIABLE"
apply_env() {
    local path="$1"
    local value="$2"

    # Only proceed if the environment variable is set
    if [ -n "$value" ]; then
        # Check if the value should be treated as a number or boolean
        case "$value" in
            true|false|[0-9]*)
                jq "$path = $value" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
                ;;
            *)
                # Treat as string (wrap in quotes)
                jq "$path = \"$value\"" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
                ;;
        esac
    fi
}

# ------------------------------------------------------
#           Environment Variable Mappings
# ------------------------------------------------------
# These will overwrite existing file values ONLY if the ENV var is provided
apply_env ".ServerName"               "${HYTALE_SERVER_NAME:-}"
apply_env ".MOTD"                     "${HYTALE_MOTD:-}"
apply_env ".Password"                 "${HYTALE_PASSWORD:-}"
apply_env ".MaxPlayers"               "${HYTALE_MAX_PLAYERS:-}"
apply_env ".MaxViewRadius"            "${HYTALE_MAX_VIEW_RADIUS:-}"
apply_env ".LocalCompressionEnabled"  "${HYTALE_COMPRESSION:-}"
apply_env ".Defaults.World"           "${HYTALE_WORLD:-}"
apply_env ".Defaults.GameMode"        "${HYTALE_GAMEMODE:-}"

printf "      ${DIM}↳ Settings Applied:${NC} ${GREEN}Sync Complete${NC}\n"