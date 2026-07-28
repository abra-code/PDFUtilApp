#!/bin/bash
# PDFUtil.ocr.mode.changed.sh - Gray out the settings the searchable path drops
#
# "Embed a searchable text layer" is a different engine, not a variation: it
# hands the document to PDFKit's own OCR, which covers the whole document and
# picks its own recognition parameters. pdfutil refuses the language, speed,
# resolution and page-range flags alongside --searchable, so none of those
# controls may stay live in this mode.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.panels.sh"

apply_ocr_mode_state
