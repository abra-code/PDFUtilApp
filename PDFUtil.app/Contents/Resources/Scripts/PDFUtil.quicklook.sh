#!/bin/bash
# PDFUtil.quicklook.sh - preview the selected file in a native Quick Look window.
# Runs in the main window context, so it reads the live table selection, hands the
# path to the Quick Look window's init via the private pasteboard, then opens the
# window (its ACTIONUI_WINDOW runs PDFUtil.quicklook.init).

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.sh"

selected_path="$OMC_ACTIONUI_TABLE_10_COLUMN_3_VALUE"

if [ -n "$selected_path" ] && [ -e "$selected_path" ]; then
    "$pasteboard_tool" "$QUICKLOOK_PB_KEY" put "$selected_path"
    "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "PDFUtil.quicklook.window"
else
    "$alert_tool" --level caution --title "PDFUtil" "File does not exist"
fi
