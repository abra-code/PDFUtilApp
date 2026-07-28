#!/bin/bash
# lib.PDFUtil.run.sh - running pdfutil and naming its output
#
# The two hard invariants live here and nowhere else: every pdfutil call passes
# -o (without it pdfutil edits the input IN PLACE) and --force (the runners
# stage through mktemp, which pre-creates a 0-byte file).
#
# Sourced by: the PDFUtil.run.* handlers that write a file (not the read-only
# ones, which never take -o and so need none of this)
# Requires lib.PDFUtil.sh (tool paths, control IDs, primitives) to be
# sourced first; every handler that needs this one sources both, in order.
#
# Also requires lib.PDFUtil.args.sh: run_save_as calls build_pdfutil_args and
# render_suffix. Running and argument-building stay separate files because
# start.batch needs the arguments without ever running anything - it builds them
# to decide which runner to chain to - so folding them together would hand every
# validation path the runner code it must not use.
#
# Runs under /bin/sh (macOS bash 3.2 in POSIX mode): no process substitution,
# no mapfile, no declare -A, no ${var,,}. Validate with `sh -n`, never `bash -n`.

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
        # merged and assembled are PDFs too. Omitting them here wrote a valid
        # PDF with no suffix whenever the user typed over the Save panel's
        # default name - the default carries .pdf, so only a renamed save hit it.
        pdf | merged | assembled)
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

# Echo the first line of a pdfutil diagnostic, without its "pdfutil: " prefix.
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
