#!/bin/bash
# PDFUtil.add.files.sh - Add files via the file picker

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.files.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.panels.sh"

# Files selected via CHOOSE_OBJECT_DIALOG arrive in OMC_DLG_CHOOSE_OBJECT_PATH
if [ -n "$OMC_DLG_CHOOSE_OBJECT_PATH" ]; then
    add_files_to_table "$OMC_DLG_CHOOSE_OBJECT_PATH"
    refresh_decrypt_panel "$LIST_PATHS"
fi

select_first_or_resync
