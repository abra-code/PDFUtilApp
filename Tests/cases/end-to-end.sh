# end-to-end.sh - every operation, built by the app and run by the real binary.
#
# The other cases assert what the app INTENDS. This one asserts that the intent
# survives contact with pdfutil: the command line the builder produced actually
# runs, exits 0, and leaves a file of the expected type. A string assertion
# cannot catch pdfutil rejecting what the app built, and that is the class of bug
# that reaches users - every one of the flag-combination refusals this app works
# around was discovered exactly this way.

reset_controls

# Run one operation the way a runner does: build, then hand the args to the
# binary with the -o and --force the runner always adds.
# Usage: run_op <operation> <input> <output>
run_op() {
    local op="$1" in="$2" out="$3"
    build_pdfutil_args "$op" >/dev/null 2>&1 || return 90
    "$PDFUTIL" "$PDFUTIL_VERB" "${PDFUTIL_ARGS[@]}" --force -o "$out" "$in" \
        "${PDFUTIL_TRAILING[@]}" >/dev/null 2>&1
}

is_pdf()  { [ -s "$1" ] && [ "$(head -c 5 "$1")" = "%PDF-" ]; }
nonempty() { [ -s "$1" ]; }

# --- one-in, one-out PDF operations ---------------------------------------
for op in reduce linearize pdfa flatten; do
    reset_controls
    if run_op "$op" "$FIX/text.pdf" "$TMP/e2e-$op.pdf"; then
        is_pdf "$TMP/e2e-$op.pdf" || fail "$op produced something that is not a PDF"
        expect_grep_all "pages: 5" "$PDFUTIL" info "$TMP/e2e-$op.pdf"
    else
        fail "$op did not run against the real binary (exit $?)"
    fi
done

# Page operations, each with the control its panel requires.
reset_controls; OMC_ACTIONUI_VIEW_140_VALUE="1-2"
run_op extract "$FIX/text.pdf" "$TMP/e2e-extract.pdf" || fail "extract did not run"
expect_grep_all "pages: 2" "$PDFUTIL" info "$TMP/e2e-extract.pdf"

reset_controls; OMC_ACTIONUI_VIEW_141_VALUE="1"
run_op delete "$FIX/text.pdf" "$TMP/e2e-delete.pdf" || fail "delete did not run"
expect_grep_all "pages: 4" "$PDFUTIL" info "$TMP/e2e-delete.pdf"

reset_controls; OMC_ACTIONUI_VIEW_130_VALUE=90
run_op rotate "$FIX/text.pdf" "$TMP/e2e-rotate.pdf" || fail "rotate did not run"
expect_grep_all "rotation 90" "$PDFUTIL" info "$TMP/e2e-rotate.pdf"

reset_controls; OMC_ACTIONUI_VIEW_186_VALUE="36,36,36,36"
run_op crop "$FIX/text.pdf" "$TMP/e2e-crop.pdf" || fail "crop did not run"
is_pdf "$TMP/e2e-crop.pdf" || fail "crop produced something that is not a PDF"

# Metadata round-trips, which is the only way to see that --set reached pdfutil.
reset_controls; OMC_ACTIONUI_VIEW_190_VALUE="E2E Title"
run_op metadata "$FIX/text.pdf" "$TMP/e2e-meta.pdf" || fail "metadata did not run"
expect_grep_all "E2E Title" "$PDFUTIL" metadata "$TMP/e2e-meta.pdf"

# --- watermark, both modes -------------------------------------------------
reset_controls; OMC_ACTIONUI_VIEW_160_VALUE="DRAFT"
run_op watermark "$FIX/text.pdf" "$TMP/e2e-wm-burn.pdf" || fail "burn-in watermark did not run"
is_pdf "$TMP/e2e-wm-burn.pdf" || fail "burn-in watermark produced something that is not a PDF"

reset_controls; OMC_ACTIONUI_VIEW_160_VALUE="DRAFT"; OMC_ACTIONUI_VIEW_166_VALUE=true
run_op watermark "$FIX/text.pdf" "$TMP/e2e-wm-ann.pdf" || fail "annotation watermark did not run"
expect_grep_all "annotations" "$PDFUTIL" info "$TMP/e2e-wm-ann.pdf"

# --- non-PDF outputs -------------------------------------------------------
reset_controls
run_op text "$FIX/text.pdf" "$TMP/e2e.txt" || fail "text extraction did not run"
nonempty "$TMP/e2e.txt" || fail "text extraction produced an empty file"
grep -q "PAGE-3-MARKER" "$TMP/e2e.txt" || fail "extracted text is missing the fixture's marker"

# 174 is render's page range - 180 is OCR's, and using it here selected no page,
# which silently put render into its multi-page PREFIX form.
reset_controls; OMC_ACTIONUI_VIEW_170_VALUE=png; OMC_ACTIONUI_VIEW_171_VALUE=36
OMC_ACTIONUI_VIEW_174_VALUE="1"
run_op render "$FIX/text.pdf" "$TMP/e2e-page.png" || fail "render did not run"
nonempty "$TMP/e2e-page.png" || fail "render produced an empty file"
expect_grep "PNG" /usr/bin/file "$TMP/e2e-page.png"

# --- many-in, one-out ------------------------------------------------------
# merge and frompages do not go through run_pdfutil's single-input shape, so
# they are driven the way their own runners drive them.
reset_controls
build_pdfutil_args merge >/dev/null 2>&1
"$PDFUTIL" merge "${PDFUTIL_ARGS[@]}" --force -o "$TMP/e2e-merge.pdf" \
    "$FIX/text.pdf" "$FIX/outline.pdf" >/dev/null 2>&1 || fail "merge did not run"
expect_grep_all "pages: 10" "$PDFUTIL" info "$TMP/e2e-merge.pdf"

reset_controls
build_pdfutil_args frompages >/dev/null 2>&1
"$PDFUTIL" frompages "${PDFUTIL_ARGS[@]}" --force -o "$TMP/e2e-assembled.pdf" \
    "$FIX/photo.png" >/dev/null 2>&1 || fail "frompages did not run"
is_pdf "$TMP/e2e-assembled.pdf" || fail "frompages produced something that is not a PDF"
# The default is fit-to-letter, so a 3000 px photo must NOT become a 3000 pt
# page. The fixture is landscape, and fitting ORIENTS the page to the image, so
# letter here means 792x612 - asserting 612x792 would be asserting a bug.
expect_grep_all "792x612" "$PDFUTIL" info "$TMP/e2e-assembled.pdf"
expect_nogrep_all "3000x" "$PDFUTIL" info "$TMP/e2e-assembled.pdf"

# Reduce must never hand back something bigger, whatever it is given. The
# assembled fixture is a smooth gradient stored as Flate, which is already close
# to optimal - JPEG does not beat it, so reduce declines and returns the
# original. That is the guard working, not a failure.
reset_controls
run_op reduce "$TMP/e2e-assembled.pdf" "$TMP/e2e-assembled-small.pdf" \
    || fail "reduce did not run on the assembled document"
before=$(wc -c < "$TMP/e2e-assembled.pdf")
after=$(wc -c < "$TMP/e2e-assembled-small.pdf")
[ "$after" -le "$before" ] \
    || fail "reduce returned a LARGER file ($before -> $after)"

# ...and on a document it can genuinely improve, it does. image.pdf is a real
# raster scan, which is the case reduce exists for.
reset_controls
run_op reduce "$FIX/image.pdf" "$TMP/e2e-scan-small.pdf" || fail "reduce did not run on the scan"
sbefore=$(wc -c < "$FIX/image.pdf")
safter=$(wc -c < "$TMP/e2e-scan-small.pdf")
[ "$safter" -lt "$sbefore" ] \
    || fail "reduce did not shrink a raster scan ($sbefore -> $safter)"

# --- split writes a series --------------------------------------------------
reset_controls; OMC_ACTIONUI_VIEW_150_VALUE=2
build_pdfutil_args split >/dev/null 2>&1
"$PDFUTIL" split "${PDFUTIL_ARGS[@]}" --force -o "$TMP/e2e-part" "$FIX/text.pdf" >/dev/null 2>&1 \
    || fail "split did not run"
count=$(ls "$TMP"/e2e-part*.pdf 2>/dev/null | wc -l | tr -d ' ')
[ "$count" -ge 2 ] || fail "split wrote $count parts from a 5-page document"

# --- the (i) button: inspection of the SELECTED file ------------------------
#
# The read-only reports used to be a batch operation with a sub-picker. They are
# not any more: inspection answers a question about one document you are looking
# at, not something queued across a list and read back as a log. What survives
# lives in the info handler, which OMC runs in an output window, so its stdout
# IS the result and can be asserted directly.
run_info() {
    OMC_APP_BUNDLE_PATH="$APP" \
    OMC_ACTIONUI_TABLE_10_COLUMN_3_VALUE="$1" \
        /bin/sh "$SCRIPTS/PDFUtil.info.sh" 2>&1
}

out="$(run_info "$FIX/text.pdf")"
contains "$out" "Size:"       || fail "info gave no file size"
contains "$out" "Type: pdf"   || fail "info did not classify the file"
contains "$out" "pages: 5"    || fail "info did not report the page count"

# The outline is shown when there is one...
out="$(run_info "$FIX/outline.pdf")"
contains "$out" "--- Outline ---" || fail "info did not show the outline of a document that has one"
contains "$out" "Chapter 1"       || fail "info showed an outline heading but no entries"

# ...and stays silent when there is not. `pdfutil outline` prints "no outline"
# and exits 0 for those, so an emptiness test alone would print a heading over
# nothing - which is what it did until this was checked against a real file.
out="$(run_info "$FIX/text.pdf")"
if contains "$out" "--- Outline ---"; then
    fail "info printed an outline heading for a document with no outline"
fi
if contains "$out" "no outline"; then
    fail "info leaked pdfutil's 'no outline' placeholder into the report"
fi

# Images and non-PDFs are handled rather than run through pdfutil.
out="$(run_info "$FIX/photo.png")"
contains "$out" "Type: image" || fail "info did not classify an image"
contains "$out" "pixelWidth"  || fail "info gave no image dimensions"

out="$(run_info "$FIX/notes.txt")"
contains "$out" "Type: other" || fail "info did not classify a non-PDF"

out="$(run_info "$FIX/does-not-exist.pdf")"
contains "$out" "does not exist" || fail "info did not report a missing file"

# A locked PDF explains itself rather than reporting a bare failure.
out="$(run_info "$FIX/locked.pdf")"
contains "$out" "password-protected" || fail "info did not explain a locked PDF"
