#!/bin/bash
# PDFUtil.run.assemble.sh - Build one PDF from the images in the list
#
# The inverse direction: every other operation reads PDFs and this one writes
# one from pictures. Structurally it is merge's twin - N inputs collapse to a
# single output, in list order - so it follows the same staging discipline
# (write to a temp file beside the destination, move it into place only on
# success) rather than run_save_as, which is built around one input path.
#
# It differs from merge in what it accepts: images are the point, and a PDF in
# the list is legal but gets REDRAWN by pdfutil, losing annotations, links, the
# outline and form fields. start.batch warns about that before the Save panel
# appears, because by the time this script runs the user has already named a
# file and the warning would arrive too late to act on.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.panels.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.args.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.run.sh"

# --- handler-local functions ---------------------------------------------
# The assemble runner's own pdfutil wrapper
#
# These live here rather than in a shared lib because this handler is their
# only caller. A shared lib is for logic several handlers use; a single-use
# function in it just makes the lib bigger and its readers guess who calls it.
#
# The markers around this block are load-bearing: the unit-test harness pulls
# the definitions out with them so it can call these directly, without running
# the handler body below.
# ---------------------------------------------------------------------------
# N inputs, one output, so run_pdfutil's single-input shape does not fit. The
# -o and --force invariants are repeated here rather than skipped: frompages
# requires -o (it is a usage error without one, not an in-place edit), and
# --force is what lets it write over the mktemp staging file.
#
# Arguments: output, then one or more input paths
run_pdfutil_frompages() {
    local out="$1"
    shift
    if [ -z "$out" ]; then
        echo "internal error: refusing to run frompages without an output path"
        return 1
    fi
    if [ $# -eq 0 ]; then
        echo "internal error: frompages needs at least one input"
        return 1
    fi
    # </dev/null for the same reason run_pdfutil does it: nothing here is meant
    # to be interactive, and a verb that read stdin would block on the caller's
    # terminal.
    "$PDFUTIL" frompages "${PDFUTIL_ARGS[@]}" --force -o "$out" "$@" 2>&1 </dev/null
}

# --- end handler-local functions -----------------------------------------

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
# frompages is all-or-nothing - one unreadable input fails the whole document -
# so the missing ones are reported here rather than handed to pdfutil as paths
# it will complain about in less useful words.
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
    set_summary "Build PDF from Images did not run: these files no longer exist.
${missing}"
    exit 0
fi

if [ "${#inputs[@]}" -eq 0 ]; then
    set_summary "Add at least one image to the list first."
    exit 0
fi

output_file="$(ensure_output_extension "$output_file")"

set_summary "Building a PDF from ${#inputs[@]} file(s)..."

out_dir="$(/usr/bin/dirname "$output_file")"
tmp_out="$(/usr/bin/mktemp "$out_dir/.pdfutil.XXXXXX")"
if [ -z "$tmp_out" ]; then
    set_summary "Could not create a temporary file in ${out_dir}."
    exit 0
fi

output="$(run_pdfutil_frompages "$tmp_out" "${inputs[@]}")"
exit_code=$?

if [ $exit_code -ne 0 ]; then
    /bin/rm -f "$tmp_out"
    set_summary "Build PDF from Images FAILED: $(first_error_line "$output")"
    exit 0
fi

# mktemp creates 0600 files - give the result normal permissions
/bin/chmod 644 "$tmp_out"
if ! /bin/mv -f "$tmp_out" "$output_file"; then
    /bin/rm -f "$tmp_out"
    set_summary "Build PDF from Images FAILED: could not write $(/usr/bin/basename "$output_file")."
    exit 0
fi

built_size="$(/usr/bin/stat -f %z "$output_file" 2>/dev/null)"
page_count="$(pdf_page_count "$output_file")"
[ -z "$page_count" ] && page_count="?"

# The page count is worth stating rather than echoing the input count: a
# multi-frame GIF or TIFF contributes one page per frame, so "6 files ->
# 11 pages" is the only place that behaviour becomes visible.
set_summary "Operation: $(operation_label "$operation")
Built $(/usr/bin/basename "$output_file") from ${#inputs[@]} file(s)
${page_count} page(s), $(format_size "$built_size")

$(structure_notice "$operation")"
