#!/bin/bash
# lib.PDFUtil.sh - Shared functions and variables for PDFUtil
#
# Sourced by every handler: the pdfutil path, every control ID, and the small
# primitives that genuinely span the whole app. Topic-specific logic lives in
# the sibling libs, and logic used by exactly one handler lives in that handler:
#
#   lib.PDFUtil.files.sh    the file table (add/remove/select/badges)
#   lib.PDFUtil.panels.sh   the settings panel switcher, notices, mode state
#   lib.PDFUtil.args.sh     build_pdfutil_args and its clamps/validators
#   lib.PDFUtil.run.sh      running pdfutil and naming its output files
#
# Each handler sources this file plus only the libs it uses.
#
# Runs under /bin/sh (macOS bash 3.2 in POSIX mode): no process substitution,
# no mapfile, no declare -A, no ${var,,}. Validate with `sh -n`, never `bash -n`.

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
GROUP_FROMPAGES_ID=214
GROUP_METADATA_ID=215
GROUP_LINEARIZE_ID=217
GROUP_PDFA_ID=218
# 219 was reserved for a Fill Form panel, which was dropped rather than built
# (DESIGN.md section 14); Convert to Grayscale took the freed id.
GROUP_GRAY_ID=219

SETTINGS_PANEL_IDS="198 200 201 202 203 204 205 206 207 208 209 210 211 212 213 214 215 217 218 219"

# Reduce controls (id band 70-80)
RED_QUALITY_ID=72
RED_DOWNSAMPLE_ID=76
RED_DPI_ID=77
RED_MAXEDGE_ON_ID=78
RED_MAXEDGE_PX_ID=79

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

# Metadata controls (id band 190-195).
#
# Five text attributes plus a strip toggle. There is deliberately no Producer or
# date field: PDFKit's writer resets Producer, the creation date and the
# modification date on every save, so a field for them would be a control that
# cannot work. pdfutil says so on stderr; the panel says so up front instead.
META_TITLE_ID=190
META_AUTHOR_ID=191
META_SUBJECT_ID=192
META_KEYWORDS_ID=193
META_CREATOR_ID=194
META_STRIP_ID=195

# Build PDF from Images controls (id band 220-221 and 225-227).
#
# Allocated above the GroupBox band (200-219) rather than squeezed next to the
# metadata fields: this operation had no band in the plan's id map, and the two
# are unrelated. 225-227 continue it past the Inspect controls at 222-224.
#
# THREE ways to size a page, because the honest default is not the useful one.
# Without a page size pdfutil makes each page as large as its image claims to
# be, and cameras record 72 DPI, so a 4284 px photo becomes a 4284 pt page -
# 59 inches across. That is faithful to the file and almost never wanted, and it
# also defeats Reduce, whose downsampling threshold is measured against the page:
# an image sitting at 72 DPI is never "above 150 DPI" however many pixels it has.
# Fitting to a real paper size is therefore the default, and the other two modes
# stay available for the cases where the image's own scale is the point.
#
# Each optional row needs an id of its own, not just its control: hiding a bare
# picker would strand its label, so label and control share an HStack that gets
# hidden.
ASSEMBLE_MODE_ID=221
FP_DPI_ID=220
FP_DPI_ROW_ID=226
FP_PAGE_SIZE_ID=225
FP_PAGE_SIZE_ROW_ID=227

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
NOTICE_FROMPAGES_ID=314
NOTICE_METADATA_ID=315
NOTICE_LINEARIZE_ID=317
NOTICE_PDFA_ID=318
NOTICE_GRAY_ID=319

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
# Primitives
#
# Kept here because they are used across unrelated areas of the app - the
# summary line, size formatting, file classification and the operation the
# picker is on. Anything used by one area belongs in that area's lib instead.
# ---------------------------------------------------------------------------

# Echo pdfutil's own diagnostic, without its "pdfutil: " prefix.
#
# Prefer the line that starts with "pdfutil" over the first line, because
# CoreGraphics and PDFKit write their own noise to the same stream and often get
# there first. A truncated PDF, for instance, leads with "CoreGraphics PDF has
# logged an error. Set environment variable CG_PDF_VERBOSE to learn more.",
# which tells the user nothing about their file. Falls back to the first line
# when pdfutil said nothing recognizable.
#
# Branch on the exit code, never on this being non-empty: pdfutil writes
# harmless PDFKit log lines to stderr on permission-restricted files while
# still exiting 0.
first_error_line() {
    local own
    own="$(printf '%s' "$1" | /usr/bin/grep -m1 '^pdfutil[: ]')"
    if [ -n "$own" ]; then
        printf '%s' "$own" | /usr/bin/sed 's/^pdfutil[a-z. ]*: //'
        return
    fi
    printf '%s' "$1" | /usr/bin/head -1
}

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
# and - unlike parsing the document with `pdfutil info` - still recognizes a
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
#                  honors that. A PDF carrying a BOM or a stray leading space
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
# The Operation picker's own title, so a message names the thing the user picked.
operation_label() {
    case "$1" in
        reduce)    echo "Reduce File Size" ;;
        linearize) echo "Linearize" ;;
        pdfa)      echo "Convert to PDF/A" ;;
        gray)      echo "Convert to Grayscale" ;;
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
        *)         echo "$1" ;;
    esac
}

# Echo how Build PDF from Images should size its pages, defaulting to fit.
#
# Whitelisted like the other pickers: a stale or transitional value must not
# choose a geometry. The default is the safe one rather than the faithful one -
# see the FP_* id block above for why "each image's own DPI" turns an ordinary
# photo into a five-foot page.
#
# Here in the core lib rather than in the argument builder because it has two
# callers that must agree: build_pdfutil_args picks the flag from it, and
# apply_assemble_mode_state picks which row to show. A second copy of this
# whitelist is a panel that displays one mode while the run uses another. It is
# the same reason render_format below lives here - the *.mode.changed handlers
# source this lib and lib.PDFUtil.panels.sh, but NOT lib.PDFUtil.args.sh.
assemble_mode() {
    case "$OMC_ACTIONUI_VIEW_221_VALUE" in
        image | dpi) echo "$OMC_ACTIONUI_VIEW_221_VALUE" ;;
        *) echo "fit" ;;
    esac
}

# Echo the selected image format, defaulting to png. Validated rather than
# passed through: a programmatic picker update can fire with a transitional
# value, and an unknown --format is a usage error the user cannot act on.
render_format() {
    case "$OMC_ACTIONUI_VIEW_170_VALUE" in
        png | jpeg | tiff | heic) echo "$OMC_ACTIONUI_VIEW_170_VALUE" ;;
        *) echo "png" ;;
    esac
}

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

# Trim leading and trailing whitespace. Only the ends: pdfutil's parser trims
# each term and each endpoint the same way, so "1 - 3" is a valid range there.
# Deleting interior whitespace instead would turn "1 2" into page 12, a page
# the user did not ask for and pdfutil would have rejected.
trim_spaces() {
    printf '%s' "$1" | /usr/bin/sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}
