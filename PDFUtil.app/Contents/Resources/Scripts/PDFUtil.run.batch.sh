#!/bin/bash
# PDFUtil.run.batch.sh - Apply the chosen operation to every file in the list
#
# Reached from PDFUtil.start.batch whenever the result cannot be expressed as a
# single Save As path: more than one input, or an operation that produces a
# numbered series of images from one input. CHOOSE_FOLDER_DIALOG has already
# asked for the destination folder.
#
# The output kind decides how each result is named, so the loop branches on
# PDFUTIL_OUTPUT_KIND rather than on the operation tag - a new verb that writes
# a PDF needs no change here.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.args.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.run.sh"

# --- handler-local functions ---------------------------------------------
# Output-name helper
#
# These live here rather than in a shared lib because this handler is their
# only caller. A shared lib is for logic several handlers use; a single-use
# function in it just makes the lib bigger and its readers guess who calls it.
#
# The markers around this block are load-bearing: the unit-test harness pulls
# the definitions out with them so it can call these directly, without running
# the handler body below.
# ---------------------------------------------------------------------------
# Echo a file's name without its extension.
path_stem() {
    local base="$(/usr/bin/basename "$1")"
    case "$base" in
        *.*) echo "${base%.*}" ;;
        *)   echo "$base" ;;
    esac
}

# --- end handler-local functions -----------------------------------------

destination="$OMC_DLG_CHOOSE_FOLDER_PATH"
if [ -z "$destination" ]; then
    # Canceled. Clear whatever start.batch left in the Summary, or its
    # "Checking the file list..." progress line would sit there implying the
    # run is still going.
    set_summary "Canceled."
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

success_count=0
error_count=0
renamed_count=0
details=""

set_summary "Running $(operation_label "$operation") on ${#files[@]} file(s)..."

file_index=0
for file_path in "${files[@]}"; do
    [ -z "$file_path" ] && continue

    filename="$(/usr/bin/basename "$file_path")"
    file_index=$((file_index + 1))
    # Before the work, not after: the point is to name the file currently being
    # chewed on, so a run that stalls says which document it stalled on.
    set_batch_progress "$operation" "$file_index" "${#files[@]}" "$filename" \
        "$success_count" "$error_count"

    if [ ! -e "$file_path" ]; then
        error_count=$((error_count + 1))
        details="${details}
FAILED ${filename}: file no longer exists"
        continue
    fi

    if [ "$PDFUTIL_OUTPUT_KIND" = "images" ]; then
        # One -o value covers both of render's output modes: with several pages
        # selected pdfutil strips the suffix back off and writes
        # <stem>-001<suffix>, and with exactly one it writes that literal path.
        # Either way the name is right and the extension is present.
        stem="$(path_stem "$file_path")"
        suffix="$(render_suffix "$(render_format)")"
        out_prefix="$(unique_render_prefix "$destination/$stem" "$suffix")"
        prefix_stem="$(strip_image_extension "$out_prefix")"

        output="$(run_pdfutil "$file_path" "$out_prefix")"
        exit_code=$?

        if [ $exit_code -ne 0 ]; then
            # render writes page by page, so a document that fails partway has
            # already left images in the destination. Clearing them keeps a
            # failed run from leaving behind a short export that looks whole.
            remove_render_outputs "$out_prefix" "$suffix"
            error_count=$((error_count + 1))
            details="${details}
FAILED ${filename}: $(first_error_line "$output")"
            continue
        fi

        # unique_render_prefix guaranteed nothing here matched before the run,
        # so every match now is one this run wrote. Three-or-more digits:
        # pdfutil's %03d is a minimum width (see render_outputs_exist).
        image_count=0
        for part in "$prefix_stem"-[0-9][0-9][0-9]*"$suffix"; do
            [ -e "$part" ] || continue
            image_count=$((image_count + 1))
        done
        if [ "$image_count" -eq 0 ] && [ -s "$out_prefix" ]; then
            image_count=1
        fi

        if [ "$image_count" -eq 0 ]; then
            error_count=$((error_count + 1))
            details="${details}
FAILED ${filename}: pdfutil wrote no images"
        else
            success_count=$((success_count + 1))
            details="${details}
OK ${filename}: ${image_count} image(s) -> $(/usr/bin/basename "$prefix_stem")${suffix}"
        fi
        continue
    fi

    if [ "$PDFUTIL_OUTPUT_KIND" = "parts" ]; then
        # One subfolder per input, so a batch of report.pdf and notes.pdf does
        # not interleave report-001.pdf with notes-001.pdf in one flat heap.
        # unique_path on the folder keeps a second run from writing into - and
        # --force overwriting - the parts an earlier one left there.
        stem="$(path_stem "$file_path")"
        subdir="$(unique_path "$destination/$stem")"
        if ! /bin/mkdir -p "$subdir"; then
            error_count=$((error_count + 1))
            details="${details}
FAILED ${filename}: could not create a folder for the parts"
            continue
        fi

        output="$(run_pdfutil "$file_path" "$subdir/$stem")"
        exit_code=$?

        if [ $exit_code -ne 0 ]; then
            # split writes part by part, so a failure partway leaves a folder of
            # pages that looks like a complete short document. The folder is
            # ours alone - unique_path just made it - so clearing it is safe.
            /bin/rm -rf "$subdir"
            error_count=$((error_count + 1))
            details="${details}
FAILED ${filename}: $(first_error_line "$output")"
            continue
        fi

        # Three-or-more digits: pdfutil's %03d is a minimum width, so a document
        # long enough to need part 1000 writes -1000.pdf.
        part_count=0
        first_part=""
        for part in "$subdir/$stem"-[0-9][0-9][0-9]*.pdf; do
            [ -e "$part" ] || continue
            part_count=$((part_count + 1))
            [ -z "$first_part" ] && first_part="$part"
        done

        if [ "$part_count" -eq 0 ]; then
            /bin/rm -rf "$subdir"
            error_count=$((error_count + 1))
            details="${details}
FAILED ${filename}: pdfutil wrote no parts"
        else
            success_count=$((success_count + 1))
            part_note=""
            [ -n "$first_part" ] && part_note="$(restrictions_note "$file_path" "$first_part")"
            details="${details}
OK ${filename}: ${part_count} part(s) -> $(/usr/bin/basename "$subdir")/${part_note:+
   Note: $part_note}"
        fi
        continue
    fi

    # PDF and text outputs are both one file per input. Never overwrite: pick a
    # fresh name when the destination already holds one.
    if [ "$PDFUTIL_OUTPUT_KIND" = "text" ]; then
        desired="$destination/$(path_stem "$file_path").txt"
    else
        desired="$destination/$filename"
    fi
    output_file="$(unique_path "$desired")"
    output_name="$(/usr/bin/basename "$output_file")"
    rename_note=""
    if [ "$output_name" != "$(/usr/bin/basename "$desired")" ]; then
        renamed_count=$((renamed_count + 1))
        rename_note=" - saved as ${output_name}, that name was taken"
    fi

    # Stage through a temp file in the destination folder so a failed run leaves
    # nothing behind, and so input and output are never the same path.
    tmp_out="$(/usr/bin/mktemp "$destination/.pdfutil.XXXXXX")"
    if [ -z "$tmp_out" ]; then
        error_count=$((error_count + 1))
        details="${details}
FAILED ${filename}: cannot write to the destination folder"
        continue
    fi

    output="$(run_pdfutil "$file_path" "$tmp_out")"
    exit_code=$?

    if [ $exit_code -ne 0 ]; then
        /bin/rm -f "$tmp_out"
        error_count=$((error_count + 1))
        details="${details}
FAILED ${filename}: $(first_error_line "$output")"
        continue
    fi

    # mktemp creates 0600 files - give the result normal permissions
    /bin/chmod 644 "$tmp_out"
    if ! /bin/mv -f "$tmp_out" "$output_file"; then
        /bin/rm -f "$tmp_out"
        error_count=$((error_count + 1))
        details="${details}
FAILED ${filename}: could not write ${output_name}"
        continue
    fi

    orig_size="$(/usr/bin/stat -f %z "$file_path" 2>/dev/null)"
    new_size="$(/usr/bin/stat -f %z "$output_file" 2>/dev/null)"
    success_count=$((success_count + 1))
    file_note=""
    if [ "$PDFUTIL_OUTPUT_KIND" = "pdf" ]; then
        file_note="$(restrictions_note "$file_path" "$output_file")"
    fi
    # Exit 0 does not mean the file got smaller - see reduce_declined_note.
    declined_note="$(reduce_declined_note "$output")"
    details="${details}
OK ${filename}: $(format_size "$orig_size") -> $(format_size "$new_size")${rename_note}${declined_note:+
   Note: $declined_note}${file_note:+
   Note: $file_note}"
done

set_summary "Operation: $(operation_label "$operation")
Destination: ${destination}

${success_count} succeeded - ${renamed_count} renamed - ${error_count} failed
${details}"
