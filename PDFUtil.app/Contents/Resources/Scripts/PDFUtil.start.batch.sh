#!/bin/bash
# PDFUtil.start.batch.sh - Save button: validate, then route to the right runner
#
# Routing branches on operation x input count x OUTPUT KIND, not on count alone.
# That is the structural difference from QuickPDF: there the output is always a
# PDF, here it can be a PDF, a text file or a set of images, and the destination
# prompt has to match. The prompt kind is fixed per command in Command.json
# (SAVE_AS_DIALOG vs CHOOSE_FOLDER_DIALOG, with the right default file name), so
# choosing a prompt means chaining to the command that declares it:
#
#   pdf,    1 input                  -> PDFUtil.run.single   Save As, .pdf
#   text,   1 input                  -> PDFUtil.run.text     Save As, .txt
#   images, 1 input, 1 page selected -> PDFUtil.run.image    Save As, image
#   merged, 2+ inputs                -> PDFUtil.run.merge    Save As, .pdf
#   parts   (split, any input count) -> PDFUtil.run.batch    destination folder
#   anything else                    -> PDFUtil.run.batch    destination folder
#
# The single-page test for images exists because render has two output modes and
# only one of them is a file: with several pages selected -o is a prefix and
# pdfutil writes <prefix>-001.<ext>, which a Save panel cannot express. Getting
# it wrong is not fatal - run_save_as detects the prefix form after the fact -
# but getting it right is what makes Save As available at all.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.PDFUtil.args.sh"

# --- handler-local functions ---------------------------------------------
# Settings validation and the structure pre-flight
#
# These live here rather than in a shared lib because this handler is their
# only caller. A shared lib is for logic several handlers use; a single-use
# function in it just makes the lib bigger and its readers guess who calls it.
#
# The markers around this block are load-bearing: the unit-test harness pulls
# the definitions out with them so it can call these directly, without running
# the handler body below.
# ---------------------------------------------------------------------------
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
# frompages is in the set as of Stage 8, but only its PDF inputs are at risk.
#
# Arguments: operation tag
operation_redraws() {
    case "$1" in
        reduce | linearize | pdfa)
            return 0
            ;;
        frompages)
            # Only its PDF inputs are at risk - images have no structure to
            # lose - but the loop below only ever asks this about PDFs, so the
            # generic pre-flight covers it without a special case.
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

# Echo why the list's file types do not suit the operation, or "" when they do.
#
# Build PDF from Images is the only operation that reads pictures; every other
# one reads PDFs. A file that is neither (classify_file's "other") is wrong for
# both, and is called out separately because "not a PDF" and "not an image"
# would each be a misleading description of, say, a .docx.
#
# Arguments: operation, total, pdf count, image count, other count, first other name
input_type_problem() {
    local op="$1" total="$2" pdfs="$3" images="$4" others="$5" other_name="$6"

    if [ "$op" = "frompages" ]; then
        if [ "$others" -gt 0 ]; then
            local other_verb="are"
            [ "$others" -eq 1 ] && other_verb="is"
            echo "Build PDF from Images cannot read \"${other_name}\"; ${others} of ${total} items ${other_verb} neither images nor PDFs.

Remove them from the list and try again."
            return
        fi
        if [ "$images" -eq 0 ]; then
            # PDFs alone are legal to pdfutil, but that is Merge's job and it
            # keeps the structure this operation would redraw away.
            echo "Build PDF from Images needs at least one image in the list.

To combine PDFs into one document, use Merge instead - it keeps annotations, links, the outline and form fields."
            return
        fi
        return
    fi

    local wrong=$((images + others))
    [ "$wrong" -eq 0 ] && return

    # "1 of 3 items are images" reads as a typo, and these messages are the
    # user's only explanation of why the run stopped.
    local what img_verb="are" oth_verb="are"
    [ "$images" -eq 1 ] && img_verb="is"
    [ "$others" -eq 1 ] && oth_verb="is"
    if [ "$others" -eq 0 ]; then
        what="${images} of ${total} items in the list ${img_verb} images"
    elif [ "$images" -eq 0 ]; then
        what="${others} of ${total} items in the list ${oth_verb} not PDFs, starting with \"${other_name}\""
    else
        what="${images} of ${total} items in the list ${img_verb} images and ${others} more ${oth_verb} neither PDFs nor images"
    fi

    echo "$(operation_label "$op") needs PDF files; ${what}.

Remove them from the list and try again."
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
        metadata)
            # A run with nothing set and nothing stripped would rewrite every
            # file to change nothing - and not even nothing, since PDFKit resets
            # Producer and both dates on save. Refusing is the honest answer.
            if [ "$OMC_ACTIONUI_VIEW_195_VALUE" != "true" ] \
               && [ -z "$(trim_spaces "$OMC_ACTIONUI_VIEW_190_VALUE")" ] \
               && [ -z "$(trim_spaces "$OMC_ACTIONUI_VIEW_191_VALUE")" ] \
               && [ -z "$(trim_spaces "$OMC_ACTIONUI_VIEW_192_VALUE")" ] \
               && [ -z "$(trim_spaces "$OMC_ACTIONUI_VIEW_193_VALUE")" ] \
               && [ -z "$(trim_spaces "$OMC_ACTIONUI_VIEW_194_VALUE")" ]; then
                echo "Fill in at least one attribute, or switch on \"Remove all metadata\".

A blank field leaves that attribute as it is; it does not clear it."
            fi
            ;;
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

# --- end handler-local functions -----------------------------------------

operation="$(current_operation)"
all_paths="$OMC_ACTIONUI_TABLE_10_COLUMN_3_ALL_ROWS"

if [ -z "$all_paths" ]; then
    "$alert_tool" --level caution --title "PDFUtil" \
        "Add at least one file to the list first."
    exit 0
fi

# Settings the run cannot proceed with - mismatched password confirmations, an
# empty page range, a malformed crop rectangle. Checked before the per-file
# pre-flight because it is instant and needs no disk access, and before any
# destination dialog because the alternative is asking the user to name an
# output file for a run that was never going to start.
#
# It also has to come before the not-implemented check below, and that ordering
# is load-bearing rather than incidental: build_pdfutil_args refuses a settings
# combination it cannot express (Edit Metadata with every field blank), and that
# refusal is indistinguishable from "this operation does not exist yet". Asking
# it first would answer an empty metadata form with "Edit Metadata is not
# available yet. ... use QuickPDF if it offers this one" - pointing the user at
# another app for a feature that is right there and merely needs a value.
settings_issue="$(settings_problem "$operation")"
if [ -n "$settings_issue" ]; then
    "$alert_tool" --level caution --title "PDFUtil" "$settings_issue"
    set_summary "$(operation_label "$operation") did not run.
${settings_issue}"
    exit 0
fi

# build_pdfutil_args is what knows which operations exist; asking it keeps the
# router from carrying a second list that could drift out of step.
if ! build_pdfutil_args "$operation"; then
    # Deliberately not a list of what does work: that sentence went stale on
    # every stage that landed, and build_pdfutil_args is already the
    # authoritative record of which operations have been built.
    "$alert_tool" --level caution --title "PDFUtil" \
        "$(operation_label "$operation") is not available yet.

Pick another operation, or use QuickPDF if it offers this one."
    exit 0
fi

# The pre-flight below spawns `file` and `pdfutil info` per entry, about 100 ms
# a file. That is invisible for a handful and a silent several-second pause for
# a big list, so say what is happening first.
if [ "$(printf '%s\n' "$all_paths" | /usr/bin/grep -c .)" -gt 2 ]; then
    set_summary "Checking the file list..."
fi

file_count=0
pdf_count=0
image_count=0
other_count=0
other_name=""
locked_count=0
locked_name=""
first_file=""
risk_count=0
risk_name=""
risk_kind=""

# Only pay for the structure check when the answer could change anything. For
# every other operation the loop below does exactly what it did before.
redraws=0
if operation_redraws "$operation"; then
    redraws=1
fi

while IFS= read -r file_path; do
    [ -z "$file_path" ] && continue
    file_count=$((file_count + 1))
    [ -z "$first_file" ] && first_file="$file_path"
    # Counted by type rather than pdf/not-pdf: with images now legal inputs the
    # message has to name what the wrong items actually are, and "3 items are
    # images" is actionable in a way "3 items are not PDFs" is not.
    file_kind="$(classify_file "$file_path")"
    case "$file_kind" in
        pdf)   pdf_count=$((pdf_count + 1)) ;;
        image) image_count=$((image_count + 1)) ;;
        *)
            other_count=$((other_count + 1))
            [ -z "$other_name" ] && other_name="$(/usr/bin/basename "$file_path")"
            ;;
    esac

    # The password and structure checks only mean anything for a PDF.
    if [ "$file_kind" = "pdf" ]; then
        if [ "$operation" != "decrypt" ] && pdf_is_locked "$file_path"; then
            # Remove Password is exempt: a locked file is precisely its input,
            # and the test is skipped rather than counted-and-ignored so it does
            # not pay for an `info` call per file it already knows the answer for.
            locked_count=$((locked_count + 1))
            [ -z "$locked_name" ] && locked_name="$(/usr/bin/basename "$file_path")"
        elif [ "$redraws" = "1" ]; then
            # Free: the guard above just ran `info` on this file and cached it,
            # so this reads that output rather than parsing the document again.
            file_risk="$(pdf_structure_at_risk "$file_path")"
            if [ -n "$file_risk" ]; then
                risk_count=$((risk_count + 1))
                if [ -z "$risk_name" ]; then
                    risk_name="$(/usr/bin/basename "$file_path")"
                    risk_kind="$file_risk"
                fi
            fi
        fi
    fi
done <<< "$all_paths"

if [ "$file_count" -eq 0 ]; then
    "$alert_tool" --level caution --title "PDFUtil" \
        "Add at least one file to the list first."
    exit 0
fi

# The list can hold PDFs and images, so which one is wrong depends on the
# operation: Build PDF from Images is the only one that reads pictures, and
# every other one reads PDFs. Naming the mismatch here beats letting pdfutil
# fail once per file with a message about a format the user never chose.
input_issue="$(input_type_problem "$operation" "$file_count" "$pdf_count" \
                                  "$image_count" "$other_count" "$other_name")"
if [ -n "$input_issue" ]; then
    set_summary "$(operation_label "$operation") did not run.
${input_issue}"
    "$alert_tool" --level caution --title "PDFUtil" "${input_issue}"
    exit 0
fi

# Password-protected PDFs are out of scope for everything except Remove
# Password. Stopping here, before any destination has been chosen, is the whole
# point: the alternative is a batch that prompts for a folder, runs, and then
# reports a row of identical failures the user cannot act on from that screen.
#
# Remove Password is exempt, in the loop above. Set Password is NOT: encrypting
# an already-protected file means opening it first, and this operation has no
# field for the password it is already carrying.
if [ "$locked_count" -gt 0 ]; then
    if [ "$locked_count" -eq 1 ]; then
        locked_desc="\"${locked_name}\" is password-protected"
    elif [ "$locked_count" -eq "$file_count" ]; then
        locked_desc="all ${file_count} files are password-protected"
    else
        locked_desc="${locked_count} of the ${file_count} files are password-protected, starting with \"${locked_name}\""
    fi
    set_summary "$(operation_label "$operation") cannot read protected PDFs.
${locked_desc}.

Use Remove Password on them first."
    "$alert_tool" --level caution --title "PDFUtil" \
        "$(operation_label "$operation") cannot read protected PDFs: ${locked_desc}.

Use Remove Password on them first, then run $(operation_label "$operation") on the unlocked copies."
    exit 0
fi

# Structure pre-flight. pdfutil is silent about degraded output - a reduce that
# dropped the outline still exits 0 - so nothing downstream can report this. The
# section notice already says the operation redraws, but a notice is read once
# and this is about THESE files, which the notice cannot know about.
#
# It is a question, not a refusal: redrawing is often exactly what the user
# wants, and the only thing missing was the knowledge that this particular
# document had something to lose. Cancel is the default-safe answer but
# Continue is a legitimate one, so both are offered.
if [ "$risk_count" -gt 0 ]; then
    if [ "$risk_count" -eq 1 ]; then
        risk_desc="\"${risk_name}\" has $(structure_risk_phrase "$risk_kind")"
    elif [ "$risk_count" -eq "$file_count" ]; then
        # The files can differ in what each one carries, so the summary phrase
        # covers the union rather than claiming they all match the first.
        risk_desc="all ${file_count} files have an outline, annotations or form fields"
    else
        risk_desc="${risk_count} of the ${file_count} files have an outline, annotations or form fields, starting with \"${risk_name}\""
    fi

    "$alert_tool" --level caution --title "PDFUtil" \
        --ok "Continue" --cancel "Cancel" \
        "$(operation_label "$operation") redraws the page content, so annotations, links, the outline and form fields are not carried over.

Right now ${risk_desc}.

Continue anyway?"
    alert_rc=$?
    if [ "$alert_rc" -ne 0 ]; then
        set_summary "Cancelled.
$(operation_label "$operation") would have discarded structure in ${risk_count} of ${file_count} file(s)."
        exit 0
    fi
fi

case "$PDFUTIL_OUTPUT_KIND" in
    pdf)
        if [ "$file_count" -eq 1 ]; then
            "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "PDFUtil.run.single"
        else
            "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "PDFUtil.run.batch"
        fi
        ;;

    text)
        if [ "$file_count" -eq 1 ]; then
            "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "PDFUtil.run.text"
        else
            "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "PDFUtil.run.batch"
        fi
        ;;

    parts)
        # Split turns one input into a numbered series, so there is no single
        # name a Save panel could confirm however short the list is.
        "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "PDFUtil.run.batch"
        ;;

    assembled)
        # The other many-to-one shape: images in, one PDF out. Unlike merge a
        # single input is legal - one photo is a one-page PDF - so there is no
        # minimum here beyond the "at least one image" the type check above
        # already enforced.
        "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "PDFUtil.run.assemble"
        ;;

    merged)
        # N inputs, one output - the only many-to-one operation, and the only
        # one whose Save As panel appears with more than one file in the list.
        if [ "$file_count" -lt 2 ]; then
            "$alert_tool" --level caution --title "PDFUtil" \
                "Merge needs at least two files in the list.

Add the other PDFs, in the order they should appear in the merged document."
            set_summary "Merge needs at least two files in the list."
            exit 0
        fi
        "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "PDFUtil.run.merge"
        ;;

    images)
        selected_pages=""
        if [ "$file_count" -eq 1 ]; then
            selected_pages="$(range_page_count "$OMC_ACTIONUI_VIEW_174_VALUE" \
                              "$(pdf_page_count "$first_file")")"
        fi
        if [ "$selected_pages" = "1" ]; then
            "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "PDFUtil.run.image"
        else
            "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "PDFUtil.run.batch"
        fi
        ;;

    *)
        "$alert_tool" --level caution --title "PDFUtil" \
            "Internal error: $(operation_label "$operation") has no output kind."
        ;;
esac
