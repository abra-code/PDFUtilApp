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

# Passwords belong to Set Password and Remove Password and nowhere else.
#
# There is deliberately no per-run password field. A protected PDF is out of
# scope for every other operation: it fails the pre-flight guard in
# PDFUtil.start.batch and the user unlocks it once with Remove Password, rather
# than re-entering the password for every operation and every batch. That keeps
# secrets out of the argument list of verbs that have no --password-stdin form,
# and keeps "is this file usable" a property of the file rather than of a text
# field somebody may have filled in wrongly.

# Settings panel switcher; one GroupBox per operation lands inside it as the
# later stages add them.
SETTINGS_STACK_ID=199

# ---------------------------------------------------------------------------
# Settings panels inside the switcher
#
# One panel is visible at a time. The placeholder (198) counts as a panel: it
# is what shows for an operation whose GroupBox has not been built yet, so the
# detail pane is never blank and never shows the wrong operation's controls.
# ---------------------------------------------------------------------------

GROUP_PLACEHOLDER_ID=198
GROUP_REDUCE_ID=200
GROUP_RENDER_ID=201
GROUP_TEXT_ID=202

SETTINGS_PANEL_IDS="198 200 201 202"

# Reduce controls (id band 70-80)
RED_QUALITY_ID=72
RED_DOWNSAMPLE_ID=76
RED_DPI_ID=77
RED_MAXEDGE_ON_ID=78
RED_MAXEDGE_PX_ID=79
RED_GRAY_ID=80

# Export Page Images controls (id band 170-174)
RND_FORMAT_ID=170
RND_DPI_ID=171
RND_QUALITY_ID=172
RND_TRANSPARENT_ID=173
RND_RANGE_ID=174

# Extract Text controls. The plan's id map assigns 175 to the text page range;
# 176 continues that pair for the page-break toggle. It does not collide with
# Reduce, whose band is 70-80, nor with OCR, which starts at 180.
TXT_RANGE_ID=175
TXT_PAGE_BREAKS_ID=176

# Per-section structure notice Text elements (band 300-319, one per GroupBox).
# Their wording is written at runtime by structure_notice so the prose lives in
# exactly one place - the same table the Stage 7 pre-flight alert will read.
NOTICE_REDUCE_ID=300
NOTICE_RENDER_ID=301
NOTICE_TEXT_ID=302

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

# Return 0 when a PDF cannot be opened without a password.
#
# pdfutil exits 2 with "PDF is password-protected (use --password)" from every
# verb in that case, so this reads the same signal the run would hit - no
# guessing, and no separate notion of "locked" that could disagree with what
# actually happens at Save time.
#
# The match is on the whole phrase, not on "password-protected" alone: pdfutil
# appends the input path to every diagnostic, so a loose match would call a
# corrupt file in a folder named "password-protected" locked and send the user
# off to Remove Password, which cannot fix it.
#
# If pdfutil ever rewords the message this returns "not locked" and the file
# degrades to an ordinary per-file failure at run time. That is the safe
# direction: a run that reports the real error beats a guard that blocks work
# for a reason it invented.
#
# Side effect: a successful `info` is cached for pdf_page_count, which the
# router calls moments later on the same file.
#
# Arguments: path
pdf_is_locked() {
    local out
    out="$("$PDFUTIL" info "$1" 2>&1)"
    if [ $? -eq 0 ]; then
        PDF_INFO_CACHE_PATH="$1"
        PDF_INFO_CACHE_OUT="$out"
        return 1
    fi
    case "$out" in
        *"PDF is password-protected (use --password)"*) return 0 ;;
        *) return 1 ;;
    esac
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
        # No plausible setting is 10 digits long, and a value that long
        # would overflow the shell's arithmetic; default it instead.
        ??????????*) q="$def" ;;
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
        # No plausible setting is 10 digits long, and a value that long
        # would overflow the shell's arithmetic; default it instead.
        ??????????*) d="$def" ;;
        *)
            [ "$d" -lt 1 ] && d="$def"
            [ "$d" -gt 2400 ] && d=2400
            ;;
    esac
    echo "$d"
}

# Validate a pixel dimension; echoes the clamped value (default on garbage).
# Zero is rejected rather than passed through: pdfutil reads -m 0 as "no cap",
# so a user who ticks "Cap longest edge" and leaves the field at 0 would get a
# toggle that silently does nothing.
# Arguments: value default
clamp_pixels() {
    local p="$1" def="$2"
    case "$p" in
        '' | *[!0-9]*) p="$def" ;;
        # No plausible setting is 10 digits long, and a value that long
        # would overflow the shell's arithmetic; default it instead.
        ??????????*) p="$def" ;;
        *)
            [ "$p" -lt 1 ] && p="$def"
            [ "$p" -gt 20000 ] && p=20000
            ;;
    esac
    echo "$p"
}

# Echo the operation tag currently selected in the Operation picker.
#
# Pickers whose options are {"title":..., "tag":...} dictionaries deliver the
# TAG, not the index, so this is a string like "reduce". Empty means the window
# has not reported a value yet (init runs before the user touches the picker),
# which corresponds to the first selectable option.
current_operation() {
    local op="$OMC_ACTIONUI_VIEW_60_VALUE"
    [ -z "$op" ] && op="reduce"
    echo "$op"
}

# Echo the human-readable name of an operation, for messages the user reads.
# Keep in sync with the Operation picker titles in Base.lproj/PDFUtil.json.
operation_label() {
    case "$1" in
        reduce)    echo "Reduce File Size" ;;
        linearize) echo "Linearize" ;;
        pdfa)      echo "Convert to PDF/A" ;;
        extract)   echo "Extract or Reorder" ;;
        delete)    echo "Delete Pages" ;;
        rotate)    echo "Rotate" ;;
        crop)      echo "Crop" ;;
        split)     echo "Split" ;;
        merge)     echo "Merge" ;;
        watermark) echo "Watermark" ;;
        flatten)   echo "Flatten" ;;
        forms)     echo "Fill Form" ;;
        metadata)  echo "Edit Metadata" ;;
        encrypt)   echo "Set Password" ;;
        decrypt)   echo "Remove Password" ;;
        render)    echo "Export Page Images" ;;
        text)      echo "Extract Text" ;;
        ocr)       echo "OCR" ;;
        frompages) echo "Build PDF from Images" ;;
        inspect)   echo "Inspect" ;;
        *)         echo "$1" ;;
    esac
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

# ---------------------------------------------------------------------------
# Structure notices
#
# pdfutil is silent about degraded output: a reduce that dropped the outline
# still exits 0. The exit code therefore cannot warn anyone, and these notices
# carry that load instead. One table, read by the always-visible Text element in
# each section and (from Stage 7) by the pre-flight alert - so the wording can
# never drift between the two.
# ---------------------------------------------------------------------------

# Echo the structure notice for an operation ("" when it has none).
structure_notice() {
    case "$1" in
        reduce)
            echo "Redraws pages: annotations, links, outline, and form fields are not carried over."
            ;;
        render)
            echo "Rasterizes pages to images. Text stops being selectable and searchable - export at a higher DPI if the result will be read on screen."
            ;;
        text)
            echo "Extracts the existing text layer only. Scanned pages have none and come out empty - use OCR for those."
            ;;
        *)
            echo ""
            ;;
    esac
}

# Echo the id of the Text element that displays the notice for an operation,
# or "" when that section has no notice element.
notice_id_for_operation() {
    case "$1" in
        reduce) echo ${NOTICE_REDUCE_ID} ;;
        render) echo ${NOTICE_RENDER_ID} ;;
        text)   echo ${NOTICE_TEXT_ID} ;;
        *)      echo "" ;;
    esac
}

# Echo the id of the settings panel for an operation, falling back to the
# placeholder for the operations later stages still have to build.
panel_for_operation() {
    case "$1" in
        reduce) echo ${GROUP_REDUCE_ID} ;;
        render) echo ${GROUP_RENDER_ID} ;;
        text)   echo ${GROUP_TEXT_ID} ;;
        *)      echo ${GROUP_PLACEHOLDER_ID} ;;
    esac
}

# Enable exactly the render controls the chosen image format supports.
#
# --quality applies to the lossy formats only, and --transparent is rejected
# outright for jpeg (pdfutil exits 1). Leaving a control live that the verb will
# refuse invites the user to set a value that is then either dropped or turned
# into a usage error, so the format picker drives their enabled state here and
# apply_operation_panel calls this when the panel first appears.
apply_render_format_state() {
    local fmt="$(render_format)"

    case "$fmt" in
        jpeg | heic) "$dialog_tool" "$window_uuid" ${RND_QUALITY_ID} omc_enable ;;
        *)           "$dialog_tool" "$window_uuid" ${RND_QUALITY_ID} omc_disable ;;
    esac

    if [ "$fmt" = "jpeg" ]; then
        "$dialog_tool" "$window_uuid" ${RND_TRANSPARENT_ID} omc_disable
    else
        "$dialog_tool" "$window_uuid" ${RND_TRANSPARENT_ID} omc_enable
    fi
}

# Show the settings panel for an operation and fill in its notice text.
#
# Called from both PDFUtil.init (the picker fires no action for its initial
# value, so the first panel would otherwise never be set up) and
# PDFUtil.operation.changed.
apply_operation_panel() {
    local op="$1"
    local want="$(panel_for_operation "$op")"
    local panel_id

    for panel_id in $SETTINGS_PANEL_IDS; do
        if [ "$panel_id" = "$want" ]; then
            "$dialog_tool" "$window_uuid" "$panel_id" omc_show
        else
            "$dialog_tool" "$window_uuid" "$panel_id" omc_hide
        fi
    done

    # Set the notice through the plain value form. omc_set_property "text" is
    # accepted but does not repaint a Text element (verified: the notice stayed
    # blank), whereas the value form does.
    local notice_id="$(notice_id_for_operation "$op")"
    if [ -n "$notice_id" ]; then
        "$dialog_tool" "$window_uuid" "$notice_id" "$(structure_notice "$op")"
    fi

    if [ "$want" = "${GROUP_PLACEHOLDER_ID}" ]; then
        "$dialog_tool" "$window_uuid" ${GROUP_PLACEHOLDER_ID} \
            "$(operation_label "$op") is not available yet.
Reduce File Size, Export Page Images and Extract Text work now."
    fi

    if [ "$want" = "${GROUP_RENDER_ID}" ]; then
        apply_render_format_state
    fi
}

# ---------------------------------------------------------------------------
# Argument builder
# ---------------------------------------------------------------------------

# Echo the selected image format, defaulting to png. Validated rather than
# passed through: a programmatic picker update can fire with a transitional
# value, and an unknown --format is a usage error the user cannot act on.
render_format() {
    case "$OMC_ACTIONUI_VIEW_170_VALUE" in
        png | jpeg | tiff | heic) echo "$OMC_ACTIONUI_VIEW_170_VALUE" ;;
        *) echo "png" ;;
    esac
}

# Echo the file suffix pdfutil writes for an image format. Encoded once here
# because jpeg is the odd one out - it produces .jpg, not .jpeg - and every
# render output path in the app depends on getting it right.
render_suffix() {
    case "$1" in
        jpeg) echo ".jpg" ;;
        tiff) echo ".tiff" ;;
        heic) echo ".heic" ;;
        *)    echo ".png" ;;
    esac
}

# Build the pdfutil invocation for an operation into these globals:
#   PDFUTIL_VERB        the subcommand
#   PDFUTIL_ARGS        flags placed between the verb and the output
#   PDFUTIL_TRAILING    args that must follow the input (rare)
#   PDFUTIL_OUTPUT_KIND pdf | text | images | prefix | none - drives routing
#   PDFUTIL_STDIN_PW    password to feed on stdin, if any
#
# Note what is deliberately NOT set here: the output path and --force. Both are
# added by run_pdfutil, so no caller can forget them (see the comment there).
#
# Arguments: operation tag
# Returns 0 when the operation is implemented, 1 when it is not - the router
# turns that into a message rather than an empty command line.
build_pdfutil_args() {
    local op="$1"

    PDFUTIL_VERB=""
    PDFUTIL_ARGS=()
    PDFUTIL_TRAILING=()
    PDFUTIL_OUTPUT_KIND=""
    PDFUTIL_STDIN_PW=""

    case "$op" in
        reduce)
            PDFUTIL_VERB="reduce"
            PDFUTIL_OUTPUT_KIND="pdf"
            PDFUTIL_ARGS+=(-q "$(clamp_quality "$OMC_ACTIONUI_VIEW_72_VALUE" 85)")
            # -r is a ceiling, and 0 disables downsampling entirely. Passing it
            # explicitly in both cases keeps the toggle honest: pdfutil's own
            # default is 150, so omitting -r when the toggle is off would
            # downsample anyway.
            if [ "$OMC_ACTIONUI_VIEW_76_VALUE" = "true" ]; then
                PDFUTIL_ARGS+=(-r "$(clamp_dpi "$OMC_ACTIONUI_VIEW_77_VALUE" 150)")
            else
                PDFUTIL_ARGS+=(-r 0)
            fi
            if [ "$OMC_ACTIONUI_VIEW_78_VALUE" = "true" ]; then
                PDFUTIL_ARGS+=(-m "$(clamp_pixels "$OMC_ACTIONUI_VIEW_79_VALUE" 2000)")
            fi
            if [ "$OMC_ACTIONUI_VIEW_80_VALUE" = "true" ]; then
                PDFUTIL_ARGS+=(--gray)
            fi
            ;;

        render)
            PDFUTIL_VERB="render"
            PDFUTIL_OUTPUT_KIND="images"
            local fmt="$(render_format)"
            PDFUTIL_ARGS+=(--format "$fmt")
            PDFUTIL_ARGS+=(--dpi "$(clamp_dpi "$OMC_ACTIONUI_VIEW_171_VALUE" 150)")
            case "$fmt" in
                jpeg | heic)
                    PDFUTIL_ARGS+=(--quality "$(clamp_quality "$OMC_ACTIONUI_VIEW_172_VALUE" 85)")
                    ;;
            esac
            # --transparent is a usage error for jpeg. The toggle is disabled in
            # that mode, but a stale value can still arrive here, so re-check
            # rather than trusting the UI state.
            if [ "$OMC_ACTIONUI_VIEW_173_VALUE" = "true" ] && [ "$fmt" != "jpeg" ]; then
                PDFUTIL_ARGS+=(--transparent)
            fi
            if [ -n "$OMC_ACTIONUI_VIEW_174_VALUE" ]; then
                PDFUTIL_ARGS+=(-p "$OMC_ACTIONUI_VIEW_174_VALUE")
            fi
            ;;

        text)
            PDFUTIL_VERB="text"
            PDFUTIL_OUTPUT_KIND="text"
            if [ -n "$OMC_ACTIONUI_VIEW_175_VALUE" ]; then
                PDFUTIL_ARGS+=(-p "$OMC_ACTIONUI_VIEW_175_VALUE")
            fi
            if [ "$OMC_ACTIONUI_VIEW_176_VALUE" = "true" ]; then
                PDFUTIL_ARGS+=(--page-breaks)
            fi
            ;;

        *)
            return 1
            ;;
    esac

    # No --password is added for any of these verbs. Protected PDFs are out of
    # scope outside Set Password and Remove Password, and start.batch refuses
    # them before a run begins. Stage 5's encrypt/decrypt paths carry their own
    # secret through PDFUTIL_STDIN_PW, which keeps it out of the process table.
    return 0
}

# Run one pdfutil pass.
#
# Runners must go through this function rather than calling $PDFUTIL directly,
# because the two flags that can destroy the user's data live here and nowhere
# else:
#
#   -o      Most verbs edit the input IN PLACE when -o is omitted. A forgotten
#           -o overwrites the user's original with no confirmation and no undo.
#           This function refuses to run without an output path rather than
#           letting that happen.
#   --force The runners stage output through mktemp, which pre-creates a 0-byte
#           file; pdfutil declines to overwrite an existing output without it.
#
# Arguments: input output
# Echoes pdfutil's combined stdout and stderr; returns pdfutil's exit code.
run_pdfutil() {
    if [ -z "$PDFUTIL_VERB" ]; then
        echo "internal error: build_pdfutil_args did not set a verb"
        return 1
    fi
    if [ -z "$2" ]; then
        echo "internal error: refusing to run pdfutil without an output path"
        return 1
    fi
    "$PDFUTIL" "$PDFUTIL_VERB" "${PDFUTIL_ARGS[@]}" --force -o "$2" "$1" \
        "${PDFUTIL_TRAILING[@]}" 2>&1
}

# Same, with PDFUTIL_STDIN_PW fed on stdin so the secret never reaches the
# process table. Used by the Stage 5 encrypt/decrypt paths; the -stdin flag
# itself belongs in PDFUTIL_ARGS.
# Arguments: input output
run_pdfutil_stdin_pw() {
    printf '%s' "$PDFUTIL_STDIN_PW" | run_pdfutil "$1" "$2"
}

# ---------------------------------------------------------------------------
# Page ranges
# ---------------------------------------------------------------------------

# Echo the number of pages in a PDF, or "" when it cannot be read (locked
# without the right password, corrupt, not a PDF).
# Arguments: path
pdf_page_count() {
    # Reuse the info the locked-file guard just read for this same file rather
    # than parsing the document twice; `info` costs a quarter of a second on a
    # large PDF, and the router runs immediately after the guard.
    if [ "$1" = "$PDF_INFO_CACHE_PATH" ] && [ -n "$PDF_INFO_CACHE_OUT" ]; then
        printf '%s\n' "$PDF_INFO_CACHE_OUT" \
            | /usr/bin/awk -F': ' '$1 == "pages" { print $2; exit }'
        return
    fi
    "$PDFUTIL" info "$1" 2>/dev/null \
        | /usr/bin/awk -F': ' '$1 == "pages" { print $2; exit }'
}

# Trim leading and trailing whitespace. Only the ends: pdfutil's parser trims
# each term and each endpoint the same way, so "1 - 3" is a valid range there.
# Deleting interior whitespace instead would turn "1 2" into page 12, a page
# the user did not ask for and pdfutil would have rejected.
trim_spaces() {
    printf '%s' "$1" | /usr/bin/sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

# Resolve one page-range endpoint to a page number, or "" when it is invalid.
# Arguments: term page-count
resolve_page_term() {
    local t="$(trim_spaces "$1")"
    case "$t" in
        end)
            echo "$2"
            ;;
        '' | *[!0-9]*)
            echo ""
            ;;
        # No document has 10-digit page numbers, and a value that long would
        # overflow the shell's arithmetic further down. Reject it here rather
        # than letting it reach $(( )).
        ??????????*)
            echo ""
            ;;
        *)
            if [ "$t" -ge 1 ] && [ "$t" -le "$2" ]; then
                # Normalise to base 10. `[` compares decimally, but $(( ))
                # reads a leading zero as OCTAL, so an accepted "008" would
                # later abort the arithmetic ("value too great for base") and
                # "010" would silently mean 8.
                echo "$((10#$t))"
            else
                echo ""
            fi
            ;;
    esac
}

# Echo how many pages a range spec selects, mirroring pdfutil's grammar
#   RANGE := TERM ("," TERM)*      TERM := N | N-M | N-end | end | all
# 1-based and inclusive; descending terms are legal and duplicates count.
# An empty spec means every page.
#
# Echoes "" when the spec does not resolve. Callers must treat that as "more
# than one page", which is the safe direction: render's prefix form yielding a
# single file is still a correct, well-named file, whereas its literal-path
# form yielding many files would overwrite them onto one name.
#
# Arguments: range-spec page-count
range_page_count() {
    local spec="$1" total="$2"
    case "$total" in
        '' | *[!0-9]*) echo ""; return ;;
    esac
    if [ -z "$spec" ]; then
        echo "$total"
        return
    fi

    local sum=0 term lo hi
    local old_ifs="$IFS"
    # set -f before the unquoted expansion: the spec is text the user typed, and
    # a "*" in it would otherwise be expanded against the working directory,
    # making the page count depend on whatever files happen to be there.
    # Restore rather than assume: an unconditional `set +f` would switch
    # globbing ON for a future caller that had deliberately turned it off.
    local glob_state="$-"
    set -f
    IFS=','
    set -- $spec
    IFS="$old_ifs"
    case "$glob_state" in *f*) ;; *) set +f ;; esac

    for term in "$@"; do
        term="$(trim_spaces "$term")"
        if [ "$term" = "all" ]; then
            sum=$((sum + total))
            continue
        fi
        case "$term" in
            *-*)
                lo="$(resolve_page_term "${term%%-*}" "$total")"
                hi="$(resolve_page_term "${term#*-}" "$total")"
                if [ -z "$lo" ] || [ -z "$hi" ]; then
                    echo ""
                    return
                fi
                if [ "$lo" -le "$hi" ]; then
                    sum=$((sum + hi - lo + 1))
                else
                    sum=$((sum + lo - hi + 1))
                fi
                ;;
            *)
                lo="$(resolve_page_term "$term" "$total")"
                if [ -z "$lo" ]; then
                    echo ""
                    return
                fi
                sum=$((sum + 1))
                ;;
        esac
    done

    echo "$sum"
}

# ---------------------------------------------------------------------------
# Output paths
# ---------------------------------------------------------------------------

# Echo a path with any image extension removed. Mirrors what pdfutil strips
# from -o when it reuses that value as a multi-page prefix - same extension
# list, and case-insensitive the same way, because pdfutil lowercases the path
# before testing it. Matching case-sensitively here would leave "Page.Png"
# intact and produce the doubled name "Page.Png.png".
strip_image_extension() {
    local path="$1"
    local lower="$(printf '%s' "$path" | /usr/bin/tr 'A-Z' 'a-z')"
    local ext
    for ext in .png .jpg .jpeg .tiff .tif .heic; do
        case "$lower" in
            *"$ext")
                echo "${path:0:$(( ${#path} - ${#ext} ))}"
                return
                ;;
        esac
    done
    echo "$path"
}

# Echo a file's name without its extension.
path_stem() {
    local base="$(/usr/bin/basename "$1")"
    case "$base" in
        *.*) echo "${base%.*}" ;;
        *)   echo "$base" ;;
    esac
}

# Echo a Save As path carrying the extension the current operation produces.
#
# The Save panel's default name has the right extension already, but the user
# can type any name over it - and for images the correct suffix is not knowable
# until the format picker is read. When the extension has to be added, route
# through unique_path: the panel only confirmed an overwrite for the name the
# user actually saw, so a different name must not clobber an existing file.
#
# Arguments: path chosen in the Save panel
ensure_output_extension() {
    local path="$1"

    case "$PDFUTIL_OUTPUT_KIND" in
        pdf)
            case "$path" in
                *.pdf | *.PDF) echo "$path" ;;
                *) unique_path "${path}.pdf" ;;
            esac
            ;;
        text)
            case "$path" in
                *.txt | *.TXT) echo "$path" ;;
                *) unique_path "${path}.txt" ;;
            esac
            ;;
        images)
            # render appends nothing in its single-page form, so the suffix is
            # entirely ours to get right. Strip whatever image extension the
            # name carries and append the one the chosen format really writes.
            local suffix="$(render_suffix "$(render_format)")"
            local stem="$(strip_image_extension "$path")"
            if [ "${stem}${suffix}" = "$path" ]; then
                echo "$path"
            else
                unique_path "${stem}${suffix}"
            fi
            ;;
        *)
            echo "$path"
            ;;
    esac
}

# Return 0 when any file a render with this prefix could write already exists.
#
# The whole series has to be probed, not just the first member. Checking only
# <stem>-001<suffix> would miss a folder holding <stem>-002<suffix> onwards -
# an ordinary state, since the user may have deleted or moved some pages - and
# --force would then overwrite them with no warning and no rename note.
#
# The numeric pattern accepts MORE than three digits on purpose: pdfutil
# formats the index with %03d, which is a minimum width, so page 1000 is
# written as -1000<suffix>. A strict three-digit pattern would stop seeing the
# series exactly where it grows past 999.
#
# Arguments: stem path (no suffix) and suffix
render_outputs_exist() {
    local stem="$1" suffix="$2" candidate
    [ -e "${stem}${suffix}" ] && return 0
    for candidate in "${stem}"-[0-9][0-9][0-9]*"$suffix"; do
        [ -e "$candidate" ] && return 0
    done
    return 1
}

# Remove every file a render with this prefix could have written.
#
# render writes page by page (pdfutil's own loop), so a document that fails on
# page 3 has already written pages 1 and 2. Leaving them behind hands the user
# a short export that looks complete - or, on the Save As path where the prefix
# is a mktemp name, hidden dotfiles nobody will ever find. Safe to delete
# unconditionally because the prefix is collision-free by construction, so
# nothing matching it predates this run.
#
# Arguments: the -o value that was passed (stem plus suffix), and the suffix
remove_render_outputs() {
    local out_prefix="$1" suffix="$2"
    local stem="$(strip_image_extension "$out_prefix")" part
    /bin/rm -f "$out_prefix"
    for part in "${stem}"-[0-9][0-9][0-9]*"$suffix"; do
        [ -e "$part" ] && /bin/rm -f "$part"
    done
    return 0
}

# Echo a render -o value inside <dir> for <stem> that collides with nothing
# already there.
#
# --force is unconditional (mktemp staging needs it), so anything the series
# would land on gets overwritten without warning. unique_path cannot help: the
# value is a prefix, not a file, so it always "does not exist". Probing the
# names pdfutil would write is what closes that hole - and it is also what
# makes counting the results afterwards honest, since every matching file in
# the destination is then one this run wrote.
#
# The returned value keeps the format's suffix, which is correct for both of
# render's output modes: with one page selected pdfutil writes that literal
# path, and with several it strips the suffix back off and writes
# <stem>-001<suffix>. One value, both modes, right name either way.
#
# Takes a whole stem path rather than a directory and a name: splitting one
# with dirname/basename would mangle a stem that ends in a slash, which is what
# a Save panel name of exactly ".png" produces, and send the series to the
# parent of the folder the user picked.
#
# Arguments: stem path (no suffix) and suffix
unique_render_prefix() {
    local stem="$1" suffix="$2"
    local candidate="$stem" n=2
    while render_outputs_exist "$candidate" "$suffix"; do
        candidate="$stem $n"
        n=$((n + 1))
    done
    echo "${candidate}${suffix}"
}

# ---------------------------------------------------------------------------
# Runners
# ---------------------------------------------------------------------------

# Echo the first line of a pdfutil diagnostic, without its "pdfutil: " prefix.
# Branch on the exit code, never on this being non-empty: pdfutil writes
# harmless PDFKit log lines to stderr on permission-restricted files while
# still exiting 0.
first_error_line() {
    printf '%s' "$1" | /usr/bin/head -1 | /usr/bin/sed 's/^pdfutil: //'
}

# Shared body of the three Save As runners - PDFUtil.run.single (PDF),
# PDFUtil.run.text (.txt) and PDFUtil.run.image (one rendered page). They differ
# only in the Save panel's default file name, which is declared per command in
# Command.json, so the logic lives here once.
#
# SAVE_AS_DIALOG has already asked for the output path ($OMC_DLG_SAVE_AS_PATH);
# an empty value means the user cancelled.
run_save_as() {
    local output_file="$OMC_DLG_SAVE_AS_PATH"
    # Cancelled. Clear whatever start.batch left in the Summary, or its
    # "Checking the file list..." progress line would sit there implying the
    # run is still going.
    if [ -z "$output_file" ]; then
        set_summary "Cancelled."
        return 0
    fi

    local file_paths="$OMC_ACTIONUI_TABLE_10_COLUMN_3_ALL_ROWS"
    [ -z "$file_paths" ] && return 0

    local operation="$(current_operation)"
    if ! build_pdfutil_args "$operation"; then
        set_summary "$(operation_label "$operation") is not available yet."
        return 0
    fi

    # Single-file mode by construction, but take the first row defensively.
    local input_file
    input_file="$(printf '%s\n' "$file_paths" | /usr/bin/head -1 | /usr/bin/tr -d '\r')"
    if [ -z "$input_file" ] || [ ! -e "$input_file" ]; then
        set_summary "Aborted: the input file no longer exists."
        return 0
    fi

    output_file="$(ensure_output_extension "$output_file")"

    local filename="$(/usr/bin/basename "$input_file")"
    set_summary "Running $(operation_label "$operation") on ${filename}..."

    # Stage through a temp file in the destination directory, then move into
    # place, so a failed run cannot leave a half-written file under the name the
    # user chose - and so input and output are never the same path.
    local out_dir="$(/usr/bin/dirname "$output_file")"
    local tmp_out
    tmp_out="$(/usr/bin/mktemp "$out_dir/.pdfutil.XXXXXX")"
    if [ -z "$tmp_out" ]; then
        set_summary "Could not create a temporary file in ${out_dir}."
        return 0
    fi

    local output exit_code
    output="$(run_pdfutil "$input_file" "$tmp_out")"
    exit_code=$?

    if [ $exit_code -ne 0 ]; then
        if [ "$PDFUTIL_OUTPUT_KIND" = "images" ]; then
            remove_render_outputs "$tmp_out" "$(render_suffix "$(render_format)")"
        fi
        /bin/rm -f "$tmp_out"
        set_summary "FAILED ${filename}: $(first_error_line "$output")"
        return 0
    fi

    # render decides between its literal-path and prefix forms from the page
    # count it resolves itself. The router predicts that to pick this runner,
    # and the prediction can disagree - an unresolvable range, or a document
    # whose page count could not be read. When it does, pdfutil wrote
    # <tmp_out>-001.<ext> and left the staging file empty; deliver those files
    # under the chosen name rather than handing back a 0-byte "image".
    if [ "$PDFUTIL_OUTPUT_KIND" = "images" ] && [ ! -s "$tmp_out" ]; then
        local suffix="$(render_suffix "$(render_format)")"

        # The Save panel confirmed exactly one name. -001, -002, ... were never
        # shown to the user, so they are not covered by that confirmation and
        # must not be overwritten - pick a series stem that collides with
        # nothing, the same way the batch runner does. That can shift the name
        # even when only the confirmed file exists; erring toward a fresh name
        # is the right trade in a branch that only runs when the page count was
        # mispredicted.
        local confirmed_stem="$(strip_image_extension "$output_file")"
        local final_stem
        final_stem="$(strip_image_extension \
            "$(unique_render_prefix "$confirmed_stem" "$suffix")")"

        # Three-or-more digits: pdfutil's %03d is a minimum width, so the
        # series keeps going past -999 (see render_outputs_exist).
        local moved=0 unsaved=0 part part_name first_part=""
        for part in "$tmp_out"-[0-9][0-9][0-9]*"$suffix"; do
            [ -e "$part" ] || continue
            part_name="${part##*-}"
            /bin/chmod 644 "$part"
            if /bin/mv -f "$part" "${final_stem}-${part_name}"; then
                [ -z "$first_part" ] && first_part="${final_stem}-${part_name}"
                moved=$((moved + 1))
            else
                # Discard rather than leave it under the mktemp name, where it
                # would be an invisible dotfile the user never finds, and count
                # it so the summary cannot claim more than was delivered.
                /bin/rm -f "$part"
                unsaved=$((unsaved + 1))
            fi
        done
        /bin/rm -f "$tmp_out"
        if [ "$moved" -eq 0 ]; then
            set_summary "FAILED ${filename}: no images could be saved."
        elif [ "$unsaved" -gt 0 ]; then
            set_summary "OK ${filename}: ${moved} image(s), ${unsaved} could not be saved
Output: ${first_part}"
        else
            set_summary "OK ${filename}: ${moved} image(s)
Output: ${first_part} and $((moved - 1)) more"
        fi
        return 0
    fi

    # mktemp creates 0600 files - give the result normal permissions
    /bin/chmod 644 "$tmp_out"
    if ! /bin/mv -f "$tmp_out" "$output_file"; then
        /bin/rm -f "$tmp_out"
        set_summary "FAILED ${filename}: could not write ${output_file}"
        return 0
    fi

    local orig_size="$(/usr/bin/stat -f %z "$input_file" 2>/dev/null)"
    local new_size="$(/usr/bin/stat -f %z "$output_file" 2>/dev/null)"

    set_summary "OK ${filename}: $(format_size "$orig_size") -> $(format_size "$new_size")
Output: $output_file"
}
