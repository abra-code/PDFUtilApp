#!/bin/bash
# lib.PDFUtil.args.sh - the pdfutil argument builder
#
# build_pdfutil_args turns the panel's controls into a pdfutil command line,
# with the clamps and whitelists that keep a stale or hand-typed control value
# from reaching the binary.
#
# Sourced by: every PDFUtil.run.* handler and PDFUtil.start.batch
# Requires lib.PDFUtil.sh (tool paths, control IDs, primitives) to be
# sourced first; every handler that needs this one sources both, in order.
#
# Runs under /bin/sh (macOS bash 3.2 in POSIX mode): no process substitution,
# no mapfile, no declare -A, no ${var,,}. Validate with `sh -n`, never `bash -n`.

# The --allow list that grants everything, in the order encrypt_allow_list
# emits. Matching it means every group is at its most permissive, which is
# exactly what omitting --allow does - so the flag can be left off entirely.
ENC_ALLOW_ALL="high-quality-printing,copying,changes,assembly"

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

# Echo a page-scale DPI for frompages, defaulting to 150.
#
# Not clamp_dpi: that allows 1..2400, which is the right range for RASTERIZING
# but absurd for the inverse direction, where the DPI decides how big a page the
# image becomes. The page is the image's pixel size divided by the DPI, so a low
# value scales without bound and pdfutil clamps nothing of its own - measured,
# --dpi 1 turns a 200 px wide image into a 14400 pt page and a 612 px wide one
# into a 44064 pt page, and both exit 0. 36 to 1200 spans a half-size poster to a
# fine-detail scan; outside that the user has not chosen a page size, they have
# made a document nobody can use. 0 is not a scale at all, so it takes the
# default rather than the floor - flooring it to 36 would silently produce the
# largest page in the range from the value that most looks like "no opinion".
# Arguments: value default
clamp_page_dpi() {
    local d="$(trim_spaces "$1")" def="$2"
    case "$d" in
        '' | *[!0-9]*) echo "$def"; return ;;
    esac
    if [ ${#d} -gt 9 ]; then echo "$def"; return ; fi
    d=$((10#$d))
    [ "$d" -eq 0 ] && { echo "$def"; return ; }
    [ "$d" -lt 36 ] && d=36
    [ "$d" -gt 1200 ] && d=1200
    echo "$d"
}

# Echo the paper size to fit to, defaulting to letter.
#
# The list matches pdfutil's own --page-size names exactly. Anything else would
# be a usage error carrying a picker value the user never chose, so an
# unrecognised value falls back rather than being passed through.
assemble_page_size() {
    case "$OMC_ACTIONUI_VIEW_225_VALUE" in
        letter | legal | tabloid | a3 | a4 | a5) echo "$OMC_ACTIONUI_VIEW_225_VALUE" ;;
        *) echo "letter" ;;
    esac
}

# Echo the Inspect sub-mode, defaulting to info.
#
# Whitelisted for the same reason as the other pickers: a stale or transitional
# value must not choose a verb. Unlike those, an unrecognised value here cannot
# be a usage error - it would just pick the wrong report - so the default is the
# harmless one.
inspect_mode() {
    case "$OMC_ACTIONUI_VIEW_222_VALUE" in
        outline | forms | search) echo "$OMC_ACTIONUI_VIEW_222_VALUE" ;;
        *) echo "info" ;;
    esac
}

# Append `--set KEY=VALUE` for a metadata field the user filled in.
#
# A BLANK FIELD LEAVES THAT ATTRIBUTE ALONE - it does not delete it. The plan
# asked for `--delete KEY` on a field "the user explicitly cleared", but the
# panel has no way to know what was there to begin with: the list can hold many
# files with different metadata, and nothing pre-populates these fields from any
# of them. "Cleared" and "never filled in" are therefore the same input, so
# deleting on blank would wipe an author or title the user never saw. Removing
# everything is what the strip toggle is for; per-field deletion needs
# per-file prefill, which belongs with a single-file inspector, not here.
add_metadata_set() {
    local key="$1" value="$(trim_spaces "$2")"
    [ -z "$value" ] && return 0
    PDFUTIL_ARGS+=(--set "${key}=${value}")
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

# Build the pdfutil invocation for an operation into these globals:
#   PDFUTIL_VERB        the subcommand
#   PDFUTIL_ARGS        flags placed between the verb and the output
#   PDFUTIL_TRAILING    args that must follow the input (rare)
#   PDFUTIL_OUTPUT_KIND pdf | text | images | parts | merged | assembled | report - drives routing
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

        frompages)
            PDFUTIL_VERB="frompages"
            # Like merge, N inputs collapse to 1 output, so it takes the same
            # many-to-one runner path rather than the per-file loop.
            PDFUTIL_OUTPUT_KIND="assembled"
            # Three page-sizing modes, and only one of them sends nothing.
            # --page-size and --dpi both decide how big a page is, so pdfutil
            # refuses the pair; the picker is what keeps them apart here.
            case "$(assemble_mode)" in
                image)
                    # pdfutil's own default: the page is as large as the image
                    # says it is. No flag expresses this, it is the absence of
                    # both others.
                    ;;
                dpi)
                    # ALWAYS sent, even for a blank field. Picking this mode is
                    # the statement that a DPI should be assumed, so a blank
                    # field means the default the prompt shows - not "fall back
                    # to the image's own DPI", which is the mode next door and
                    # the one that produces the five-foot pages. clamp_page_dpi
                    # turns blank and garbage alike into 150.
                    PDFUTIL_ARGS+=(--dpi "$(clamp_page_dpi "$OMC_ACTIONUI_VIEW_220_VALUE" 150)")
                    ;;
                *)
                    PDFUTIL_ARGS+=(--page-size "$(assemble_page_size)")
                    ;;
            esac
            ;;

        inspect)
            # The only read-only operation: it writes nothing and is never given
            # -o, so its runner does not go through run_pdfutil. "report" is the
            # output kind the router uses to send it to an output window instead
            # of a destination prompt.
            PDFUTIL_OUTPUT_KIND="report"
            case "$(inspect_mode)" in
                outline) PDFUTIL_VERB="outline" ;;
                forms)
                    PDFUTIL_VERB="forms"
                    PDFUTIL_ARGS+=(--list)
                    ;;
                search)
                    PDFUTIL_VERB="search"
                    # `search <in.pdf> <query>` takes the query AFTER the input,
                    # so it goes in TRAILING rather than ARGS. Position alone
                    # does not protect it: pdfutil's option scanner is not
                    # positional, so a query like "-1" or "--count" is still read
                    # as a flag and the run fails with a message about the
                    # document. "--" ends option scanning, so the query reaches
                    # the verb as a query whatever it starts with.
                    PDFUTIL_TRAILING+=(-- "$(trim_spaces "$OMC_ACTIONUI_VIEW_224_VALUE")")
                    ;;
                *) PDFUTIL_VERB="info" ;;
            esac
            ;;

        metadata)
            PDFUTIL_VERB="metadata"
            PDFUTIL_OUTPUT_KIND="pdf"
            if [ "$OMC_ACTIONUI_VIEW_195_VALUE" = "true" ]; then
                # --strip clears everything. pdfutil applies it as a starting
                # condition rather than as an ordered step, so --strip --set and
                # --set --strip both keep the set value - the pair is well
                # defined, just not what the checkbox promises. "Remove all
                # metadata" that quietly puts one attribute back is a lie, so the
                # panel disables the fields and the builder sends the flag alone.
                PDFUTIL_ARGS+=(--strip)
            else
                add_metadata_set title "$OMC_ACTIONUI_VIEW_190_VALUE"
                add_metadata_set author "$OMC_ACTIONUI_VIEW_191_VALUE"
                add_metadata_set subject "$OMC_ACTIONUI_VIEW_192_VALUE"
                add_metadata_set keywords "$OMC_ACTIONUI_VIEW_193_VALUE"
                add_metadata_set creator "$OMC_ACTIONUI_VIEW_194_VALUE"
                # With no --set and no --strip, `metadata` is its own READ verb,
                # and -o there names a file to write the LISTING to - so the
                # runner would put an ASCII attribute dump inside the .pdf the
                # user asked for, exit 0, and report success. start.batch's
                # settings check already refuses this, but that guard lives in
                # another file; a builder arm should not depend on a distant
                # caller to keep it from emitting something destructive.
                if [ ${#PDFUTIL_ARGS[@]} -eq 0 ]; then
                    return 1
                fi
            fi
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

        # Both take nothing but the common options - no flags to build, and no
        # settings panel beyond their notice. They are separate arms rather than
        # one shared arm with the verb interpolated, because that is the shape
        # every other operation has and the saving would be one line.
        linearize)
            PDFUTIL_VERB="linearize"
            PDFUTIL_OUTPUT_KIND="pdf"
            ;;

        pdfa)
            PDFUTIL_VERB="pdfa"
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
