#!/bin/bash
# PDFUtil.operation.changed.sh - Swap the visible settings panel
#
# Pickers deliver the option's TAG, not its index, when options are declared as
# {"title": ..., "tag": ...} dictionaries - so $OMC_ACTIONUI_VIEW_60_VALUE is a
# string like "reduce". {"section": ...} entries carry no tag and are never
# delivered.
#
# The switching itself lives in apply_operation_panel, because PDFUtil.init
# needs the same work done for the picker's initial value: a picker fires no
# action for the selection it starts with, so without that call the first panel
# would come up with an empty structure notice.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.panels.sh"

apply_operation_panel "$(current_operation)"
