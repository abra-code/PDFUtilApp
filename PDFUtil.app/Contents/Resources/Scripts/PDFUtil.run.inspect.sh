#!/bin/bash
# PDFUtil.run.inspect.sh - Read-only reports, printed to an output window
#
# The only operation that writes nothing. It asks for no destination, produces
# no file, and its stdout IS the result: Command.json declares
# exe_script_file_with_output_window, so everything echoed here lands in the
# window OMC opens.
#
# THE -o INVARIANT DOES NOT APPLY HERE, and that is deliberate. Every other
# runner must pass -o, because pdfutil edits its input IN PLACE without one.
# These four verbs (info, outline, forms --list, search) never write, so there
# is nothing to redirect and passing -o would create a file the user did not ask
# for. That is why this handler does not use run_pdfutil - the shared wrapper
# enforces an invariant that would be wrong here.
#
# Search is the mode that needs care. `pdfutil search` exits 0 with NO OUTPUT
# when there are no matches, which in an output window is indistinguishable from
# a broken run. Each file is therefore counted first with --count, so a document
# with nothing in it says so.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.args.sh"

# --- handler-local functions ---------------------------------------------
# The inspect runner's read-only pdfutil call
#
# These live here rather than in a shared lib because this handler is their
# only caller. A shared lib is for logic several handlers use; a single-use
# function in it just makes the lib bigger and its readers guess who calls it.
#
# The markers around this block are load-bearing: the unit-test harness pulls
# the definitions out with them so it can call these directly, without running
# the handler body below.
# ---------------------------------------------------------------------------
# Run a read-only verb against one file and echo its combined output.
# No -o, no --force: see the header.
#
# Arguments: input path
run_pdfutil_read() {
    # </dev/null for the same reason run_pdfutil does it, and with a sharper
    # consequence here: this runs inside a `while read` loop fed by a here-string
    # of file paths, so a verb that read stdin would swallow the remaining paths
    # and silently truncate the report.
    "$PDFUTIL" "$PDFUTIL_VERB" "${PDFUTIL_ARGS[@]}" "$1" "${PDFUTIL_TRAILING[@]}" 2>&1 </dev/null
}

# Echo the match count for a query in one file, or "" if pdfutil failed.
# Separate from the report itself because zero matches has to be detectable
# BEFORE deciding what to print.
#
# Arguments: input path, query
search_match_count() {
    local n
    # -- so a query starting with "-" is not read as a flag; see the search arm
    # of build_pdfutil_args. stderr is folded in so a failure carries its reason
    # rather than collapsing to a blank string the caller cannot explain.
    #
    # This deliberately does NOT replay PDFUTIL_ARGS, which is empty for search
    # today. If the Inspect panel ever gains --case-sensitive or a page range,
    # this call has to take them too or the count and the listing below will
    # disagree - the count would answer a different question than the report.
    # </dev/null for the same reason run_pdfutil_read has it: this runs inside
    # the `while read` loop over the file list, and a verb that read stdin would
    # eat the remaining paths.
    n="$("$PDFUTIL" search --count "$1" -- "$2" 2>&1 </dev/null)"
    case "$n" in
        '' | *[!0-9]*) echo "" ;;
        *) echo "$n" ;;
    esac
}

# Echo why a search could not run against one file. Only called after
# search_match_count returns "", so it re-runs a failing command rather than
# threading the error out of the counting path.
# Arguments: input path, query
search_failure_reason() {
    first_error_line "$("$PDFUTIL" search --count "$1" -- "$2" 2>&1 </dev/null)"
}

# --- end handler-local functions -----------------------------------------

all_paths="$OMC_ACTIONUI_TABLE_10_COLUMN_3_ALL_ROWS"
if [ -z "$all_paths" ]; then
    echo "Add at least one file to the list first."
    exit 0
fi

operation="$(current_operation)"
if ! build_pdfutil_args "$operation"; then
    echo "$(operation_label "$operation") is not available yet."
    exit 0
fi

mode="$(inspect_mode)"
query="$(trim_spaces "$OMC_ACTIONUI_VIEW_224_VALUE")"

case "$mode" in
    outline) heading="Outline" ;;
    forms)   heading="Form fields" ;;
    search)  heading="Search for \"${query}\"" ;;
    *)       heading="Document info" ;;
esac

echo "${heading}"
echo

file_count=0
while IFS= read -r file_path; do
    [ -z "$file_path" ] && continue

    echo "=============================================================="
    echo "$(/usr/bin/basename "$file_path")"
    echo "=============================================================="

    if [ ! -e "$file_path" ]; then
        echo "This file no longer exists."
        echo
        continue
    fi
    # Counted here rather than at the top of the loop so the closing summary
    # reports files actually inspected, not list rows.
    file_count=$((file_count + 1))

    if [ "$mode" = "search" ]; then
        # Count first: a search that found nothing prints nothing, and an empty
        # block under a filename reads as a failure rather than as an answer.
        count="$(search_match_count "$file_path" "$query")"
        if [ -z "$count" ]; then
            echo "Could not search this file: $(search_failure_reason "$file_path" "$query")"
            echo
            continue
        fi
        if [ "$count" = "0" ]; then
            echo "No matches for \"${query}\"."
            echo
            continue
        fi
        echo "${count} match(es):"
    fi

    output="$(run_pdfutil_read "$file_path")"
    exit_code=$?

    if [ $exit_code -ne 0 ]; then
        echo "Could not read this file: $(first_error_line "$output")"
    elif [ -z "$output" ]; then
        # Not expected to be reachable: an empty report always carries a
        # sentence. `outline` prints "no outline" on STDERR and `forms --list`
        # prints "(no form fields)" on stdout, and this captures 2>&1, so both
        # arrive as text. Kept as a backstop so a future verb that really does
        # say nothing cannot render as a blank block under a filename.
        echo "(nothing to report)"
    else
        printf '%s\n' "$output"
    fi
    echo
done <<< "$all_paths"

set_summary "$(operation_label "$operation"): ${heading} for ${file_count} file(s).
Results are in the output window."
