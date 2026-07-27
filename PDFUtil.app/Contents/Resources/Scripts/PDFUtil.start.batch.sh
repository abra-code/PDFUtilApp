#!/bin/bash
# PDFUtil.start.batch.sh - Save button: validate, then route to the right runner
#
# Routing branches on operation x input count x OUTPUT KIND, not on count alone.
# That is the structural difference from QuickPDF: there the output is always a
# PDF, here it can be a PDF, a text file or a set of images, and the destination
# prompt has to match. The prompt kind is fixed per command in Command.json
# (SAVE_AS_DIALOG vs CHOOSE_FOLDER_DIALOG, with the right default file name), so
# choosing a prompt means chaining to the command that declares it:
#
#   pdf,    1 input                  -> PDFUtil.run.single   Save As, .pdf
#   text,   1 input                  -> PDFUtil.run.text     Save As, .txt
#   images, 1 input, 1 page selected -> PDFUtil.run.image    Save As, image
#   merged, 2+ inputs                -> PDFUtil.run.merge    Save As, .pdf
#   parts   (split, any input count) -> PDFUtil.run.batch    destination folder
#   anything else                    -> PDFUtil.run.batch    destination folder
#
# The single-page test for images exists because render has two output modes and
# only one of them is a file: with several pages selected -o is a prefix and
# pdfutil writes <prefix>-001.<ext>, which a Save panel cannot express. Getting
# it wrong is not fatal - run_save_as detects the prefix form after the fact -
# but getting it right is what makes Save As available at all.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.sh"

operation="$(current_operation)"
all_paths="$OMC_ACTIONUI_TABLE_10_COLUMN_3_ALL_ROWS"

if [ -z "$all_paths" ]; then
    "$alert_tool" --level caution --title "PDFUtil" \
        "Add at least one file to the list first."
    exit 0
fi

# build_pdfutil_args is what knows which operations exist; asking it keeps the
# router from carrying a second list that could drift out of step.
if ! build_pdfutil_args "$operation"; then
    # Deliberately not a list of what does work: that sentence went stale on
    # every stage that landed, and build_pdfutil_args is already the
    # authoritative record of which operations have been built.
    "$alert_tool" --level caution --title "PDFUtil" \
        "$(operation_label "$operation") is not available yet.

Pick another operation, or use QuickPDF if it offers this one."
    exit 0
fi

# Settings the run cannot proceed with - mismatched password confirmations, an
# empty page range, a malformed crop rectangle. Checked before the per-file
# pre-flight because it is instant and needs no disk access, and before any
# destination dialog because the alternative is asking the user to name an
# output file for a run that was never going to start.
settings_issue="$(settings_problem "$operation")"
if [ -n "$settings_issue" ]; then
    "$alert_tool" --level caution --title "PDFUtil" "$settings_issue"
    set_summary "$(operation_label "$operation") did not run.
${settings_issue}"
    exit 0
fi

# The pre-flight below spawns `file` and `pdfutil info` per entry, about 100 ms
# a file. That is invisible for a handful and a silent several-second pause for
# a big list, so say what is happening first.
if [ "$(printf '%s\n' "$all_paths" | /usr/bin/grep -c .)" -gt 2 ]; then
    set_summary "Checking the file list..."
fi

file_count=0
non_pdf_count=0
locked_count=0
locked_name=""
first_file=""
risk_count=0
risk_name=""
risk_kind=""

# Only pay for the structure check when the answer could change anything. For
# every other operation the loop below does exactly what it did before.
redraws=0
if operation_redraws "$operation"; then
    redraws=1
fi

while IFS= read -r file_path; do
    [ -z "$file_path" ] && continue
    file_count=$((file_count + 1))
    [ -z "$first_file" ] && first_file="$file_path"
    if [ "$(classify_file "$file_path")" != "pdf" ]; then
        non_pdf_count=$((non_pdf_count + 1))
    elif [ "$operation" != "decrypt" ] && pdf_is_locked "$file_path"; then
        # Remove Password is exempt: a locked file is precisely its input, and
        # the test is skipped rather than counted-and-ignored so it does not pay
        # for an `info` call per file it already knows the answer for.
        locked_count=$((locked_count + 1))
        [ -z "$locked_name" ] && locked_name="$(/usr/bin/basename "$file_path")"
    elif [ "$redraws" = "1" ]; then
        # Free: the guard above just ran `info` on this file and cached it, so
        # this reads that output rather than parsing the document again.
        file_risk="$(pdf_structure_at_risk "$file_path")"
        if [ -n "$file_risk" ]; then
            risk_count=$((risk_count + 1))
            if [ -z "$risk_name" ]; then
                risk_name="$(/usr/bin/basename "$file_path")"
                risk_kind="$file_risk"
            fi
        fi
    fi
done <<< "$all_paths"

if [ "$file_count" -eq 0 ]; then
    "$alert_tool" --level caution --title "PDFUtil" \
        "Add at least one file to the list first."
    exit 0
fi

# Every operation built so far reads a PDF. Say which items are wrong and how
# many, rather than letting pdfutil fail per file with a message about a format
# the user never chose. Build PDF from Images (Stage 8) is the one operation
# that will need the opposite test.
if [ "$non_pdf_count" -gt 0 ]; then
    set_summary "$(operation_label "$operation") needs PDF files.
${non_pdf_count} of ${file_count} items in the list are not PDFs."
    "$alert_tool" --level caution --title "PDFUtil" \
        "$(operation_label "$operation") needs PDF files; ${non_pdf_count} of ${file_count} items in the list are not PDFs.

Remove them from the list and try again."
    exit 0
fi

# Password-protected PDFs are out of scope for everything except Remove
# Password. Stopping here, before any destination has been chosen, is the whole
# point: the alternative is a batch that prompts for a folder, runs, and then
# reports a row of identical failures the user cannot act on from that screen.
#
# Remove Password is exempt, in the loop above. Set Password is NOT: encrypting
# an already-protected file means opening it first, and this operation has no
# field for the password it is already carrying.
if [ "$locked_count" -gt 0 ]; then
    if [ "$locked_count" -eq 1 ]; then
        locked_desc="\"${locked_name}\" is password-protected"
    elif [ "$locked_count" -eq "$file_count" ]; then
        locked_desc="all ${file_count} files are password-protected"
    else
        locked_desc="${locked_count} of the ${file_count} files are password-protected, starting with \"${locked_name}\""
    fi
    set_summary "$(operation_label "$operation") cannot read protected PDFs.
${locked_desc}.

Use Remove Password on them first."
    "$alert_tool" --level caution --title "PDFUtil" \
        "$(operation_label "$operation") cannot read protected PDFs: ${locked_desc}.

Use Remove Password on them first, then run $(operation_label "$operation") on the unlocked copies."
    exit 0
fi

# Structure pre-flight. pdfutil is silent about degraded output - a reduce that
# dropped the outline still exits 0 - so nothing downstream can report this. The
# section notice already says the operation redraws, but a notice is read once
# and this is about THESE files, which the notice cannot know about.
#
# It is a question, not a refusal: redrawing is often exactly what the user
# wants, and the only thing missing was the knowledge that this particular
# document had something to lose. Cancel is the default-safe answer but
# Continue is a legitimate one, so both are offered.
if [ "$risk_count" -gt 0 ]; then
    if [ "$risk_count" -eq 1 ]; then
        risk_desc="\"${risk_name}\" has $(structure_risk_phrase "$risk_kind")"
    elif [ "$risk_count" -eq "$file_count" ]; then
        # The files can differ in what each one carries, so the summary phrase
        # covers the union rather than claiming they all match the first.
        risk_desc="all ${file_count} files have an outline, annotations or form fields"
    else
        risk_desc="${risk_count} of the ${file_count} files have an outline, annotations or form fields, starting with \"${risk_name}\""
    fi

    "$alert_tool" --level caution --title "PDFUtil" \
        --ok "Continue" --cancel "Cancel" \
        "$(operation_label "$operation") redraws the page content, so annotations, links, the outline and form fields are not carried over.

Right now ${risk_desc}.

Continue anyway?"
    alert_rc=$?
    if [ "$alert_rc" -ne 0 ]; then
        set_summary "Cancelled.
$(operation_label "$operation") would have discarded structure in ${risk_count} of ${file_count} file(s)."
        exit 0
    fi
fi

case "$PDFUTIL_OUTPUT_KIND" in
    pdf)
        if [ "$file_count" -eq 1 ]; then
            "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "PDFUtil.run.single"
        else
            "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "PDFUtil.run.batch"
        fi
        ;;

    text)
        if [ "$file_count" -eq 1 ]; then
            "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "PDFUtil.run.text"
        else
            "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "PDFUtil.run.batch"
        fi
        ;;

    parts)
        # Split turns one input into a numbered series, so there is no single
        # name a Save panel could confirm however short the list is.
        "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "PDFUtil.run.batch"
        ;;

    merged)
        # N inputs, one output - the only many-to-one operation, and the only
        # one whose Save As panel appears with more than one file in the list.
        if [ "$file_count" -lt 2 ]; then
            "$alert_tool" --level caution --title "PDFUtil" \
                "Merge needs at least two files in the list.

Add the other PDFs, in the order they should appear in the merged document."
            set_summary "Merge needs at least two files in the list."
            exit 0
        fi
        "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "PDFUtil.run.merge"
        ;;

    images)
        selected_pages=""
        if [ "$file_count" -eq 1 ]; then
            selected_pages="$(range_page_count "$OMC_ACTIONUI_VIEW_174_VALUE" \
                              "$(pdf_page_count "$first_file")")"
        fi
        if [ "$selected_pages" = "1" ]; then
            "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "PDFUtil.run.image"
        else
            "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "PDFUtil.run.batch"
        fi
        ;;

    *)
        "$alert_tool" --level caution --title "PDFUtil" \
            "Internal error: $(operation_label "$operation") has no output kind."
        ;;
esac
