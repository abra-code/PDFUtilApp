#!/bin/sh
# Tests/50-library.test.sh - the library functions the handlers are built from.
#
# The other files dispatch handlers and read the window. This one calls into the
# lib.PDFUtil.* libraries directly, because most of what they decide is not
# observable from outside: which flags an operation produces, which flags it
# must never produce together, what a junk control value gets clamped to, and
# what the pre-flight would have found.
#
# These assertions used to live in ./test.sh, driven by Tests/harness.sh. They
# moved here when that suite was narrowed to the embedded pdfutil binary, and
# they are stronger for it - omctest starts every section from the control
# defaults declared in PDFUtil.json rather than from a hand-built environment,
# so what the builder sees is what a user's window holds.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.pdfutil.sh"

section "preconditions"
check_preconditions

text_pdf="$(fixture text.pdf)"
image_pdf="$(fixture image.pdf)"
outline_pdf="$(fixture outline.pdf)"
form_pdf="$(fixture form.pdf)"
locked_pdf="$(fixture locked.pdf)"
restricted_pdf="$(fixture restricted.pdf)"
photo_png="$(fixture photo.png)"
notes_txt="$(fixture notes.txt)"
mislabeled_pdf="$(fixture mislabeled.pdf)"

# No trailer of ui_unknown_writes / ui_suspect_writes checks in this file, on
# purpose: nothing here dispatches a handler, so those answers would be empty by
# construction, which is the definition of a check that cannot fail.

# Give an operation the one value it legitimately refuses to run without, so a
# check about something else does not measure a refusal instead.
configure_operation() { # <operation>
    case "$1" in
        extract)  omc_control "$EXT_RANGE_ID" "1-2" ;;
        delete)   omc_control "$DEL_RANGE_ID" "2" ;;
        crop)     omc_control "$CROP_VALUES_ID" "36,36,36,36" ;;
        encrypt)  omc_control "$ENC_USER_PW_ID" "pw"
                  omc_control "$ENC_USER_PW_CONFIRM_ID" "pw" ;;
        decrypt)  omc_control "$DEC_PASSWORD_ID" "pw" ;;
        metadata) omc_control "$META_TITLE_ID" "A Title" ;;
        watermark) omc_control "$WM_TEXT_ID" "DRAFT" ;;
    esac
}

# --------------------------------------------------------------------------
section "every operation the window offers builds a command line"
# --------------------------------------------------------------------------
# Walked from the picker rather than a list retyped here, so an operation added
# to the UI and forgotten in the builder shows up as a refusal.
_ops="$(operation_tags)"
check "the picker's operations were read" "yes" \
    "$([ -n "$_ops" ] && echo yes || echo no)"

_refused="" _no_verb="" _no_kind=""
for _op in $_ops; do
    reset_document
    configure_operation "$_op"
    if [ "$(pdfutil_builds "$_op")" != yes ]; then
        _refused="${_refused:+$_refused }$_op"
        continue
    fi
    [ -n "$(pdfutil_verb_for "$_op")" ] || _no_verb="${_no_verb:+$_no_verb }$_op"
    [ -n "$(pdfutil_kind_for "$_op")" ] || _no_kind="${_no_kind:+$_no_kind }$_op"
done
check "none of them is refused when configured" "" "$_refused"
check "each produces a pdfutil verb"            "" "$_no_verb"
check "each declares an output kind"            "" "$_no_kind"

# --------------------------------------------------------------------------
section "the builder never names its own output"
# --------------------------------------------------------------------------
# The highest-stakes invariant in the applet. Most pdfutil verbs edit the input
# IN PLACE without -o, and the runners stage through mktemp, which pre-creates
# the destination and so needs --force. Neither flag is the builder's to emit:
# both are added at the single call site in _exec_pdfutil. A builder that
# emitted its own -o would have the runner append a second one, and the user's
# file would be written somewhere they never asked for.
_own_output="" _own_force=""
for _op in $_ops; do
    reset_document
    configure_operation "$_op"
    [ "$(pdfutil_has_arg "$_op" -o)" = no ] || _own_output="${_own_output:+$_own_output }$_op"
    [ "$(pdfutil_has_arg "$_op" --force)" = no ] || _own_force="${_own_force:+$_own_force }$_op"
done
check "no operation emits its own -o"      "" "$_own_output"
check "no operation emits its own --force" "" "$_own_force"

# ...and the one place that does emit them still does. This is a source check
# because the flags are added positionally rather than through anything a test
# can call: there is no build step to interrogate.
_exec_body="$(/usr/bin/awk '/^_exec_pdfutil\(\) \{/,/^\}/' \
    "$APP_SCRIPTS/lib.PDFUtil.run.sh")"
check "the single call site was found" "yes" \
    "$([ -n "$_exec_body" ] && echo yes || echo no)"
check "and it still passes --force"    "yes" "$(contains "$_exec_body" '--force')"
check "and it still passes -o"         "yes" "$(contains "$_exec_body" '-o "$2"')"

# The backstop for the whole in-place hazard: asked to run with no output path
# at all, the runner refuses rather than letting pdfutil edit the input.
#
# Run from inside a throwaway directory, and that is not tidiness. If the guard
# below ever regresses, this call reaches the binary with -o "" - which resolves
# to the process's CURRENT DIRECTORY, and --force then unlinks it. pdfutil
# replaces the directory with a PDF file and exits 0. A test file's own shell
# keeps the directory the suite was launched from, normally the repo root, so
# the unguarded version of this check would delete the repository at exactly the
# moment it was supposed to report the regression. Verified against the real
# binary: a directory containing a file became an 18 KB PDF.
reset_document
_sacrificial="$OMCTEST_WORK/empty-output-probe"
/bin/mkdir -p "$_sacrificial"
export OMCTEST_PU_CWD="$_sacrificial" OMCTEST_PU_IN="$text_pdf"
_refusal="$(pdfutil_eval 'cd "$OMCTEST_PU_CWD" || exit 1
    build_pdfutil_args reduce >/dev/null 2>&1
    run_pdfutil "$OMCTEST_PU_IN" "" 2>&1
    printf "|%s" "$?"')"
check "running with no output path fails"   "yes" "$(contains "$_refusal" "|1")"
check "and says why"                        "yes" \
    "$(contains "$_refusal" "refusing to run pdfutil without an output path")"
# The consequence, asserted rather than merely avoided: nothing reached the
# binary, so the directory the call ran in is still a directory. This is what
# turns the hazard above into a reported failure instead of a deleted tree.
check "and the working directory survived" "yes" \
    "$([ -d "$_sacrificial" ] && echo yes || echo no)"

# --------------------------------------------------------------------------
section "flag combinations pdfutil refuses are never built"
# --------------------------------------------------------------------------
# Each pair below is a combination the binary rejects with a usage error. The UI
# makes them unreachable; the builder is the last line of defense, because a
# control keeps its value after a mode toggle moves away from it.

# Convert to Grayscale is its own operation, not a mode of Reduce. pdfutil
# refuses --gray alongside -q/-r/-m, so whatever the Reduce controls happen to
# hold, the grayscale run must send --gray and nothing else.
reset_document
omc_control "$RED_QUALITY_ID" 85
omc_control "$RED_DOWNSAMPLE_ID" true
omc_control "$RED_DPI_ID" 150
omc_control "$RED_MAXEDGE_ON_ID" true
omc_control "$RED_MAXEDGE_PX_ID" 2000
check "grayscale sends --gray" "yes" "$(pdfutil_has_arg gray --gray)"
_leaked=""
for _flag in -q -r -m; do
    [ "$(pdfutil_has_arg gray "$_flag")" = no ] || _leaked="${_leaked:+$_leaked }$_flag"
done
check "and none of the reduce flags with it" "" "$_leaked"

# ...and Reduce never sends --gray, whatever it is handed.
reset_document
check "reduce never sends --gray" "no" "$(pdfutil_has_arg reduce --gray)"
# Both run the same verb, so the router cannot tell them apart by verb alone.
check "grayscale runs the reduce verb" "reduce" "$(pdfutil_verb_for gray)"

# --------------------------------------------------------------------------
section "an unchecked box in Reduce means off, not the engine's default"
# --------------------------------------------------------------------------
# Both -r and -m have a non-zero DEFAULT in pdfutil - 150 DPI and 2400 pixels -
# so omitting either when its toggle is off does not disable it, it silently
# applies the engine's value. The user unchecks a box and the thing still
# happens. Both flags are therefore passed explicitly in both states, with 0
# meaning "no ceiling" and "no cap".
#
# This is asserted on the VALUE, not on the flag's presence: the bug this
# guards against ships a build where the flag is absent, and a presence check
# would have to be spelled as an absence check, which passes just as well when
# the whole operation stops emitting arguments.
reset_document
omc_control "$RED_DOWNSAMPLE_ID" false
check "downsampling off sends -r 0, not silence" "0" "$(pdfutil_arg_after reduce -r)"

reset_document
omc_control "$RED_MAXEDGE_ON_ID" false
check "edge cap off sends -m 0, not silence" "0" "$(pdfutil_arg_after reduce -m)"

# The on states, so the checks above cannot pass by the builder emitting 0 for
# everything - which is the failure they would otherwise be blind to.
reset_document
omc_control "$RED_DOWNSAMPLE_ID" true
omc_control "$RED_DPI_ID" 150
check "downsampling on sends its DPI" "150" "$(pdfutil_arg_after reduce -r)"

reset_document
omc_control "$RED_MAXEDGE_ON_ID" true
omc_control "$RED_MAXEDGE_PX_ID" 2000
check "edge cap on sends its pixel count" "2000" "$(pdfutil_arg_after reduce -m)"

# --------------------------------------------------------------------------
section "an UNSET box in Reduce means its declared isOn, which is not always off"
# --------------------------------------------------------------------------
# Neither of the two states above, and the one that shipped broken. OMC exports
# a Toggle's value once it has a value to report; until then
# the variable is absent, and absent means the toggle's declared isOn - not off.
# reset_document seeds every control from the JSON defaults, so nothing else in
# this suite ever sees a control the way a freshly opened window does, which is
# exactly how a first Reduce run came to send -r 0 while the panel displayed a
# checked box at 150.
#
# The two toggles need opposite spellings and only one of them is forgiving:
# 78 declares isOn: false, so `= "true"` reads unset correctly by luck, while 76
# declares isOn: true and must be tested as `!= "false"`. Both are asserted here
# so a future edit that unifies them on the wrong spelling fails.
# 200, not the 150 this field defaults to: clamp_dpi falls back to 150 when the
# field's value is missing, so asserting 150 here would pass whether the field
# was read or thrown away. A non-default value makes the check prove both that
# the toggle was read as on AND that the DPI the user typed is what gets sent.
reset_document
unset "OMC_ACTIONUI_VIEW_${RED_DOWNSAMPLE_ID}_VALUE"
omc_control "$RED_DPI_ID" 200
check "an unset downsample toggle is on, its declared state" "200" "$(pdfutil_arg_after reduce -r)"

reset_document
unset "OMC_ACTIONUI_VIEW_${RED_MAXEDGE_ON_ID}_VALUE"
check "an unset edge-cap toggle is off, its declared state" "0" "$(pdfutil_arg_after reduce -m)"

# OCR: --searchable covers the whole document and picks its own parameters.
reset_document
omc_control "$OCR_SEARCHABLE_ID" true
omc_control "$OCR_RANGE_ID" "1-2"
omc_control "$OCR_LANG_ID" "en-US"
omc_control "$OCR_FAST_ID" true
check "searchable OCR sends --searchable" "yes" "$(pdfutil_has_arg ocr --searchable)"
_leaked=""
for _flag in -p --lang --fast --dpi; do
    [ "$(pdfutil_has_arg ocr "$_flag")" = no ] || _leaked="${_leaked:+$_leaked }$_flag"
done
check "and none of the per-page flags with it" "" "$_leaked"

# Watermark: --annotation is text-only and cannot be rotated or placed under.
reset_document
omc_control "$WM_ANNOTATION_ID" true
omc_control "$WM_TEXT_ID" "DRAFT"
omc_control "$WM_IMAGE_ID" "/tmp/mark.png"
omc_control "$WM_ROTATION_ID" 45
omc_control "$WM_UNDER_ID" true
check "an annotation watermark sends --annotation" "yes" \
    "$(pdfutil_has_arg watermark --annotation)"
_leaked=""
for _flag in --image --rotate-mark --under; do
    [ "$(pdfutil_has_arg watermark "$_flag")" = no ] || _leaked="${_leaked:+$_leaked }$_flag"
done
check "and none of the burn-in flags with it" "" "$_leaked"

# frompages: --page-size and --dpi both decide the page geometry, so only one of
# them may ever appear.
_both=""
for _mode in fit image dpi ""; do
    reset_document
    omc_control "$ASSEMBLE_MODE_ID" "$_mode"
    omc_control "$FP_DPI_ID" 300
    if [ "$(pdfutil_has_arg frompages --page-size)" = yes ] \
        && [ "$(pdfutil_has_arg frompages --dpi)" = yes ]; then
        _both="${_both:+$_both }${_mode:-untouched}"
    fi
done
check "no assemble mode sends both --page-size and --dpi" "" "$_both"

# --------------------------------------------------------------------------
section "junk in a control never reaches the binary as a usage error"
# --------------------------------------------------------------------------
# A control can hold anything: a stale value from before a toggle moved, or text
# the user typed. What must not happen is that it arrives at pdfutil as a usage
# error the user cannot connect to anything they did.
reset_document
omc_control "$RED_QUALITY_ID" "not a number"
check "junk quality falls back to the default" "yes" \
    "$(contains "$(pdfutil_args_for reduce)" "-q 85")"

reset_document
omc_control "$RED_QUALITY_ID" 9999
check "over-range quality is clamped" "yes" \
    "$(contains "$(pdfutil_args_for reduce)" "-q 100")"

reset_document
omc_control "$ROT_ANGLE_ID" "banana"
# An exact element, not a substring of the joined list. "90" as a substring is
# also found in "190" and "290", and pdfutil refuses anything that is not one of
# 90/180/270/-90 - so the substring form stayed green for a fallback that had
# become a usage error, which is the exact bug the check is named after.
check "junk rotation falls back to 90" "yes" "$(pdfutil_has_arg rotate 90)"

# A picker delivers its option's TAG. If a label ever arrives instead - which is
# what a mis-declared option produces - the builder must not pass it through.
reset_document
omc_control "$ASSEMBLE_MODE_ID" fit
omc_control "$FP_PAGE_SIZE_ID" "A4"
check "a picker label rather than a tag falls back to letter" "yes" \
    "$(contains "$(pdfutil_args_for frompages)" "--page-size letter")"

# --------------------------------------------------------------------------
section "each operation declares the output kind its runner needs"
# --------------------------------------------------------------------------
# Routing keys off the KIND, not the operation: a PDF goes to a Save As dialog,
# images to a folder chooser, a report to an output window. Sending an operation
# to the wrong one asks the user to name a file that will never be written.
_wrong_kind=""
expect_kind() { # <operation> <kind>
    reset_document
    configure_operation "$1"
    [ "$(pdfutil_kind_for "$1")" = "$2" ] \
        || _wrong_kind="${_wrong_kind:+$_wrong_kind }$1:$(pdfutil_kind_for "$1")!=$2"
}
for _op in reduce gray linearize pdfa extract delete rotate crop watermark \
           flatten metadata encrypt decrypt; do
    expect_kind "$_op" pdf
done
expect_kind render    images
expect_kind text      text
expect_kind merge     merged
expect_kind frompages assembled
expect_kind split     parts
check "every operation declares the kind its runner expects" "" "$_wrong_kind"

# OCR changes its kind with the mode, which is the whole reason routing keys off
# the kind rather than the operation name.
reset_document
check "OCR produces text by default" "text" "$(pdfutil_kind_for ocr)"
reset_document
omc_control "$OCR_SEARCHABLE_ID" true
check "searchable OCR produces a PDF instead" "pdf" "$(pdfutil_kind_for ocr)"

# An operation nobody has built must be reported as missing rather than routed.
reset_document
check "an operation that does not exist is refused" "no" \
    "$(pdfutil_builds nosuchoperation)"

# --------------------------------------------------------------------------
section "classify_file decides what each list entry is"
# --------------------------------------------------------------------------
# The answer drives per-operation validation: PDFs for nearly everything, images
# for Build PDF from Images, and "other" for anything else. Getting it wrong
# hands pdfutil a file it rejects in words that describe the file rather than
# the choice the user made.
check "a real PDF"                    "pdf"   "$(pdfutil_call classify_file "$text_pdf")"
check "an image-only PDF is still one" "pdf"   "$(pdfutil_call classify_file "$image_pdf")"
check "an encrypted PDF is still one"  "pdf"   "$(pdfutil_call classify_file "$locked_pdf")"
check "a PNG"                          "image" "$(pdfutil_call classify_file "$photo_png")"
check "a text file is neither"         "other" "$(pdfutil_call classify_file "$notes_txt")"
# The header decides, not the extension, or the run fails inside pdfutil instead
# of in validation.
check "a text file named .pdf"         "other" "$(pdfutil_call classify_file "$mislabeled_pdf")"

# A path that does not exist has to classify as SOMETHING. Returning nothing
# makes the caller's arithmetic collapse rather than producing a clean refusal.
check "a missing file still classifies as something" "yes" \
    "$([ -n "$(pdfutil_call classify_file "$OMCTEST_WORK/nope.pdf")" ] && echo yes || echo no)"

# Paths with spaces are the normal case in a real file list, not an edge case.
_spaced="$OMCTEST_WORK/a file with spaces.pdf"
/bin/cp "$text_pdf" "$_spaced"
check "a path containing spaces" "pdf" "$(pdfutil_call classify_file "$_spaced")"

# --------------------------------------------------------------------------
section "output naming, including the literal-path trap"
# --------------------------------------------------------------------------
# render has two output modes and only one of them is a file. With one page
# selected, -o is a LITERAL PATH and pdfutil appends nothing, so the app has to
# supply the extension itself - and jpeg is the odd one out, producing .jpg.
check "png suffix"   ".png"  "$(pdfutil_call render_suffix png)"
check "jpeg produces .jpg, not .jpeg" ".jpg" "$(pdfutil_call render_suffix jpeg)"
check "tiff suffix"  ".tiff" "$(pdfutil_call render_suffix tiff)"
check "heic suffix"  ".heic" "$(pdfutil_call render_suffix heic)"
check "an unknown format falls back to png" ".png" "$(pdfutil_call render_suffix nonsense)"

ext_for() { # <output-kind> <path>
    export OMCTEST_PU_KIND="$1" OMCTEST_PU_PATH="$2"
    pdfutil_eval 'PDFUTIL_OUTPUT_KIND="$OMCTEST_PU_KIND"
        ensure_output_extension "$OMCTEST_PU_PATH"'
}
check "a .pdf name is left alone" "$OMCTEST_WORK/x.pdf" "$(ext_for pdf "$OMCTEST_WORK/x.pdf")"
check "an uppercase .PDF counts too" "$OMCTEST_WORK/X.PDF" "$(ext_for pdf "$OMCTEST_WORK/X.PDF")"
check "a pdf output with no extension gains one" "yes" \
    "$(contains "$(ext_for pdf "$OMCTEST_WORK/noext")" ".pdf")"
# merged and assembled are PDFs too. Omitting them wrote a valid PDF with no
# suffix whenever the user typed over the Save panel's default name.
for _kind in merged assembled; do
    check "output kind '$_kind' gains .pdf" "yes" \
        "$(contains "$(ext_for "$_kind" "$OMCTEST_WORK/typed-over")" ".pdf")"
done
check "a text output gains .txt" "yes" \
    "$(contains "$(ext_for text "$OMCTEST_WORK/notes")" ".txt")"

# Images take their suffix from the format picker, so the answer changes with a
# control rather than being fixed per kind.
reset_document
omc_control "$RND_FORMAT_ID" jpeg
check "a jpeg render produces .jpg" "yes" \
    "$(contains "$(ext_for images "$OMCTEST_WORK/pic")" ".jpg")"
omc_control "$RND_FORMAT_ID" png
check "a png render produces .png" "yes" \
    "$(contains "$(ext_for images "$OMCTEST_WORK/pic")" ".png")"
# The stem's existing image extension is REPLACED, not appended to, or a name
# typed as "Page.png" for a jpeg render becomes "Page.png.jpg".
omc_control "$RND_FORMAT_ID" jpeg
check "an image extension is not doubled" "no" \
    "$(contains "$(ext_for images "$OMCTEST_WORK/Page.png")" ".png.jpg")"

# unique_path never hands back a name that already exists. The Save panel
# confirmed an overwrite for the name the user SAW; once the app changes that
# name, the confirmation no longer covers it.
: > "$OMCTEST_WORK/taken.pdf"
_unique="$(pdfutil_call unique_path "$OMCTEST_WORK/taken.pdf")"
check "a taken path is not handed back" "no" \
    "$([ "$_unique" = "$OMCTEST_WORK/taken.pdf" ] && echo yes || echo no)"
check "and neither is another existing one" "no" \
    "$([ -e "$_unique" ] && echo yes || echo no)"
check "an unused path is returned unchanged" "$OMCTEST_WORK/free.pdf" \
    "$(pdfutil_call unique_path "$OMCTEST_WORK/free.pdf")"

# --------------------------------------------------------------------------
section "which operations redraw, and what that costs the document"
# --------------------------------------------------------------------------
# Several operations reach their result by REDRAWING the page content, which
# discards annotations, links, the outline and form fields. The pre-flight only
# fires when THIS document actually has something to lose; a warning that fires
# on every file is one people learn to dismiss.
redraws() { # <operation> -> yes | no
    reset_document
    omc_control "$OPERATION_PICKER_ID" "$1"
    pdfutil_handler_call PDFUtil.start.batch.sh operation_redraws "$1" \
        && echo yes || echo no
}

_missing_from_set=""
for _op in reduce gray linearize pdfa frompages; do
    [ "$(redraws "$_op")" = yes ] || _missing_from_set="${_missing_from_set:+$_missing_from_set }$_op"
done
check "every redrawing operation is in the redraw set" "" "$_missing_from_set"

_wrongly_in_set=""
for _op in extract delete rotate crop merge metadata decrypt encrypt text render; do
    [ "$(redraws "$_op")" = no ] || _wrongly_in_set="${_wrongly_in_set:+$_wrongly_in_set }$_op"
done
check "and nothing else is" "" "$_wrongly_in_set"

# flatten is deliberately absent: removing the fields is what the user asked
# for, so warning about it would be warning that the operation worked.
check "flatten does not warn - removing fields is the point" "no" "$(redraws flatten)"

# Watermark is the one that depends on a control rather than the operation.
reset_document
omc_control "$OPERATION_PICKER_ID" watermark
check "a burn-in watermark redraws" "yes" \
    "$(pdfutil_handler_call PDFUtil.start.batch.sh operation_redraws watermark \
        && echo yes || echo no)"
omc_control "$WM_ANNOTATION_ID" true
check "an annotation watermark does not" "no" \
    "$(pdfutil_handler_call PDFUtil.start.batch.sh operation_redraws watermark \
        && echo yes || echo no)"

# --- what a given document actually has to lose ----------------------------
# It ECHOES what it found rather than returning a status, so these are string
# assertions. `info` counts form fields as annotations and cannot separate them,
# which is why the wording never claims to know which it found.
at_risk() { pdfutil_handler_call PDFUtil.start.batch.sh pdf_structure_at_risk "$1"; }
check "a plain document has nothing at risk" "" "$(at_risk "$text_pdf")"
check "an outline is at risk" "yes" "$(contains "$(at_risk "$outline_pdf")" "outline")"
check "form fields are reported as annotations" "yes" \
    "$(contains "$(at_risk "$form_pdf")" "annotations")"
# A guard should not block work over a question it could not answer.
check "an unreadable file does not trip the pre-flight" "" "$(at_risk "$notes_txt")"

# The phrase takes what was FOUND, not a path, and has to name it or the user
# cannot judge whether they care.
phrase_for() { pdfutil_handler_call PDFUtil.start.batch.sh structure_risk_phrase "$1"; }
check "the phrase names the outline" "yes" \
    "$(contains "$(phrase_for "$(at_risk "$outline_pdf")")" "outline")"
# Every input yields SOME phrase, including one the case table does not know:
# the caller only reaches it when something was found, so the catch-all keeps an
# unexpected value from rendering as 'report.pdf has .'
_empty_phrase=""
for _found in "outline annotations" "outline" "annotations" "" "something new"; do
    [ -n "$(phrase_for "$_found")" ] \
        || _empty_phrase="${_empty_phrase:+$_empty_phrase }[$_found]"
done
check "and no input leaves the sentence unfinished" "" "$_empty_phrase"

# --------------------------------------------------------------------------
section "the permanent notices under each settings panel"
# --------------------------------------------------------------------------
# The pre-flight is conditional; the notice is not. An operation that silently
# discards structure with no notice is the exact hazard this design exists for.
notice_for() { pdfutil_call structure_notice "$1"; }

_no_notice=""
for _op in reduce gray linearize pdfa frompages watermark flatten; do
    [ -n "$(notice_for "$_op")" ] || _no_notice="${_no_notice:+$_no_notice }$_op"
done
check "every redrawing operation carries a notice" "" "$_no_notice"

# The ones that discard structure say so in those words. frompages is excluded:
# only its PDF inputs are at risk, and its notice says "redrawn" and points at
# Merge, which is the actionable form of the same fact.
_silent=""
for _op in reduce gray linearize pdfa watermark flatten; do
    [ "$(contains "$(notice_for "$_op")" "outline")" = yes ] \
        || _silent="${_silent:+$_silent }$_op"
done
check "and says what it discards" "" "$_silent"
check "the assemble notice says PDF inputs are redrawn" "yes" \
    "$(contains "$(notice_for frompages)" "redrawn")"

# Succinct is a requirement, not a preference: these sit under a settings panel,
# and a notice nobody finishes reading is not a notice.
_too_long=""
for _op in $_ops; do
    _n="$(notice_for "$_op")"
    [ ${#_n} -le 160 ] || _too_long="${_too_long:+$_too_long }$_op:${#_n}"
done
check "no notice is too long to be read" "" "$_too_long"

# Two of them must steer, not merely warn.
check "the linearize notice points at the tool with the better hint table" "yes" \
    "$(contains "$(notice_for linearize)" "QuickPDF")"
check "the PDF/A notice says conformance is unverified" "yes" \
    "$(contains "$(notice_for pdfa)" "veraPDF")"

# The read-only tier stopped being a batch operation. It must have no notice and
# no panel left behind, or a half-removed stage reaches a Save dialog.
check "inspect has no notice any more" "" "$(notice_for inspect)"
check "inspect has no panel any more" "$GROUP_PLACEHOLDER_ID" \
    "$(pdfutil_call panel_for_operation inspect)"

# --------------------------------------------------------------------------
section "settings the panel must refuse before a destination is asked for"
# --------------------------------------------------------------------------
problem_for() { pdfutil_handler_call PDFUtil.start.batch.sh settings_problem "$1"; }

# An empty Remove Password field is a real request: a PDF that opens without a
# password needs none. Which files do need one is the router's per-file check
# (30-router), not a settings problem.
reset_document
check "an empty decrypt password is not a settings problem" "" "$(problem_for decrypt)"
omc_control "$DEC_PASSWORD_ID" "pw"
check "nor is a supplied one" "" "$(problem_for decrypt)"

# Set Password confirms each password twice; a mismatch has to be caught here
# rather than after the user has named an output file.
reset_document
omc_control "$ENC_USER_PW_ID" "one"
omc_control "$ENC_USER_PW_CONFIRM_ID" "two"
check "mismatched user passwords are refused" "yes" \
    "$([ -n "$(problem_for encrypt)" ] && echo yes || echo no)"
reset_document
omc_control "$ENC_USER_PW_ID" "same"
omc_control "$ENC_USER_PW_CONFIRM_ID" "same"
check "matching passwords are fine" "" "$(problem_for encrypt)"

# Encrypting with no password at all would produce a document with no protection
# while telling the user it was protected.
reset_document
check "encrypt with no password at all is refused" "yes" \
    "$([ -n "$(problem_for encrypt)" ] && echo yes || echo no)"

# --------------------------------------------------------------------------
section "passwords reach pdfutil on stdin, never in the argument list"
# --------------------------------------------------------------------------
# A password in argv is visible to every process on the machine through `ps`.
# 30-router asserts the secret's absence; what is asserted here is the other
# half - that a stdin form is actually being asked for, so absence means "sent
# another way" rather than "not sent at all".
reset_document
omc_control "$ENC_USER_PW_ID" "hunter2"
omc_control "$ENC_USER_PW_CONFIRM_ID" "hunter2"
check "encrypt asks for a stdin password form" "yes" \
    "$(contains "$(pdfutil_args_for encrypt)" "stdin")"

# Only ONE password can come from stdin, so a run that sets both must not ask
# for two - pdfutil exits 1 on that.
omc_control "$ENC_OWNER_PW_ID" "ownerpw"
omc_control "$ENC_OWNER_PW_CONFIRM_ID" "ownerpw"
check "and never for two of them" "yes" \
    "$([ "$(pdfutil_args_for encrypt | /usr/bin/tr ' ' '\n' \
        | /usr/bin/grep -c -- '-stdin')" -le 1 ] && echo yes || echo no)"

reset_document
omc_control "$DEC_PASSWORD_ID" "hunter2"
check "decrypt asks for one too" "yes" \
    "$(contains "$(pdfutil_args_for decrypt)" "stdin")"

# An empty field sends no password at all: pdfutil refuses an empty stdin
# password, and a PDF that opens without one needs none.
reset_document
check "an empty decrypt field sends no password" "no" \
    "$(contains "$(pdfutil_args_for decrypt)" "password")"
check "and feeds nothing on stdin" "" \
    "$(pdfutil_eval 'build_pdfutil_args decrypt >/dev/null 2>&1; printf "%s" "$PDFUTIL_STDIN_PW"')"

# --------------------------------------------------------------------------
section "a PDF's protection is read, not asked for"
# --------------------------------------------------------------------------
# A PDF that opens without a password but is encrypted has an empty user
# password; only its owner password restricts it. Nobody can be expected to know
# that, so the app has to tell the three cases apart itself.
check "a plain pdf is not protected" "none" "$(pdfutil_call pdf_protection "$text_pdf")"
check "a password-protected pdf is locked" "locked" "$(pdfutil_call pdf_protection "$locked_pdf")"
check "an owner-password pdf is restricted" "restricted" "$(pdfutil_call pdf_protection "$restricted_pdf")"
check "a file that is not a pdf has no protection to report" "" \
    "$(pdfutil_call pdf_protection "$notes_txt")"

restricted_flags="$(pdfutil_call pdf_permission_flags "$restricted_pdf")"
check "the restricted fixture withholds assembly" "no" \
    "$(pdfutil_call flags_allow "$restricted_flags" assembly && echo yes || echo no)"
check "and allows copying" "yes" \
    "$(pdfutil_call flags_allow "$restricted_flags" copying && echo yes || echo no)"
check "a flag name that is only part of another does not match" "no" \
    "$(pdfutil_call flags_allow "printing, high-quality-printing" quality && echo yes || echo no)"
check "an unreadable pdf allows everything" "yes" \
    "$(pdfutil_call flags_allow "" assembly && echo yes || echo no)"
check "what it does not allow, in words" \
    "removing or rotating pages, editing, adding comments and filling in forms" \
    "$(pdfutil_call restriction_words "$restricted_flags")"
check "a plain pdf restricts nothing" "" \
    "$(pdfutil_call restriction_words "$(pdfutil_call pdf_permission_flags "$text_pdf")")"
check "full-resolution printing is named when only it is withheld" "printing at full resolution" \
    "$(pdfutil_call restriction_words "printing, changes, assembly, copying, accessibility, commenting, forms")"

omctest_end
