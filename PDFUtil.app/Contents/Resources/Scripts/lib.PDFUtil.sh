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
GROUP_ENCRYPT_ID=203
GROUP_DECRYPT_ID=204
GROUP_EXTRACT_ID=205
GROUP_DELETE_ID=206
GROUP_ROTATE_ID=207
GROUP_CROP_ID=208
GROUP_SPLIT_ID=209
GROUP_MERGE_ID=210
GROUP_OCR_ID=211
GROUP_WATERMARK_ID=212
GROUP_FLATTEN_ID=213

SETTINGS_PANEL_IDS="198 200 201 202 203 204 205 206 207 208 209 210 211 212 213"

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

# Set Password controls (id band 110-121).
#
# Each password is typed twice. This is the one typo the tool can never recover
# from: a wrong password on Remove Password merely fails against the file, but a
# wrong password on Set Password is written into the document, so nobody can
# open the result and nothing here can report what was actually typed.
ENC_USER_PW_ID=110
ENC_USER_PW_CONFIRM_ID=111
ENC_OWNER_PW_ID=112
ENC_OWNER_PW_CONFIRM_ID=113

# Permissions: three Pickers and one Toggle rather than the eight checkboxes
# pdfutil's --allow list suggests, because the eight flags are not independent.
# Verified against the raw /P bits (pdfutil writes them, qpdf reads them back):
#
#   --allow high-quality-printing  ->  print low AND high resolution
#   --allow printing               ->  print low resolution only
#   --allow copying                ->  extract for any purpose AND accessibility
#   --allow accessibility          ->  extract for accessibility only
#   --allow changes                ->  modify forms, annotations and other
#   --allow commenting             ->  modify forms and annotations
#   --allow forms                  ->  modify forms only
#   --allow assembly               ->  document assembly only
#
# So three of the four groups are ladders where each rung implies the ones below
# it, and one flag per ladder is sufficient - passing "printing,high-quality-
# printing" writes exactly the bits "high-quality-printing" writes alone. Eight
# checkboxes would let the user express combinations that collapse to the same
# file, which is eight switches pretending to be independent.
#
# Note pdfutil's help states the coupling the other way round ("granting
# printing also permits high-quality-printing"). That describes PDFKit's
# permission *reporting*, which conflates the two print bits; the bits actually
# written follow the table above.
ENC_PRINTING_ID=114
ENC_COPYING_ID=115
ENC_CHANGES_ID=116
ENC_ASSEMBLY_ID=117

# Remove Password controls. 122 rather than 120: the encrypt band above grew to
# hold the two confirmation fields.
DEC_PASSWORD_ID=122

# Page operation controls
EXT_RANGE_ID=140
DEL_RANGE_ID=141
ROT_ANGLE_ID=130
ROT_RANGE_ID=131
SPLIT_EVERY_ID=150
SPLIT_CHAPTERS_ID=151
CROP_MODE_ID=185
CROP_VALUES_ID=186
CROP_BOX_ID=187
CROP_RANGE_ID=188

# OCR controls (id band 180-184).
#
# --searchable is not a variation of the same run, it is a different engine:
# the default path rasterizes each page and reads it with Vision, producing
# text, while --searchable hands the document to PDFKit's own OCR and saves a
# PDF. The help used to name only --lang/--fast/--dpi as inapplicable there.
# Measured: -p did not apply either - `ocr --searchable -p 1` on a three-page
# scan returned all three pages, every one carrying a text layer, and `-p 99`
# on a three-page file exited 0 without complaint. All four were reported
# upstream and pdfutil now REFUSES them alongside --searchable rather than
# dropping them, so emitting any of them here would be a usage error, not a
# silent no-op. Hence all four controls go dead when 183 is on.
OCR_LANG_ID=180
OCR_FAST_ID=181
OCR_DPI_ID=182
OCR_SEARCHABLE_ID=183
OCR_RANGE_ID=184

# Watermark controls (id band 160-168).
#
# Two modes that share almost no flags. Burn-in redraws the page with the mark
# painted into it; --annotation adds a freeText annotation and leaves the
# document's structure alone. pdfutil rejects --annotation with --image, and
# (since the ignored-parameter sweep) with --rotate-mark and --under too - all
# three used to be a mix of hard error and silent drop. The mode toggle drives
# which controls are live, so none of the three can be sent in that mode.
WM_TEXT_ID=160
WM_IMAGE_ID=161
WM_POSITION_ID=162
WM_ROTATION_ID=163
WM_OPACITY_ID=164
WM_UNDER_ID=165
WM_ANNOTATION_ID=166
WM_RANGE_ID=167
WM_CHOOSE_IMAGE_ID=168

# Per-section structure notice Text elements (band 300-319, one per GroupBox).
# Their wording is written at runtime by structure_notice so the prose lives in
# exactly one place - the same table the Stage 7 pre-flight alert will read.
NOTICE_REDUCE_ID=300
NOTICE_RENDER_ID=301
NOTICE_TEXT_ID=302
NOTICE_ENCRYPT_ID=303
NOTICE_DECRYPT_ID=304
NOTICE_EXTRACT_ID=305
NOTICE_DELETE_ID=306
NOTICE_ROTATE_ID=307
NOTICE_CROP_ID=308
NOTICE_SPLIT_ID=309
NOTICE_MERGE_ID=310
NOTICE_OCR_ID=311
NOTICE_WATERMARK_ID=312
NOTICE_FLATTEN_ID=313

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
            echo "Redraws pages: annotations, links, outline, and form fields are not carried over. \"Convert to grayscale\" uses a different filter that replaces the quality, resolution and edge settings rather than adding to them."
            ;;
        render)
            echo "Rasterizes pages to images. Text stops being selectable and searchable - export at a higher DPI if the result will be read on screen."
            ;;
        text)
            echo "Extracts the existing text layer only. Scanned pages have none and come out empty - use OCR for those."
            ;;
        encrypt)
            echo "Writes 128-bit AES (revision 4): ASCII passwords only, and only their first 32 characters count. Use QuickPDF's 256-bit AES if you need more. Permissions bind only readers who open with the user password, so a single password serving as both restricts nobody."
            ;;
        decrypt)
            echo "Saves an unlocked copy and leaves the original untouched."
            ;;
        extract)
            echo "Keeps the listed pages in the listed order, so repeats and reordering are legal. Rebuilds the document: the outline is not carried over."
            ;;
        delete)
            echo "Edits in place and keeps the outline, so entries pointing at removed pages may dangle."
            ;;
        rotate)
            echo "Lossless: only each page's rotation entry changes. Degrees are added to the current rotation, not set - rotating 90 twice gives 180."
            ;;
        crop)
            echo "Lossless: content is untouched and only the page box changes, so cropped-away material is hidden rather than removed."
            ;;
        split)
            echo "Each part keeps its pages' annotations, links and form fields; the document outline is not carried into the parts."
            ;;
        merge)
            echo "Inputs are joined in list order. Page-level structure is carried over; the document outline is not merged across inputs."
            ;;
        ocr)
            echo "Reads the pages as pictures, so it works on scans with no text layer at all. Recognition is never perfect - check the result before relying on it. \"Embed a searchable text layer\" saves a PDF through a different engine, which covers the whole document and picks its own settings, so the language, speed, resolution and page-range controls do not apply to it."
            ;;
        watermark)
            echo "Burning the mark in redraws the pages: annotations, links, the outline and form fields are not carried over. Adding it as an annotation keeps all of that and stays editable, but is text-only and cannot be rotated."
            ;;
        flatten)
            echo "Removes interactivity deliberately: filled-in values and annotation appearances are painted into the page and the fields themselves are gone. The outline survives; nothing can be edited afterwards."
            ;;
        *)
            echo ""
            ;;
    esac
}

# Return 0 when an operation reaches its result by REDRAWING the page content,
# which discards annotations, links, the outline and form fields.
#
# Measured rather than assumed - each verb was run against a fixture with an
# outline and one with form fields, and the output re-read with `info` and
# `forms --list`:
#
#   reduce, linearize, pdfa, watermark (burn-in)  outline AND fields lost
#   watermark --annotation                        both kept
#   ocr --searchable                              both kept
#   flatten                                       outline kept, fields removed
#
# flatten is deliberately absent: removing the fields is what the user asked
# for, so warning about it would be warning about the operation succeeding. Its
# section text explains the effect instead.
#
# linearize and pdfa are listed although their panels arrive in a later stage:
# the measurement is done and the table is the thing that must not go stale.
# frompages joins them when it lands, but only for PDF inputs.
#
# Arguments: operation tag
operation_redraws() {
    case "$1" in
        reduce | linearize | pdfa)
            return 0
            ;;
        watermark)
            # Annotation mode is the structure-preserving alternative, so the
            # toggle decides. Unset means the toggle's declared isOn, which is
            # off - burn-in, the mode that redraws.
            if [ "$OMC_ACTIONUI_VIEW_166_VALUE" = "true" ]; then
                return 1
            fi
            return 0
            ;;
    esac
    return 1
}

# Echo the id of the Text element that displays the notice for an operation,
# or "" when that section has no notice element.
notice_id_for_operation() {
    case "$1" in
        reduce)  echo ${NOTICE_REDUCE_ID} ;;
        render)  echo ${NOTICE_RENDER_ID} ;;
        text)    echo ${NOTICE_TEXT_ID} ;;
        encrypt) echo ${NOTICE_ENCRYPT_ID} ;;
        decrypt) echo ${NOTICE_DECRYPT_ID} ;;
        extract) echo ${NOTICE_EXTRACT_ID} ;;
        delete)  echo ${NOTICE_DELETE_ID} ;;
        rotate)  echo ${NOTICE_ROTATE_ID} ;;
        crop)    echo ${NOTICE_CROP_ID} ;;
        split)   echo ${NOTICE_SPLIT_ID} ;;
        merge)   echo ${NOTICE_MERGE_ID} ;;
        ocr)       echo ${NOTICE_OCR_ID} ;;
        watermark) echo ${NOTICE_WATERMARK_ID} ;;
        flatten)   echo ${NOTICE_FLATTEN_ID} ;;
        *)       echo "" ;;
    esac
}

# Echo the id of the settings panel for an operation, falling back to the
# placeholder for the operations later stages still have to build.
panel_for_operation() {
    case "$1" in
        reduce)  echo ${GROUP_REDUCE_ID} ;;
        render)  echo ${GROUP_RENDER_ID} ;;
        text)    echo ${GROUP_TEXT_ID} ;;
        encrypt) echo ${GROUP_ENCRYPT_ID} ;;
        decrypt) echo ${GROUP_DECRYPT_ID} ;;
        extract) echo ${GROUP_EXTRACT_ID} ;;
        delete)  echo ${GROUP_DELETE_ID} ;;
        rotate)  echo ${GROUP_ROTATE_ID} ;;
        crop)    echo ${GROUP_CROP_ID} ;;
        split)   echo ${GROUP_SPLIT_ID} ;;
        merge)   echo ${GROUP_MERGE_ID} ;;
        ocr)       echo ${GROUP_OCR_ID} ;;
        watermark) echo ${GROUP_WATERMARK_ID} ;;
        flatten)   echo ${GROUP_FLATTEN_ID} ;;
        *)       echo ${GROUP_PLACEHOLDER_ID} ;;
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

# Enable the crop value field's companions for the chosen mode.
#
# --rect and --margins both take four comma-separated numbers but mean opposite
# things, so the prompt has to say which one is being typed. Called when the
# mode picker changes and when the panel first appears.
apply_crop_mode_state() {
    if [ "$OMC_ACTIONUI_VIEW_185_VALUE" = "rect" ]; then
        "$dialog_tool" "$window_uuid" ${CROP_VALUES_ID} \
            omc_set_property "prompt" "X,Y,W,H in points from the bottom-left"
        # --rect is absolute against the media box, so --box picks which box to
        # write, not which box to measure from. Leave it live either way.
    else
        "$dialog_tool" "$window_uuid" ${CROP_VALUES_ID} \
            omc_set_property "prompt" "left,bottom,right,top margins in points"
    fi
}

# Enable exactly the split controls the chosen mode uses. --chapters and --every
# are alternatives and pdfutil rejects the pair outright ("--every and --chapters
# are mutually exclusive", exit 1 - re-measured, an earlier note here claimed it
# silently preferred --every), so the UI must never let both reach the builder.
apply_split_mode_state() {
    if [ "$OMC_ACTIONUI_VIEW_151_VALUE" = "true" ]; then
        "$dialog_tool" "$window_uuid" ${SPLIT_EVERY_ID} omc_disable
    else
        "$dialog_tool" "$window_uuid" ${SPLIT_EVERY_ID} omc_enable
    fi
}

# Switch off the recompression controls that grayscale mode replaces.
#
# --gray selects the system Gray Tone filter, which is built INSTEAD of the
# recompression filter rather than on top of it, so quality, resolution and
# max-edge have nothing to act on. pdfutil used to accept all three and drop
# them silently (-q 1 and -q 100 gave byte-identical files); it now refuses the
# combination, so build_pdfutil_args must stop emitting them as well - see the
# reduce case there.
apply_reduce_mode_state() {
    local state=omc_enable
    [ "$OMC_ACTIONUI_VIEW_80_VALUE" = "true" ] && state=omc_disable

    "$dialog_tool" "$window_uuid" ${RED_QUALITY_ID} "$state"
    "$dialog_tool" "$window_uuid" ${RED_DOWNSAMPLE_ID} "$state"
    "$dialog_tool" "$window_uuid" ${RED_DPI_ID} "$state"
    "$dialog_tool" "$window_uuid" ${RED_MAXEDGE_ON_ID} "$state"
    "$dialog_tool" "$window_uuid" ${RED_MAXEDGE_PX_ID} "$state"
}

# Switch off the OCR controls the searchable path cannot use.
#
# All four, not the three the help used to name: -p does not apply there either
# (measured - see the id block above). pdfutil refuses all four alongside
# --searchable, so a live control here would offer a setting that cannot even be
# sent; before that fix it was worse still, silently doing nothing while the
# output read as evidence the setting had been honoured.
apply_ocr_mode_state() {
    local state=omc_enable
    [ "$OMC_ACTIONUI_VIEW_183_VALUE" = "true" ] && state=omc_disable

    "$dialog_tool" "$window_uuid" ${OCR_LANG_ID} "$state"
    "$dialog_tool" "$window_uuid" ${OCR_FAST_ID} "$state"
    "$dialog_tool" "$window_uuid" ${OCR_DPI_ID} "$state"
    "$dialog_tool" "$window_uuid" ${OCR_RANGE_ID} "$state"
}

# Switch off the watermark controls the annotation mode cannot use.
#
# pdfutil refuses --image, --rotate-mark and --under alongside --annotation, so
# all three are usage errors now; --rotate-mark and --under used to be accepted
# and then ignored, which is why the toggle already took them out of play before
# the refusals landed. Either way the user must not be able to set them here.
apply_watermark_mode_state() {
    local state=omc_enable
    [ "$OMC_ACTIONUI_VIEW_166_VALUE" = "true" ] && state=omc_disable

    "$dialog_tool" "$window_uuid" ${WM_IMAGE_ID} "$state"
    "$dialog_tool" "$window_uuid" ${WM_CHOOSE_IMAGE_ID} "$state"
    "$dialog_tool" "$window_uuid" ${WM_ROTATION_ID} "$state"
    "$dialog_tool" "$window_uuid" ${WM_UNDER_ID} "$state"
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
        # Deliberately not a list of what does work: that sentence went stale
        # every time a stage landed, and panel_for_operation above is already
        # the authoritative record of which operations have been built.
        "$dialog_tool" "$window_uuid" ${GROUP_PLACEHOLDER_ID} \
            "$(operation_label "$op") is not available yet.
Pick another operation, or use QuickPDF if it offers this one."
    fi

    if [ "$want" = "${GROUP_REDUCE_ID}" ]; then
        apply_reduce_mode_state
    fi

    if [ "$want" = "${GROUP_RENDER_ID}" ]; then
        apply_render_format_state
    fi

    if [ "$want" = "${GROUP_CROP_ID}" ]; then
        apply_crop_mode_state
    fi

    if [ "$want" = "${GROUP_SPLIT_ID}" ]; then
        apply_split_mode_state
    fi

    if [ "$want" = "${GROUP_OCR_ID}" ]; then
        apply_ocr_mode_state
    fi

    if [ "$want" = "${GROUP_WATERMARK_ID}" ]; then
        apply_watermark_mode_state
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

# Append -p RANGE to PDFUTIL_ARGS, but only when the field holds something.
#
# Every optional page-range field goes through here so the emptiness test and
# the value passed are the SAME string. Testing the raw field and then passing a
# trimmed copy is the bug this replaces: a field holding only a space is
# non-empty, so -p was added, but it trimmed to "" and pdfutil rejected the run
# with "empty page-range term in ''" - an optional field the user meant to leave
# blank, failing the whole operation with a parser message.
#
# Arguments: raw field value
add_page_range() {
    local range="$(trim_spaces "$1")"
    if [ -n "$range" ]; then
        PDFUTIL_ARGS+=(-p "$range")
    fi
    return 0
}

# Echo the rotation in degrees, defaulting to 90. Only the four values pdfutil
# accepts get through; anything else would be a usage error carrying a stale
# picker value the user never chose.
rotate_angle() {
    case "$OMC_ACTIONUI_VIEW_130_VALUE" in
        90 | 180 | 270 | -90) echo "$OMC_ACTIONUI_VIEW_130_VALUE" ;;
        *) echo "90" ;;
    esac
}

# Echo the watermark position, defaulting to center. pdfutil exits 1 on an
# unrecognised --position, so a stale or transitional picker value would turn
# into a usage error rather than a mark in the wrong corner.
watermark_position() {
    case "$OMC_ACTIONUI_VIEW_162_VALUE" in
        center | top-left | top-right | bottom-left | bottom-right)
            echo "$OMC_ACTIONUI_VIEW_162_VALUE"
            ;;
        *) echo "center" ;;
    esac
}

# Echo a whole-degree rotation for the mark, defaulting to 45.
#
# pdfutil accepts any integer here, 400 and -45 included, so there is nothing
# to clamp to - only non-numeric junk has to be turned into something. The
# leading "-" is peeled off before the digit test so negatives survive it.
# Arguments: value default
clamp_degrees() {
    local v="$(trim_spaces "$1")" sign=""
    case "$v" in
        -*) sign="-"; v="${v#-}" ;;
    esac
    case "$v" in
        "" | *[!0-9]*) echo "$2"; return ;;
    esac
    # Beyond nine digits the value is meaningless as an angle and would
    # overflow the arithmetic that normalises it; take the default instead.
    if [ ${#v} -gt 9 ]; then echo "$2"; return; fi
    echo "${sign}$((10#$v))"
}

# Echo an opacity from 0 to 100, defaulting to 25.
#
# Not clamp_quality: that floors at 1, and pdfutil accepts --opacity 0. Zero is
# a legal value here (an invisible mark), so silently raising it to 1 would be
# changing a setting the user chose. Out-of-range values are a usage error
# (exit 1, verified at 150), which is what this exists to prevent.
clamp_opacity() {
    local v="$(trim_spaces "$1")"
    case "$v" in
        "" | *[!0-9]*) echo "$2"; return ;;
    esac
    if [ ${#v} -gt 9 ]; then echo "100"; return; fi
    v=$((10#$v))
    [ "$v" -gt 100 ] && v=100
    echo "$v"
}

# Append one --lang FLAG per tag in a comma-separated list, skipping anything
# that is not a plausible BCP-47 tag.
#
# The filter is not about recognition: Vision ignores a tag it does not know
# (verified, --lang zz-ZZ exits 0), so a wrong tag costs nothing.
#
# Nor is it strictly required for safety. pdfutil's parser consumes the argv
# after a flag unconditionally, even one beginning with "-" (verified against
# the binary), so a tag like "--force" would arrive as a language name rather
# than as a second flag. What the filter buys is that garbage in this field
# stays in this field: a value the parser would accept and Vision would discard
# never reaches the command line, so the invocation says what was really asked
# for. Defence in depth, at the cost of one case label.
#
# An empty list is correct and means "auto-detect".
#
# Arguments: raw field value
add_ocr_langs() {
    local raw="$(trim_spaces "$1")" tag
    [ -z "$raw" ] && return 0

    local old_ifs="$IFS"
    # set -f for the same reason range_page_count does it: this is text the
    # user typed, and a "*" would otherwise expand against the working
    # directory. Restore rather than assume - an unconditional `set +f` would
    # switch globbing on for a caller that had turned it off.
    local glob_state="$-"
    set -f
    IFS=','
    set -- $raw
    IFS="$old_ifs"
    case "$glob_state" in *f*) ;; *) set +f ;; esac

    for tag in "$@"; do
        tag="$(trim_spaces "$tag")"
        case "$tag" in
            "" | [!A-Za-z]* | *[!A-Za-z0-9-]*) continue ;;
        esac
        PDFUTIL_ARGS+=(--lang "$tag")
    done
    return 0
}

# Echo the page box to write, defaulting to crop (pdfutil's own default).
crop_box() {
    case "$OMC_ACTIONUI_VIEW_187_VALUE" in
        media | crop | art | bleed | trim) echo "$OMC_ACTIONUI_VIEW_187_VALUE" ;;
        *) echo "crop" ;;
    esac
}

# Echo a pages-per-part count of at least 1.
#
# Digits only, and length-capped before the numeric comparison: [ -gt ] on a
# value wider than a 64-bit integer is an error, not a false, so an unbounded
# field could take the guard down instead of being clamped by it.
# Arguments: value fallback
clamp_every() {
    local v="$(trim_spaces "$1")"
    case "$v" in
        "" | *[!0-9]*) echo "$2"; return ;;
    esac
    if [ ${#v} -gt 9 ]; then echo "999999999"; return; fi
    v=$((10#$v))
    [ "$v" -lt 1 ] && v="$2"
    echo "$v"
}

# The --allow list that grants everything, in the order encrypt_allow_list
# emits. Matching it means every group is at its most permissive, which is
# exactly what omitting --allow does - so the flag can be left off entirely.
ENC_ALLOW_ALL="high-quality-printing,copying,changes,assembly"

# Echo the comma-joined --allow list for the four permission controls.
#
# One flag per group: each is the top of a ladder that implies the rungs below
# it, so "high-quality-printing" alone writes the same bits as
# "printing,high-quality-printing" (see the id block near the top of this file
# for the verified table). "none" contributes nothing.
#
# An empty result means every permission was denied. pdfutil cannot express
# that - `--allow ""` is a usage error and omitting the flag grants everything -
# so start.batch checks for it and refuses before a run starts.
encrypt_allow_list() {
    local allow=""

    case "$OMC_ACTIONUI_VIEW_114_VALUE" in
        printing | high-quality-printing) allow="$OMC_ACTIONUI_VIEW_114_VALUE" ;;
        none) ;;
        # Unset means the picker has not reported yet, which is its first and
        # most permissive option. Defaulting the other way would silently
        # restrict a document the user never asked to restrict.
        *) allow="high-quality-printing" ;;
    esac

    case "$OMC_ACTIONUI_VIEW_115_VALUE" in
        copying | accessibility) allow="${allow:+$allow,}$OMC_ACTIONUI_VIEW_115_VALUE" ;;
        none) ;;
        *) allow="${allow:+$allow,}copying" ;;
    esac

    case "$OMC_ACTIONUI_VIEW_116_VALUE" in
        changes | commenting | forms) allow="${allow:+$allow,}$OMC_ACTIONUI_VIEW_116_VALUE" ;;
        none) ;;
        *) allow="${allow:+$allow,}changes" ;;
    esac

    # A Toggle reports "true"/"false"; unset is its declared isOn, which is on.
    if [ "$OMC_ACTIONUI_VIEW_117_VALUE" != "false" ]; then
        allow="${allow:+$allow,}assembly"
    fi

    echo "$allow"
}

# Echo why the chosen operation cannot run with the settings as they stand, or
# "" when it can. The router turns a non-empty answer into an alert.
#
# These are the checks that must happen before a destination is chosen, because
# the alternative is asking for a filename and only then reporting that the
# passwords disagreed - by which point the user has committed to a location for
# a file that was never going to be written.
# Arguments: operation tag
settings_problem() {
    case "$1" in
        encrypt) encrypt_settings_problem ;;
        decrypt)
            if [ -z "$OMC_ACTIONUI_VIEW_122_VALUE" ]; then
                echo "Enter the password that opens these PDFs.

pdfutil treats an empty password as a usage error rather than as a blank password."
            fi
            ;;
        extract)
            if [ -z "$(trim_spaces "$OMC_ACTIONUI_VIEW_140_VALUE")" ]; then
                echo "Enter the pages to keep, for example 1-5,8 or 3,1,2 to reorder."
            fi
            ;;
        delete)
            if [ -z "$(trim_spaces "$OMC_ACTIONUI_VIEW_141_VALUE")" ]; then
                echo "Enter the pages to remove, for example 2 or 4-6."
            fi
            ;;
        crop)
            local v="$(trim_spaces "$OMC_ACTIONUI_VIEW_186_VALUE")"
            if [ -z "$v" ]; then
                echo "Enter four comma-separated numbers in points."
            elif ! printf '%s' "$v" | \
                 /usr/bin/grep -Eq '^-?[0-9]+(\.[0-9]+)?(,-?[0-9]+(\.[0-9]+)?){3}$'; then
                echo "Crop needs exactly four comma-separated numbers in points, for example 36,36,36,36.

\"${v}\" is not in that form."
            fi
            ;;
        watermark) watermark_settings_problem ;;
    esac
}

# Echo why Watermark cannot run, or "" when it can.
watermark_settings_problem() {
    local text="$(trim_spaces "$OMC_ACTIONUI_VIEW_160_VALUE")"
    local image="$(trim_spaces "$OMC_ACTIONUI_VIEW_161_VALUE")"

    if [ "$OMC_ACTIONUI_VIEW_166_VALUE" = "true" ]; then
        # The image field is disabled in this mode but can still hold a path
        # from before the toggle was flipped, and build_pdfutil_args drops it
        # rather than passing --image into a usage error.
        #
        # Refused whether or not there is text to fall back on. Dropping it
        # silently when text happens to be filled in would make the outcome
        # depend on a field the user is not looking at, and it is the same
        # ambiguity the burn-in branch below refuses outright - one mark was
        # asked for and two were described. Making the user clear one of them
        # is the same answer in both modes.
        if [ -n "$image" ]; then
            echo "An annotation watermark is text-only, so the chosen image cannot be used.

Clear the image field, or turn the annotation option off to stamp the image instead."
            return
        fi
        if [ -z "$text" ]; then
            echo "Enter the text to stamp."
        fi
        return
    fi

    if [ -z "$text" ] && [ -z "$image" ]; then
        echo "Enter the text to stamp, or choose an image."
        return
    fi
    # pdfutil rejects the pair outright (exit 1) rather than picking one.
    if [ -n "$text" ] && [ -n "$image" ]; then
        echo "Stamp either text or an image, not both.

Clear the text field or the image field and try again."
        return
    fi
    # An image that has been moved or deleted since it was chosen fails per
    # file with "watermark image not found", once for every PDF in the list.
    # One message before the run beats a column of identical ones after it.
    if [ -n "$image" ] && [ ! -e "$image" ]; then
        echo "The watermark image is no longer at:
${image}

Choose it again."
        return
    fi
}

# Echo why Set Password cannot run, or "" when it can.
encrypt_settings_problem() {
    local user_pw="$OMC_ACTIONUI_VIEW_110_VALUE"
    local owner_pw="$OMC_ACTIONUI_VIEW_112_VALUE"

    # Checked before the empty test because a mismatch is the more specific
    # diagnosis: it names the field that went wrong instead of asking for a
    # password the user believes they already entered.
    if [ "$user_pw" != "$OMC_ACTIONUI_VIEW_111_VALUE" ]; then
        echo "The user password and its confirmation do not match.

Retype both fields and try again."
        return
    fi
    if [ "$owner_pw" != "$OMC_ACTIONUI_VIEW_113_VALUE" ]; then
        echo "The owner password and its confirmation do not match.

Retype both fields and try again."
        return
    fi
    if [ -z "$user_pw" ] && [ -z "$owner_pw" ]; then
        echo "Enter a user password, an owner password, or both.

The user password is needed to open the file; the owner password grants full access to whoever has it."
        return
    fi

    # Non-ASCII passwords are rejected outright by the writer: pdfutil exits 2
    # with "failed to write PDF" and produces no file. Verified with cafe-acute,
    # naive-diaeresis and Greek omega - so this is not "outside Latin-1", it is
    # anything above plain ASCII, accents included.
    #
    # Caught here because the failure it replaces is uninformative: the user
    # would pick a destination, wait, and then be told the PDF could not be
    # written, with nothing pointing at the password field as the cause.
    if printf '%s%s' "$user_pw" "$owner_pw" | LC_ALL=C /usr/bin/grep -q '[^ -~]'; then
        echo "Passwords must use plain ASCII characters only.

The 128-bit AES handler pdfutil writes cannot store accented or non-Latin characters, and refuses to write the file at all rather than producing one nobody can open. QuickPDF's 256-bit AES option accepts them."
        return
    fi

    # pdfutil has no way to say "grant nothing": omitting --allow grants
    # everything and passing it an empty list is a usage error. Saying so here
    # beats letting the run fail with "expects a comma-separated flag list",
    # which does not hint at which control caused it.
    if [ -z "$(encrypt_allow_list)" ]; then
        echo "Set at least one permission to something other than \"Not allowed\".

A PDF cannot deny every permission at once - that combination has no representation in the format, so pdfutil refuses it."
        return
    fi
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
            if [ "$OMC_ACTIONUI_VIEW_80_VALUE" = "true" ]; then
                # Grayscale is a different filter, not a modifier on the
                # recompression one: pdfutil builds the Gray Tone filter INSTEAD
                # of the quality/dpi/max-edge one, and refuses the combination
                # rather than accepting the three and dropping them. So this
                # branch emits --gray alone, exactly as the OCR searchable
                # branch emits --searchable alone. The panel greys the three
                # controls out to match (apply_reduce_mode_state).
                PDFUTIL_ARGS+=(--gray)
            else
                PDFUTIL_ARGS+=(-q "$(clamp_quality "$OMC_ACTIONUI_VIEW_72_VALUE" 85)")
                # -r is a ceiling, and 0 disables downsampling entirely. Passing
                # it explicitly in both cases keeps the toggle honest: pdfutil's
                # own default is 150, so omitting -r when the toggle is off
                # would downsample anyway.
                if [ "$OMC_ACTIONUI_VIEW_76_VALUE" = "true" ]; then
                    PDFUTIL_ARGS+=(-r "$(clamp_dpi "$OMC_ACTIONUI_VIEW_77_VALUE" 150)")
                else
                    PDFUTIL_ARGS+=(-r 0)
                fi
                if [ "$OMC_ACTIONUI_VIEW_78_VALUE" = "true" ]; then
                    PDFUTIL_ARGS+=(-m "$(clamp_pixels "$OMC_ACTIONUI_VIEW_79_VALUE" 2000)")
                fi
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
            add_page_range "$OMC_ACTIONUI_VIEW_174_VALUE"
            ;;

        text)
            PDFUTIL_VERB="text"
            PDFUTIL_OUTPUT_KIND="text"
            add_page_range "$OMC_ACTIONUI_VIEW_175_VALUE"
            if [ "$OMC_ACTIONUI_VIEW_176_VALUE" = "true" ]; then
                PDFUTIL_ARGS+=(--page-breaks)
            fi
            ;;

        encrypt)
            PDFUTIL_VERB="encrypt"
            PDFUTIL_OUTPUT_KIND="pdf"

            local user_pw="$OMC_ACTIONUI_VIEW_110_VALUE"
            local owner_pw="$OMC_ACTIONUI_VIEW_112_VALUE"

            # Which password travels on stdin is a real trade, because pdfutil
            # accepts at most one that way and the other lands in the argument
            # list, where `ps` can read it for the life of the call.
            #
            # The user password goes on stdin because it is the one whose
            # disclosure breaks confidentiality of the document itself; the
            # owner password only unlocks the permission bits. When just one
            # password was entered, nothing goes inline at all - pdfutil uses
            # the single password for both roles.
            #
            # This protects the argument list, not the environment: OMC exports
            # every control value to each handler, so the values are also in
            # this process's environment. Narrowing the exposure is the honest
            # claim here, not eliminating it.
            if [ -n "$user_pw" ]; then
                PDFUTIL_STDIN_PW="$user_pw"
                PDFUTIL_ARGS+=(--user-password-stdin)
                if [ -n "$owner_pw" ]; then
                    PDFUTIL_ARGS+=(--owner-password "$owner_pw")
                fi
            else
                # Owner password only: it can take the stdin slot instead.
                PDFUTIL_STDIN_PW="$owner_pw"
                PDFUTIL_ARGS+=(--owner-password-stdin)
            fi

            # Omitting --allow grants everything, which is also pdfutil's
            # default. An empty list is a usage error rather than "grant
            # nothing", so start.batch refuses that case before we get here.
            local allow="$(encrypt_allow_list)"
            if [ -n "$allow" ] && [ "$allow" != "$ENC_ALLOW_ALL" ]; then
                PDFUTIL_ARGS+=(--allow "$allow")
            fi
            ;;

        decrypt)
            PDFUTIL_VERB="decrypt"
            PDFUTIL_OUTPUT_KIND="pdf"
            PDFUTIL_STDIN_PW="$OMC_ACTIONUI_VIEW_122_VALUE"
            PDFUTIL_ARGS+=(--password-stdin)
            ;;

        extract)
            PDFUTIL_VERB="pages"
            PDFUTIL_OUTPUT_KIND="pdf"
            PDFUTIL_ARGS+=(--extract "$(trim_spaces "$OMC_ACTIONUI_VIEW_140_VALUE")")
            ;;

        delete)
            PDFUTIL_VERB="pages"
            PDFUTIL_OUTPUT_KIND="pdf"
            PDFUTIL_ARGS+=(--delete "$(trim_spaces "$OMC_ACTIONUI_VIEW_141_VALUE")")
            ;;

        rotate)
            PDFUTIL_VERB="rotate"
            PDFUTIL_OUTPUT_KIND="pdf"
            add_page_range "$OMC_ACTIONUI_VIEW_131_VALUE"
            # Degrees is positional and must precede the input path. run_pdfutil
            # emits PDFUTIL_ARGS before "--force -o OUT IN", so appending it last
            # here puts it in the only place the parser accepts it.
            PDFUTIL_ARGS+=("$(rotate_angle)")
            ;;

        crop)
            PDFUTIL_VERB="crop"
            PDFUTIL_OUTPUT_KIND="pdf"
            local crop_values="$(trim_spaces "$OMC_ACTIONUI_VIEW_186_VALUE")"
            if [ "$OMC_ACTIONUI_VIEW_185_VALUE" = "rect" ]; then
                PDFUTIL_ARGS+=(--rect "$crop_values")
            else
                PDFUTIL_ARGS+=(--margins "$crop_values")
            fi
            PDFUTIL_ARGS+=(--box "$(crop_box)")
            add_page_range "$OMC_ACTIONUI_VIEW_188_VALUE"
            ;;

        split)
            PDFUTIL_VERB="split"
            # Not "pdf": one input becomes a numbered series, so -o is a prefix
            # and the destination has to be a folder however few files are in
            # the list. See the router.
            PDFUTIL_OUTPUT_KIND="parts"
            if [ "$OMC_ACTIONUI_VIEW_151_VALUE" = "true" ]; then
                PDFUTIL_ARGS+=(--chapters)
            else
                PDFUTIL_ARGS+=(--every "$(clamp_every "$OMC_ACTIONUI_VIEW_150_VALUE" 1)")
            fi
            ;;

        merge)
            PDFUTIL_VERB="merge"
            # N inputs, 1 output: run_pdfutil takes a single input, so merge has
            # its own call path in run_pdfutil_merge.
            PDFUTIL_OUTPUT_KIND="merged"
            ;;

        ocr)
            PDFUTIL_VERB="ocr"
            if [ "$OMC_ACTIONUI_VIEW_183_VALUE" = "true" ]; then
                # A different engine and a different result: PDFKit's own OCR
                # saves a PDF. --lang, --fast, --dpi and -p cannot apply on
                # this path and pdfutil now refuses them here, so emitting any
                # of them would fail the run outright. Even when they were
                # merely ignored this branch sent --searchable alone, because a
                # flag that does nothing makes the command line lie about what
                # ran; the upstream fix turned that caution into a requirement.
                PDFUTIL_OUTPUT_KIND="pdf"
                PDFUTIL_ARGS+=(--searchable)
            else
                PDFUTIL_OUTPUT_KIND="text"
                add_ocr_langs "$OMC_ACTIONUI_VIEW_180_VALUE"
                if [ "$OMC_ACTIONUI_VIEW_181_VALUE" = "true" ]; then
                    PDFUTIL_ARGS+=(--fast)
                fi
                PDFUTIL_ARGS+=(--dpi "$(clamp_dpi "$OMC_ACTIONUI_VIEW_182_VALUE" 300)")
                add_page_range "$OMC_ACTIONUI_VIEW_184_VALUE"
            fi
            ;;

        watermark)
            PDFUTIL_VERB="watermark"
            PDFUTIL_OUTPUT_KIND="pdf"

            local wm_text="$(trim_spaces "$OMC_ACTIONUI_VIEW_160_VALUE")"
            local wm_image="$(trim_spaces "$OMC_ACTIONUI_VIEW_161_VALUE")"

            if [ "$OMC_ACTIONUI_VIEW_166_VALUE" = "true" ]; then
                # Annotation mode is text-only; pdfutil exits 1 if --image comes
                # with it. settings_problem has already refused both an empty
                # text field and a non-empty image field, so the mark is never
                # built without text and $wm_image is never silently discarded
                # here - by the time this runs it is known to be empty.
                PDFUTIL_ARGS+=(--text "$wm_text" --annotation)
            else
                if [ -n "$wm_text" ]; then
                    PDFUTIL_ARGS+=(--text "$wm_text")
                else
                    PDFUTIL_ARGS+=(--image "$wm_image")
                fi
                PDFUTIL_ARGS+=(--rotate-mark "$(clamp_degrees "$OMC_ACTIONUI_VIEW_163_VALUE" 45)")
                if [ "$OMC_ACTIONUI_VIEW_165_VALUE" = "true" ]; then
                    PDFUTIL_ARGS+=(--under)
                fi
            fi

            PDFUTIL_ARGS+=(--position "$(watermark_position)")
            PDFUTIL_ARGS+=(--opacity "$(clamp_opacity "$OMC_ACTIONUI_VIEW_164_VALUE" 25)")
            add_page_range "$OMC_ACTIONUI_VIEW_167_VALUE"
            ;;

        flatten)
            PDFUTIL_VERB="flatten"
            PDFUTIL_OUTPUT_KIND="pdf"
            ;;

        *)
            return 1
            ;;
    esac

    # No --password is added for the verbs that read an existing document.
    # Protected PDFs are out of scope outside Set Password and Remove Password,
    # and start.batch refuses them before a run begins. The encrypt and decrypt
    # paths above carry their secret through PDFUTIL_STDIN_PW instead, which
    # keeps it out of the argument list.
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
#
# When PDFUTIL_STDIN_PW is set the password is fed on stdin, so the secret stays
# out of the argument list. Doing it here rather than in a second "run it with a
# password" function means no runner has to know which operations carry one -
# encrypt and decrypt work through the same three call sites as every other
# verb, and a future password-bearing verb needs no runner change at all.
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
    if [ -n "$PDFUTIL_STDIN_PW" ]; then
        printf '%s' "$PDFUTIL_STDIN_PW" | _exec_pdfutil "$1" "$2"
    else
        # </dev/null so a verb that reads stdin can never block on the caller's
        # terminal; nothing here is meant to be interactive.
        _exec_pdfutil "$1" "$2" </dev/null
    fi
}

# The single place the binary is named with an output path. Kept separate only
# so run_pdfutil can choose stdin without writing this line twice - duplicating
# it is how -o or --force eventually goes missing from one of the copies.
# Arguments: input output
_exec_pdfutil() {
    "$PDFUTIL" "$PDFUTIL_VERB" "${PDFUTIL_ARGS[@]}" --force -o "$2" "$1" \
        "${PDFUTIL_TRAILING[@]}" 2>&1
}

# Merge's own call path: N inputs, one output, so it cannot use run_pdfutil's
# single-input shape. The -o and --force invariants are repeated here rather
# than skipped - merge without --force fails against the staging file, and
# merge without -o is a usage error rather than an in-place edit.
#
# Arguments: output, then one or more input paths
run_pdfutil_merge() {
    local out="$1"
    shift
    if [ -z "$out" ]; then
        echo "internal error: refusing to run merge without an output path"
        return 1
    fi
    if [ $# -eq 0 ]; then
        echo "internal error: merge needs at least one input"
        return 1
    fi
    "$PDFUTIL" merge "${PDFUTIL_ARGS[@]}" --force -o "$out" "$@" 2>&1
}

# ---------------------------------------------------------------------------
# Page ranges
# ---------------------------------------------------------------------------

# Echo the number of pages in a PDF, or "" when it cannot be read (locked
# without the right password, corrupt, not a PDF).
# Arguments: path
pdf_page_count() {
    pdf_info_for "$1" | /usr/bin/awk -F': ' '$1 == "pages" { print $2; exit }'
}

# Echo `pdfutil info` for a path, reusing what the locked-file guard just read
# for this same file rather than parsing the document twice. `info` costs a
# quarter of a second on a large PDF and both the page count and the structure
# pre-flight want it immediately after the guard has run.
#
# Echoes nothing when the document cannot be read - a locked or corrupt file -
# so every caller has to treat "" as "unknown", never as "zero".
# Arguments: path
pdf_info_for() {
    if [ "$1" = "$PDF_INFO_CACHE_PATH" ] && [ -n "$PDF_INFO_CACHE_OUT" ]; then
        printf '%s\n' "$PDF_INFO_CACHE_OUT"
        return
    fi
    "$PDFUTIL" info "$1" 2>/dev/null
}

# Echo what a redraw would discard from a document: "outline", "annotations",
# "outline annotations", or "" when there is nothing to lose.
#
# Both facts come out of `info`, which the caller has usually already paid for:
#
#   outline items: 3                          -> an outline
#   page 1: 612x792 pt, text, 2 annotations   -> annotations or form fields
#
# `info` counts form fields as annotations and does not separate them, so the
# wording never claims to know which it found. The page-line anchor matters:
# matching "annotations" anywhere in the output would fire on a document whose
# own path happens to contain the word.
#
# An unreadable document yields "", which reads as "nothing at risk" and lets
# the run proceed to the real error. That is the right direction - a guard
# should not block work over a question it could not answer.
# Arguments: path
pdf_structure_at_risk() {
    local info="$(pdf_info_for "$1")"
    [ -z "$info" ] && return 0

    local found=""
    local items="$(printf '%s\n' "$info" \
        | /usr/bin/awk -F': ' '$1 == "outline items" { print $2; exit }')"
    if [ -n "$items" ] && [ "$items" != "0" ]; then
        found="outline"
    fi
    if printf '%s\n' "$info" \
        | /usr/bin/awk '/^page [0-9]+: .* annotations/ { found = 1 } END { exit !found }'; then
        found="${found:+$found }annotations"
    fi
    echo "$found"
}

# Turn what pdf_structure_at_risk found into a phrase that completes
# "<FILE> has ...".
structure_risk_phrase() {
    case "$1" in
        "outline annotations") echo "an outline and annotations or form fields" ;;
        "outline")             echo "an outline" ;;
        "annotations")         echo "annotations or form fields" ;;
        *)                     echo "structure that will not survive" ;;
    esac
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
