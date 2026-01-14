#!/bin/sh
set -eu

# ------------------------------------------------------
#               Load Dependencies
# ------------------------------------------------------
. "$SCRIPTS_PATH/utils.sh"
. "$SCRIPTS_PATH/checks/lib/prod-logic.sh"

# ------------------------------------------------------
#                    Execute
# ------------------------------------------------------
log_section "Production Readiness Audit"
check_java_mem
check_system_resources
check_filesystem
check_stability

echo -e "\n${BOLD}${GREEN}✔ Production readiness checks finished.${NC}"
exit 0