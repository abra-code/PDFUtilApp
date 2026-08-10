#!/bin/bash
# lib.PDFUtil.panels.sh - the settings panel switcher
#
# Which GroupBox is visible for the chosen operation, the per-section structure
# notice text, and the mode toggles that gray out controls their mode cannot use.
#
# Sourced by: PDFUtil.init, .operation.changed, every *.mode.changed handler,
# .render.format.changed, and the many-to-one runners (.run.merge, .run.assemble)
# Requires lib.PDFUtil.sh (tool paths, control IDs, primitives) to be
# sourced first; every handler that needs this one sources both, in order.
#
# Runs under /bin/sh (macOS bash 3.2 in POSIX mode): no process substitution,
# no mapfile, no declare -A, no ${var,,}. Validate with `sh -n`, never `bash -n`.

# Echo the structure notice for an operation ("" when it has none).
structure_notice() {
    case "$1" in
        reduce)
            echo "Redraws pages: annotations, links, the outline and form fields are lost."
            ;;
        gray)
            echo "Redraws pages: annotations, links, the outline and form fields are lost. Color is discarded, not recoverable."
            ;;
        linearize)
            echo "Redraws pages: annotations, links, the outline and form fields are lost. QuickPDF linearizes without that loss."
            ;;
        pdfa)
            echo "Redraws pages: annotations, links, the outline and form fields are lost. Tagged PDF/A-2B, conformance unverified - check with veraPDF."
            ;;
        render)
            echo "Text stops being selectable. Use a higher DPI for anything read on screen."
            ;;
        text)
            echo "Extracts an existing text layer. Scans have none - use OCR for those."
            ;;
        ocr)
            echo "Reads pages as pictures, so recognition is never perfect. The searchable-PDF mode uses a different engine, so the settings above do not apply to it."
            ;;
        encrypt)
            echo "128-bit AES, ASCII passwords, first 32 characters only. QuickPDF does 256-bit. Permissions bind only readers who open with the user password."
            ;;
        decrypt)
            echo "Saves an unlocked copy; the original is untouched."
            ;;
        extract)
            echo "Keeps the listed pages in the listed order, so repeats and reordering work. The outline is not carried over."
            ;;
        delete)
            echo "Keeps the outline, so entries pointing at removed pages may dangle."
            ;;
        rotate)
            echo "Lossless. Degrees are added to the current rotation, not set - 90 twice gives 180."
            ;;
        crop)
            echo "Lossless: only the page box changes, so cropped-away content is hidden rather than removed."
            ;;
        split)
            echo "Each part keeps its pages' annotations and links. The outline is not carried into the parts."
            ;;
        merge)
            echo "Joined in list order. Page-level structure is kept; outlines are not merged."
            ;;
        watermark)
            echo "Burning in redraws pages and loses annotations, links, the outline and form fields. Annotation mode keeps them but is text-only."
            ;;
        flatten)
            echo "Fields and annotations are painted into the page and removed. The outline survives; nothing stays editable."
            ;;
        frompages)
            echo "Images become pages in list order; one page per frame for animated GIF or multi-page TIFF. A PDF in the list is redrawn - use Merge to combine PDFs."
            ;;
        metadata)
            echo "Keeps the document's structure. PDFKit resets Producer and both dates on every save regardless."
            ;;
        *)
            echo ""
            ;;
    esac
}

# Echo the id of the Text element that displays the notice for an operation,
# or "" when that section has no notice element.
notice_id_for_operation() {
    case "$1" in
        reduce)  echo ${NOTICE_REDUCE_ID} ;;
        render)  echo ${NOTICE_RENDER_ID} ;;
        text)    echo ${NOTICE_TEXT_ID} ;;
        encrypt) echo ${NOTICE_ENCRYPT_ID} ;;
        decrypt) echo ${NOTICE_DECRYPT_ID} ;;
        extract) echo ${NOTICE_EXTRACT_ID} ;;
        delete)  echo ${NOTICE_DELETE_ID} ;;
        rotate)  echo ${NOTICE_ROTATE_ID} ;;
        crop)    echo ${NOTICE_CROP_ID} ;;
        split)   echo ${NOTICE_SPLIT_ID} ;;
        merge)   echo ${NOTICE_MERGE_ID} ;;
        ocr)       echo ${NOTICE_OCR_ID} ;;
        watermark) echo ${NOTICE_WATERMARK_ID} ;;
        flatten)   echo ${NOTICE_FLATTEN_ID} ;;
        frompages) echo ${NOTICE_FROMPAGES_ID} ;;
        metadata)  echo ${NOTICE_METADATA_ID} ;;
        linearize) echo ${NOTICE_LINEARIZE_ID} ;;
        pdfa)      echo ${NOTICE_PDFA_ID} ;;
        gray)      echo ${NOTICE_GRAY_ID} ;;
        *)       echo "" ;;
    esac
}

# Echo the id of the settings panel for an operation, falling back to the
# placeholder for the operations later stages still have to build.
panel_for_operation() {
    case "$1" in
        reduce)  echo ${GROUP_REDUCE_ID} ;;
        render)  echo ${GROUP_RENDER_ID} ;;
        text)    echo ${GROUP_TEXT_ID} ;;
        encrypt) echo ${GROUP_ENCRYPT_ID} ;;
        decrypt) echo ${GROUP_DECRYPT_ID} ;;
        extract) echo ${GROUP_EXTRACT_ID} ;;
        delete)  echo ${GROUP_DELETE_ID} ;;
        rotate)  echo ${GROUP_ROTATE_ID} ;;
        crop)    echo ${GROUP_CROP_ID} ;;
        split)   echo ${GROUP_SPLIT_ID} ;;
        merge)   echo ${GROUP_MERGE_ID} ;;
        ocr)       echo ${GROUP_OCR_ID} ;;
        watermark) echo ${GROUP_WATERMARK_ID} ;;
        flatten)   echo ${GROUP_FLATTEN_ID} ;;
        frompages) echo ${GROUP_FROMPAGES_ID} ;;
        metadata)  echo ${GROUP_METADATA_ID} ;;
        linearize) echo ${GROUP_LINEARIZE_ID} ;;
        pdfa)      echo ${GROUP_PDFA_ID} ;;
        gray)      echo ${GROUP_GRAY_ID} ;;
        *)       echo ${GROUP_PLACEHOLDER_ID} ;;
    esac
}

# Enable exactly the render controls the chosen image format supports.
#
# --quality applies to the lossy formats only, and --transparent is rejected
# outright for jpeg (pdfutil exits 1). Leaving a control live that the verb will
# refuse invites the user to set a value that is then either dropped or turned
# into a usage error, so the format picker drives their enabled state here and
# apply_operation_panel calls this when the panel first appears.
apply_render_format_state() {
    local fmt="$(render_format)"

    case "$fmt" in
        jpeg | heic) "$dialog_tool" "$window_uuid" ${RND_QUALITY_ID} omc_enable ;;
        *)           "$dialog_tool" "$window_uuid" ${RND_QUALITY_ID} omc_disable ;;
    esac

    if [ "$fmt" = "jpeg" ]; then
        "$dialog_tool" "$window_uuid" ${RND_TRANSPARENT_ID} omc_disable
    else
        "$dialog_tool" "$window_uuid" ${RND_TRANSPARENT_ID} omc_enable
    fi
}

# Enable the crop value field's companions for the chosen mode.
#
# --rect and --margins both take four comma-separated numbers but mean opposite
# things, so the prompt has to say which one is being typed. Called when the
# mode picker changes and when the panel first appears.
apply_crop_mode_state() {
    if [ "$OMC_ACTIONUI_VIEW_185_VALUE" = "rect" ]; then
        "$dialog_tool" "$window_uuid" ${CROP_VALUES_ID} \
            omc_set_property "prompt" "X,Y,W,H in points from the bottom-left"
        # --rect is absolute against the media box, so --box picks which box to
        # write, not which box to measure from. Leave it live either way.
    else
        "$dialog_tool" "$window_uuid" ${CROP_VALUES_ID} \
            omc_set_property "prompt" "left,bottom,right,top margins in points"
    fi
}

# Enable exactly the split controls the chosen mode uses. --chapters and --every
# are alternatives and pdfutil rejects the pair outright ("--every and --chapters
# are mutually exclusive", exit 1 - re-measured, an earlier note here claimed it
# silently preferred --every), so the UI must never let both reach the builder.
apply_split_mode_state() {
    if [ "$OMC_ACTIONUI_VIEW_151_VALUE" = "true" ]; then
        "$dialog_tool" "$window_uuid" ${SPLIT_EVERY_ID} omc_disable
    else
        "$dialog_tool" "$window_uuid" ${SPLIT_EVERY_ID} omc_enable
    fi
}

# Show the one row the chosen page-sizing mode actually uses.
#
# Hidden rather than disabled: a
# grayed-out paper picker reads as something there is a way to switch on, and
# here there is not - picking the other mode IS the switch. "From each image's
# DPI" needs no row at all, so both are hidden.
apply_assemble_mode_state() {
    local mode="$(assemble_mode)"
    local paper=omc_hide dpi=omc_hide
    case "$mode" in
        fit) paper=omc_show ;;
        dpi) dpi=omc_show ;;
    esac
    "$dialog_tool" "$window_uuid" ${FP_PAGE_SIZE_ROW_ID} "$paper"
    "$dialog_tool" "$window_uuid" ${FP_DPI_ROW_ID} "$dpi"
}

# Switch off the metadata fields that stripping makes meaningless.
#
# --strip removes every attribute, so a --set alongside it would be a value the
# user typed and then asked to have deleted. pdfutil accepts the pair and keeps
# the set value regardless of argument order (--strip is a starting condition,
# not an ordered step), so the result of ticking the box with fields filled in
# would be "removed all metadata except this one" - not what the box says. The
# panel takes the fields out of play instead.
apply_metadata_mode_state() {
    local state=omc_enable
    [ "$OMC_ACTIONUI_VIEW_195_VALUE" = "true" ] && state=omc_disable

    "$dialog_tool" "$window_uuid" ${META_TITLE_ID} "$state"
    "$dialog_tool" "$window_uuid" ${META_AUTHOR_ID} "$state"
    "$dialog_tool" "$window_uuid" ${META_SUBJECT_ID} "$state"
    "$dialog_tool" "$window_uuid" ${META_KEYWORDS_ID} "$state"
    "$dialog_tool" "$window_uuid" ${META_CREATOR_ID} "$state"
}

# Switch off the OCR controls the searchable path cannot use.
#
# All four, not the three the help used to name: -p does not apply there either
# (measured - see the id block above). pdfutil refuses all four alongside
# --searchable, so a live control here would offer a setting that cannot even be
# sent; before that fix it was worse still, silently doing nothing while the
# output read as evidence the setting had been honored.
apply_ocr_mode_state() {
    local state=omc_enable
    [ "$OMC_ACTIONUI_VIEW_183_VALUE" = "true" ] && state=omc_disable

    "$dialog_tool" "$window_uuid" ${OCR_LANG_ID} "$state"
    "$dialog_tool" "$window_uuid" ${OCR_FAST_ID} "$state"
    "$dialog_tool" "$window_uuid" ${OCR_DPI_ID} "$state"
    "$dialog_tool" "$window_uuid" ${OCR_RANGE_ID} "$state"
}

# Switch off the watermark controls the annotation mode cannot use.
#
# pdfutil refuses --image, --rotate-mark and --under alongside --annotation, so
# all three are usage errors now; --rotate-mark and --under used to be accepted
# and then ignored, which is why the toggle already took them out of play before
# the refusals landed. Either way the user must not be able to set them here.
apply_watermark_mode_state() {
    local state=omc_enable
    [ "$OMC_ACTIONUI_VIEW_166_VALUE" = "true" ] && state=omc_disable

    "$dialog_tool" "$window_uuid" ${WM_IMAGE_ID} "$state"
    "$dialog_tool" "$window_uuid" ${WM_CHOOSE_IMAGE_ID} "$state"
    "$dialog_tool" "$window_uuid" ${WM_ROTATION_ID} "$state"
    "$dialog_tool" "$window_uuid" ${WM_UNDER_ID} "$state"
}

# Show the settings panel for an operation and fill in its notice text.
#
# Called from both PDFUtil.init (the picker fires no action for its initial
# value, so the first panel would otherwise never be set up) and
# PDFUtil.operation.changed.
apply_operation_panel() {
    local op="$1"
    local want="$(panel_for_operation "$op")"
    local panel_id

    for panel_id in $SETTINGS_PANEL_IDS; do
        if [ "$panel_id" = "$want" ]; then
            "$dialog_tool" "$window_uuid" "$panel_id" omc_show
        else
            "$dialog_tool" "$window_uuid" "$panel_id" omc_hide
        fi
    done

    # Set the notice through the plain value form. omc_set_property "text" is
    # accepted but does not repaint a Text element (verified: the notice stayed
    # blank), whereas the value form does.
    local notice_id="$(notice_id_for_operation "$op")"
    if [ -n "$notice_id" ]; then
        "$dialog_tool" "$window_uuid" "$notice_id" "$(structure_notice "$op")"
    fi

    if [ "$want" = "${GROUP_PLACEHOLDER_ID}" ]; then
        # Deliberately not a list of what does work: that sentence went stale
        # every time a stage landed, and panel_for_operation above is already
        # the authoritative record of which operations have been built.
        "$dialog_tool" "$window_uuid" ${GROUP_PLACEHOLDER_ID} \
            "$(operation_label "$op") is not available yet.
Pick another operation, or use QuickPDF if it offers this one."
    fi

    if [ "$want" = "${GROUP_RENDER_ID}" ]; then
        apply_render_format_state
    fi

    if [ "$want" = "${GROUP_CROP_ID}" ]; then
        apply_crop_mode_state
    fi

    if [ "$want" = "${GROUP_SPLIT_ID}" ]; then
        apply_split_mode_state
    fi

    if [ "$want" = "${GROUP_OCR_ID}" ]; then
        apply_ocr_mode_state
    fi

    if [ "$want" = "${GROUP_WATERMARK_ID}" ]; then
        apply_watermark_mode_state
    fi

    if [ "$want" = "${GROUP_FROMPAGES_ID}" ]; then
        apply_assemble_mode_state
    fi

    if [ "$want" = "${GROUP_METADATA_ID}" ]; then
        apply_metadata_mode_state
    fi
}
