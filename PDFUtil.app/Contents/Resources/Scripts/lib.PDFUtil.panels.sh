#!/bin/bash
# lib.PDFUtil.panels.sh - the settings panel switcher
#
# Which GroupBox is visible for the chosen operation, the per-section structure
# notice text, and the mode toggles that grey out controls their mode cannot use.
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
            echo "Redraws pages: annotations, links, outline, and form fields are not carried over. \"Convert to grayscale\" uses a different filter that replaces the quality, resolution and edge settings rather than adding to them."
            ;;
        render)
            echo "Rasterizes pages to images. Text stops being selectable and searchable - export at a higher DPI if the result will be read on screen."
            ;;
        text)
            echo "Extracts the existing text layer only. Scanned pages have none and come out empty - use OCR for those."
            ;;
        encrypt)
            echo "Writes 128-bit AES (revision 4): ASCII passwords only, and only their first 32 characters count. Use QuickPDF's 256-bit AES if you need more. Permissions bind only readers who open with the user password, so a single password serving as both restricts nobody."
            ;;
        decrypt)
            echo "Saves an unlocked copy and leaves the original untouched."
            ;;
        extract)
            echo "Keeps the listed pages in the listed order, so repeats and reordering are legal. Rebuilds the document: the outline is not carried over."
            ;;
        delete)
            echo "Edits in place and keeps the outline, so entries pointing at removed pages may dangle."
            ;;
        rotate)
            echo "Lossless: only each page's rotation entry changes. Degrees are added to the current rotation, not set - rotating 90 twice gives 180."
            ;;
        crop)
            echo "Lossless: content is untouched and only the page box changes, so cropped-away material is hidden rather than removed."
            ;;
        split)
            echo "Each part keeps its pages' annotations, links and form fields; the document outline is not carried into the parts."
            ;;
        merge)
            echo "Inputs are joined in list order. Page-level structure is carried over; the document outline is not merged across inputs."
            ;;
        ocr)
            echo "Reads the pages as pictures, so it works on scans with no text layer at all. Recognition is never perfect - check the result before relying on it. \"Embed a searchable text layer\" saves a PDF through a different engine, which covers the whole document and picks its own settings, so the language, speed, resolution and page-range controls do not apply to it."
            ;;
        watermark)
            echo "Burning the mark in redraws the pages: annotations, links, the outline and form fields are not carried over. Adding it as an annotation keeps all of that and stays editable, but is text-only and cannot be rotated."
            ;;
        flatten)
            echo "Removes interactivity deliberately: filled-in values and annotation appearances are painted into the page and the fields themselves are gone. The outline survives; nothing can be edited afterwards."
            ;;
        linearize)
            echo "Redraws the pages, so annotations, links, the outline and form fields are not carried over. QuickPDF builds a better hint table through qpdf and keeps the structure - use it instead when the document has any of that to lose, or when strict validity matters."
            ;;
        pdfa)
            echo "Redraws the pages, so annotations, links, the outline and form fields are not carried over. The output is tagged PDF/A-2B but its conformance is NOT verified - validate with veraPDF before relying on it for archival."
            ;;
        frompages)
            echo "The one operation whose inputs are images rather than PDFs; pages come out in list order. An animated GIF or multi-page TIFF contributes one page per frame. A PDF in the list is redrawn, losing annotations, links, the outline and form fields - use Merge to combine PDFs instead."
            ;;
        inspect)
            echo "Read-only: nothing is written and no destination is asked for. Results open in an output window. Search reports a count per file, so a document with no matches says so instead of printing nothing."
            ;;
        metadata)
            echo "Edits the Info dictionary and keeps the document's structure. PDFKit's writer resets Producer and both dates on every save whatever is set here, so those three are not offered as fields."
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
        inspect)   echo ${NOTICE_INSPECT_ID} ;;
        linearize) echo ${NOTICE_LINEARIZE_ID} ;;
        pdfa)      echo ${NOTICE_PDFA_ID} ;;
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
        inspect)   echo ${GROUP_INSPECT_ID} ;;
        linearize) echo ${GROUP_LINEARIZE_ID} ;;
        pdfa)      echo ${GROUP_PDFA_ID} ;;
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

# Switch off the recompression controls that grayscale mode replaces.
#
# --gray selects the system Gray Tone filter, which is built INSTEAD of the
# recompression filter rather than on top of it, so quality, resolution and
# max-edge have nothing to act on. pdfutil used to accept all three and drop
# them silently (-q 1 and -q 100 gave byte-identical files); it now refuses the
# combination, so build_pdfutil_args must stop emitting them as well - see the
# reduce case there.
apply_reduce_mode_state() {
    local state=omc_enable
    [ "$OMC_ACTIONUI_VIEW_80_VALUE" = "true" ] && state=omc_disable

    "$dialog_tool" "$window_uuid" ${RED_QUALITY_ID} "$state"
    "$dialog_tool" "$window_uuid" ${RED_DOWNSAMPLE_ID} "$state"
    "$dialog_tool" "$window_uuid" ${RED_DPI_ID} "$state"
    "$dialog_tool" "$window_uuid" ${RED_MAXEDGE_ON_ID} "$state"
    "$dialog_tool" "$window_uuid" ${RED_MAXEDGE_PX_ID} "$state"
}

# Show the search query field only in the mode that uses it.
#
# The other three inspect modes take no argument, so a live query box would be a
# control with nothing to act on. Hidden rather than disabled: a greyed-out field
# still reads as "something I could turn on", and there is no toggle to turn on.
apply_inspect_mode_state() {
    if [ "$OMC_ACTIONUI_VIEW_222_VALUE" = "search" ]; then
        "$dialog_tool" "$window_uuid" ${INSPECT_QUERY_ROW_ID} omc_show
    else
        "$dialog_tool" "$window_uuid" ${INSPECT_QUERY_ROW_ID} omc_hide
    fi
}

# Show the one row the chosen page-sizing mode actually uses.
#
# Hidden rather than disabled, for the same reason as the Inspect query box: a
# greyed-out paper picker reads as something there is a way to switch on, and
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
# output read as evidence the setting had been honoured.
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

    if [ "$want" = "${GROUP_REDUCE_ID}" ]; then
        apply_reduce_mode_state
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

    if [ "$want" = "${GROUP_INSPECT_ID}" ]; then
        apply_inspect_mode_state
    fi
}
