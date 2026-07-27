#!/bin/bash
# PDFUtil.watermark.choose.image.sh - Pick the image to stamp
#
# ActionUI has no file-picker element, so the field is a plain TextField and
# this button supplies the path through CHOOSE_OBJECT_DIALOG. The field stays
# editable on purpose: a path can be pasted or cleared by hand, which is also
# the only way to go back to a text watermark after choosing an image.
#
# The value is written with the plain value form. omc_set_property "text" is
# accepted but does not repaint the control (the same trap the structure
# notices hit).

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.sh"

# Empty means the panel was cancelled. Leave the field alone in that case -
# clearing it would make Cancel destructive, which is the one thing a cancel
# button must never be.
if [ -n "$OMC_DLG_CHOOSE_OBJECT_PATH" ]; then
    # ALLOW_MULTIPLE_ITEMS is false, so this is one path; take the first line
    # defensively anyway, since a second one would land in the field verbatim
    # and become part of the path pdfutil is asked to open.
    chosen="$(printf '%s\n' "$OMC_DLG_CHOOSE_OBJECT_PATH" | /usr/bin/head -1)"
    "$dialog_tool" "$window_uuid" ${WM_IMAGE_ID} "$chosen"
fi
