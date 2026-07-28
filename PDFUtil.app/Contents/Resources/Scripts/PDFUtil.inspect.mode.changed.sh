#!/bin/bash
# PDFUtil.inspect.mode.changed.sh - Show the query field only for Search
#
# Document info, Outline and Form fields take no argument, so the query box is
# hidden rather than greyed out for them: a disabled field still suggests there
# is something to switch on, and here there is not.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.panels.sh"

apply_inspect_mode_state
