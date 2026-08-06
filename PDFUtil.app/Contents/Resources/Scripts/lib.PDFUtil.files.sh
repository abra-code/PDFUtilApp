#!/bin/bash
# lib.PDFUtil.files.sh - the file list table
#
# Everything that reads or writes Table 10: adding paths, the type badge, the
# selection-dependent button state, and the row lookup they share.
#
# Sourced by: PDFUtil.add.files, .files.drop, .files.selection.changed, .init, .remove.selected
# Requires lib.PDFUtil.sh (tool paths, control IDs, primitives) to be
# sourced first; every handler that needs this one sources both, in order.
#
# Runs under /bin/sh (macOS bash 3.2 in POSIX mode): no process substitution,
# no mapfile, no declare -A, no ${var,,}. Validate with `sh -n`, never `bash -n`.

# Echo the SF Symbol badge for a file type
# Arguments: pdf | image | other
badge_for_type() {
    case "$1" in
        pdf)   echo "$PDF_BADGE" ;;
        image) echo "$IMAGE_BADGE" ;;
        *)     echo "" ;;
    esac
}

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
    # Loop variables, declared so they stay in this function. Both loops below
    # read from a here-string or a file rather than a pipeline, so they run in
    # the current shell and would otherwise assign at global scope. The two
    # names immediately below are global on purpose - they are this function's
    # documented outputs - and must stay that way.
    local file_path found_file

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

    # pdfutil info exits 2 on a password-protected PDF. Say so plainly and name
    # the one operation that can do anything about it, rather than reporting a
    # blank document.
    local info
    info="$("$PDFUTIL" info "$selected_path" 2>/dev/null)"

    if [ -z "$info" ]; then
        if pdf_is_locked "$selected_path"; then
            set_summary "$(/usr/bin/basename "$selected_path")
Size: $(format_size "$size")

This PDF is password-protected. Every other operation will refuse it - use
Remove Password first to save an unlocked copy, then work on that."
        else
            set_summary "$(/usr/bin/basename "$selected_path")
Size: $(format_size "$size")
Pages: ?

This PDF could not be read."
        fi
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
