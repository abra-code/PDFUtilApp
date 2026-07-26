#!/bin/bash
# lib.PDFUtil.sh - Shared functions and variables for PDFUtil
#
# Sourced by every handler. Runs under /bin/sh (macOS bash 3.2 in POSIX mode):
# no process substitution, no mapfile, no declare -A, no ${var,,}. Validate
# changes with `sh -n`, never `bash -n`.

# Embedded pdfutil binary - the single engine behind every operation.
PDFUTIL="$OMC_APP_BUNDLE_PATH/Contents/Helpers/pdfutil"

# ---------------------------------------------------------------------------
# Control IDs (must match the id values in Base.lproj/PDFUtil.json)
# ---------------------------------------------------------------------------

TABLE_ID=10
SUMMARY_VIEW_ID=12

# The Table's columns are: 1 = type badge (SF Symbol), 2 = display name,
# 3 = full path (hidden). Handlers read the path through column 3, so every
# command that touches the file list must declare
# OMC_ACTIONUI_TABLE_10_COLUMN_3_ALL_ROWS in its ENVIRONMENT_VARIABLES or the
# variable is never exported and the list reads as empty.
TABLE_PATH_COLUMN=3

OPERATION_PICKER_ID=60
RUN_BUTTON_ID=90

ADD_BUTTON_ID=101
REMOVE_BUTTON_ID=102
CLEAR_BUTTON_ID=103
REVEAL_BUTTON_ID=104
PREVIEW_BUTTON_ID=105
INFO_BUTTON_ID=106

# Input password - applies to every operation that reads a document
INPUT_PASSWORD_ID=125

# Settings panel switcher; one GroupBox per operation lands inside it as the
# later stages add them.
SETTINGS_STACK_ID=199

# Runtime tools
dialog_tool="$OMC_OMC_SUPPORT_PATH/omc_dialog_control"
next_cmd="$OMC_OMC_SUPPORT_PATH/omc_next_command"
alert_tool="$OMC_OMC_SUPPORT_PATH/alert"
pasteboard_tool="$OMC_OMC_SUPPORT_PATH/pasteboard"
window_uuid="${OMC_ACTIONUI_WINDOW_UUID:-$OMC_NIB_DLG_GUID}"

# Private pasteboard keys: hand off a selection to a window that does not exist
# yet, so its init script can pick it up.
OPEN_PATHS_PB_KEY="PDFUTIL_OPEN_PATHS"
QUICKLOOK_PB_KEY="PDFUTIL_QUICKLOOK_PATH"

# SF Symbols used as the type badge in table column 1
PDF_BADGE="doc.richtext"
IMAGE_BADGE="photo"

# A literal tab. Table rows are tab-separated, so a path containing one would
# split into extra fields and silently corrupt the hidden path column.
TAB="$(printf '\t')"

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

# Set the Summary text view content
# Arguments: text
set_summary() {
    "$dialog_tool" "$window_uuid" ${SUMMARY_VIEW_ID} "$1"
}

# Echo the per-run input password (control 125), or "" when unset. Every
# pdfutil verb that reads a document accepts --password, so this applies
# uniformly rather than per operation.
input_password() {
    printf '%s' "$OMC_ACTIONUI_VIEW_125_VALUE"
}

# Classify a file by CONTENT, echoing one of: pdf | image | other
#
# Arguments: path
#
# Content, not extension: an extension check alone lets a renamed non-PDF
# through to a confusing runtime error, which is exactly what this guards
# against. `file --mime-type` reads the magic bytes, costs about a millisecond,
# and - unlike parsing the document with `pdfutil info` - still recognises a
# password-protected PDF, which `info` rejects with exit 2 until it is given
# the right password. Decrypt takes encrypted PDFs as its input, so a
# classifier that called them "other" would lock the user out of the one
# operation that fixes them.
#
# Two mime results need special handling, both measured rather than assumed:
#
#   image/svg+xml  `file` calls SVG an image, but it is XML, not a raster.
#                  ImageIO does not read it, so `frompages` exits 2 with "no
#                  images found". Admitting it would put a file in the list
#                  that can only fail at Save time, so it is classified other.
#
#   octet-stream / text-plain
#                  `file` only matches %PDF- at byte 0, but the PDF spec allows
#                  the header anywhere in the first 1024 bytes and PDFKit
#                  honours that. A PDF carrying a BOM or a stray leading space
#                  reads perfectly (`pdfutil info` exits 0) yet is reported as
#                  octet-stream. Falling back to a header scan keeps those
#                  files in the list instead of silently dropping them.
classify_file() {
    local mime
    mime="$(/usr/bin/file -b --mime-type "$1" 2>/dev/null)"
    case "$mime" in
        application/pdf)  echo "pdf" ;;
        image/svg+xml)    echo "other" ;;
        image/*)          echo "image" ;;
        application/octet-stream | text/plain)
            if /usr/bin/head -c 1024 "$1" 2>/dev/null \
                 | LC_ALL=C /usr/bin/grep -qa '%PDF-'; then
                echo "pdf"
            else
                echo "other"
            fi
            ;;
        *)                echo "other" ;;
    esac
}

# Echo the SF Symbol badge for a file type
# Arguments: pdf | image | other
badge_for_type() {
    case "$1" in
        pdf)   echo "$PDF_BADGE" ;;
        image) echo "$IMAGE_BADGE" ;;
        *)     echo "" ;;
    esac
}

# Human-readable file size
# Arguments: byte count
format_size() {
    local bytes="$1"
    if [ -z "$bytes" ]; then
        echo "?"
    elif [ "$bytes" -ge 1048576 ]; then
        echo "$(( bytes / 1048576 )).$(( (bytes % 1048576) * 10 / 1048576 )) MB"
    elif [ "$bytes" -ge 1024 ]; then
        echo "$(( bytes / 1024 )) KB"
    else
        echo "${bytes} bytes"
    fi
}

# Echo a path that does not exist yet. If the given path is taken, append
# " 2", " 3", ... before the extension (or to the name for folders and
# extensionless paths).
# Arguments: desired path
unique_path() {
    local path="$1"
    if [ ! -e "$path" ]; then
        echo "$path"
        return
    fi
    local stem ext
    local dir="$(/usr/bin/dirname "$path")"
    local base="$(/usr/bin/basename "$path")"
    case "$base" in
        *.*)
            stem="${base%.*}"
            ext=".${base##*.}"
            ;;
        *)
            stem="$base"
            ext=""
            ;;
    esac
    local n=2
    local candidate="$dir/$stem $n$ext"
    while [ -e "$candidate" ]; do
        n=$((n + 1))
        candidate="$dir/$stem $n$ext"
    done
    echo "$candidate"
}

# Validate a 1-100 integer; echoes the clamped value (default on garbage)
# Arguments: value default
clamp_quality() {
    local q="$1" def="$2"
    case "$q" in
        '' | *[!0-9]*) q="$def" ;;
        *)
            [ "$q" -gt 100 ] && q=100
            [ "$q" -lt 1 ] && q=1
            ;;
    esac
    echo "$q"
}

# Validate a positive integer DPI; echoes the clamped value (default on garbage)
# Arguments: value default
clamp_dpi() {
    local d="$1" def="$2"
    case "$d" in
        '' | *[!0-9]*) d="$def" ;;
        *)
            [ "$d" -lt 1 ] && d="$def"
            [ "$d" -gt 2400 ] && d=2400
            ;;
    esac
    echo "$d"
}

# ---------------------------------------------------------------------------
# File list
# ---------------------------------------------------------------------------

# Add files to the table, keeping existing rows, deduped and sorted by name.
# Directories are searched recursively for PDFs and images.
#
# Rows are emitted as three tab-separated fields: badge, display name, path.
# The sort key is therefore the badge first, which would group PDFs and images
# apart; sorting on the name field instead keeps the list alphabetical, which
# is what the user sees.
#
# Arguments: newline-separated list of file/directory paths to add
#
# Outputs read by the caller via select_first_or_resync:
#   LIST_WAS_EMPTY  1 if the table had no rows before this add
#   FIRST_FILE_PATH full path of the first row after this add ("" if none)
add_files_to_table() {
    local new_paths="$1"
    local buffer=""

    FIRST_FILE_PATH=""
    if [ -n "$OMC_ACTIONUI_TABLE_10_COLUMN_3_ALL_ROWS" ]; then
        LIST_WAS_EMPTY=0
    else
        LIST_WAS_EMPTY=1
    fi

    # Keep existing rows. Re-classifying them is cheap and self-healing: a file
    # replaced on disk since it was added gets the right badge back.
    #
    # The [ -e ] guard matters more than it looks. The rows arrive newline-
    # joined, so a file whose own name contains a newline comes back as two
    # half-paths. Without the guard those halves would be re-emitted as rows on
    # every subsequent add and the corruption would be permanent; with it they
    # fail the existence test once and drop out.
    local existing_paths="$OMC_ACTIONUI_TABLE_10_COLUMN_3_ALL_ROWS"
    if [ -n "$existing_paths" ]; then
        while IFS= read -r file_path; do
            if [ -n "$file_path" ] && [ -e "$file_path" ]; then
                buffer="${buffer}$(row_for_path "$file_path")
"
            fi
        done <<< "$existing_paths"
    fi

    # Add new files and folders, filtered to PDFs and images
    while IFS= read -r file_path; do
        # A tab in the name would split the row into extra fields and leave the
        # hidden path column holding a fragment, so every later action would
        # target a path that does not exist. Skip rather than corrupt.
        case "$file_path" in *"$TAB"*) continue ;; esac

        if [ -d "$file_path" ]; then
            local tmp_files
            tmp_files="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/pdfutil.XXXXXX")" || continue
            /usr/bin/find "$file_path" -type f ! -path "*/.*" -print > "$tmp_files" 2>/dev/null
            while IFS= read -r found_file; do
                case "$found_file" in *"$TAB"*) continue ;; esac
                local found_type="$(classify_file "$found_file")"
                if [ "$found_type" != "other" ]; then
                    buffer="${buffer}$(row_for_path "$found_file" "$found_type")
"
                fi
            done < "$tmp_files"
            /bin/rm -f "$tmp_files"
        elif [ -e "$file_path" ]; then
            local file_type="$(classify_file "$file_path")"
            if [ "$file_type" != "other" ]; then
                buffer="${buffer}$(row_for_path "$file_path" "$file_type")
"
            fi
        fi
    done <<< "$new_paths"

    if [ -n "$buffer" ]; then
        # Sort and dedupe on fields 2+3 (display name, then path) rather than
        # on the whole line. A plain `sort -u` would key on field 1, the badge,
        # which groups PDFs apart from images instead of listing them
        # alphabetically. Keying on name+path also keeps two same-named files
        # from different folders as two distinct rows.
        local sorted="$(printf "%s" "$buffer" | /usr/bin/sort -u -t'	' -k2,2 -k3,3)"
        printf "%s" "$sorted" | "$dialog_tool" "$window_uuid" ${TABLE_ID} omc_table_set_rows_from_stdin
        FIRST_FILE_PATH="$(printf "%s" "$sorted" | /usr/bin/head -1 | /usr/bin/cut -f3)"
    else
        "$dialog_tool" "$window_uuid" ${TABLE_ID} omc_table_remove_all_rows
    fi
}

# Echo one tab-separated table row for a path: badge, display name, path.
# Arguments: path [precomputed type]
row_for_path() {
    local file_path="$1"
    local file_type="$2"
    [ -z "$file_type" ] && file_type="$(classify_file "$file_path")"
    printf '%s\t%s\t%s' "$(badge_for_type "$file_type")" \
        "$(/usr/bin/basename "$file_path")" "$file_path"
}

# Update the detail pane (summary + per-file action buttons) for a selected
# file. Pass the file's full path, or "" when nothing is selected.
#
# Used two ways:
#   - the selection-changed handler passes the live table value (a real user
#     click);
#   - the add handlers pass the known first-row path after auto-selecting it.
# The add handlers call this directly rather than chaining
# PDFUtil.files.selection.changed, because omc_select_row fires no actionID AND
# a chained handler would race the (fire-and-forget) selection message on the
# host's main runloop - it could read the table value before the new selection
# is applied. Passing the path explicitly is race-free.
apply_file_selection() {
    local selected_path="$1"

    if [ -z "$selected_path" ]; then
        "$dialog_tool" "$window_uuid" ${REMOVE_BUTTON_ID} omc_disable
        "$dialog_tool" "$window_uuid" ${REVEAL_BUTTON_ID} omc_disable
        "$dialog_tool" "$window_uuid" ${PREVIEW_BUTTON_ID} omc_disable
        "$dialog_tool" "$window_uuid" ${INFO_BUTTON_ID} omc_disable
        return
    fi

    "$dialog_tool" "$window_uuid" ${REMOVE_BUTTON_ID} omc_enable
    "$dialog_tool" "$window_uuid" ${REVEAL_BUTTON_ID} omc_enable
    "$dialog_tool" "$window_uuid" ${PREVIEW_BUTTON_ID} omc_enable
    "$dialog_tool" "$window_uuid" ${INFO_BUTTON_ID} omc_enable

    if [ ! -e "$selected_path" ]; then
        set_summary "$(/usr/bin/basename "$selected_path")
File no longer exists at this path."
        return
    fi

    local size="$(/usr/bin/stat -f %z "$selected_path" 2>/dev/null)"
    local file_type="$(classify_file "$selected_path")"

    # Report the type actually found, not a hard-coded "image": a file replaced
    # on disk since it was added can now classify as "other", and claiming it is
    # an image would be a lie the user cannot act on.
    if [ "$file_type" != "pdf" ]; then
        set_summary "$(/usr/bin/basename "$selected_path")
Size: $(format_size "$size")
Type: $file_type"
        return
    fi

    # pdfutil info exits 2 on a password-protected PDF until it is handed the
    # right password, so feed it the input-password field when the user has
    # filled it in and say so plainly when it is still locked.
    local pw="$(input_password)"
    local info
    if [ -n "$pw" ]; then
        info="$("$PDFUTIL" info --password "$pw" "$selected_path" 2>/dev/null)"
    else
        info="$("$PDFUTIL" info "$selected_path" 2>/dev/null)"
    fi

    if [ -z "$info" ]; then
        set_summary "$(/usr/bin/basename "$selected_path")
Size: $(format_size "$size")
Pages: ?
Locked: could not read this PDF. If it is password-protected, enter the
password above and reselect the file."
        return
    fi

    local pages="$(printf '%s\n' "$info" | /usr/bin/awk -F': ' '$1 == "pages" { print $2; exit }')"
    local encrypted="$(printf '%s\n' "$info" | /usr/bin/awk -F': ' '$1 == "encrypted" { print $2; exit }')"
    case "$encrypted" in
        true)  encrypted="Yes" ;;
        false) encrypted="No" ;;
        *)     encrypted="?" ;;
    esac

    set_summary "$(/usr/bin/basename "$selected_path")
Size: $(format_size "$size")
Pages: ${pages:-?}
Encrypted: $encrypted"
}

# Called by the add handlers right after add_files_to_table. If files were just
# added to a previously empty list, select and show the first row. Otherwise
# re-sync the detail pane to the live selection through the normal handler.
select_first_or_resync() {
    if [ "$LIST_WAS_EMPTY" = "1" ] && [ -n "$FIRST_FILE_PATH" ]; then
        # Visual selection only (fires no actionID); update the detail pane
        # directly from the known path to avoid the selection-vs-handler race.
        "$dialog_tool" "$window_uuid" ${TABLE_ID} omc_select_row 0
        apply_file_selection "$FIRST_FILE_PATH"
    else
        "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "PDFUtil.files.selection.changed"
    fi
}
