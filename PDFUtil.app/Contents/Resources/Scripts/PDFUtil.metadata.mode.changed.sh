#!/bin/bash
# PDFUtil.metadata.mode.changed.sh - Grey out the fields stripping would discard
#
# "Remove all metadata" clears every attribute, so a value typed into a field
# alongside it is a value the user asked to set and delete in the same run.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.panels.sh"

apply_metadata_mode_state
