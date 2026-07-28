# argbuilder.sh - build_pdfutil_args for every operation.
#
# This is the highest-value case file in the suite. The argument builder is the
# single place where a UI control becomes a command line, and two of its
# invariants can destroy a user's data if they ever lapse:
#
#   -o      most verbs edit the input IN PLACE without it
#   --force the runners stage through mktemp, which pre-creates the output
#
# Neither is emitted by the builder - both are added by run_pdfutil - so the test
# is that the builder never emits an -o of its own AND that the runner's single
# call site still carries both.

reset_controls

# Every operation the picker offers, in picker order.
ALL_OPS="reduce gray linearize pdfa extract delete rotate crop split merge \
         watermark flatten metadata encrypt decrypt render text ocr \
         frompages"

# --- every operation builds, and none invents its own -o or --force ---------
for op in $ALL_OPS; do
    reset_controls
    # Operations with a required value need one, or they legitimately refuse.
    case "$op" in
        extract) OMC_ACTIONUI_VIEW_140_VALUE="1-2" ;;
        delete)  OMC_ACTIONUI_VIEW_141_VALUE="2" ;;
        crop)    OMC_ACTIONUI_VIEW_186_VALUE="36,36,36,36" ;;
        encrypt) OMC_ACTIONUI_VIEW_110_VALUE="pw"; OMC_ACTIONUI_VIEW_111_VALUE="pw" ;;
        decrypt) OMC_ACTIONUI_VIEW_122_VALUE="pw" ;;
        metadata) OMC_ACTIONUI_VIEW_190_VALUE="A Title" ;;
    esac
    if ! build_pdfutil_args "$op" >/dev/null 2>&1; then
        fail "build_pdfutil_args refused a configured '$op'"
        continue
    fi
    [ -n "$PDFUTIL_VERB" ] || fail "$op produced no verb"
    [ -n "$PDFUTIL_OUTPUT_KIND" ] || fail "$op produced no output kind"
    joined="${PDFUTIL_ARGS[*]}"
    # The builder must never name an output. If it did, run_pdfutil would append
    # a second -o and the user's file would be written somewhere they did not ask.
    if contains " $joined " " -o "; then
        fail "$op emitted its own -o: $joined"
    fi
    if contains " $joined " " --force "; then
        fail "$op emitted its own --force: $joined"
    fi
done

# --- the invariants live in exactly one place, and it still has them --------
run_body="$(awk '/^_exec_pdfutil\(\) \{/,/^\}/' "$SCRIPTS/lib.PDFUtil.run.sh")"
contains "$run_body" '--force' || fail "_exec_pdfutil no longer passes --force"
contains "$run_body" '-o "$2"' || fail "_exec_pdfutil no longer passes -o"

# run_pdfutil refuses rather than running without an output path. This is the
# backstop for the whole in-place hazard, so assert the refusal itself.
reset_controls
build_pdfutil_args reduce >/dev/null 2>&1
out="$(run_pdfutil "$FIX/text.pdf" "" 2>&1)"; code=$?
expect_eq "1" "$code" "run_pdfutil with no output path must fail"
contains "$out" "refusing to run pdfutil without an output path" \
    || fail "run_pdfutil's refusal lost its explanation: $out"

# --- mutually exclusive flags never co-occur -------------------------------
# Each pair below is a combination pdfutil REFUSES (exit 1). The UI is supposed
# to make them unreachable; the builder is the last line of defence, because a
# control can hold a stale value from before a mode toggle was flipped.

# Convert to Grayscale is its own operation, not a mode of Reduce. pdfutil
# refuses --gray alongside -q/-r/-m, so the separation has to hold in the
# arguments and not only in the UI: whatever the Reduce controls happen to
# contain, the grayscale run must send --gray and nothing else.
reset_controls
OMC_ACTIONUI_VIEW_72_VALUE=85 OMC_ACTIONUI_VIEW_76_VALUE=true OMC_ACTIONUI_VIEW_77_VALUE=150
OMC_ACTIONUI_VIEW_78_VALUE=true OMC_ACTIONUI_VIEW_79_VALUE=2000
joined="$(args_for gray)"
contains "$joined" "--gray" || fail "grayscale lost --gray: $joined"
for flag in -q -r -m; do
    if contains " $joined " " $flag "; then
        fail "grayscale also emitted $flag (pdfutil refuses the pair): $joined"
    fi
done
# ...and Reduce never sends --gray, whatever it is handed.
reset_controls
joined="$(args_for reduce)"
if contains "$joined" "--gray"; then fail "Reduce emitted --gray: $joined"; fi
# Both run the same verb, so the router must not tell them apart by verb alone.
expect_eq "reduce" "$(build_pdfutil_args gray >/dev/null 2>&1; printf '%s' "$PDFUTIL_VERB")" \
    "grayscale runs the reduce verb"

# ocr: --searchable covers the whole document and picks its own parameters.
reset_controls
OMC_ACTIONUI_VIEW_183_VALUE=true
OMC_ACTIONUI_VIEW_180_VALUE="1-2" OMC_ACTIONUI_VIEW_181_VALUE="en-US" OMC_ACTIONUI_VIEW_182_VALUE=true
joined="$(args_for ocr)"
contains "$joined" "--searchable" || fail "searchable OCR lost --searchable: $joined"
for flag in -p --lang --fast --dpi; do
    if contains " $joined " " $flag "; then
        fail "searchable OCR also emitted $flag (pdfutil refuses it): $joined"
    fi
done

# watermark: --annotation is text-only and cannot be rotated or placed under.
reset_controls
OMC_ACTIONUI_VIEW_166_VALUE=true
OMC_ACTIONUI_VIEW_160_VALUE="DRAFT" OMC_ACTIONUI_VIEW_161_VALUE="/tmp/mark.png"
OMC_ACTIONUI_VIEW_163_VALUE=45 OMC_ACTIONUI_VIEW_165_VALUE=true
joined="$(args_for watermark)"
contains "$joined" "--annotation" || fail "annotation watermark lost --annotation: $joined"
for flag in --image --rotate-mark --under; do
    if contains " $joined " " $flag "; then
        fail "annotation watermark also emitted $flag (pdfutil refuses it): $joined"
    fi
done

# frompages: --page-size and --dpi both decide the page geometry.
for mode in fit image dpi ""; do
    reset_controls
    OMC_ACTIONUI_VIEW_221_VALUE="$mode" OMC_ACTIONUI_VIEW_220_VALUE=300
    joined="$(args_for frompages)"
    if contains "$joined" "--page-size" && contains "$joined" "--dpi"; then
        fail "frompages mode '$mode' emitted both --page-size and --dpi: $joined"
    fi
done

# --- clamps turn junk into something the binary accepts --------------------
# A control can hold anything: a stale programmatic update, or text the user
# typed. What must never happen is that it reaches pdfutil as a usage error the
# user cannot connect to anything they did.
reset_controls; OMC_ACTIONUI_VIEW_72_VALUE="not a number"
contains "$(args_for reduce)" "-q 85" || fail "junk quality did not fall back to the default"
reset_controls; OMC_ACTIONUI_VIEW_72_VALUE="9999"
contains "$(args_for reduce)" "-q 100" || fail "over-range quality was not clamped"
reset_controls; OMC_ACTIONUI_VIEW_130_VALUE="banana"
contains "$(args_for rotate)" "90" || fail "junk rotation did not fall back to 90"
reset_controls; OMC_ACTIONUI_VIEW_221_VALUE=fit OMC_ACTIONUI_VIEW_225_VALUE="A4"
contains "$(args_for frompages)" "--page-size letter" \
    || fail "a picker label instead of a tag should fall back to letter"
