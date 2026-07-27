#!/bin/bash
# PDFUtil.run.image.sh - One PDF page in, one image out, through a Save As panel
#
# Reached only when the page range resolves to a single page, which is the case
# where render writes one literal file rather than a numbered series.
#
# The Save panel's default name ends in .png, but the format picker may say
# otherwise; ensure_output_extension replaces the suffix with the one the chosen
# format actually writes. pdfutil appends nothing here, so that suffix is the
# app's responsibility - without it the user gets an extensionless file macOS
# cannot open by double-click.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.args.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.run.sh"

run_save_as
