#!/bin/bash
# PDFUtil.watermark.mode.changed.sh - Match the controls to the watermark mode
#
# An annotation mark is text-only and axis-aligned: pdfutil exits 1 when
# --image, --rotate-mark or --under comes with --annotation. The toggle takes
# all three out of play so none of them can reach the builder.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.sh"

apply_watermark_mode_state
