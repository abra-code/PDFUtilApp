#!/bin/bash
# PDFUtil.remove.selected.sh - Remove the selected file from the table

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.files.sh"

selected_path="$OMC_ACTIONUI_TABLE_10_COLUMN_3_VALUE"

if [ -n "$selected_path" ]; then
    all_paths="$OMC_ACTIONUI_TABLE_10_COLUMN_3_ALL_ROWS"

    # The [ -e ] guard mirrors add_files_to_table: rows arrive newline-joined,
    # so a half-path left by a filename containing a newline drops out here
    # instead of being re-emitted forever.
    buffer=""
    while IFS= read -r file_path; do
        if [ -n "$file_path" ] && [ -e "$file_path" ] && [ "$file_path" != "$selected_path" ]; then
            buffer="${buffer}$(row_for_path "$file_path")
"
        fi
    done <<< "$all_paths"

    if [ -n "$buffer" ]; then
        # Not sorted: the rest of the list keeps the order the user gave it.
        printf "%s" "$buffer" | "$dialog_tool" "$window_uuid" ${TABLE_ID} omc_table_set_rows_from_stdin
    else
        "$dialog_tool" "$window_uuid" ${TABLE_ID} omc_table_remove_all_rows
    fi
fi

"$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "PDFUtil.files.selection.changed"
