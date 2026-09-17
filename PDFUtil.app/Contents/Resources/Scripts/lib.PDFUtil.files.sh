#!/bin/bash
# lib.PDFUtil.files.sh - the file list table
#
# Everything that reads or writes Table 10: adding paths, the type badge, the
# selection-dependent button state, and the row lookup they share.
#
# Sourced by: PDFUtil.add.files, .files.drop, .files.selection.changed, .init, .remove.selected,
# .move.selected.up, .move.selected.down
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

# Add files to the table, keeping existing rows in their order and appending the
# new ones sorted by name. A file already in the list keeps its place.
# Directories are searched recursively for PDFs and images.
#
# The existing order is kept because it is the user's: Merge and Build PDF from
# Images take the files in list order, and Up and Down arrange it. Sorting the
# whole list here would undo that arrangement on every add.
#
# Rows are emitted as three tab-separated fields: badge, display name, path.
# The sort key is therefore the badge first, which would group PDFs and images
# apart; sorting the new rows on the name field instead lists them
# alphabetically, which is what the user sees.
#
# Arguments: newline-separated list of file/directory paths to add
#
# Outputs read by the caller via select_first_or_resync:
#   LIST_WAS_EMPTY  1 if the table had no rows before this add
#   FIRST_FILE_PATH full path of the first row after this add ("" if none)
#   LIST_PATHS      the paths in the list after this add, one per line
add_files_to_table() {
    local new_paths="$1"
    local buffer=""
    local new_buffer=""
    # Loop variables, declared so they stay in this function. Both loops below
    # read from a here-string or a file rather than a pipeline, so they run in
    # the current shell and would otherwise assign at global scope. The two
    # names immediately below are global on purpose - they are this function's
    # documented outputs - and must stay that way.
    local file_path found_file

    FIRST_FILE_PATH=""
    LIST_PATHS=""
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
                    new_buffer="${new_buffer}$(row_for_path "$found_file" "$found_type")
"
                fi
            done < "$tmp_files"
            /bin/rm -f "$tmp_files"
        elif [ -e "$file_path" ]; then
            local file_type="$(classify_file "$file_path")"
            if [ "$file_type" != "other" ]; then
                new_buffer="${new_buffer}$(row_for_path "$file_path" "$file_type")
"
            fi
        fi
    done <<< "$new_paths"

    if [ -n "$new_buffer" ]; then
        # Sort the new rows on fields 2+3 (display name, then path) rather than
        # on the whole line. A plain `sort` would key on field 1, the badge,
        # which groups PDFs apart from images instead of listing them
        # alphabetically.
        buffer="${buffer}$(printf "%s" "$new_buffer" | /usr/bin/sort -t'	' -k2,2 -k3,3)
"
    fi

    if [ -n "$buffer" ]; then
        # Drop repeats by path, keeping each row's first place: an existing row
        # stays where it is, and a file added twice in one go is listed once.
        # Two same-named files from different folders stay two rows.
        local rows="$(printf "%s" "$buffer" | /usr/bin/awk -F'	' 'length($0) && !seen[$3]++')"
        printf "%s\n" "$rows" | "$dialog_tool" "$window_uuid" ${TABLE_ID} omc_table_set_rows_from_stdin
        LIST_PATHS="$(printf "%s\n" "$rows" | /usr/bin/cut -f3)"
        FIRST_FILE_PATH="$(printf "%s\n" "$LIST_PATHS" | /usr/bin/head -1)"
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
# file. Pass the file's full path, or "" when nothing is selected, and the paths
# in the list, one per line, which place Up and Down.
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

    update_move_buttons "$selected_path" "$2"

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
    local protection=""
    case "$encrypted" in
        true)
            # `info` succeeded without a password, so this PDF opens freely and
            # any protection is an owner password's restrictions. Say what they
            # are, and that removing them needs no password - nobody can be
            # expected to know the PDF has an empty user password.
            local flags="$(printf '%s\n' "$info" | /usr/bin/awk -F': ' '$1 == "permissions" { print $2; exit }')"
            local words="$(restriction_words "$flags")"
            encrypted="Yes, but it opens without a password"
            if [ -n "$words" ]; then
                protection="
Does not allow: ${words}
Remove Password removes these restrictions; no password is needed."
            fi
            ;;
        false) encrypted="No" ;;
        *)     encrypted="?" ;;
    esac

    set_summary "$(/usr/bin/basename "$selected_path")
Size: $(format_size "$size")
Pages: ${pages:-?}
Encrypted: ${encrypted}${protection}"
}

# Called by the add handlers right after add_files_to_table. If files were just
# added to a previously empty list, select and show the first row. Otherwise
# re-sync the detail pane to the live selection through the normal handler.
select_first_or_resync() {
    if [ "$LIST_WAS_EMPTY" = "1" ] && [ -n "$FIRST_FILE_PATH" ]; then
        # Visual selection only (fires no actionID); update the detail pane
        # directly from the known path to avoid the selection-vs-handler race.
        "$dialog_tool" "$window_uuid" ${TABLE_ID} omc_select_row 0
        apply_file_selection "$FIRST_FILE_PATH" "$LIST_PATHS"
    else
        "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "PDFUtil.files.selection.changed"
    fi
}

# Echo the 1-based place of a path in a list of paths, then a space and the
# number of paths, e.g. "2 3". The place is 0 when the path is empty or not in
# the list.
# Arguments: path, newline-separated paths
list_position() {
    local position=0
    local count=0
    local file_path
    while IFS= read -r file_path; do
        [ -n "$file_path" ] || continue
        count=$((count + 1))
        if [ "$position" = 0 ] && [ -n "$1" ] && [ "$file_path" = "$1" ]; then
            position=$count
        fi
    done <<< "$2"
    echo "$position $count"
}

# Enable Up for a selected file below the first row, and Down for one above the
# last. Both are off with nothing selected.
# Arguments: selected path or "", newline-separated paths in list order
update_move_buttons() {
    local place="$(list_position "$1" "$2")"
    local position="${place% *}"
    local count="${place#* }"
    if [ "$position" -gt 1 ]; then
        "$dialog_tool" "$window_uuid" ${MOVE_UP_BUTTON_ID} omc_enable
    else
        "$dialog_tool" "$window_uuid" ${MOVE_UP_BUTTON_ID} omc_disable
    fi
    if [ "$position" -ge 1 ] && [ "$position" -lt "$count" ]; then
        "$dialog_tool" "$window_uuid" ${MOVE_DOWN_BUTTON_ID} omc_enable
    else
        "$dialog_tool" "$window_uuid" ${MOVE_DOWN_BUTTON_ID} omc_disable
    fi
}

# Move the selected file one place up or down the list, which is the order Merge
# and Build PDF from Images take the files in. It stays selected. At either end
# of the list, or with nothing selected, nothing changes.
#
# A move does not wait for a run to finish, as Remove does not: a run reads the
# list once, when it starts, so a move made while it works changes the next run
# and not this one.
#
# Arguments: up | down
move_selected_file() {
    local selected_path="$OMC_ACTIONUI_TABLE_10_COLUMN_3_VALUE"
    [ -n "$selected_path" ] || return 0

    # The [ -e ] guard mirrors Remove: rows arrive newline-joined, so a
    # half-path left by a filename containing a newline drops out here, before
    # the places are counted.
    local all_paths=""
    local file_path
    while IFS= read -r file_path; do
        if [ -n "$file_path" ] && [ -e "$file_path" ]; then
            all_paths="${all_paths}${file_path}
"
        fi
    done <<< "$OMC_ACTIONUI_TABLE_10_COLUMN_3_ALL_ROWS"

    local place="$(list_position "$selected_path" "$all_paths")"
    local position="${place% *}"
    local count="${place#* }"
    local other
    case "$1" in
        up)   other=$((position - 1)) ;;
        down) other=$((position + 1)) ;;
        *)    return 1 ;;
    esac
    [ "$position" -ge 1 ] && [ "$other" -ge 1 ] && [ "$other" -le "$count" ] || return 0

    # Only line numbers go through -v, so a backslash in a path is never read as
    # an escape. The numbers are checked against the lines awk read, so a count
    # that disagrees with the list swaps nothing rather than losing a path.
    local moved
    moved="$(printf '%s' "$all_paths" | /usr/bin/awk -v a="$position" -v b="$other" '
        length($0) { line[++n] = $0 }
        END {
            if (a >= 1 && a <= n && b >= 1 && b <= n) { t = line[a]; line[a] = line[b]; line[b] = t }
            for (i = 1; i <= n; i++) print line[i]
        }')"
    local awk_status=$?
    [ "$awk_status" -eq 0 ] && [ -n "$moved" ] || return 1

    local buffer=""
    while IFS= read -r file_path; do
        buffer="${buffer}$(row_for_path "$file_path")
"
    done <<< "$moved"
    printf "%s" "$buffer" | "$dialog_tool" "$window_uuid" ${TABLE_ID} omc_table_set_rows_from_stdin
    # Replacing the rows keeps the selection on the same row, wherever it now
    # is; selecting it by its path makes sure. Neither fires the selection
    # handler, so the buttons are placed here from the new order.
    "$dialog_tool" "$window_uuid" ${TABLE_ID} omc_select_row_with_content "$selected_path" ${TABLE_PATH_COLUMN}
    update_move_buttons "$selected_path" "$moved"
}
