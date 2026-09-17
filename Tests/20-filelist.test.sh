#!/bin/sh
# Tests/20-filelist.test.sh - the file list: adding, dropping, removing, selecting.
#
# None of this is reachable by calling library functions, which is all the suite
# this replaced could do. Everything here goes through the real handler scripts,
# so the wiring between them - which handler reads which variable, which one
# chains to which - is under test too.
#
# The list itself lives in table 10 and comes back to the handlers as
# OMC_ACTIONUI_TABLE_10_COLUMN_3_ALL_ROWS. sync_file_list is what reproduces
# that round trip; see lib.test.pdfutil.sh for why the harness cannot.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.pdfutil.sh"

section "preconditions"
check_preconditions

text_pdf="$(fixture text.pdf)"
image_pdf="$(fixture image.pdf)"
photo_png="$(fixture photo.png)"
notes_txt="$(fixture notes.txt)"

# --------------------------------------------------------------------------
section "adding a file through the picker"
# --------------------------------------------------------------------------
reset_document
omc_dialog_answer choose_object "$text_pdf"
run_with_list PDFUtil.add.files
check_status "the handler succeeded" 0

check "the file is in the list"      "1"          "$(file_count)"
check "with its full path"           "$text_pdf"  "$(file_list)"
check "and its display name"         "text.pdf"   "$(file_list_names)"
check "badged as a pdf"              "doc.richtext" "$(file_list_badges)"

# Adding to an empty list selects the first row, and does it by the dedicated
# verb - setting a table's VALUE to select a row is the classic mistake and
# would replace the rows with one string.
check "the first row was selected"   "1" "$(ui_calls "omc_select_row")"
check "the rows survived it"         "1" "$(file_count)"
check "the detail buttons came alive" "1" "$(ui_enabled "$REMOVE_BUTTON_ID")"
check "and so did Info"               "1" "$(ui_enabled "$INFO_BUTTON_ID")"

# --------------------------------------------------------------------------
section "the summary describes the selected pdf"
# --------------------------------------------------------------------------
check "it names the file"     "yes" "$(contains "$(summary)" "text.pdf")"
check "it reports a size"     "yes" "$(contains "$(summary)" "Size:")"
check "it reports a page count" "yes" "$(contains "$(summary)" "Pages:")"
# A page count of "?" is what a failed read prints, and it would satisfy a
# check that only looked for the word "Pages".
check "the page count is a real number" "no" "$(contains "$(summary)" "Pages: ?")"

# --------------------------------------------------------------------------
section "a second add keeps the first file"
# --------------------------------------------------------------------------
omc_dialog_answer choose_object "$photo_png"
run_with_list PDFUtil.add.files

check "both files are listed" "2" "$(file_count)"
check "the pdf is still there" "yes" "$(contains "$(file_list)" "$text_pdf")"
check "and the image arrived"  "yes" "$(contains "$(file_list)" "$photo_png")"
check "the image got the image badge" "yes" "$(contains "$(file_list_badges)" "photo")"

# The list was not empty this time, so the handler must resync the detail pane
# through the normal selection handler rather than force-selecting row 0.
check "it resynced instead of reselecting" "1" \
    "$(chain_requested PDFUtil.files.selection.changed)"

# --------------------------------------------------------------------------
section "the same file twice is still one row"
# --------------------------------------------------------------------------
omc_dialog_answer choose_object "$text_pdf"
run_with_list PDFUtil.add.files
check "the duplicate was folded away" "2" "$(file_count)"

# --------------------------------------------------------------------------
section "a file the tool cannot use is refused"
# --------------------------------------------------------------------------
reset_document
omc_dialog_answer choose_object "$notes_txt"
run_with_list PDFUtil.add.files
check "a text file never enters the list" "0" "$(file_count)"

# The positive control: the filter has to admit something, or the check above
# passes for an applet that refuses everything.
omc_dialog_answer choose_object "$text_pdf"
run_with_list PDFUtil.add.files
check "but a pdf does" "1" "$(file_count)"

# --------------------------------------------------------------------------
section "a mislabeled file is classified by content, not by name"
# --------------------------------------------------------------------------
# mislabeled.pdf is not a PDF. Trusting the extension would put it in the list
# and fail much later, inside the run, with a message about a broken document.
reset_document
mislabeled="$(fixture mislabeled.pdf)"
check "the fixture is named like a pdf" "pdf" "${mislabeled##*.}"
check "but is not one"                  "no"  "$(contains "$(pdfutil_call classify_file "$mislabeled")" pdf)"
omc_dialog_answer choose_object "$mislabeled"
run_with_list PDFUtil.add.files
check "so it never reaches the list" "0" "$(file_count)"

# --------------------------------------------------------------------------
section "dropping files on the table"
# --------------------------------------------------------------------------
reset_document
omc_trigger "$TABLE_ID"
omc_drop "$text_pdf" "$photo_png"
run_with_list PDFUtil.files.drop
check_status "the drop handler succeeded" 0
check "both dropped files landed" "2" "$(file_count)"

# A drop with nothing usable in it must leave the list alone rather than
# clearing it.
omc_trigger "$TABLE_ID"
omc_drop "$notes_txt"
run_with_list PDFUtil.files.drop
check "an unusable drop changes nothing" "2" "$(file_count)"

# --------------------------------------------------------------------------
section "a drop carrying no context at all is survivable"
# --------------------------------------------------------------------------
omc_trigger "$TABLE_ID"
run_with_list PDFUtil.files.drop
check_status "the handler exited cleanly" 0
check "and the list is untouched" "2" "$(file_count)"

# --------------------------------------------------------------------------
section "removing the selected file"
# --------------------------------------------------------------------------
reset_document
omc_dialog_answer choose_object "$text_pdf"
run_with_list PDFUtil.add.files
omc_dialog_answer choose_object "$photo_png"
run_with_list PDFUtil.add.files
check "two files to start" "2" "$(file_count)"

# The two adds above already chained files.selection.changed, and the pending
# slot holds one value - so without this reset the resync check below would be
# satisfied by THEIR chain and would stay green with remove.selected's own
# chain call deleted. Measured, not assumed.
chains_reset
select_file "$text_pdf"
run_with_list PDFUtil.remove.selected
check "one file remains"            "1"            "$(file_count)"
check "and it is the other one"     "$photo_png"   "$(file_list)"
check "the pane was told to resync" "1"            "$(chain_requested PDFUtil.files.selection.changed)"

# --------------------------------------------------------------------------
section "remove with nothing selected removes nothing"
# --------------------------------------------------------------------------
clear_selection
run_with_list PDFUtil.remove.selected
check "the list is unchanged" "1" "$(file_count)"

# --------------------------------------------------------------------------
section "clear all empties the list and resets the buttons"
# --------------------------------------------------------------------------
reset_document
omc_dialog_answer choose_object "$text_pdf"
run_with_list PDFUtil.add.files
check "one file before clearing" "1" "$(file_count)"

run_with_list PDFUtil.clear.all
check "the list is empty"    "0" "$(file_count)"
check "the table was emptied by the dedicated verb" "1" \
    "$(ui_calls "omc_table_remove_all_rows")"

# Clearing chains the selection handler, which is what actually disables the
# buttons. Draining the chain is how the test sees the whole user-visible
# effect rather than only the first half of it.
clear_selection
sync_file_list
omc_drain_chain
check "Remove went dead"  "0" "$(ui_enabled "$REMOVE_BUTTON_ID")"
check "Reveal went dead"  "0" "$(ui_enabled "$REVEAL_BUTTON_ID")"
check "Quick Look went dead" "0" "$(ui_enabled "$PREVIEW_BUTTON_ID")"
check "Info went dead"    "0" "$(ui_enabled "$INFO_BUTTON_ID")"

# --------------------------------------------------------------------------
section "selecting a file that has since been deleted"
# --------------------------------------------------------------------------
reset_document
ghost="$OMCTEST_WORK/ghost.pdf"
/bin/cp "$text_pdf" "$ghost"
omc_dialog_answer choose_object "$ghost"
run_with_list PDFUtil.add.files
check "it is listed" "1" "$(file_count)"

/bin/rm -f "$ghost"
select_file "$ghost"
run_with_list PDFUtil.files.selection.changed
check "the summary says the file is gone" "yes" \
    "$(contains "$(summary)" "no longer exists")"
# The buttons stay live on purpose: Remove is the one action that still makes
# sense for a row pointing at nothing.
check "Remove is still offered" "1" "$(ui_enabled "$REMOVE_BUTTON_ID")"

# --------------------------------------------------------------------------
section "a password-protected pdf is explained, not reported as blank"
# --------------------------------------------------------------------------
reset_document
locked="$(fixture locked.pdf)"
omc_dialog_answer choose_object "$locked"
run_with_list PDFUtil.add.files
select_file "$locked"
run_with_list PDFUtil.files.selection.changed
check "the summary says it is protected" "yes" \
    "$(contains "$(summary)" "password-protected")"
check "and names the way out"            "yes" \
    "$(contains "$(summary)" "Remove Password")"

# --------------------------------------------------------------------------
section "adding keeps the list's order and appends the new files by name"
# --------------------------------------------------------------------------
# Merge and Build PDF from Images take the files in list order, and Up and Down
# arrange it, so an add must not sort the files already there.
reset_document
order_dir="$OMCTEST_WORK/order"
/bin/mkdir -p "$order_dir"
for _name in c a b d; do /bin/cp "$text_pdf" "$order_dir/$_name.pdf"; done
add_one() { omc_dialog_answer choose_object "$1"; run_with_list PDFUtil.add.files; }
names_order() { file_list_names | /usr/bin/paste -sd '|' -; }
add_one "$order_dir/c.pdf"
add_one "$order_dir/a.pdf"
check "a later add goes after the earlier one" "c.pdf|a.pdf" "$(names_order)"
add_one "$order_dir/d.pdf
$order_dir/b.pdf
$order_dir/a.pdf"
check "the new ones follow sorted, and a repeat keeps its place" \
    "c.pdf|a.pdf|b.pdf|d.pdf" "$(names_order)"

select_file "$order_dir/a.pdf"
run_with_list PDFUtil.remove.selected
check "Remove keeps the order of the rest" "c.pdf|b.pdf|d.pdf" "$(names_order)"

# --------------------------------------------------------------------------
section "Up and Down move the selected file one place, and stop at either end"
# --------------------------------------------------------------------------
reset_document
order_a="$OMCTEST_WORK/order a.pdf"
order_b="$OMCTEST_WORK/order\\b.pdf"
order_c="$OMCTEST_WORK/order c.pdf"
for _path in "$order_a" "$order_b" "$order_c"; do /bin/cp "$text_pdf" "$_path"; done
# The backslash path is the one the selected file swaps with, not the selected
# one: the harness finds a row by content through awk -v, which reads a
# backslash as an escape, so it could not select that row even though the app
# can.
add_one "$order_b"
add_one "$order_a"
add_one "$order_c"
list_order() { file_list | /usr/bin/paste -sd '|' -; }
check "three files in the order they were added" "$order_b|$order_a|$order_c" "$(list_order)"

clear_selection
run_with_list PDFUtil.files.selection.changed
check "both wait for a selection" "0 0" \
    "$(ui_enabled "$MOVE_UP_BUTTON_ID") $(ui_enabled "$MOVE_DOWN_BUTTON_ID")"
run_with_list PDFUtil.move.selected.up
check "a move with nothing selected changes nothing" "$order_b|$order_a|$order_c" "$(list_order)"

select_file "$order_a"
run_with_list PDFUtil.files.selection.changed
check "a file in the middle can go either way" "1 1" \
    "$(ui_enabled "$MOVE_UP_BUTTON_ID") $(ui_enabled "$MOVE_DOWN_BUTTON_ID")"

run_with_list PDFUtil.move.selected.up
check_status "move up exits cleanly" 0
check "it swapped with the backslash path" "$order_a|$order_b|$order_c" "$(list_order)"
check "the names moved with the paths" "order a.pdf|order\\b.pdf|order c.pdf" "$(names_order)"
check "and the badges too" "doc.richtext|doc.richtext|doc.richtext" \
    "$(file_list_badges | /usr/bin/paste -sd '|' -)"
check "it stays selected, found by its path" "0" "$(ui_selection "$TABLE_ID")"
check "at the top, only Down is offered" "0 1" \
    "$(ui_enabled "$MOVE_UP_BUTTON_ID") $(ui_enabled "$MOVE_DOWN_BUTTON_ID")"

run_with_list PDFUtil.move.selected.up
check "moving the first one up changes nothing" "$order_a|$order_b|$order_c" "$(list_order)"

run_with_list PDFUtil.move.selected.down
run_with_list PDFUtil.move.selected.down
check "it moved down twice" "$order_b|$order_c|$order_a" "$(list_order)"
check "and is still selected" "2" "$(ui_selection "$TABLE_ID")"
check "at the bottom, only Up is offered" "1 0" \
    "$(ui_enabled "$MOVE_UP_BUTTON_ID") $(ui_enabled "$MOVE_DOWN_BUTTON_ID")"

run_with_list PDFUtil.move.selected.down
check "moving the last one down changes nothing" "$order_b|$order_c|$order_a" "$(list_order)"

# Adding to an empty list selects the first row, and places the buttons for it.
reset_document
add_one "$order_dir/c.pdf
$order_dir/d.pdf"
check "a first add offers only Down" "0 1" \
    "$(ui_enabled "$MOVE_UP_BUTTON_ID") $(ui_enabled "$MOVE_DOWN_BUTTON_ID")"

# --------------------------------------------------------------------------
section "a pdf that opens without a password but is protected says so"
# --------------------------------------------------------------------------
reset_document
restricted="$(fixture restricted.pdf)"
omc_dialog_answer choose_object "$restricted"
run_with_list PDFUtil.add.files
select_file "$restricted"
run_with_list PDFUtil.files.selection.changed
check "the summary says it opens without a password" "yes" \
    "$(contains "$(summary)" "Encrypted: Yes, but it opens without a password")"
check "and what it does not allow" "yes" \
    "$(contains "$(summary)" "Does not allow: removing or rotating pages, editing, adding comments and filling in forms")"
check "and that removing it needs no password" "yes" \
    "$(contains "$(summary)" "no password is needed")"
# The control: a plain PDF says none of this.
reset_document
omc_dialog_answer choose_object "$text_pdf"
run_with_list PDFUtil.add.files
check "a plain pdf is not encrypted" "yes" "$(contains "$(summary)" "Encrypted: No")"
check "and names no restrictions" "no" "$(contains "$(summary)" "Does not allow")"

# --------------------------------------------------------------------------
section "the Remove Password notice describes the listed pdfs"
# --------------------------------------------------------------------------
decrypt_notice() { ui_value "$NOTICE_DECRYPT_ID"; }
decrypt_prompt() { ui_prop "$DEC_PASSWORD_ID" prompt; }

reset_document
omc_control "$OPERATION_PICKER_ID" decrypt
omc_dialog_answer choose_object "$restricted"
run_with_list PDFUtil.add.files
check "one restricted pdf: no password needed" "yes" \
    "$(contains "$(decrypt_notice)" "No password needed: this PDF opens without one, but it does not allow removing or rotating pages")"
check "and the field says so" "not needed - this PDF opens without one" "$(decrypt_prompt)"

omc_dialog_answer choose_object "$locked"
run_with_list PDFUtil.add.files
check "adding a locked pdf names it" "yes" \
    "$(contains "$(decrypt_notice)" "\"locked.pdf\" needs the password that opens it")"
check "and says the other needs none" "yes" "$(contains "$(decrypt_notice)" "The other protected PDF opens without a password and needs none")"
check "and the field asks for the password again" "the password that opens these PDFs" "$(decrypt_prompt)"

chains_reset
select_file "$locked"
run_with_list PDFUtil.remove.selected
check "removing the locked pdf goes back to no password needed" "yes" \
    "$(contains "$(decrypt_notice)" "No password needed")"

run_with_list PDFUtil.clear.all
check "clearing the list restores the plain notice" "Saves an unlocked copy; the original is untouched." \
    "$(decrypt_notice)"

locked_copy="$OMCTEST_WORK/locked copy.pdf"
/bin/cp "$locked" "$locked_copy"
omc_dialog_answer choose_object "$locked
$locked_copy"
run_with_list PDFUtil.add.files
check "two locked pdfs: both need the password" "Both PDFs need the password that opens them. Saves unlocked copies; the originals are untouched." \
    "$(decrypt_notice)"
run_with_list PDFUtil.clear.all

# Picking the operation with PDFs already listed describes them too.
reset_document
omc_dialog_answer choose_object "$text_pdf"
run_with_list PDFUtil.add.files
check "another operation leaves the notice alone" "" "$(decrypt_notice)"
omc_control "$OPERATION_PICKER_ID" decrypt
run_with_list PDFUtil.operation.changed
check "picking Remove Password says there is nothing to remove" \
    "This PDF is not protected, so there is nothing to remove." "$(decrypt_notice)"

# --------------------------------------------------------------------------
section "the engine only gets variables the manifest actually declares"
# --------------------------------------------------------------------------
# The harness is more generous than the engine: it exports whatever a test sets,
# while the engine exports a scanned variable only where the command definition
# asks for it. So a handler reading the whole file list from a command that
# never declares it passes here and comes up empty in the shipped app. This
# compares the two lists rather than trusting either.
readers=$(handlers_reading_file_list)
check "some handler reads the whole list" "yes" \
    "$([ -n "$readers" ] && echo yes || echo no)"
# Indirect readers are the majority here, so if they are missing from the list
# the cross-check below is only inspecting a handful of files.
check "and the indirect readers were found too" "yes" \
    "$(contains "$readers" "PDFUtil.run.single")"

declarers=$(/usr/bin/python3 - "$OMC_APP_BUNDLE_PATH/Contents/Resources/Command.json" \
                               "OMC_ACTIONUI_TABLE_${TABLE_ID}_COLUMN_${TABLE_PATH_COLUMN}_ALL_ROWS" <<'PY'
import json, sys
manifest, wanted = sys.argv[1], sys.argv[2]
doc = json.load(open(manifest))
for command in doc.get("COMMAND_LIST", []):
    if wanted in (command.get("ENVIRONMENT_VARIABLES") or {}):
        print(command.get("COMMAND_ID", ""))
PY
)
check "the manifest declares it somewhere" "yes" \
    "$([ -n "$declarers" ] && echo yes || echo no)"

undeclared=""
for _reader in $readers; do
    case "
$declarers
" in
        *"
$_reader
"*) ;;
        *) undeclared="$undeclared $_reader" ;;
    esac
done
check "every handler that reads the list is given it by the manifest" "" "$undeclared"

# --------------------------------------------------------------------------
section "cumulative: no handler wrote to a view id the window does not declare"
# --------------------------------------------------------------------------
check "no undeclared ids" "" "$(ui_unknown_writes)"
check "no bare value write clobbered a table's rows" "" "$(ui_suspect_writes)"
check "the harness detected no misuse" "" "$(ui_errors)"
check "the id set was extracted" "yes" \
    "$([ -s "$OMCTEST_UI/known_ids.txt" ] && echo yes || echo no)"

omctest_end
