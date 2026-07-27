#!/bin/bash
# PDFUtil.watermark.mode.changed.sh - Match the controls to the watermark mode
#
# An annotation mark is text-only: pdfutil exits 1 when --image comes with
# --annotation, and accepts --rotate-mark and --under there only to ignore
# them. Both are settings that would not happen, so the toggle takes them out
# of play rather than leaving them live and inert.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.sh"

apply_watermark_mode_state
