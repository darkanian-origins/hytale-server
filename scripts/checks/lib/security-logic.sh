#!/bin/sh

# ------------------------------------------------------
#               Load Dependencies
# ------------------------------------------------------
. "${SCRIPTS_PATH:-.}/utils.sh"

# ------------------------------------------------------
#             File System Integrity
# ------------------------------------------------------
check_integrity() {
    log_step "File System Integrity"
    
    if [ -f "${SERVER_JAR_PATH:-}" ]; then
        local perms
        perms=$(stat -c "%a" "$SERVER_JAR_PATH")
        
        if [ "$perms" != "444" ]; then
            log_warning "Insecure JAR permissions ($perms)." "Fixing to Read-Only (444) for protection."
            chmod 444 "$SERVER_JAR_PATH"
        else
            log_success
        fi
    else
        log_error "Server JAR missing!" "Expected at: $SERVER_JAR_PATH"
        exit 1
    fi
}

# ------------------------------------------------------
#            Container Hardening Checks
# ------------------------------------------------------
check_container_hardening() {
    # Privileges check
    log_step "Process Privileges"
    if grep -q "NoNewPrivs:.*1" /proc/self/status 2>/dev/null; then
        log_success
    else
        log_warning "NoNewPrivs disabled." "Container could allow privilege escalation. Use --security-opt=no-new-privileges."
    fi

    # Kernel Capabilities
    log_step "Kernel Capabilities"
    local cap_eff
    cap_eff=$(grep "CapEff:" /proc/self/status | awk '{print $2}' || echo "unknown")
    if [ "$cap_eff" = "0000000000000000" ]; then
        log_success
    else
        log_warning "Extra capabilities found." "Process has kernel caps ($cap_eff). Consider 'cap_drop: ALL'."
    fi

    # User Identity Check
    log_step "Non-Root Enforcement"
    if [ "$(id -u)" = "0" ]; then
        log_error "Running as ROOT!" "Game servers should never run as root. Set 'user: 1000:1000' in Docker Compose."
        exit 1
    else
        log_success
    fi
}

# ------------------------------------------------------
#              Network Time Sync
# ------------------------------------------------------
check_clock_sync() {
    log_step "Network Time Sync"
    
    # Extract date from header safely
    local http_date
    http_date=$(curl -sI --connect-timeout 3 https://google.com | grep -i '^date:' | cut -d' ' -f2-7 || echo "")
    
    if [ -n "$http_date" ]; then
        local container_now network_now diff abs_diff
        container_now=$(date +%s)
        network_now=$(date -d "$http_date" +%s)
        diff=$((container_now - network_now))
        abs_diff=${diff#-} # Absolute value
        
        if [ "$abs_diff" -gt 60 ]; then
            log_error "Clock drift detected!" "Container is off by ${abs_diff}s. This causes SSL and Auth failures."
            exit 1
        else
            log_success
            echo -e "      ${DIM}↳ Drift: ${abs_diff}s (within acceptable limits)${NC}"
        fi
    else
        log_warning "Time check skipped." "Could not reach Google to verify network time."
    fi
}