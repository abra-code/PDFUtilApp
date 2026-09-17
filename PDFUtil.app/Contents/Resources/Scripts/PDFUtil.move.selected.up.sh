#!/bin/bash
# PDFUtil.move.selected.up.sh - Move the selected file one place up the list,
# which is the order Merge and Build PDF from Images take the files in

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.files.sh"

move_selected_file up
