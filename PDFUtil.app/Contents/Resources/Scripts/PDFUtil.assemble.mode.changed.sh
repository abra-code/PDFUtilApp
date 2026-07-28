#!/bin/bash
# PDFUtil.assemble.mode.changed.sh - Build PDF from Images: page-sizing picker
#
# Shows the one row the chosen mode uses and hides the other. The work is in
# apply_assemble_mode_state, because apply_operation_panel has to run the same
# logic when the panel first appears: a Picker fires no action for its initial
# value, so without that call the panel would open showing whichever rows the
# JSON happened to declare visible.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.panels.sh"

apply_assemble_mode_state
