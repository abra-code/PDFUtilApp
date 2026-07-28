# router.sh - every operation reaches the right runner.
#
# The routing decision is output KIND, not operation: a PDF goes to a Save As
# dialog, images to a folder chooser, a report to an output window. Each of those
# prompts is declared on a different COMMAND_ID in Command.json, so choosing a
# prompt means chaining to the command that declares it. Sending an operation to
# the wrong one asks the user to name a file that will never be written.

reset_controls

# The kind each operation declares. This is the table the runners key off.
check_kind() {
    reset_controls
    case "$1" in
        extract) OMC_ACTIONUI_VIEW_140_VALUE="1-2" ;;
        delete)  OMC_ACTIONUI_VIEW_141_VALUE="2" ;;
        crop)    OMC_ACTIONUI_VIEW_186_VALUE="36,36,36,36" ;;
        encrypt) OMC_ACTIONUI_VIEW_110_VALUE="pw"; OMC_ACTIONUI_VIEW_111_VALUE="pw" ;;
        decrypt) OMC_ACTIONUI_VIEW_122_VALUE="pw" ;;
        metadata) OMC_ACTIONUI_VIEW_190_VALUE="T" ;;
    esac
    build_pdfutil_args "$1" >/dev/null 2>&1
    expect_eq "$2" "$PDFUTIL_OUTPUT_KIND" "output kind for $1"
}
for op in reduce linearize pdfa extract delete rotate crop watermark flatten \
          metadata encrypt decrypt; do
    check_kind "$op" pdf
done
check_kind render images
check_kind text   text
check_kind merge  merged
check_kind frompages assembled
check_kind split     parts

# OCR changes its output kind with the mode, which is the whole reason the
# router keys off the kind rather than the operation name.
reset_controls
check_kind ocr text
reset_controls; OMC_ACTIONUI_VIEW_183_VALUE=true
build_pdfutil_args ocr >/dev/null 2>&1
expect_eq "pdf" "$PDFUTIL_OUTPUT_KIND" "searchable OCR produces a PDF, not text"

# Each kind must be one the routing case in start.batch actually handles. A kind
# with no arm falls through and the Save button does nothing at all.
router="$(awk '/^case "\$PDFUTIL_OUTPUT_KIND" in/,/^esac/' "$SCRIPTS/PDFUtil.start.batch.sh")"
for kind in pdf text images merged assembled parts; do
    contains "$router" "$kind)" || fail "start.batch has no routing arm for output kind '$kind'"
done

# An operation nobody has built must be reported as missing, not routed. This is
# the guard that keeps a half-built stage from reaching a Save panel.
reset_controls
if build_pdfutil_args "nosuchoperation" >/dev/null 2>&1; then
    fail "build_pdfutil_args accepted an operation that does not exist"
fi

# ...and the panel switch agrees with it, so the UI and the router cannot
# disagree about what exists.
expect_eq "$GROUP_PLACEHOLDER_ID" "$(panel_for_operation nosuchoperation)" \
    "an unknown operation shows the placeholder panel"
for op in reduce linearize pdfa frompages metadata; do
    if [ "$(panel_for_operation "$op")" = "$GROUP_PLACEHOLDER_ID" ]; then
        fail "$op is built but still shows the 'not available yet' placeholder"
    fi
done
