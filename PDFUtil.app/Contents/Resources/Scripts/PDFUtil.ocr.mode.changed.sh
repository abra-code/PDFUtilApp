#!/bin/bash
# PDFUtil.ocr.mode.changed.sh - Grey out the settings the searchable path drops
#
# "Embed a searchable text layer" is a different engine, not a variation: it
# hands the document to PDFKit's own OCR, where the language, speed, resolution
# and page-range settings are all accepted and then ignored.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.sh"

apply_ocr_mode_state
