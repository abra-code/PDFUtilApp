#!/bin/bash
# PDFUtil.files.double.click.sh - Open the double-clicked file in the default viewer

selected_path="$OMC_ACTIONUI_TABLE_10_COLUMN_3_VALUE"

if [ -n "$selected_path" ] && [ -e "$selected_path" ]; then
    /usr/bin/open "$selected_path"
fi
