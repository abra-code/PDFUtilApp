#!/bin/bash
# PDFUtil.run.single.sh - One PDF in, one PDF out, through a Save As panel
#
# Reached from PDFUtil.start.batch when the list holds exactly one file and the
# operation produces a PDF. SAVE_AS_DIALOG has already asked for the output
# path; the work is in run_save_as, which the .txt and image runners share.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.sh"

run_save_as
