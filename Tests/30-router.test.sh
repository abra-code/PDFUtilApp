#!/bin/sh
# Tests/30-router.test.sh - the Save button: validation, pre-flight, and where
# the run is sent.
#
# PDFUtil.start.batch is the applet's decision point. It refuses bad settings,
# refuses inputs the operation cannot read, asks before discarding document
# structure, and then chains to one of six runners. 50-library covers the
# validation functions it consults one at a time; this file is about the handler
# that consults them - the ORDER of the refusals, the alerts they raise, and the
# command each path chains to.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.pdfutil.sh"

section "preconditions"
check_preconditions

text_pdf="$(fixture text.pdf)"
outline_pdf="$(fixture outline.pdf)"
photo_png="$(fixture photo.png)"
locked_pdf="$(fixture locked.pdf)"
restricted_pdf="$(fixture restricted.pdf)"

# Put files in the list without going through the add handlers - this file is
# about the router, and a failure in add_files_to_table should fail 20- rather
# than confusing every section here.
seed_list() { # <path ...>
    local rows=""
    for _p in "$@"; do
        rows="$rows$(pdfutil_call row_for_path "$_p")
"
    done
    printf '%s' "$rows" | "$OMC_OMC_SUPPORT_PATH/omc_dialog_control" \
        "$OMC_ACTIONUI_WINDOW_UUID" "$TABLE_ID" omc_table_set_rows_from_stdin
    sync_file_list
}

# --------------------------------------------------------------------------
section "an empty list is refused before anything else happens"
# --------------------------------------------------------------------------
reset_document
omc_control "$OPERATION_PICKER_ID" reduce
run_with_list PDFUtil.start.batch
check_status "the handler exits cleanly" 0
check "the user was told"       "1" "$(alerts_count)"
check "and told what to do"     "1" "$(alerts_mention 'Add at least one file')"
check "nothing was chained"     "0" "$(chain_asked PDFUtil.run.single)"

# --------------------------------------------------------------------------
section "a one-in one-out operation goes to the single runner"
# --------------------------------------------------------------------------
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" linearize
run_with_list PDFUtil.start.batch
check "no alert was raised"        "0" "$(alerts_count)"
check "it chained to run.single"   "1" "$(chain_requested PDFUtil.run.single)"

# --------------------------------------------------------------------------
section "the same operation over several files goes to the batch runner"
# --------------------------------------------------------------------------
reset_document
second_pdf="$OMCTEST_WORK/second.pdf"
/bin/cp "$text_pdf" "$second_pdf"
seed_list "$text_pdf" "$second_pdf"
omc_control "$OPERATION_PICKER_ID" linearize
run_with_list PDFUtil.start.batch
check "it chained to run.batch"    "1" "$(chain_requested PDFUtil.run.batch)"
check "and not to run.single"      "0" "$(chain_requested PDFUtil.run.single)"

# --------------------------------------------------------------------------
section "text extraction has its own runner, and only for one file"
# --------------------------------------------------------------------------
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" text
run_with_list PDFUtil.start.batch
check "one file goes to run.text" "1" "$(chain_requested PDFUtil.run.text)"

reset_document
seed_list "$text_pdf" "$second_pdf"
omc_control "$OPERATION_PICKER_ID" text
run_with_list PDFUtil.start.batch
check "several files go to run.batch" "1" "$(chain_requested PDFUtil.run.batch)"

# --------------------------------------------------------------------------
section "split always goes to the batch runner, even for one file"
# --------------------------------------------------------------------------
# One input becomes a numbered series, so there is no single name a Save panel
# could confirm.
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" split
run_with_list PDFUtil.start.batch
check "one file still goes to run.batch" "1" "$(chain_requested PDFUtil.run.batch)"
check "and not to run.single"            "0" "$(chain_requested PDFUtil.run.single)"

# --------------------------------------------------------------------------
section "merge refuses a single file and names the reason"
# --------------------------------------------------------------------------
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" merge
run_with_list PDFUtil.start.batch
check "the user was told"      "1" "$(alerts_mention 'at least two files')"
check "the run did not start"  "0" "$(chain_asked PDFUtil.run.merge)"
check "and the summary says so" "yes" "$(contains "$(summary)" "at least two files")"

reset_document
seed_list "$text_pdf" "$second_pdf"
omc_control "$OPERATION_PICKER_ID" merge
run_with_list PDFUtil.start.batch
check "two files are enough"   "1" "$(chain_requested PDFUtil.run.merge)"
check "with no complaint"      "0" "$(alerts_count)"

# --------------------------------------------------------------------------
section "building a pdf from images goes to the assemble runner"
# --------------------------------------------------------------------------
reset_document
seed_list "$photo_png"
omc_control "$OPERATION_PICKER_ID" frompages
run_with_list PDFUtil.start.batch
check "it chained to run.assemble" "1" "$(chain_requested PDFUtil.run.assemble)"
# Unlike merge, one image is legal - it is a one-page PDF.
check "one image is not refused"   "0" "$(alerts_count)"

# --------------------------------------------------------------------------
section "an operation cannot be given a file it cannot read"
# --------------------------------------------------------------------------
reset_document
seed_list "$photo_png"
omc_control "$OPERATION_PICKER_ID" linearize
run_with_list PDFUtil.start.batch
check "the run was refused"    "1" "$([ "$(alerts_count)" -gt 0 ] && echo 1 || echo 0)"
check "nothing was chained"    "0" "$(chain_asked PDFUtil.run.single)"

# The mirror image, and the positive control for it: the image-only operation
# refuses a PDF.
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" frompages
run_with_list PDFUtil.start.batch
check "frompages refuses a pdf"  "1" "$([ "$(alerts_count)" -gt 0 ] && echo 1 || echo 0)"
check "and chains nothing"       "0" "$(chain_asked PDFUtil.run.assemble)"

# --------------------------------------------------------------------------
section "a locked pdf is refused with the one operation that can help"
# --------------------------------------------------------------------------
reset_document
seed_list "$locked_pdf"
omc_control "$OPERATION_PICKER_ID" linearize
run_with_list PDFUtil.start.batch
check "the run was refused"           "0" "$(chain_asked PDFUtil.run.single)"
check "and Remove Password is named"  "yes" "$(contains "$(summary)" "Remove Password")"

# The positive control: decrypt is exactly the operation a locked file is for,
# so it must NOT be refused.
reset_document
seed_list "$locked_pdf"
omc_control "$OPERATION_PICKER_ID" decrypt
omc_control "$DEC_PASSWORD_ID" secret
run_with_list PDFUtil.start.batch
check "decrypt accepts a locked pdf" "1" "$(chain_requested PDFUtil.run.single)"

# --------------------------------------------------------------------------
section "Remove Password needs a password only for a PDF that needs one to open"
# --------------------------------------------------------------------------
# A PDF that opens without a password has an empty user password; its owner
# password only restricts it. An empty field is the right request for it.
reset_document
seed_list "$restricted_pdf"
omc_control "$OPERATION_PICKER_ID" decrypt
run_with_list PDFUtil.start.batch
check "an empty field is accepted for a restricted pdf" "1" "$(chain_requested PDFUtil.run.single)"
check "with no alert" "0" "$(alerts_count)"

# The empty field is refused for a PDF that does need a password, and the
# refusal names it - before any destination is asked for.
reset_document
seed_list "$restricted_pdf" "$locked_pdf"
omc_control "$OPERATION_PICKER_ID" decrypt
run_with_list PDFUtil.start.batch
check "an empty field is refused when a pdf needs a password" "0" "$(chain_asked PDFUtil.run.batch)"
check "the alert was raised" "1" "$([ "$(alerts_count)" -gt 0 ] && echo 1 || echo 0)"
check "the summary names the file that needs it" "yes" "$(contains "$(summary)" "\"locked.pdf\" needs the password")"
check "and says the others need none" "yes" "$(contains "$(summary)" "need none")"
omc_control "$DEC_PASSWORD_ID" test
run_with_list PDFUtil.start.batch
check "with the password it runs" "1" "$(chain_requested PDFUtil.run.batch)"

# Nothing to remove is said before a destination is asked for, too.
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" decrypt
run_with_list PDFUtil.start.batch
check "an unprotected pdf is refused" "0" "$(chain_asked PDFUtil.run.single)"
check "because there is nothing to remove" "yes" "$(contains "$(summary)" "nothing to remove")"

# --------------------------------------------------------------------------
section "an edit a restricted pdf forbids is refused before a destination is chosen"
# --------------------------------------------------------------------------
reset_document
seed_list "$restricted_pdf"
omc_control "$OPERATION_PICKER_ID" delete
omc_control "$DEL_RANGE_ID" "1"
run_with_list PDFUtil.start.batch
check "delete is refused" "0" "$(chain_asked PDFUtil.run.single)"
check "the alert was raised" "1" "$([ "$(alerts_count)" -gt 0 ] && echo 1 || echo 0)"
check "the summary says what it does not allow" "yes" \
    "$(contains "$(summary)" "\"restricted.pdf\" does not allow removing or rotating pages")"
check "and that no password is needed to fix it" "yes" \
    "$(contains "$(summary)" "Use Remove Password on it first - no password is needed")"

reset_document
seed_list "$restricted_pdf"
omc_control "$OPERATION_PICKER_ID" metadata
omc_control "$META_TITLE_ID" "A Title"
run_with_list PDFUtil.start.batch
check "edit metadata is refused" "0" "$(chain_asked PDFUtil.run.single)"
check "for editing" "yes" "$(contains "$(summary)" "does not allow editing")"

reset_document
seed_list "$restricted_pdf"
omc_control "$OPERATION_PICKER_ID" watermark
omc_control "$WM_TEXT_ID" "DRAFT"
omc_control "$WM_ANNOTATION_ID" true
run_with_list PDFUtil.start.batch
check "an annotation watermark is refused" "0" "$(chain_asked PDFUtil.run.single)"
check "for adding comments" "yes" "$(contains "$(summary)" "does not allow adding comments")"

# The controls: an edit the PDF allows still runs, and so does a plain PDF.
reset_document
seed_list "$restricted_pdf"
omc_control "$OPERATION_PICKER_ID" crop
omc_control "$CROP_VALUES_ID" "36,36,36,36"
run_with_list PDFUtil.start.batch
check "crop is not restricted" "1" "$(chain_requested PDFUtil.run.single)"

reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" delete
omc_control "$DEL_RANGE_ID" "1"
run_with_list PDFUtil.start.batch
check "delete runs on a plain pdf" "1" "$(chain_requested PDFUtil.run.single)"

# --------------------------------------------------------------------------
section "bad settings are refused before the operation is even resolved"
# --------------------------------------------------------------------------
# The ordering is load-bearing. build_pdfutil_args refuses a settings
# combination it cannot express, and that refusal is indistinguishable from
# "this operation does not exist yet" - so asking it first would answer an empty
# metadata form by pointing the user at another app for a feature that is right
# there and merely needs a value.
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" metadata
omc_control "$META_TITLE_ID" ""
omc_control "$META_AUTHOR_ID" ""
omc_control "$META_SUBJECT_ID" ""
omc_control "$META_KEYWORDS_ID" ""
omc_control "$META_CREATOR_ID" ""
omc_control "$META_STRIP_ID" false
run_with_list PDFUtil.start.batch
check "the run was refused"                 "0" "$(chain_asked PDFUtil.run.single)"
check "and NOT by pointing at another app"  "0" "$(alerts_mention 'use QuickPDF')"
check "the user was told what is missing"   "1" "$([ "$(alerts_count)" -gt 0 ] && echo 1 || echo 0)"

# --------------------------------------------------------------------------
section "mismatched password confirmations stop the run"
# --------------------------------------------------------------------------
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" encrypt
omc_control "$ENC_USER_PW_ID" "hunter2"
omc_control "$ENC_USER_PW_CONFIRM_ID" "hunter3"
run_with_list PDFUtil.start.batch
check "the run was refused"    "0" "$(chain_asked PDFUtil.run.single)"
check "and the mismatch named" "1" "$([ "$(alerts_count)" -gt 0 ] && echo 1 || echo 0)"

# Positive control: matching confirmations get through, so the check above is
# about the mismatch rather than about encrypt being broken.
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" encrypt
omc_control "$ENC_USER_PW_ID" "hunter2"
omc_control "$ENC_USER_PW_CONFIRM_ID" "hunter2"
run_with_list PDFUtil.start.batch
check "matching passwords proceed" "1" "$(chain_requested PDFUtil.run.single)"

# --------------------------------------------------------------------------
section "a password never appears in the process arguments"
# --------------------------------------------------------------------------
# argv is world-readable through ps. The builder must pass the password on
# stdin instead, and this is the assertion that keeps it that way.
reset_document
omc_control "$OPERATION_PICKER_ID" encrypt
omc_control "$ENC_USER_PW_ID" "correct horse battery staple"
omc_control "$ENC_USER_PW_CONFIRM_ID" "correct horse battery staple"
check "the encrypt argv is free of the password" "no" \
    "$(contains "$(pdfutil_args_for encrypt)" "correct horse battery staple")"
check "and the builder did produce arguments" "yes" \
    "$([ -n "$(pdfutil_args_for encrypt)" ] && echo yes || echo no)"

omc_control "$OPERATION_PICKER_ID" decrypt
omc_control "$DEC_PASSWORD_ID" "correct horse battery staple"
check "the decrypt argv is free of the password" "no" \
    "$(contains "$(pdfutil_args_for decrypt)" "correct horse battery staple")"

# --------------------------------------------------------------------------
section "the structure pre-flight asks before discarding an outline"
# --------------------------------------------------------------------------
# pdfutil is silent about degraded output - a reduce that dropped the outline
# still exits 0 - so nothing downstream can report this.
reset_document
seed_list "$outline_pdf"
omc_control "$OPERATION_PICKER_ID" reduce
alert_answer 1                      # Cancel
run_with_list PDFUtil.start.batch
check "the user was asked"        "1" "$(alerts_mention 'Continue anyway')"
check "cancel stopped the run"    "0" "$(chain_asked PDFUtil.run.single)"
check "and the summary says so"   "yes" "$(contains "$(summary)" "Canceled")"

reset_document
seed_list "$outline_pdf"
omc_control "$OPERATION_PICKER_ID" reduce
alert_answer 0                      # Continue
run_with_list PDFUtil.start.batch
check "continuing proceeds to the run" "1" "$(chain_requested PDFUtil.run.single)"

# The positive control: a document with nothing to lose must NOT be interrupted,
# or the pre-flight is just a dialog on every run.
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" reduce
run_with_list PDFUtil.start.batch
check "a plain document is not queried" "0" "$(alerts_mention 'Continue anyway')"
check "and runs straight through"       "1" "$(chain_requested PDFUtil.run.single)"

# An operation that does not redraw must not ask either, whatever the document
# carries.
reset_document
seed_list "$outline_pdf"
omc_control "$OPERATION_PICKER_ID" encrypt
omc_control "$ENC_USER_PW_ID" "pw"
omc_control "$ENC_USER_PW_CONFIRM_ID" "pw"
run_with_list PDFUtil.start.batch
check "encrypt keeps the outline, so it does not ask" "0" \
    "$(alerts_mention 'Continue anyway')"

# --------------------------------------------------------------------------
section "every output kind the builder can produce has a routing arm"
# --------------------------------------------------------------------------
# A new operation whose kind the router does not know falls through to
# "Internal error". Comparing the two sets catches that at the point the kind is
# added rather than the first time a user picks the operation.
kinds=$(for _op in $(operation_tags); do pdfutil_kind_for "$_op"; echo; done \
    | /usr/bin/sort -u | /usr/bin/grep -v '^$')
check "the builder reported some output kinds" "yes" \
    "$([ -n "$kinds" ] && echo yes || echo no)"

unrouted=""
for _kind in $kinds; do
    if ! /usr/bin/grep -q "^    ${_kind})" "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/PDFUtil.start.batch.sh"; then
        unrouted="$unrouted $_kind"
    fi
done
check "every output kind has a routing arm" "" "$unrouted"

# The control: the pattern above must be able to miss something, or it is only
# proving that grep runs.
check "a kind that does not exist is not matched" "1" \
    "$(/usr/bin/grep -q '^    nosuchkind)' "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/PDFUtil.start.batch.sh" && echo 0 || echo 1)"

# --------------------------------------------------------------------------
section "cumulative: no handler wrote to a view id the window does not declare"
# --------------------------------------------------------------------------
check "no undeclared ids" "" "$(ui_unknown_writes)"
check "no bare value write clobbered a table's rows" "" "$(ui_suspect_writes)"
check "the harness detected no misuse" "" "$(ui_errors)"
check "the id set was extracted" "yes" \
    "$([ -s "$OMCTEST_UI/known_ids.txt" ] && echo yes || echo no)"

omctest_end
