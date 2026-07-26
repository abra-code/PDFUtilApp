#!/bin/bash
# PDFUtil.operation.changed.sh - Swap the visible settings panel
#
# Stage 2 stub. The Operation picker (id 60) already carries the full sectioned
# tag list, but no per-operation GroupBox exists inside the settings ZStack
# (id 199) yet. Stage 3 onward adds one GroupBox per operation and one `case`
# arm here, so this file grows across stages while the picker never changes.
#
# Pickers deliver the option's TAG, not its index, when options are declared as
# {"title": ..., "tag": ...} dictionaries - so $OMC_ACTIONUI_VIEW_60_VALUE is a
# string like "reduce". {"section": ...} entries carry no tag and are never
# delivered.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.sh"

operation="$OMC_ACTIONUI_VIEW_60_VALUE"
[ -z "$operation" ] && operation="reduce"

set_summary "Operation: ${operation}

Settings for this operation arrive in a later stage. The file list, Quick Look,
Reveal and Info all work now."
