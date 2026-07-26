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

destination="$OMC_DLG_CHOOSE_FOLDER_PATH"
if [ -z "$destination" ]; then
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

success_count=0
error_count=0
renamed_count=0
details=""

set_summary "Running $(operation_label "$operation") on ${#files[@]} file(s)..."

for file_path in "${files[@]}"; do
    [ -z "$file_path" ] && continue

    filename="$(/usr/bin/basename "$file_path")"

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
    details="${details}
OK ${filename}: $(format_size "$orig_size") -> $(format_size "$new_size")${rename_note}"
done

set_summary "Operation: $(operation_label "$operation")
Destination: ${destination}

${success_count} succeeded - ${renamed_count} renamed - ${error_count} failed
${details}"
