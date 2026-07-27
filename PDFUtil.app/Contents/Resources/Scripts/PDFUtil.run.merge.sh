#!/bin/bash
# PDFUtil.run.merge.sh - Join every PDF in the list into one document
#
# The only many-to-one operation, and so the only one that reaches a Save As
# panel with more than one file in the list. It cannot share run_save_as, which
# is built around a single input path; what it does share is the staging
# discipline - write to a temp file beside the destination, move it into place
# only on success - so a failed merge cannot leave a partial document under the
# name the user confirmed.
#
# Inputs are merged in list order. There is no per-input page range here: that
# needs a range field per row, which the file table has no room for; Extract or
# Reorder on the individual files first covers the same ground.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.sh"

output_file="$OMC_DLG_SAVE_AS_PATH"
if [ -z "$output_file" ]; then
    # Cancelled. Clear whatever start.batch left in the Summary, or its
    # "Checking the file list..." progress line would sit there implying the
    # run is still going.
    set_summary "Cancelled."
    exit 0
fi

file_paths="$OMC_ACTIONUI_TABLE_10_COLUMN_3_ALL_ROWS"
if [ -z "$file_paths" ]; then
    exit 0
fi

operation="$(current_operation)"
if ! build_pdfutil_args "$operation"; then
    set_summary "$(operation_label "$operation") is not available yet."
    exit 0
fi

IFS=$'\n' read -r -d '' -a files <<< "$file_paths" || true

# Drop blank rows and anything that vanished from disk since it was listed.
# merge is all-or-nothing - one unreadable input fails the whole document - so
# the missing ones are reported here rather than handed to pdfutil as paths it
# will complain about in less useful words.
inputs=()
missing=""
for file_path in "${files[@]}"; do
    [ -z "$file_path" ] && continue
    if [ ! -e "$file_path" ]; then
        missing="${missing}
${file_path}"
        continue
    fi
    inputs+=("$file_path")
done

if [ -n "$missing" ]; then
    set_summary "Merge did not run: these files no longer exist.
${missing}"
    exit 0
fi

if [ "${#inputs[@]}" -lt 2 ]; then
    set_summary "Merge needs at least two files in the list."
    exit 0
fi

output_file="$(ensure_output_extension "$output_file")"

set_summary "Merging ${#inputs[@]} files..."

out_dir="$(/usr/bin/dirname "$output_file")"
tmp_out="$(/usr/bin/mktemp "$out_dir/.pdfutil.XXXXXX")"
if [ -z "$tmp_out" ]; then
    set_summary "Could not create a temporary file in ${out_dir}."
    exit 0
fi

output="$(run_pdfutil_merge "$tmp_out" "${inputs[@]}")"
exit_code=$?

if [ $exit_code -ne 0 ]; then
    /bin/rm -f "$tmp_out"
    set_summary "Merge FAILED: $(first_error_line "$output")"
    exit 0
fi

# mktemp creates 0600 files - give the result normal permissions
/bin/chmod 644 "$tmp_out"
if ! /bin/mv -f "$tmp_out" "$output_file"; then
    /bin/rm -f "$tmp_out"
    set_summary "Merge FAILED: could not write $(/usr/bin/basename "$output_file")."
    exit 0
fi

merged_size="$(/usr/bin/stat -f %z "$output_file" 2>/dev/null)"
page_count="$(pdf_page_count "$output_file")"
[ -z "$page_count" ] && page_count="?"

set_summary "Operation: $(operation_label "$operation")
Merged ${#inputs[@]} files -> $(/usr/bin/basename "$output_file")
${page_count} page(s), $(format_size "$merged_size")

$(structure_notice "$operation")"
