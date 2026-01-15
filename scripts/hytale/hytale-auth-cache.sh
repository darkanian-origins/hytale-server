#!/bin/sh
set -eu

# ------------------------------------------------------
#         Hytale Authentication with Token Caching
# ------------------------------------------------------
# Handles OAuth authentication with persistent token caching.
# Caches refresh_token + profile_uuid, generates fresh
# session tokens on each startup.
# ------------------------------------------------------

. "$SCRIPTS_PATH/utils.sh"

AUTH_CACHE_FILE="$BASE_DIR/.hytale-auth-cache.json"
# Verify BASE_DIR is writable
if [ ! -w "$BASE_DIR" ]; then
    log_warn "Warning: $BASE_DIR is not writable - cache will not persist"
fi
OAUTH_BASE_URL="https://oauth.accounts.hytale.com"
SESSIONS_URL="https://sessions.hytale.com"
ACCOUNT_DATA_URL="https://account-data.hytale.com"
CLIENT_ID="hytale-server"
SCOPES="openid offline auth:server"

# Initialize export variables
export HYTALE_SESSION_TOKEN_FLAG=""
export HYTALE_IDENTITY_TOKEN_FLAG=""
export HYTALE_OWNER_UUID_FLAG=""

# ------------------------------------------------------
#                 Helper Functions
# ------------------------------------------------------

check_cached_tokens() {
    if [ ! -f "$AUTH_CACHE_FILE" ]; then
        return 1
    fi

    # Validate JSON format
    if ! jq empty "$AUTH_CACHE_FILE" 2>/dev/null; then
        log_step "Invalid cache file, removing"
        rm -f "$AUTH_CACHE_FILE"
        printf "${YELLOW}removed${NC}\n"
        return 1
    fi

    # Check if required keys exist
    REFRESH_EXISTS=$(jq -r 'has("refresh_token")' "$AUTH_CACHE_FILE")
    PROFILE_EXISTS=$(jq -r 'has("profile_uuid")' "$AUTH_CACHE_FILE")

    if [ "$REFRESH_EXISTS" != "true" ] || [ "$PROFILE_EXISTS" != "true" ]; then
        log_step "Incomplete cache, removing"
        rm -f "$AUTH_CACHE_FILE"
        printf "${YELLOW}removed${NC}\n"
        return 1
    fi

    return 0
}

load_cached_tokens() {
    REFRESH_TOKEN=$(jq -r '.refresh_token' "$AUTH_CACHE_FILE")
    PROFILE_UUID=$(jq -r '.profile_uuid' "$AUTH_CACHE_FILE")

    if [ -z "$REFRESH_TOKEN" ] || [ "$REFRESH_TOKEN" = "null" ] || \
       [ -z "$PROFILE_UUID" ] || [ "$PROFILE_UUID" = "null" ]; then
        return 1
    fi

    return 0
}

save_auth_cache() {
    # Validate required variables
    if [ -z "$REFRESH_TOKEN" ] || [ "$REFRESH_TOKEN" = "null" ]; then
        printf "  ${RED}Error: REFRESH_TOKEN is empty, cannot save cache${NC}\n"
        return 1
    fi
    
    if [ -z "$PROFILE_UUID" ] || [ "$PROFILE_UUID" = "null" ]; then
        printf "  ${RED}Error: PROFILE_UUID is empty, cannot save cache${NC}\n"
        return 1
    fi
    
    printf "  Saving cache to: %s\n" "$AUTH_CACHE_FILE"
    
    # Create cache directory if it doesn't exist
    CACHE_DIR=$(dirname "$AUTH_CACHE_FILE")
    if [ ! -d "$CACHE_DIR" ]; then
        mkdir -p "$CACHE_DIR" || {
            printf "  ${RED}Failed to create cache directory${NC}\n"
            return 1
        }
    fi
    
    cat > "$AUTH_CACHE_FILE" << EOF
{
  "refresh_token": "$REFRESH_TOKEN",
  "profile_uuid": "$PROFILE_UUID",
  "timestamp": $(date +%s)
}
EOF
    
    if [ $? -eq 0 ]; then
        chmod 600 "$AUTH_CACHE_FILE"
        # Verify the file was created
        if [ -f "$AUTH_CACHE_FILE" ]; then
            printf "  ${GREEN}Cache saved successfully to: %s${NC}\n" "$AUTH_CACHE_FILE"
            return 0
        else
            printf "  ${RED}Cache file was not created${NC}\n"
            return 1
        fi
    else
        printf "  ${RED}Failed to write cache file${NC}\n"
        return 1
    fi
}


refresh_access_token() {
    TOKEN_RESPONSE=$(curl -s -X POST "$OAUTH_BASE_URL/oauth2/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=$CLIENT_ID" \
        -d "grant_type=refresh_token" \
        -d "refresh_token=$REFRESH_TOKEN")

    ERROR=$(echo "$TOKEN_RESPONSE" | jq -r '.error // empty')
    if [ -n "$ERROR" ]; then
        return 1
    fi

    ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
    NEW_REFRESH=$(echo "$TOKEN_RESPONSE" | jq -r '.refresh_token // empty')

    if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
        return 1
    fi

    # Update refresh token if rotated
    if [ -n "$NEW_REFRESH" ] && [ "$NEW_REFRESH" != "null" ]; then
        REFRESH_TOKEN="$NEW_REFRESH"
    fi

    return 0
}

create_game_session() {
    SESSION_RESPONSE=$(curl -s -X POST "$SESSIONS_URL/game-session/new" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"uuid\": \"$PROFILE_UUID\"}")

    if ! echo "$SESSION_RESPONSE" | jq empty 2>/dev/null; then
        return 1
    fi

    SESSION_TOKEN=$(echo "$SESSION_RESPONSE" | jq -r '.sessionToken')
    IDENTITY_TOKEN=$(echo "$SESSION_RESPONSE" | jq -r '.identityToken')

    if [ -z "$SESSION_TOKEN" ] || [ "$SESSION_TOKEN" = "null" ]; then
        return 1
    fi

    # Export as flags for server startup
    export HYTALE_SESSION_TOKEN_FLAG="--session-token $SESSION_TOKEN"
    export HYTALE_IDENTITY_TOKEN_FLAG="--identity-token $IDENTITY_TOKEN"
    export HYTALE_OWNER_UUID_FLAG="--owner-uuid $PROFILE_UUID"

    return 0
}

perform_device_auth() {
    log_step "Starting device auth"
    printf "${CYAN}pending${NC}\n"

    # Request device code
    AUTH_RESPONSE=$(curl -s -X POST "$OAUTH_BASE_URL/oauth2/device/auth" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=$CLIENT_ID" \
        -d "scope=$SCOPES")

    DEVICE_CODE=$(echo "$AUTH_RESPONSE" | jq -r '.device_code')
    USER_CODE=$(echo "$AUTH_RESPONSE" | jq -r '.user_code')
    VERIFICATION_URI=$(echo "$AUTH_RESPONSE" | jq -r '.verification_uri_complete')
    EXPIRES_IN=$(echo "$AUTH_RESPONSE" | jq -r '.expires_in // 900')
    POLL_INTERVAL=$(echo "$AUTH_RESPONSE" | jq -r '.interval // 5')

    if [ -z "$DEVICE_CODE" ] || [ "$DEVICE_CODE" = "null" ]; then
        printf "      ${RED}Failed to get device code${NC}\n"
        return 1
    fi

    # Display auth prompt
    printf "\n"
    printf "${BOLD}════════════════════════════════════════════════════════════════${NC}\n"
    printf "${BOLD}              HYTALE SERVER AUTHENTICATION REQUIRED${NC}\n"
    printf "${BOLD}════════════════════════════════════════════════════════════════${NC}\n"
    printf "\n"
    printf "  Visit: ${CYAN}%s${NC}\n" "$VERIFICATION_URI"
    printf "\n"
    printf "  Or go to: ${CYAN}https://accounts.hytale.com/device${NC}\n"
    printf "  And enter: ${BOLD}${GREEN}%s${NC}\n" "$USER_CODE"
    printf "\n"
    printf "${BOLD}════════════════════════════════════════════════════════════════${NC}\n"
    printf "\n"
    printf "  Waiting for authentication (expires in %d seconds)...\n" "$EXPIRES_IN"

    # Poll for token
    ELAPSED=0
    while [ "$ELAPSED" -lt "$EXPIRES_IN" ]; do
        sleep "$POLL_INTERVAL"
        ELAPSED=$((ELAPSED + POLL_INTERVAL))

        TOKEN_RESPONSE=$(curl -s -X POST "$OAUTH_BASE_URL/oauth2/token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "client_id=$CLIENT_ID" \
            -d "grant_type=urn:ietf:params:oauth:grant-type:device_code" \
            -d "device_code=$DEVICE_CODE")

        ERROR=$(echo "$TOKEN_RESPONSE" | jq -r '.error // empty')

        if [ "$ERROR" = "authorization_pending" ]; then
            printf "."
            continue
        elif [ "$ERROR" = "slow_down" ]; then
            POLL_INTERVAL=$((POLL_INTERVAL + 1))
            continue
        elif [ -n "$ERROR" ]; then
            printf "\n  ${RED}Authentication failed: %s${NC}\n" "$ERROR"
            return 1
        fi

        ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
        REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.refresh_token')

        if [ -n "$ACCESS_TOKEN" ] && [ "$ACCESS_TOKEN" != "null" ]; then
            printf "\n\n  ${GREEN}Authentication successful!${NC}\n\n"
            break
        fi
    done

    if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
        printf "\n  ${RED}Authentication timed out${NC}\n"
        return 1
    fi

    # Get profiles
    printf "  Fetching game profiles...\n"
    PROFILES_RESPONSE=$(curl -s -X GET "$ACCOUNT_DATA_URL/my-account/get-profiles" \
        -H "Authorization: Bearer $ACCESS_TOKEN")

    PROFILES_COUNT=$(echo "$PROFILES_RESPONSE" | jq '.profiles | length')

    if [ "$PROFILES_COUNT" -eq 0 ]; then
        printf "  ${RED}No game profiles found. You need to purchase Hytale.${NC}\n"
        return 1
    fi

    # Use first profile or specified one
    if [ -n "${HYTALE_PROFILE:-}" ]; then
        PROFILE_UUID=$(echo "$PROFILES_RESPONSE" | jq -r ".profiles[] | select(.username == \"$HYTALE_PROFILE\") | .uuid")
        if [ -z "$PROFILE_UUID" ] || [ "$PROFILE_UUID" = "null" ]; then
            printf "  ${RED}Profile '%s' not found${NC}\n" "$HYTALE_PROFILE"
            printf "  Available profiles:\n"
            echo "$PROFILES_RESPONSE" | jq -r '.profiles[] | "    - \(.username)"'
            return 1
        fi
        printf "  Using profile: %s\n" "$HYTALE_PROFILE"
    else
        PROFILE_UUID=$(echo "$PROFILES_RESPONSE" | jq -r '.profiles[0].uuid')
        PROFILE_NAME=$(echo "$PROFILES_RESPONSE" | jq -r '.profiles[0].username')
        printf "  Using profile: %s\n" "$PROFILE_NAME"
    fi

    # Validate variables before saving
if [ -z "$PROFILE_UUID" ] || [ "$PROFILE_UUID" = "null" ]; then
    printf "  ${RED}Could not determine profile UUID${NC}\n"
    return 1
fi

if [ -z "$REFRESH_TOKEN" ] || [ "$REFRESH_TOKEN" = "null" ]; then
    printf "  ${RED}Could not get refresh token${NC}\n"
    return 1
fi

    # Save cache
    save_auth_cache
    printf "  ${GREEN}Credentials cached for future restarts${NC}\n\n"

    return 0
}

# ------------------------------------------------------
#                     Main Logic
# ------------------------------------------------------

log_section "Authentication"

AUTH_SUCCESS=0

# Check if tokens are passed directly via environment
if [ -n "${HYTALE_SERVER_SESSION_TOKEN:-}" ] && [ -n "${HYTALE_SERVER_IDENTITY_TOKEN:-}" ]; then
    log_step "Token Auth"
    export HYTALE_SESSION_TOKEN_FLAG="--session-token $HYTALE_SERVER_SESSION_TOKEN"
    export HYTALE_IDENTITY_TOKEN_FLAG="--identity-token $HYTALE_SERVER_IDENTITY_TOKEN"
    if [ -n "${HYTALE_OWNER_UUID:-}" ]; then
        export HYTALE_OWNER_UUID_FLAG="--owner-uuid $HYTALE_OWNER_UUID"
    fi
    log_success
    AUTH_SUCCESS=1
fi

# Try cached authentication
if check_cached_tokens; then
    log_step "Loading cache"
    if load_cached_tokens; then
        log_success

        log_step "Refreshing token"
        if refresh_access_token; then
            log_success

            # Update cache in case token rotated
            save_auth_cache

            log_step "Creating session"
            if create_game_session; then
                log_success
                AUTH_SUCCESS=1
            else
                printf "${RED}failed${NC}\n"
            fi
        else
            printf "${YELLOW}expired${NC}\n"
        fi

        if [ "$AUTH_SUCCESS" = "0" ]; then
            # Cache refresh failed, need full re-auth
            log_step "Cache expired"
            printf "${YELLOW}re-authenticating${NC}\n"
            rm -f "$AUTH_CACHE_FILE"
        fi
    else
        printf "${RED}invalid${NC}\n"
    fi
fi

# Perform full device authentication if needed
if [ "$AUTH_SUCCESS" = "0" ]; then
    if perform_device_auth; then
        log_step "Creating session"
        if create_game_session; then
            log_success
        else
            printf "${RED}failed${NC}\n"
            printf "\n${RED}Authentication failed. Server will start without auth.${NC}\n"
            printf "${YELLOW}You can authenticate via console: /auth login device${NC}\n\n"
        fi
    else
        printf "\n${YELLOW}Authentication skipped. Use /auth login device in console.${NC}\n\n"
    fi
fi
