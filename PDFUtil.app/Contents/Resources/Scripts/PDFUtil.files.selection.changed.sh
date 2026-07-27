#!/bin/bash
# PDFUtil.files.selection.changed.sh - Handle file selection changes

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.files.sh"

# Table column 1 is the type badge, 2 the display name, 3 the full path
# (hidden). This handler fires on a real user selection, so the live table
# value is current here.
apply_file_selection "$OMC_ACTIONUI_TABLE_10_COLUMN_3_VALUE"
