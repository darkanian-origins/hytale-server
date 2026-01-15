#!/bin/sh
set -eu

# ------------------------------------------------------
#               Default Configuration
# ------------------------------------------------------
export SCRIPTS_PATH="/usr/local/bin/scripts"
export SERVER_PORT="${SERVER_PORT:-5520}"
export SERVER_IP="${SERVER_IP:-0.0.0.0}"
export DEBUG="${DEBUG:-FALSE}"
export PROD="${PROD:-FALSE}"
export BASE_DIR="/home/container"
export GAME_DIR="$BASE_DIR/game"
export SERVER_JAR_PATH="$GAME_DIR/Server/HytaleServer.jar"
export CACHE="${CACHE:-FALSE}"

# ------------------------------------------------------
#               Memory Configuration
# ------------------------------------------------------
# Simple memory config: use MEMORY for both min/max, or set individually
export MEMORY="${MEMORY:-}"
export MEMORY_MIN="${MEMORY_MIN:-}"
export MEMORY_MAX="${MEMORY_MAX:-}"
export JAVA_ARGS="${JAVA_ARGS:-}"

# Build memory arguments from simple variables
MEMORY_ARGS=""
if [ -n "$MEMORY" ]; then
    # Single MEMORY value sets both min and max
    MEMORY_ARGS="-Xms${MEMORY} -Xmx${MEMORY}"
else
    # Individual min/max settings
    if [ -n "$MEMORY_MIN" ]; then
        MEMORY_ARGS="-Xms${MEMORY_MIN}"
    fi
    if [ -n "$MEMORY_MAX" ]; then
        MEMORY_ARGS="$MEMORY_ARGS -Xmx${MEMORY_MAX}"
    fi
fi

# Combine memory args with any additional JAVA_ARGS
if [ -n "$MEMORY_ARGS" ]; then
    export JAVA_ARGS="$MEMORY_ARGS $JAVA_ARGS"
fi

# ------------------------------------------------------
#               Hytale Environment
# ------------------------------------------------------
export HYTALE_ACCEPT_EARLY_PLUGINS="${HYTALE_ACCEPT_EARLY_PLUGINS:-FALSE}"
export HYTALE_ALLOW_OP="${HYTALE_ALLOW_OP:-FALSE}"
export HYTALE_AUTH_MODE="${HYTALE_AUTH_MODE:-FALSE}"
export HYTALE_BACKUP="${HYTALE_BACKUP:-FALSE}"
export HYTALE_BACKUP_FREQUENCY="${HYTALE_BACKUP_FREQUENCY:-}"

# OAuth Authentication Tokens (optional - for token passthrough)
export HYTALE_SERVER_SESSION_TOKEN="${HYTALE_SERVER_SESSION_TOKEN:-}"
export HYTALE_SERVER_IDENTITY_TOKEN="${HYTALE_SERVER_IDENTITY_TOKEN:-}"
export HYTALE_OWNER_UUID="${HYTALE_OWNER_UUID:-}"
export HYTALE_PROFILE="${HYTALE_PROFILE:-}"

export HYTALE_CACHE_FLAG=""
export HYTALE_ACCEPT_EARLY_PLUGINS_FLAG=""
export HYTALE_ALLOW_OP_FLAG=""
export HYTALE_AUTH_MODE_FLAG=""
export HYTALE_BACKUP_FLAG=""
export HYTALE_BACKUP_FREQUENCY_FLAG=""
export HYTALE_QUIET_FLAGS=""
export HYTALE_SESSION_TOKEN_FLAG=""
export HYTALE_IDENTITY_TOKEN_FLAG=""
export HYTALE_OWNER_UUID_FLAG=""

. "$SCRIPTS_PATH/utils.sh"

# ------------------------------------------------------
#               Audits
# ------------------------------------------------------
log_section "Audit Suite"

if [ "$DEBUG" = "TRUE" ]; then
    sh "$SCRIPTS_PATH/checks/security.sh"
    sh "$SCRIPTS_PATH/checks/network.sh"
else
    printf "%sSystem debug skipped (DEBUG=FALSE)%s\n" "$DIM" "$NC"
fi

if [ "$PROD" = "TRUE" ]; then
    sh "$SCRIPTS_PATH/checks/prod.sh"
else
    printf "%sProduction audit skipped (PROD=FALSE)%s\n" "$DIM" "$NC"
fi

ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    printf "############################################################\n"
    printf "  WARNING: UNSUPPORTED ARCHITECTURE DETECTED\n"
    printf "############################################################\n"
    printf " Architecture: %s\n\n" "$ARCH"
    printf " Hytale-Downloader only works for x86_64 at the moment.\n"
    printf " Status: Waiting for Hytale to release the native ARM64 binary.\n"
    printf "############################################################\n"
fi

# ------------------------------------------------------
#               Initialize Scripts
# ------------------------------------------------------
sh "$SCRIPTS_PATH/hytale/hytale-downloader.sh"
sh "$SCRIPTS_PATH/hytale/hytale-config.sh"
sh "$SCRIPTS_PATH/hytale/hytale-flags.sh"

# Source auth cache to set session token flags
. "$SCRIPTS_PATH/hytale/hytale-auth-cache.sh"

log_section "Process Execution"
log_step "Finalizing Environment"
cd "$BASE_DIR"
log_success

# ------------------------------------------------------
#               Execution
# ------------------------------------------------------
printf "\n%s🚀 Launching Hytale Server...%s\n\n" "$BOLD$CYAN" "$NC"

if command -v gosu >/dev/null 2>&1; then
    RUNTIME="gosu $USER"
elif command -v su-exec >/dev/null 2>&1; then
    RUNTIME="su-exec $USER"
else
    RUNTIME=""
fi

exec $RUNTIME java $JAVA_ARGS \
    -Dterminal.jline=false \
    -Dterminal.ansi=true \
    $HYTALE_CACHE_FLAG \
    $HYTALE_ACCEPT_EARLY_PLUGINS_FLAG \
    $HYTALE_ALLOW_OP_FLAG \
    $HYTALE_AUTH_MODE_FLAG \
    $HYTALE_BACKUP_FLAG \
    $HYTALE_BACKUP_FREQUENCY_FLAG \
    $HYTALE_QUIET_FLAGS \
    -jar "$SERVER_JAR_PATH" \
    --assets "$GAME_DIR/Assets.zip" \
    --bind "$SERVER_IP:$SERVER_PORT" \
    $HYTALE_SESSION_TOKEN_FLAG \
    $HYTALE_IDENTITY_TOKEN_FLAG \
    $HYTALE_OWNER_UUID_FLAG