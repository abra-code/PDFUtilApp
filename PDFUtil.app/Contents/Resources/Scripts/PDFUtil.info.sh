#!/bin/bash
# PDFUtil.info.sh - Show detailed file info in an output window

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

# Every pdfutil verb that reads a document accepts --password; pass the
# per-run input password (control 125) when the user has supplied one, and
# report the exit code rather than guessing from stderr, which pdfutil also
# uses for harmless PDFKit log lines on permission-restricted files.
pw="$(input_password)"
if [ -n "$pw" ]; then
    "$PDFUTIL" info --password "$pw" "$selected_path" 2>&1
else
    "$PDFUTIL" info "$selected_path" 2>&1
fi
info_status=$?

if [ $info_status -ne 0 ]; then
    echo ""
    echo "pdfutil info exited $info_status."
    echo "If this PDF is password-protected, type the password into the"
    echo "Password field in the main window and try again."
fi
