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
    "$alert_tool" --level caution --title "PDFUtil" \
        "$(operation_label "$operation") is not available yet.

Reduce File Size, Export Page Images and Extract Text work now."
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
