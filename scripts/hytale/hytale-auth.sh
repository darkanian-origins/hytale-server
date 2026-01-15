#!/bin/sh
set -eu

# ------------------------------------------------------
#         Hytale OAuth Authentication Helper
# ------------------------------------------------------
# This script helps obtain OAuth tokens for server auth.
# Run this on your host machine to get tokens, then pass
# them to the container via environment variables.
#
# Usage: ./hytale-auth.sh [command]
#   login    - Start device code OAuth flow
#   refresh  - Refresh existing tokens
#   session  - Create a new game session
#   status   - Check token status
#   env      - Output tokens as environment variables
# ------------------------------------------------------

# Load utilities if available
if [ -f "$SCRIPTS_PATH/utils.sh" ] 2>/dev/null; then
    . "$SCRIPTS_PATH/utils.sh"
else
    # Minimal color definitions for standalone use
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m'
fi

# ------------------------------------------------------
#                   Configuration
# ------------------------------------------------------
OAUTH_BASE_URL="${HYTALE_OAUTH_BASE_URL:-https://oauth.accounts.hytale.com}"
SESSIONS_BASE_URL="${HYTALE_SESSIONS_BASE_URL:-https://sessions.hytale.com}"
ACCOUNT_DATA_URL="${HYTALE_ACCOUNT_DATA_URL:-https://account-data.hytale.com}"
CLIENT_ID="hytale-server"
SCOPES="openid offline auth:server"

# Token storage location
TOKEN_FILE="${HYTALE_TOKEN_FILE:-$HOME/.hytale-tokens.json}"

# ------------------------------------------------------
#                 Helper Functions
# ------------------------------------------------------
log_info() {
    printf "${CYAN}[INFO]${NC} %s\n" "$1"
}

log_success() {
    printf "${GREEN}[OK]${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1" >&2
}

log_warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1"
}

check_dependencies() {
    for cmd in curl jq; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "Required command '$cmd' not found. Please install it."
            exit 1
        fi
    done
}

save_tokens() {
    local access_token="$1"
    local refresh_token="$2"
    local expires_in="${3:-3600}"

    local expires_at
    expires_at=$(date -d "+${expires_in} seconds" +%s 2>/dev/null || date -v+${expires_in}S +%s 2>/dev/null || echo "0")

    jq -n \
        --arg at "$access_token" \
        --arg rt "$refresh_token" \
        --arg exp "$expires_at" \
        '{access_token: $at, refresh_token: $rt, expires_at: ($exp | tonumber)}' > "$TOKEN_FILE"

    chmod 600 "$TOKEN_FILE"
    log_success "Tokens saved to $TOKEN_FILE"
}

load_tokens() {
    if [ ! -f "$TOKEN_FILE" ]; then
        log_error "No token file found at $TOKEN_FILE"
        log_info "Run '$0 login' to authenticate first."
        exit 1
    fi

    cat "$TOKEN_FILE"
}

save_session() {
    local session_token="$1"
    local identity_token="$2"
    local profile_uuid="$3"
    local expires_at="$4"

    local tokens
    tokens=$(load_tokens)

    echo "$tokens" | jq \
        --arg st "$session_token" \
        --arg it "$identity_token" \
        --arg uuid "$profile_uuid" \
        --arg exp "$expires_at" \
        '. + {session_token: $st, identity_token: $it, profile_uuid: $uuid, session_expires_at: $exp}' > "$TOKEN_FILE"

    log_success "Session tokens saved"
}

# ------------------------------------------------------
#              Device Code Flow Login
# ------------------------------------------------------
do_login() {
    log_info "Starting device code authentication flow..."

    # Request device code
    local response
    response=$(curl -s -X POST "$OAUTH_BASE_URL/oauth2/device/auth" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=$CLIENT_ID" \
        -d "scope=$SCOPES")

    local device_code user_code verification_uri verification_uri_complete expires_in interval
    device_code=$(echo "$response" | jq -r '.device_code // empty')
    user_code=$(echo "$response" | jq -r '.user_code // empty')
    verification_uri=$(echo "$response" | jq -r '.verification_uri // empty')
    verification_uri_complete=$(echo "$response" | jq -r '.verification_uri_complete // empty')
    expires_in=$(echo "$response" | jq -r '.expires_in // 900')
    interval=$(echo "$response" | jq -r '.interval // 5')

    if [ -z "$device_code" ] || [ -z "$user_code" ]; then
        log_error "Failed to get device code. Response:"
        echo "$response" | jq .
        exit 1
    fi

    printf "\n"
    printf "${BOLD}═══════════════════════════════════════════════════════════${NC}\n"
    printf "${BOLD}              DEVICE AUTHORIZATION${NC}\n"
    printf "${BOLD}═══════════════════════════════════════════════════════════${NC}\n"
    printf "\n"
    printf "  Visit: ${CYAN}%s${NC}\n" "$verification_uri"
    printf "  Enter code: ${BOLD}${GREEN}%s${NC}\n" "$user_code"
    printf "\n"
    printf "  Or visit: ${CYAN}%s${NC}\n" "$verification_uri_complete"
    printf "\n"
    printf "${BOLD}═══════════════════════════════════════════════════════════${NC}\n"
    printf "\n"

    log_info "Waiting for authorization (expires in $expires_in seconds)..."

    # Poll for token
    local elapsed=0
    while [ "$elapsed" -lt "$expires_in" ]; do
        sleep "$interval"
        elapsed=$((elapsed + interval))

        response=$(curl -s -X POST "$OAUTH_BASE_URL/oauth2/token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "client_id=$CLIENT_ID" \
            -d "grant_type=urn:ietf:params:oauth:grant-type:device_code" \
            -d "device_code=$device_code")

        local error access_token refresh_token token_expires_in
        error=$(echo "$response" | jq -r '.error // empty')

        if [ "$error" = "authorization_pending" ]; then
            printf "."
            continue
        elif [ "$error" = "slow_down" ]; then
            interval=$((interval + 1))
            continue
        elif [ -n "$error" ]; then
            printf "\n"
            log_error "Authorization failed: $error"
            echo "$response" | jq -r '.error_description // empty'
            exit 1
        fi

        access_token=$(echo "$response" | jq -r '.access_token // empty')
        refresh_token=$(echo "$response" | jq -r '.refresh_token // empty')
        token_expires_in=$(echo "$response" | jq -r '.expires_in // 3600')

        if [ -n "$access_token" ]; then
            printf "\n"
            log_success "Authentication successful!"
            save_tokens "$access_token" "$refresh_token" "$token_expires_in"
            printf "\n"
            log_info "Next step: Run '$0 session' to create a game session"
            return 0
        fi
    done

    printf "\n"
    log_error "Authorization timed out. Please try again."
    exit 1
}

# ------------------------------------------------------
#              Refresh OAuth Token
# ------------------------------------------------------
do_refresh() {
    log_info "Refreshing OAuth tokens..."

    local tokens refresh_token
    tokens=$(load_tokens)
    refresh_token=$(echo "$tokens" | jq -r '.refresh_token // empty')

    if [ -z "$refresh_token" ]; then
        log_error "No refresh token found. Run '$0 login' first."
        exit 1
    fi

    local response
    response=$(curl -s -X POST "$OAUTH_BASE_URL/oauth2/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=$CLIENT_ID" \
        -d "grant_type=refresh_token" \
        -d "refresh_token=$refresh_token")

    local error access_token new_refresh_token expires_in
    error=$(echo "$response" | jq -r '.error // empty')

    if [ -n "$error" ]; then
        log_error "Token refresh failed: $error"
        echo "$response" | jq -r '.error_description // empty'
        exit 1
    fi

    access_token=$(echo "$response" | jq -r '.access_token // empty')
    new_refresh_token=$(echo "$response" | jq -r '.refresh_token // empty')
    expires_in=$(echo "$response" | jq -r '.expires_in // 3600')

    # Use new refresh token if provided, otherwise keep the old one
    if [ -z "$new_refresh_token" ]; then
        new_refresh_token="$refresh_token"
    fi

    save_tokens "$access_token" "$new_refresh_token" "$expires_in"
    log_success "Tokens refreshed successfully!"
}

# ------------------------------------------------------
#              Get Profiles
# ------------------------------------------------------
get_profiles() {
    local access_token="$1"

    local response
    response=$(curl -s -X GET "$ACCOUNT_DATA_URL/my-account/get-profiles" \
        -H "Authorization: Bearer $access_token")

    echo "$response"
}

# ------------------------------------------------------
#              Create Game Session
# ------------------------------------------------------
do_session() {
    log_info "Creating game session..."

    local tokens access_token
    tokens=$(load_tokens)
    access_token=$(echo "$tokens" | jq -r '.access_token // empty')

    if [ -z "$access_token" ]; then
        log_error "No access token found. Run '$0 login' first."
        exit 1
    fi

    # Check if token needs refresh
    local expires_at now
    expires_at=$(echo "$tokens" | jq -r '.expires_at // 0')
    now=$(date +%s)

    if [ "$expires_at" -le "$now" ]; then
        log_warn "Access token expired. Refreshing..."
        do_refresh
        tokens=$(load_tokens)
        access_token=$(echo "$tokens" | jq -r '.access_token // empty')
    fi

    # Get profiles
    log_info "Fetching available profiles..."
    local profiles_response profiles profile_uuid profile_username
    profiles_response=$(get_profiles "$access_token")

    profiles=$(echo "$profiles_response" | jq -r '.profiles // []')
    local profile_count
    profile_count=$(echo "$profiles" | jq 'length')

    if [ "$profile_count" -eq 0 ]; then
        log_error "No profiles found for this account."
        exit 1
    elif [ "$profile_count" -eq 1 ]; then
        profile_uuid=$(echo "$profiles" | jq -r '.[0].uuid')
        profile_username=$(echo "$profiles" | jq -r '.[0].username')
        log_info "Using profile: $profile_username ($profile_uuid)"
    else
        printf "\n${BOLD}Available profiles:${NC}\n"
        echo "$profiles" | jq -r 'to_entries | .[] | "  \(.key + 1). \(.value.username) (\(.value.uuid))"'
        printf "\nSelect profile number: "
        read -r selection
        selection=$((selection - 1))
        profile_uuid=$(echo "$profiles" | jq -r ".[$selection].uuid")
        profile_username=$(echo "$profiles" | jq -r ".[$selection].username")

        if [ -z "$profile_uuid" ] || [ "$profile_uuid" = "null" ]; then
            log_error "Invalid selection."
            exit 1
        fi

        log_info "Selected profile: $profile_username"
    fi

    # Create session
    log_info "Creating game session for profile..."
    local session_response session_token identity_token expires_at_str
    session_response=$(curl -s -X POST "$SESSIONS_BASE_URL/game-session/new" \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" \
        -d "{\"uuid\": \"$profile_uuid\"}")

    local error
    error=$(echo "$session_response" | jq -r '.error // empty')

    if [ -n "$error" ]; then
        log_error "Failed to create session: $error"
        echo "$session_response" | jq .
        exit 1
    fi

    session_token=$(echo "$session_response" | jq -r '.sessionToken // empty')
    identity_token=$(echo "$session_response" | jq -r '.identityToken // empty')
    expires_at_str=$(echo "$session_response" | jq -r '.expiresAt // empty')

    if [ -z "$session_token" ] || [ -z "$identity_token" ]; then
        log_error "Failed to get session tokens. Response:"
        echo "$session_response" | jq .
        exit 1
    fi

    save_session "$session_token" "$identity_token" "$profile_uuid" "$expires_at_str"

    printf "\n"
    log_success "Game session created successfully!"
    printf "\n"
    printf "${BOLD}Session expires at:${NC} %s\n" "$expires_at_str"
    printf "\n"
    log_info "Run '$0 env' to get environment variables for Docker"
}

# ------------------------------------------------------
#              Check Status
# ------------------------------------------------------
do_status() {
    if [ ! -f "$TOKEN_FILE" ]; then
        log_warn "Not authenticated. Run '$0 login' to authenticate."
        exit 0
    fi

    local tokens
    tokens=$(load_tokens)

    local access_token refresh_token session_token profile_uuid
    local oauth_expires session_expires
    access_token=$(echo "$tokens" | jq -r '.access_token // empty')
    refresh_token=$(echo "$tokens" | jq -r '.refresh_token // empty')
    session_token=$(echo "$tokens" | jq -r '.session_token // empty')
    profile_uuid=$(echo "$tokens" | jq -r '.profile_uuid // empty')
    oauth_expires=$(echo "$tokens" | jq -r '.expires_at // 0')
    session_expires=$(echo "$tokens" | jq -r '.session_expires_at // empty')

    local now
    now=$(date +%s)

    printf "\n${BOLD}═══════════════════════════════════════════════════════════${NC}\n"
    printf "${BOLD}              AUTHENTICATION STATUS${NC}\n"
    printf "${BOLD}═══════════════════════════════════════════════════════════${NC}\n\n"

    # OAuth Token Status
    printf "${BOLD}OAuth Access Token:${NC} "
    if [ -n "$access_token" ]; then
        if [ "$oauth_expires" -gt "$now" ]; then
            local remaining=$((oauth_expires - now))
            printf "${GREEN}Valid${NC} (expires in %d minutes)\n" "$((remaining / 60))"
        else
            printf "${RED}Expired${NC}\n"
        fi
    else
        printf "${DIM}Not set${NC}\n"
    fi

    printf "${BOLD}Refresh Token:${NC} "
    if [ -n "$refresh_token" ]; then
        printf "${GREEN}Available${NC}\n"
    else
        printf "${RED}Not available${NC}\n"
    fi

    # Session Token Status
    printf "\n${BOLD}Session Token:${NC} "
    if [ -n "$session_token" ]; then
        if [ -n "$session_expires" ]; then
            printf "${GREEN}Active${NC} (expires: %s)\n" "$session_expires"
        else
            printf "${GREEN}Active${NC}\n"
        fi
    else
        printf "${DIM}Not created${NC}\n"
    fi

    printf "${BOLD}Profile UUID:${NC} "
    if [ -n "$profile_uuid" ]; then
        printf "%s\n" "$profile_uuid"
    else
        printf "${DIM}Not selected${NC}\n"
    fi

    printf "\n${BOLD}═══════════════════════════════════════════════════════════${NC}\n\n"
}

# ------------------------------------------------------
#              Output Environment Variables
# ------------------------------------------------------
do_env() {
    if [ ! -f "$TOKEN_FILE" ]; then
        log_error "No tokens found. Run '$0 login' and '$0 session' first."
        exit 1
    fi

    local tokens session_token identity_token profile_uuid
    tokens=$(load_tokens)
    session_token=$(echo "$tokens" | jq -r '.session_token // empty')
    identity_token=$(echo "$tokens" | jq -r '.identity_token // empty')
    profile_uuid=$(echo "$tokens" | jq -r '.profile_uuid // empty')

    if [ -z "$session_token" ] || [ -z "$identity_token" ]; then
        log_error "No session tokens found. Run '$0 session' first."
        exit 1
    fi

    printf "\n${BOLD}# Add these to your docker-compose.yml or export them:${NC}\n\n"
    printf "HYTALE_SERVER_SESSION_TOKEN=%s\n" "$session_token"
    printf "HYTALE_SERVER_IDENTITY_TOKEN=%s\n" "$identity_token"

    if [ -n "$profile_uuid" ]; then
        printf "HYTALE_OWNER_UUID=%s\n" "$profile_uuid"
    fi

    printf "\n${BOLD}# Or use docker run:${NC}\n"
    printf "docker run -e HYTALE_SERVER_SESSION_TOKEN=\"...\" -e HYTALE_SERVER_IDENTITY_TOKEN=\"...\" ...\n\n"
}

# ------------------------------------------------------
#                   Main
# ------------------------------------------------------
main() {
    check_dependencies

    local command="${1:-help}"

    case "$command" in
        login)
            do_login
            ;;
        refresh)
            do_refresh
            ;;
        session)
            do_session
            ;;
        status)
            do_status
            ;;
        env)
            do_env
            ;;
        help|--help|-h)
            printf "\n${BOLD}Hytale Server Authentication Helper${NC}\n\n"
            printf "Usage: %s <command>\n\n" "$0"
            printf "Commands:\n"
            printf "  ${CYAN}login${NC}    - Start OAuth device code flow to authenticate\n"
            printf "  ${CYAN}refresh${NC}  - Refresh OAuth tokens\n"
            printf "  ${CYAN}session${NC}  - Create a new game session\n"
            printf "  ${CYAN}status${NC}   - Check current authentication status\n"
            printf "  ${CYAN}env${NC}      - Output tokens as environment variables\n"
            printf "  ${CYAN}help${NC}     - Show this help message\n\n"
            printf "Typical workflow:\n"
            printf "  1. %s login     # Authenticate with Hytale\n" "$0"
            printf "  2. %s session   # Create a game session\n" "$0"
            printf "  3. %s env       # Get env vars for Docker\n\n" "$0"
            ;;
        *)
            log_error "Unknown command: $command"
            printf "Run '%s help' for usage.\n" "$0"
            exit 1
            ;;
    esac
}

main "$@"
