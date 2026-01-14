#!/bin/sh
set -eu

# ------------------------------------------------------
#               Load Dependencies
# ------------------------------------------------------
. "$SCRIPTS_PATH/utils.sh"

log_section "Hytale Downloader"

# ------------------------------------------------------
#             Server Installation Check
# ------------------------------------------------------
log_step "Hytale Server Binary Check"

if [ ! -f "$SERVER_JAR_PATH" ]; then
    log_warning "HytaleServer.jar not found at $SERVER_JAR_PATH." \
    "Initializing first-time installation/extraction..."

    # Find the downloaded zip
    ZIP_FILE=$(ls "$BASE_DIR"/2026.01*.zip 2>/dev/null | head -n 1)
    
    # ------------------------------------------------------
    #             Download Missing Package
    # ------------------------------------------------------
    if [ -z "$ZIP_FILE" ]; then
        log_step "Download Status"
        log_warning "No update package found. Running downloader..."
        hytale-downloader
        
        ZIP_FILE=$(ls "$BASE_DIR"/2026.01*.zip 2>/dev/null | head -n 1)
        
        if [ -z "$ZIP_FILE" ]; then
            log_error "Download failed." "Could not find a valid 2026.01*.zip after running downloader."
            exit 1
        fi
        log_success
    fi

    # ------------------------------------------------------
    #              Content Extraction
    # ------------------------------------------------------
    log_step "Extracting Game Content"
    # Replaced echo -e with printf for POSIX compatibility
    printf "      ${DIM}↳ Target:${NC} ${GREEN}%s${NC}\n" "$GAME_DIR"
    
    # x: eXtract with full paths
    # -aoa: Overwrite All existing files
    # -bsp1: Show progress percentage
    # -mmt=on: Full multi-core CPU performance
    # -o: Output directory
    if 7z x "$ZIP_FILE" -aoa -bsp1 -mmt=on -o"$GAME_DIR"; then
        log_success
    else
        log_error "Extraction failed" "Check disk space or 7z compatibility."
        exit 1
    fi

    # ------------------------------------------------------
    #                 Finalization
    # ------------------------------------------------------
    log_step "Post-Extraction Cleanup"
    rm -f "$ZIP_FILE"
    log_success
    
    chown -R container:container /home/container || log_warning "Chown failed" "User or group may not exist."

    log_step "File Permissions"
    if chmod -R 755 "$GAME_DIR"; then
        log_success
    else
        log_warning "Chmod failed" "Permissions might need manual adjustment."
    fi
else
    log_success
    printf "      ${DIM}↳ Info:${NC} HytaleServer.jar exists. Skipping extraction.\n"
fi