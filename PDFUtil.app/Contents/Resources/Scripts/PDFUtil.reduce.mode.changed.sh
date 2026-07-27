#!/bin/bash
# PDFUtil.reduce.mode.changed.sh - Grey out the settings grayscale mode replaces
#
# "Convert to grayscale" selects the system Gray Tone filter, which pdfutil
# builds INSTEAD of the recompression filter, so quality, resolution and
# max-edge have nothing to act on. pdfutil refuses the combination outright, so
# leaving the three controls live would offer settings that cannot be sent.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.sh"

apply_reduce_mode_state
