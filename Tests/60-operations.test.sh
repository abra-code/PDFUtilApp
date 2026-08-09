#!/bin/sh
# Tests/60-operations.test.sh - every operation, built by the app and run by the
# real binary.
#
# 50-library asserts what the builder INTENDS. This file asserts that the intent
# survives contact with pdfutil: the command line the builder produced actually
# runs, exits 0, and leaves a file of the expected shape. A string assertion
# cannot catch pdfutil rejecting what the app built, and that is the class of
# bug that reaches users - every flag-combination refusal this applet works
# around was discovered exactly this way.
#
# It also covers the two handlers whose only output is text: the (i) report,
# which OMC runs in an output window so its stdout IS the result, and the batch
# progress line, which is the difference between "working" and "hung" on a
# twenty-file run.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.pdfutil.sh"

section "preconditions"
check_preconditions

text_pdf="$(fixture text.pdf)"
image_pdf="$(fixture image.pdf)"
outline_pdf="$(fixture outline.pdf)"
locked_pdf="$(fixture locked.pdf)"
photo_png="$(fixture photo.png)"
notes_txt="$(fixture notes.txt)"

# Read back with the same binary the app runs, so a claim about the output is
# made in the engine's own terms rather than by guessing at bytes.
pdf_pages() { # <path>
    "$PDFUTIL_BIN" info "$1" 2>&1 \
        | /usr/bin/awk -F': ' '$1 == "pages" { print $2; exit }'
}
is_pdf() { # <path> -> yes | no
    if [ -s "$1" ] && [ "$(/usr/bin/head -c 5 "$1")" = "%PDF-" ]; then
        echo yes
    else
        echo no
    fi
}

# --------------------------------------------------------------------------
section "one-in one-out operations run and keep the document whole"
# --------------------------------------------------------------------------
# The page count is the cheap proof that the operation transformed rather than
# truncated: all four of these are supposed to leave the document's shape alone.
_failed_run="" _not_pdf="" _wrong_pages=""
for _op in reduce gray linearize pdfa flatten; do
    reset_document
    _out="$OMCTEST_WORK/e2e-$_op.pdf"
    if [ "$(pdfutil_run_built_args "$_op" "$text_pdf" "$_out")" != 0 ]; then
        _failed_run="${_failed_run:+$_failed_run }$_op"
        continue
    fi
    [ "$(is_pdf "$_out")" = yes ] || _not_pdf="${_not_pdf:+$_not_pdf }$_op"
    [ "$(pdf_pages "$_out")" = 5 ] || _wrong_pages="${_wrong_pages:+$_wrong_pages }$_op:$(pdf_pages "$_out")"
done
check "each ran against the real binary" "" "$_failed_run"
check "each produced a PDF"              "" "$_not_pdf"
check "and left all five pages"          "" "$_wrong_pages"

# --------------------------------------------------------------------------
section "page operations change the document the way they claim"
# --------------------------------------------------------------------------
reset_document
omc_control "$EXT_RANGE_ID" "1-2"
_out="$OMCTEST_WORK/e2e-extract.pdf"
check "extract ran"        "0" "$(pdfutil_run_built_args extract "$text_pdf" "$_out")"
check "and kept two pages" "2" "$(pdf_pages "$_out")"

reset_document
omc_control "$DEL_RANGE_ID" "1"
_out="$OMCTEST_WORK/e2e-delete.pdf"
check "delete ran"          "0" "$(pdfutil_run_built_args delete "$text_pdf" "$_out")"
check "and left four pages" "4" "$(pdf_pages "$_out")"

reset_document
omc_control "$ROT_ANGLE_ID" 90
_out="$OMCTEST_WORK/e2e-rotate.pdf"
check "rotate ran" "0" "$(pdfutil_run_built_args rotate "$text_pdf" "$_out")"
check "and the rotation is recorded in the file" "yes" \
    "$(contains "$("$PDFUTIL_BIN" info "$_out" 2>&1)" "rotation 90")"

reset_document
omc_control "$CROP_VALUES_ID" "36,36,36,36"
_out="$OMCTEST_WORK/e2e-crop.pdf"
check "crop ran"            "0"   "$(pdfutil_run_built_args crop "$text_pdf" "$_out")"
check "and produced a PDF"  "yes" "$(is_pdf "$_out")"

# Metadata round-trips, which is the only way to see that --set reached pdfutil
# rather than being built and dropped.
reset_document
omc_control "$META_TITLE_ID" "E2E Title"
_out="$OMCTEST_WORK/e2e-meta.pdf"
check "metadata ran" "0" "$(pdfutil_run_built_args metadata "$text_pdf" "$_out")"
check "and the title is in the file" "yes" \
    "$(contains "$("$PDFUTIL_BIN" metadata "$_out" 2>&1)" "E2E Title")"

# --------------------------------------------------------------------------
section "watermark, in both of its modes"
# --------------------------------------------------------------------------
reset_document
omc_control "$WM_TEXT_ID" "DRAFT"
_out="$OMCTEST_WORK/e2e-wm-burn.pdf"
check "a burn-in watermark ran" "0" "$(pdfutil_run_built_args watermark "$text_pdf" "$_out")"
check "and produced a PDF"      "yes" "$(is_pdf "$_out")"

reset_document
omc_control "$WM_TEXT_ID" "DRAFT"
omc_control "$WM_ANNOTATION_ID" true
_out="$OMCTEST_WORK/e2e-wm-ann.pdf"
check "an annotation watermark ran" "0" "$(pdfutil_run_built_args watermark "$text_pdf" "$_out")"
# The two modes must be distinguishable in the RESULT, not just in the flags:
# annotation mode adds an annotation, burn-in mode redraws the page instead.
check "and left an annotation behind" "yes" \
    "$(contains "$("$PDFUTIL_BIN" info "$_out" 2>&1)" "annotations")"
check "where the burn-in mode left none" "no" \
    "$(contains "$("$PDFUTIL_BIN" info "$OMCTEST_WORK/e2e-wm-burn.pdf" 2>&1)" "annotations")"

# --------------------------------------------------------------------------
section "the operations whose output is not a PDF"
# --------------------------------------------------------------------------
reset_document
_out="$OMCTEST_WORK/e2e.txt"
check "text extraction ran" "0" "$(pdfutil_run_built_args text "$text_pdf" "$_out")"
check "and wrote something" "yes" "$([ -s "$_out" ] && echo yes || echo no)"
check "with the fixture's marker in it" "yes" \
    "$(contains "$(/bin/cat "$_out")" "PAGE-3-MARKER")"

# 174 is render's page range. Using OCR's range here instead selected no page,
# which silently put render into its multi-page PREFIX form and wrote nothing at
# the path the app had just promised the user.
reset_document
omc_control "$RND_FORMAT_ID" png
omc_control "$RND_DPI_ID" 36
omc_control "$RND_RANGE_ID" "1"
_out="$OMCTEST_WORK/e2e-page.png"
check "render ran"          "0"   "$(pdfutil_run_built_args render "$text_pdf" "$_out")"
check "and wrote the file"  "yes" "$([ -s "$_out" ] && echo yes || echo no)"
check "and it really is a PNG" "yes" \
    "$(contains "$(/usr/bin/file "$_out")" "PNG")"

# --------------------------------------------------------------------------
section "many-in, one-out"
# --------------------------------------------------------------------------
# merge and frompages do not go through the single-input shape, so they are
# driven the way their own runners drive them.
run_multi() { # <operation> <output> <input ...>
    export OMCTEST_PU_OP="$1" OMCTEST_PU_OUT="$2"
    shift 2
    pdfutil_eval 'build_pdfutil_args "$OMCTEST_PU_OP" >/dev/null 2>&1
        "$PDFUTIL" "$PDFUTIL_VERB" "${PDFUTIL_ARGS[@]}" --force \
            -o "$OMCTEST_PU_OUT" "$@" >/dev/null 2>&1
        printf "%s" "$?"' "$@"
}

reset_document
_out="$OMCTEST_WORK/e2e-merge.pdf"
check "merge ran" "0" "$(run_multi merge "$_out" "$text_pdf" "$outline_pdf")"
check "and the pages of both are there" "10" "$(pdf_pages "$_out")"

reset_document
_out="$OMCTEST_WORK/e2e-assembled.pdf"
check "frompages ran"      "0"   "$(run_multi frompages "$_out" "$photo_png")"
check "and produced a PDF" "yes" "$(is_pdf "$_out")"
check "one image made one page" "1" "$(pdf_pages "$_out")"

# --------------------------------------------------------------------------
section "split writes a series rather than a file"
# --------------------------------------------------------------------------
# -o is a PREFIX here, which is why split routes to a folder chooser instead of
# a Save As panel.
reset_document
omc_control "$SPLIT_EVERY_ID" 2
_prefix="$OMCTEST_WORK/e2e-part"
check "split ran" "0" "$(run_multi split "$_prefix" "$text_pdf")"
check "and wrote more than one part" "yes" \
    "$([ "$(/bin/ls "$OMCTEST_WORK"/e2e-part*.pdf 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')" -ge 2 ] \
        && echo yes || echo no)"

# --------------------------------------------------------------------------
section "encrypt and decrypt, with the password fed the way the app feeds it"
# --------------------------------------------------------------------------
# The two operations the sweep above cannot reach, and the reason is the point:
# their command line refuses to run without a password, and the app never puts
# one in argv. It sets PDFUTIL_STDIN_PW and lets run_pdfutil pipe it in.
#
# Both halves are covered elsewhere and neither is enough on its own. 50-library
# proves the argv asks for a -stdin form and holds no secret; Tests/cases
# proves the BINARY's --password-stdin works when fed by hand. Only this joins
# them, and the join is where it breaks: disabling the pipe in run_pdfutil
# leaves both of those green while the app silently encrypts nothing.
run_with_password() { # <operation> <password> <input> <output>
    export OMCTEST_PU_OP="$1" OMCTEST_PU_PW="$2" OMCTEST_PU_IN="$3" OMCTEST_PU_OUT="$4"
    pdfutil_eval '
        if ! build_pdfutil_args "$OMCTEST_PU_OP" >/dev/null 2>&1; then
            printf "build-refused"
            exit 0
        fi
        PDFUTIL_STDIN_PW="$OMCTEST_PU_PW"
        run_pdfutil "$OMCTEST_PU_IN" "$OMCTEST_PU_OUT" >/dev/null 2>&1
        printf "%s" "$?"'
}

reset_document
omc_control "$ENC_USER_PW_ID" "s3cret"
omc_control "$ENC_USER_PW_CONFIRM_ID" "s3cret"
_enc="$OMCTEST_WORK/e2e-encrypted.pdf"
check "encrypt ran"          "0"   "$(run_with_password encrypt s3cret "$text_pdf" "$_enc")"
check "and wrote a file"     "yes" "$([ -s "$_enc" ] && echo yes || echo no)"
# The proof that the password actually arrived is that the document now REFUSES
# to open without one. Asserting "encrypted: true" on an unprotected read would
# pass vacuously - it never gets that far.
check "the output really is protected" "yes" \
    "$(contains "$("$PDFUTIL_BIN" info "$_enc" 2>&1)" "password-protected")"
check "and opens with the password"    "yes" \
    "$(contains "$("$PDFUTIL_BIN" info --password s3cret "$_enc" 2>&1)" "encrypted: true")"

reset_document
omc_control "$DEC_PASSWORD_ID" "s3cret"
_dec="$OMCTEST_WORK/e2e-decrypted.pdf"
check "decrypt ran"                 "0" "$(run_with_password decrypt s3cret "$_enc" "$_dec")"
check "and the protection is gone" "yes" \
    "$(contains "$("$PDFUTIL_BIN" info "$_dec" 2>&1)" "encrypted: false")"
check "with the content intact"    "yes" \
    "$(contains "$("$PDFUTIL_BIN" text "$_dec" 2>&1)" "PAGE-3-MARKER")"

# --------------------------------------------------------------------------
section "the (i) report"
# --------------------------------------------------------------------------
# The read-only tier is no longer a batch operation - inspection answers a
# question about the one document you are looking at. OMC runs the handler in an
# output window, so its stdout IS the result and there is no window write to
# inspect; omctest records that stdout in handlers.log, and run_capturing
# returns the slice this dispatch added.
info_for() { # <path>
    reset_document
    select_file "$1"
    run_capturing PDFUtil.info
}

_report="$(info_for "$text_pdf")"
check "it names a size"          "yes" "$(contains "$_report" "Size:")"
check "it classifies the file"   "yes" "$(contains "$_report" "Type: pdf")"
check "it reports the page count" "yes" "$(contains "$_report" "pages: 5")"

# The outline is shown when there is one...
_report="$(info_for "$outline_pdf")"
check "an outline is shown"      "yes" "$(contains "$_report" "--- Outline ---")"
check "with its entries"         "yes" "$(contains "$_report" "Chapter 1")"

# ...and stays silent when there is not. `pdfutil outline` prints "no outline"
# and exits 0 for those, so an emptiness test alone would print a heading over
# nothing - which is what it did until this was checked against a real file.
_report="$(info_for "$text_pdf")"
check "no heading for a document without one" "no" "$(contains "$_report" "--- Outline ---")"
check "and the engine's placeholder does not leak through" "no" \
    "$(contains "$_report" "no outline")"

_report="$(info_for "$photo_png")"
check "an image is classified"   "yes" "$(contains "$_report" "Type: image")"
check "with its dimensions"      "yes" "$(contains "$_report" "pixelWidth")"

_report="$(info_for "$notes_txt")"
check "a non-PDF is classified"  "yes" "$(contains "$_report" "Type: other")"

_report="$(info_for "$OMCTEST_WORK/does-not-exist.pdf")"
check "a missing file is reported as missing" "yes" "$(contains "$_report" "does not exist")"

# A locked PDF explains itself rather than reporting a bare failure.
_report="$(info_for "$locked_pdf")"
check "a locked PDF explains itself" "yes" "$(contains "$_report" "password-protected")"

# --------------------------------------------------------------------------
section "batch progress"
# --------------------------------------------------------------------------
# pdfutil has no --progress and the slow runs are slow INSIDE a file, so nothing
# can report finer than per-file. That is still the difference between "working"
# and "hung" on a twenty-file OCR batch. The Summary is the surface: OMC's
# PROGRESS dialog only works for popen-based execution modes, and the batch
# runner is exe_script_file.
progress_line() { # <operation> <index> <total> <name> <done> <failed>
    ui_reset
    pdfutil_call set_batch_progress "$@" >/dev/null 2>&1
    summary
}

reset_document
_prog="$(progress_line reduce 3 12 "report.pdf" 2 0)"
check "it reports the position"       "yes" "$(contains "$_prog" "File 3 of 12")"
check "it names the file"             "yes" "$(contains "$_prog" "report.pdf")"
check "it names the operation"        "yes" "$(contains "$_prog" "Reduce File Size")"
check "it carries the running tally"  "yes" "$(contains "$_prog" "2 done")"

# Failures are carried too, so a batch going wrong says so while it runs rather
# than only in the final report.
_prog="$(progress_line ocr 5 5 "scan.pdf" 3 1)"
check "and the failure count"         "yes" "$(contains "$_prog" "1 failed")"

# The first file has nothing to tally yet, and a bare "0 done" reads as a stall.
_prog="$(progress_line reduce 1 4 "first.pdf" 0 0)"
check "the first file shows no empty tally" "no" "$(contains "$_prog" "0 done")"
check "but still shows its position"  "yes" "$(contains "$_prog" "File 1 of 4")"

# It REPLACES the Summary rather than appending, or a long batch scrolls away
# from the user.
ui_reset
pdfutil_call set_batch_progress reduce 1 4 "first.pdf" 0 0 >/dev/null 2>&1
pdfutil_call set_batch_progress reduce 2 4 "second.pdf" 1 0 >/dev/null 2>&1
_prog="$(summary)"
check "the previous file is gone from the summary" "no" "$(contains "$_prog" "first.pdf")"
check "and the current one is there"  "yes" "$(contains "$_prog" "second.pdf")"

# All of the above is theatre unless the batch runner calls it. There is no way
# to observe this from a dispatch - the runner's final summary overwrites every
# progress line it wrote - so the call site is asserted in the source.
#
# Anchored to the start of a line rather than matched anywhere in the file: a
# mention of the name in a comment, or a call commented out during debugging,
# both leave a bare substring match green. That is not hypothetical - the first
# version of this check was a substring match, and disabling the call while
# leaving the name in place did not redden it.
#
# It remains a check on SPELLING, and its limit is worth stating: a call left
# intact inside `if false; then ... fi` still satisfies it. Reaching further
# would mean running a batch and observing the progress line, which the runner's
# final summary overwrites before anything can read it.
calls_in_batch_runner() { # <function-name> -> yes | no
    /usr/bin/grep -qE "^[[:space:]]*$1([[:space:]]|\$)" \
        "$APP_SCRIPTS/PDFUtil.run.batch.sh" && echo yes || echo no
}
check "the batch runner calls it" "yes" "$(calls_in_batch_runner set_batch_progress)"
# The negative control: the same pattern against a name that is only ever
# mentioned, never called, has to answer no - otherwise the check above is
# measuring the file's existence rather than its contents.
check "and the pattern can still say no" "no" "$(calls_in_batch_runner no_such_function)"

# --------------------------------------------------------------------------
section "cumulative: no handler wrote to a view id the window does not declare"
# --------------------------------------------------------------------------
check "no undeclared ids" "" "$(ui_unknown_writes)"
check "no bare value write clobbered a table's rows" "" "$(ui_suspect_writes)"
check "the harness detected no misuse" "" "$(ui_errors)"

omctest_end
