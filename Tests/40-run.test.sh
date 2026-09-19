#!/bin/sh
# Tests/40-run.test.sh - the runners: real pdfutil, real output files.
#
# pdfutil is deterministic and safe to run headless, so it is run for real
# rather than stubbed. A staging-and-move assertion is worth nothing against a
# fake that never writes anything.
#
# What is under test here is the runner handlers, not the engine: that Cancel
# writes no file, that a failed run leaves nothing behind under the name the
# user chose, that the extension is corrected, and that a collision does not
# silently overwrite. 60-operations covers the other half - that the command
# line the builder produced actually runs - and ./test.sh covers pdfutil's own
# verbs; neither reaches these handlers, because they need a Save As answer and
# a file list, which are engine-supplied.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.pdfutil.sh"

section "preconditions"
check_preconditions

text_pdf="$(fixture text.pdf)"
photo_png="$(fixture photo.png)"
restricted_pdf="$(fixture restricted.pdf)"

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
section "a single-file run writes the file the user named"
# --------------------------------------------------------------------------
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" linearize
out="$OMCTEST_WORK/linearized.pdf"
omc_dialog_answer save_as "$out"
run_with_list PDFUtil.run.single
check_status "the runner succeeded" 0

check_exists "the output file is there" "$out"
check "and it is a real pdf" "pdf" "$(pdfutil_call classify_file "$out")"
check "the input was left alone" "yes" \
    "$([ -s "$text_pdf" ] && echo yes || echo no)"
check "the summary reports success for that file" "yes" \
    "$(contains "$(summary)" "OK text.pdf")"
check "and names where it went" "yes" "$(contains "$(summary)" "Output: $out")"

# Nothing staged should survive a successful run either.
check "no staging file was left behind" "0" \
    "$(/usr/bin/find "$OMCTEST_WORK" -maxdepth 1 -name '.pdfutil.*' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

# --------------------------------------------------------------------------
section "cancelling the save panel writes nothing"
# --------------------------------------------------------------------------
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" linearize
before="$(/usr/bin/find "$OMCTEST_WORK" -maxdepth 1 -type f | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
# An empty save_as answer is how the harness spells Cancel.
omc_dialog_answer save_as ""
run_with_list PDFUtil.run.single
check_status "the runner still exits cleanly" 0
check "the summary says it was canceled" "yes" "$(contains "$(summary)" "Canceled")"
after="$(/usr/bin/find "$OMCTEST_WORK" -maxdepth 1 -type f | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
check "no file was created" "$before" "$after"

# --------------------------------------------------------------------------
section "the extension is appended, never substituted"
# --------------------------------------------------------------------------
# Text extraction asked to write "extracted.pdf" must not produce a .pdf holding
# plain text - the file would open in a PDF reader and fail. The applet appends
# rather than replacing, so the name the user typed is never destroyed: what
# comes out is extracted.pdf.txt, which is ugly and honest rather than wrong.
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" text
omc_dialog_answer save_as "$OMCTEST_WORK/extracted.pdf"
run_with_list PDFUtil.run.text
check_absent "nothing was written under the misleading name" "$OMCTEST_WORK/extracted.pdf"
check_exists "the real extension was appended"              "$OMCTEST_WORK/extracted.pdf.txt"
# Every page's marker, not just the first: an extraction that stopped after
# page one would still satisfy a check for any single string.
extracted="$(/bin/cat "$OMCTEST_WORK/extracted.pdf.txt" 2>/dev/null)"
check "the first page came through" "yes" "$(contains "$extracted" "PAGE-1-MARKER")"
check "and so did the last"         "yes" "$(contains "$extracted" "PAGE-5-MARKER")"
check "with the page-3 needle"      "yes" "$(contains "$extracted" "needle in the haystack")"

# The ordinary case, and the control for the one above: a name that already
# carries the right extension is passed through untouched.
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" text
omc_dialog_answer save_as "$OMCTEST_WORK/plain.txt"
run_with_list PDFUtil.run.text
check_exists "the chosen name was used as typed" "$OMCTEST_WORK/plain.txt"
check_absent "with nothing appended to it"       "$OMCTEST_WORK/plain.txt.txt"

# --------------------------------------------------------------------------
section "only a name the Save panel confirmed may be overwritten"
# --------------------------------------------------------------------------
# The Save As panel has already asked the user about replacing the name they
# typed, so overwriting it is the correct behavior, not a bug. What is NOT
# covered by that confirmation is a name the applet derived afterwards - the
# user never saw it and never agreed to lose it.
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" linearize
confirmed="$OMCTEST_WORK/confirmed.pdf"
printf 'stale output from an earlier run' > "$confirmed"
omc_dialog_answer save_as "$confirmed"
run_with_list PDFUtil.run.single
check "the confirmed name was replaced, as the panel promised" "no" \
    "$(contains "$(/bin/cat "$confirmed")" "stale output")"
check "and holds the new run's output" "pdf" "$(pdfutil_call classify_file "$confirmed")"

# The derived name: text extraction appends .txt, and that appended name was
# never shown to the user, so an existing file there must survive.
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" text
printf 'never confirmed, must survive' > "$OMCTEST_WORK/derived.pdf.txt"
omc_dialog_answer save_as "$OMCTEST_WORK/derived.pdf"
run_with_list PDFUtil.run.text
check "the derived name was not clobbered" "never confirmed, must survive" \
    "$(/bin/cat "$OMCTEST_WORK/derived.pdf.txt")"
check_exists "the run went to a numbered name instead" "$OMCTEST_WORK/derived.pdf 2.txt"

# --------------------------------------------------------------------------
section "saving over the input file works, because the run is staged"
# --------------------------------------------------------------------------
# Overwriting the document you started from is what the Save panel's default
# name invites, so it has to work.
#
# Note what this does NOT prove: it is not a test of the staging file. pdfutil
# is PDFKit-based and reads the whole document before writing, so it survives
# input == output on its own - measured by pointing it at one path for both,
# which succeeds. The staging file earns itself on the failure path instead, in
# the section below.
reset_document
inplace="$OMCTEST_WORK/inplace.pdf"
/bin/cp "$text_pdf" "$inplace"
pages_before="$(pdfutil_call pdf_page_count "$inplace")"
check "the input starts as a readable pdf" "yes" \
    "$([ -n "$pages_before" ] && [ "$pages_before" -gt 0 ] 2>/dev/null && echo yes || echo no)"

seed_list "$inplace"
omc_control "$OPERATION_PICKER_ID" linearize
omc_dialog_answer save_as "$inplace"
run_with_list PDFUtil.run.single
check_status "the runner succeeded" 0
check "the file is still a pdf afterwards" "pdf" "$(pdfutil_call classify_file "$inplace")"
check "with all its pages intact"          "$pages_before" \
    "$(pdfutil_call pdf_page_count "$inplace")"
check "and the summary reports success"    "yes" "$(contains "$(summary)" "OK inplace.pdf")"

# --------------------------------------------------------------------------
section "a failed run leaves nothing under the name the user chose"
# --------------------------------------------------------------------------
# Hand the PDF operation an input that is not a PDF. The engine refuses, and the
# staging file must be cleaned up rather than moved into place.
reset_document
notpdf="$OMCTEST_WORK/broken.pdf"
printf 'this is not a pdf at all' > "$notpdf"
# Past add_files_to_table's classifier on purpose: this is about the runner's
# failure path, which a user reaches when a file changes underneath them.
seed_list "$text_pdf"
omctest_setvar "OMC_ACTIONUI_TABLE_${TABLE_ID}_COLUMN_${TABLE_PATH_COLUMN}_ALL_ROWS" "$notpdf"
omc_control "$OPERATION_PICKER_ID" linearize
failed_out="$OMCTEST_WORK/should-not-exist.pdf"
omc_dialog_answer save_as "$failed_out"
omc_run PDFUtil.run.single
check_status "the runner still exits cleanly" 0
check_absent "no output file was created" "$failed_out"
check "the summary reports the failure" "yes" "$(contains "$(summary)" "FAILED")"
check "no staging file was left behind" "0" \
    "$(/usr/bin/find "$OMCTEST_WORK" -maxdepth 1 -name '.pdfutil.*' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

# --------------------------------------------------------------------------
section "a failed run does not destroy a file already at that path"
# --------------------------------------------------------------------------
# This is what the staging file is for, and the only scenario that tells a
# staged run from an unstaged one. The user picks a name that already holds
# something, the run fails, and the previous file has to still be there - an
# unstaged run truncates it on the way to failing and the contents are gone
# with nothing to say so.
reset_document
seed_list "$text_pdf"
survivor="$OMCTEST_WORK/survivor.pdf"
/bin/cp "$text_pdf" "$survivor"
survivor_size="$(/usr/bin/stat -f %z "$survivor")"

# Point the run at an input the engine will refuse, so the failure is the
# engine's and not the harness's.
notpdf2="$OMCTEST_WORK/broken2.pdf"
printf 'this is not a pdf at all' > "$notpdf2"
omctest_setvar "OMC_ACTIONUI_TABLE_${TABLE_ID}_COLUMN_${TABLE_PATH_COLUMN}_ALL_ROWS" "$notpdf2"
omc_control "$OPERATION_PICKER_ID" linearize
omc_dialog_answer save_as "$survivor"
omc_run PDFUtil.run.single
check "the run failed, as intended"        "yes" "$(contains "$(summary)" "FAILED")"
check_exists "the existing file is still there" "$survivor"
check "and is byte for byte what it was"   "$survivor_size" \
    "$(/usr/bin/stat -f %z "$survivor" 2>/dev/null)"
check "and still opens as a pdf"           "pdf" "$(pdfutil_call classify_file "$survivor")"

# --------------------------------------------------------------------------
section "an input that vanished between Save and run is reported, not crashed on"
# --------------------------------------------------------------------------
reset_document
ghost="$OMCTEST_WORK/ghost.pdf"
/bin/cp "$text_pdf" "$ghost"
seed_list "$ghost"
/bin/rm -f "$ghost"
omc_control "$OPERATION_PICKER_ID" linearize
omc_dialog_answer save_as "$OMCTEST_WORK/from-ghost.pdf"
run_with_list PDFUtil.run.single
check_status "the runner exits cleanly" 0
check "it says the input is gone" "yes" "$(contains "$(summary)" "no longer exists")"
check_absent "and wrote nothing" "$OMCTEST_WORK/from-ghost.pdf"

# --------------------------------------------------------------------------
section "merging two documents produces one with both"
# --------------------------------------------------------------------------
reset_document
second="$OMCTEST_WORK/second.pdf"
/bin/cp "$text_pdf" "$second"
seed_list "$text_pdf" "$second"
omc_control "$OPERATION_PICKER_ID" merge
merged="$OMCTEST_WORK/merged.pdf"
omc_dialog_answer save_as "$merged"
run_with_list PDFUtil.run.merge
check_status "the merge succeeded" 0
check_exists "the merged file exists" "$merged"

# The page count is the assertion with teeth: a merge that silently copied only
# the first input would still leave a valid PDF at that path.
pages_one="$(pdfutil_call pdf_page_count "$text_pdf")"
pages_merged="$(pdfutil_call pdf_page_count "$merged")"
check "the source has a readable page count" "yes" \
    "$([ -n "$pages_one" ] && [ "$pages_one" -gt 0 ] 2>/dev/null && echo yes || echo no)"
check "the merge has both documents' pages" "$((pages_one * 2))" "$pages_merged"

# --------------------------------------------------------------------------
section "building a pdf from an image"
# --------------------------------------------------------------------------
reset_document
seed_list "$photo_png"
omc_control "$OPERATION_PICKER_ID" frompages
assembled="$OMCTEST_WORK/assembled.pdf"
omc_dialog_answer save_as "$assembled"
run_with_list PDFUtil.run.assemble
check_status "the assemble succeeded" 0
check_exists "the pdf exists" "$assembled"
check "and it really is a pdf" "pdf" "$(pdfutil_call classify_file "$assembled")"
check "one image made one page" "1" "$(pdfutil_call pdf_page_count "$assembled")"

# --------------------------------------------------------------------------
section "a batch run writes one output per input"
# --------------------------------------------------------------------------
reset_document
dest="$OMCTEST_WORK/batch-out"
/bin/mkdir -p "$dest"
a="$OMCTEST_WORK/a.pdf"; b="$OMCTEST_WORK/b.pdf"
/bin/cp "$text_pdf" "$a"; /bin/cp "$text_pdf" "$b"
seed_list "$a" "$b"
omc_control "$OPERATION_PICKER_ID" linearize
omc_dialog_answer choose_folder "$dest"
run_with_list PDFUtil.run.batch
check_status "the batch succeeded" 0
check "both files were written" "2" \
    "$(/usr/bin/find "$dest" -maxdepth 1 -name '*.pdf' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
check "the summary counts them" "yes" "$(contains "$(summary)" "2")"
check "no staging file survived in the destination" "0" \
    "$(/usr/bin/find "$dest" -maxdepth 1 -name '.pdfutil.*' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

# --------------------------------------------------------------------------
section "a reduce that could not shrink the file says so"
# --------------------------------------------------------------------------
# The assembled pdf is a smooth gradient stored losslessly, which JPEG cannot
# beat, so pdfutil declines its own result: exit 0, an unchanged copy, and one
# line on stderr saying why. Before the note existed the summary read "OK ...
# 104 KB -> 104 KB" and nothing else, which looks exactly like a reduce that is
# broken. The size comparison is what keeps the two note checks honest - if a
# future Quartz starts shrinking this file, it fails here rather than letting
# "no note" pass for the wrong reason.
reset_document
seed_list "$assembled"
omc_control "$OPERATION_PICKER_ID" reduce
declined="$OMCTEST_WORK/declined.pdf"
omc_dialog_answer save_as "$declined"
run_with_list PDFUtil.run.single
check_status "the runner succeeded" 0
check_exists "an output was still written" "$declined"
check "and it is the original, byte for byte" "same" \
    "$(/usr/bin/cmp -s "$assembled" "$declined" && echo same || echo different)"
check "the summary still reports the file as handled" "yes" \
    "$(contains "$(summary)" "OK assembled.pdf")"
check "and explains why nothing changed" "yes" \
    "$(contains "$(summary)" "could not be made smaller")"
check "naming the copy for what it is" "yes" \
    "$(contains "$(summary)" "unchanged copy of the original")"

# The batch runner assembles its own summary, so it needs its own look.
reset_document
dest="$OMCTEST_WORK/declined-batch"
/bin/mkdir -p "$dest"
seed_list "$assembled" "$(fixture image.pdf)"
omc_control "$OPERATION_PICKER_ID" reduce
omc_dialog_answer choose_folder "$dest"
run_with_list PDFUtil.run.batch
check_status "the batch succeeded" 0
check "the batch summary carries the same explanation" "yes" \
    "$(contains "$(summary)" "could not be made smaller")"
# image.pdf is a real raster scan, which reduce does shrink, so exactly one
# file earns the note. Not text.pdf: with nothing to recompress, the redraw's
# overhead makes it 0.3% larger and it is declined as well.
check "only for the file it applies to" "1" \
    "$(summary | /usr/bin/grep -c 'could not be made smaller')"

# --------------------------------------------------------------------------
section "a copy that drops an open-freely pdf's restrictions says so"
# --------------------------------------------------------------------------
# restricted.pdf opens without a password; its owner password forbids page
# changes, editing, comments and form filling. Nothing is refused over it - the
# summary just says when the saved copy no longer carries the restrictions.
restricted_words="removing or rotating pages, editing, adding comments and filling in forms"

reset_document
seed_list "$restricted_pdf"
omc_control "$OPERATION_PICKER_ID" extract
omc_control "$EXT_RANGE_ID" "1-2"
extracted="$OMCTEST_WORK/restricted-extract.pdf"
omc_dialog_answer save_as "$extracted"
run_with_list PDFUtil.run.single
check_exists "extract wrote a copy" "$extracted"
check "the copy is not encrypted" "not encrypted" \
    "$(pdfutil_call file_has_encryption "$extracted" && echo encrypted || echo "not encrypted")"
check "and the summary says what the original did not allow" "yes" \
    "$(contains "$(summary)" "Note: The original did not allow ${restricted_words}; this copy has no such restrictions.")"

# PDFKit re-saves 128-bit encryption, so a crop keeps the restrictions and there
# is nothing to say.
reset_document
seed_list "$restricted_pdf"
omc_control "$OPERATION_PICKER_ID" crop
omc_control "$CROP_VALUES_ID" "10,10,10,10"
cropped="$OMCTEST_WORK/restricted-crop.pdf"
omc_dialog_answer save_as "$cropped"
run_with_list PDFUtil.run.single
check_exists "crop wrote a copy" "$cropped"
check "the crop kept the encryption" "encrypted" \
    "$(pdfutil_call file_has_encryption "$cropped" && echo encrypted || echo "not encrypted")"
check "so there is no note" "no" "$(contains "$(summary)" "Note:")"

# A plain pdf gets no note either.
reset_document
seed_list "$text_pdf"
omc_control "$OPERATION_PICKER_ID" extract
omc_control "$EXT_RANGE_ID" "1"
omc_dialog_answer save_as "$OMCTEST_WORK/plain-extract.pdf"
run_with_list PDFUtil.run.single
check "a plain pdf's copy has no note" "no" "$(contains "$(summary)" "Note:")"

# Remove Password drops the restrictions by design, so it does not remark on it.
reset_document
seed_list "$restricted_pdf"
omc_control "$OPERATION_PICKER_ID" decrypt
unrestricted="$OMCTEST_WORK/restricted-decrypt.pdf"
omc_dialog_answer save_as "$unrestricted"
run_with_list PDFUtil.run.single
check_exists "remove password wrote a copy" "$unrestricted"
check "with no note" "no" "$(contains "$(summary)" "Note:")"

# A batch notes it per file, and only for the file it applies to.
reset_document
dest="$OMCTEST_WORK/restricted-batch"
/bin/mkdir -p "$dest"
seed_list "$restricted_pdf" "$text_pdf"
omc_control "$OPERATION_PICKER_ID" extract
omc_control "$EXT_RANGE_ID" "1"
omc_dialog_answer choose_folder "$dest"
run_with_list PDFUtil.run.batch
check "the batch notes the restricted file" "yes" \
    "$(contains "$(summary)" "OK restricted.pdf: ")"
check "one note, for one file" "1" \
    "$(summary | /usr/bin/grep -c "Note: The original did not allow")"

# Split writes parts into a folder; the note is judged from the first part.
reset_document
dest="$OMCTEST_WORK/restricted-split"
/bin/mkdir -p "$dest"
seed_list "$restricted_pdf"
omc_control "$OPERATION_PICKER_ID" split
omc_dialog_answer choose_folder "$dest"
run_with_list PDFUtil.run.batch
check "split notes it too" "1" \
    "$(summary | /usr/bin/grep -c "Note: The original did not allow")"

# Merge names the restricted input.
reset_document
seed_list "$text_pdf" "$restricted_pdf"
omc_control "$OPERATION_PICKER_ID" merge
omc_dialog_answer save_as "$OMCTEST_WORK/restricted-merge.pdf"
run_with_list PDFUtil.run.merge
check "merge names the restricted input" "yes" \
    "$(contains "$(summary)" "Note: \"restricted.pdf\" had restrictions set by its creator; the result has none.")"

# --------------------------------------------------------------------------
section "cumulative: no handler wrote to a view id the window does not declare"
# --------------------------------------------------------------------------
check "no undeclared ids" "" "$(ui_unknown_writes)"
check "no bare value write clobbered a table's rows" "" "$(ui_suspect_writes)"
check "the harness detected no misuse" "" "$(ui_errors)"
check "the id set was extracted" "yes" \
    "$([ -s "$OMCTEST_UI/known_ids.txt" ] && echo yes || echo no)"

omctest_end
