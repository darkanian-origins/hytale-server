#!/bin/sh
set -eu

# ------------------------------------------------------
#               Load Dependencies
# ------------------------------------------------------
. "$SCRIPTS_PATH/utils.sh"
. "$SCRIPTS_PATH/checks/lib/security-logic.sh"

# ------------------------------------------------------
#                    Execute
# ------------------------------------------------------
log_section "Security & Integrity Audit"
check_integrity
check_container_hardening
check_clock_sync

echo -e "\n${BOLD}${GREEN}✔ Security audit finished.${NC}"
exit 0