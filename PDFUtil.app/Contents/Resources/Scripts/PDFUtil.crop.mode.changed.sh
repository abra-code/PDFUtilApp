#!/bin/bash
# PDFUtil.crop.mode.changed.sh - Retitle the crop value field for the chosen mode
#
# --rect and --margins both take four comma-separated numbers, so the field
# cannot say what it wants without knowing the mode.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.sh"

apply_crop_mode_state
