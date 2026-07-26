#!/bin/bash
# PDFUtil.clear.all.sh - Clear all files from the table

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.sh"

"$dialog_tool" "$window_uuid" ${TABLE_ID} omc_table_remove_all_rows

"$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "PDFUtil.files.selection.changed"
