#!/bin/bash
# PDFUtil.render.format.changed.sh - Keep the render controls honest
#
# --quality is meaningful only for the lossy formats, and --transparent is a
# usage error for jpeg. Rather than accepting a value pdfutil will drop or
# reject, the format picker disables the controls it does not apply to.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.panels.sh"

apply_render_format_state
