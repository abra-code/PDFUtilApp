#!/bin/bash
# PDFUtil.init.sh - Initialize the window

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.sh"

# Start with an empty file list
"$dialog_tool" "$window_uuid" ${TABLE_ID} omc_table_remove_all_rows

pdfutil_version="$("$PDFUTIL" --version 2>/dev/null | /usr/bin/head -1)"
set_summary "Drop PDF files or images into the list, pick an operation, then press Save.

Engine: ${pdfutil_version:-pdfutil (missing!)}"

# Seed the file list: from objects dropped on the app icon, or from the
# Open... panel selection handed off via the private pasteboard
if [ -n "$OMC_OBJ_PATH" ]; then
    add_files_to_table "$OMC_OBJ_PATH"
    select_first_or_resync
else
    open_paths="$("$pasteboard_tool" "$OPEN_PATHS_PB_KEY" get)"
    if [ -n "$open_paths" ]; then
        "$pasteboard_tool" "$OPEN_PATHS_PB_KEY" set ""
        add_files_to_table "$open_paths"
        select_first_or_resync
    fi
fi
