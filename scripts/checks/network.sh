#!/bin/sh
set -eu

# ------------------------------------------------------
#               Load Dependencies
# ------------------------------------------------------
. "$SCRIPTS_PATH/utils.sh"
. "$SCRIPTS_PATH/checks/lib/network-logic.sh"

# ------------------------------------------------------
#                    Execute
# ------------------------------------------------------
log_section "Network Configuration Audit"
check_connectivity
validate_port_cfg
check_port_availability
check_udp_stack

# ------------------------------------------------------
#                    Complete
# ------------------------------------------------------
echo -e "\n${GREEN}${BOLD}✔ Network audit finished successfully.${NC}"
exit 0