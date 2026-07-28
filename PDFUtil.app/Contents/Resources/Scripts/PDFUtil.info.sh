#!/bin/bash
# PDFUtil.info.sh - Inspect the selected file, in an output window
#
# This is where the read-only reports live. They were briefly a batch operation
# with a sub-picker (info / outline / fields / search), and that was the wrong
# shape: inspection answers a question about ONE document you are looking at,
# not something you queue across a list and read back as a log. Search in
# particular is worthless without somewhere to show the hits. So the whole tier
# was removed and the parts that suit a selected file live here instead.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.sh"

selected_path="$OMC_ACTIONUI_TABLE_10_COLUMN_3_VALUE"

if [ -z "$selected_path" ]; then
    echo "No file selected"
    exit 0
fi

if [ ! -e "$selected_path" ]; then
    echo "File does not exist: $selected_path"
    exit 0
fi

file_size="$(/usr/bin/stat -f %z "$selected_path" 2>/dev/null)"
created="$(/usr/bin/stat -f "%SB" "$selected_path" 2>/dev/null)"
modified="$(/usr/bin/stat -f "%Sm" "$selected_path" 2>/dev/null)"
file_type="$(classify_file "$selected_path")"

echo "File: $selected_path"
echo ""
echo "Size: $(format_size "$file_size") ($file_size bytes)"
echo "Created: $created"
echo "Modified: $modified"
echo "Type: $file_type"
echo ""

if [ "$file_type" = "image" ]; then
    echo "--- Image ---"
    /usr/bin/sips -g pixelWidth -g pixelHeight -g format -g dpiWidth "$selected_path" 2>&1
    exit 0
elif [ "$file_type" != "pdf" ]; then
    # Reached when a file was replaced on disk after it was added to the list.
    echo "--- Unsupported ---"
    echo "This file is neither a PDF nor an image PDFUtil can read."
    /usr/bin/file -b "$selected_path" 2>&1
    exit 0
fi

echo "--- Document ---"

# Report the exit code rather than guessing from stderr, which pdfutil also
# uses for harmless PDFKit log lines on permission-restricted files.
"$PDFUTIL" info "$selected_path" 2>&1
info_status=$?

# The outline, when there is one. Worth showing beside the info because it is
# the other thing you want to know about a document you are about to redraw -
# several operations discard it, and this is where you find out whether that
# matters for THIS file. Silent when the document has none, rather than
# printing a heading over nothing.
if [ $info_status -eq 0 ]; then
    outline_out="$("$PDFUTIL" outline "$selected_path" 2>&1 </dev/null)"
    outline_status=$?
    # "no outline" is what the verb prints for a document without one, and it
    # exits 0 doing it - so an emptiness test is not enough to stay silent.
    [ "$outline_out" = "no outline" ] && outline_out=""
    if [ $outline_status -eq 0 ] && [ -n "$outline_out" ]; then
        echo ""
        echo "--- Outline ---"
        printf '%s\n' "$outline_out"
    fi
fi

if [ $info_status -ne 0 ]; then
    echo ""
    if pdf_is_locked "$selected_path"; then
        echo "This PDF is password-protected, so none of its details can be read"
        echo "and every operation except Remove Password will refuse it."
        echo ""
        echo "Pick Remove Password, enter the password, and save an unlocked copy."
    else
        echo "pdfutil info exited $info_status; this PDF could not be read."
    fi
fi
