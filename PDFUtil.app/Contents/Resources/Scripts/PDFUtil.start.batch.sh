#!/bin/bash
# PDFUtil.start.batch.sh - Validate, then route to the right runner
#
# Stage 2 stub. Stage 3 turns this into the router described in the plan
# (branch on operation x input count x output kind, then chain with
# omc_next_command). For now it only proves the button is wired and the file
# list is readable from this command - which is exactly what the
# ENVIRONMENT_VARIABLES declaration on PDFUtil.start.batch buys.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.sh"

operation="$OMC_ACTIONUI_VIEW_60_VALUE"
[ -z "$operation" ] && operation="reduce"

all_paths="$OMC_ACTIONUI_TABLE_10_COLUMN_3_ALL_ROWS"

if [ -z "$all_paths" ]; then
    "$alert_tool" --level caution --title "PDFUtil" \
        "Add at least one file to the list first."
    exit 0
fi

file_count="$(printf '%s\n' "$all_paths" | /usr/bin/grep -c .)"

set_summary "Operation: ${operation}
Files: ${file_count}

Running operations arrives in a later stage."
