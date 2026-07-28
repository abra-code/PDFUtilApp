#!/bin/bash
# PDFUtil.split.mode.changed.sh - Gray out the pages-per-part field for chapters
#
# --chapters and --every are alternatives, and pdfutil takes --every when both
# arrive. A live field whose value is about to be ignored is worse than a
# disabled one.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.panels.sh"

apply_split_mode_state
