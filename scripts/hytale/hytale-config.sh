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
log_step "Config File Status\n"
if [ ! -f "$CONFIG_FILE" ]; then
    printf "[ ${CYAN}NEW${NC} ]\n"
    printf "      ${DIM}↳ Path:${NC} ${CYAN}%s${NC}\n" "$CONFIG_FILE"
    printf "      ${DIM}↳ Action:${NC} ${GREEN}Creating default template${NC}\n"
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
else
    printf "[ ${GREEN}OK${NC} ]\n"
    printf "      ${DIM}↳ Path:${NC} ${CYAN}%s${NC}\n" "$CONFIG_FILE"
    printf "      ${DIM}↳ Action:${NC} ${GREEN}Using existing config${NC}\n"
fi

# ------------------------------------------------------
#               ENV Injection Helper
# ------------------------------------------------------
ENV_APPLIED=0

apply_env() {
    local path="$1"
    local value="$2"
    local name="$3"

    if [ -n "$value" ]; then
        case "$value" in
            true|false|[0-9]*)
                jq "$path = $value" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
                ;;
            *)
                jq "$path = \"$value\"" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
                ;;
        esac
        ENV_APPLIED=$((ENV_APPLIED + 1))
        printf "      ${DIM}↳${NC} ${CYAN}%-20s${NC} ${DIM}→${NC} ${GREEN}%s${NC}\n" "$name" "$value"
    fi
}

# ------------------------------------------------------
#           Environment Variable Mappings
# ------------------------------------------------------
log_step "Environment Overrides\n"

apply_env ".ServerName"               "${HYTALE_SERVER_NAME:-}"        "ServerName"
apply_env ".MOTD"                     "${HYTALE_MOTD:-}"               "MOTD"
apply_env ".Password"                 "${HYTALE_PASSWORD:-}"           "Password"
apply_env ".MaxPlayers"               "${HYTALE_MAX_PLAYERS:-}"        "MaxPlayers"
apply_env ".MaxViewRadius"            "${HYTALE_MAX_VIEW_RADIUS:-}"    "MaxViewRadius"
apply_env ".LocalCompressionEnabled"  "${HYTALE_COMPRESSION:-}"        "Compression"
apply_env ".Defaults.World"           "${HYTALE_WORLD:-}"              "World"
apply_env ".Defaults.GameMode"        "${HYTALE_GAMEMODE:-}"           "GameMode"

if [ "$ENV_APPLIED" -gt 0 ]; then
    printf "  %-35s[ ${GREEN}OK${NC} ] ${GREEN}✔${NC}\n" ""
    printf "      ${DIM}↳ Total:${NC} ${BOLD}${CYAN}%d${NC} ${DIM}override(s) applied${NC}\n" "$ENV_APPLIED"
else
    printf "[ ${DIM}SKIP${NC} ]\n"
    printf "      ${DIM}↳ Info: No environment overrides provided${NC}\n"
fi