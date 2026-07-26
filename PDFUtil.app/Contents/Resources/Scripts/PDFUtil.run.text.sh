#!/bin/bash
# PDFUtil.run.text.sh - One PDF in, one .txt out, through a Save As panel
#
# Identical to PDFUtil.run.single apart from the Save panel's default file name,
# which is declared in Command.json rather than here - that is the whole reason
# text needs its own command instead of a flag on the PDF runner.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.sh"

run_save_as
