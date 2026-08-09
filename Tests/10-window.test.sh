#!/bin/sh
# Tests/10-window.test.sh - the window as it opens, and the settings panel switcher.
#
# The panel switcher is the applet's largest piece of pure UI behavior, and the
# only place it can be observed properly is against a modeled window: the claim
# worth making is not "a show was sent to 200" but "200 ended up visible and the
# other eighteen did not". A flat log of dialog calls cannot tell those apart,
# which is why the suite this replaced could only approximate it.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.pdfutil.sh"

section "preconditions"
check_preconditions

# --------------------------------------------------------------------------
section "the window opens in its declared state"
# --------------------------------------------------------------------------
reset_document

# The structural control for every assertion below that reads a control value:
# if the extraction silently matched nothing, this is the check that says so
# rather than letting twenty later checks pass against an empty window.
check "the declared defaults loaded" "yes" \
    "$([ "${OMCTEST_DEFAULTS_APPLIED:-0}" -gt 40 ] && echo yes || echo no)"
check "the operation picker starts on the first real option" "reduce" \
    "$OMC_ACTIONUI_VIEW_60_VALUE"
check "a section header is never the default" "no" \
    "$(contains "$OMC_ACTIONUI_VIEW_60_VALUE" "Size &")"

omc_run PDFUtil.init
check_status "init succeeded" 0

check "the file list starts empty" "0" "$(file_count)"
check "the table was actively emptied, not merely never filled" "1" \
    "$(ui_calls "omc_table_remove_all_rows")"
# Not just "Engine:" - the version has to have come back from the real binary.
# "Engine: pdfutil (missing!)" is what a broken bundle prints, and it would
# satisfy a laxer pattern.
check "the summary names the engine"          "yes" "$(contains "$(summary)" "Engine: pdfutil ")"
check "and the engine was not reported missing" "no"  "$(contains "$(summary)" "(missing!)")"
check "the summary tells the user what to do" "yes" \
    "$(contains "$(summary)" "Drop PDF files")"

# A picker fires no action for the value it starts with, so if init did not call
# the switcher itself the first panel would come up blank. That is a real
# regression this catches.
check "init opened the panel for the starting operation" "1" "$(ui_visible "$GROUP_REDUCE_ID")"
check "and its structure notice is filled in" "yes" \
    "$(contains "$(ui_value 300)" "Redraws pages")"

# --------------------------------------------------------------------------
section "choosing an operation shows exactly one panel"
# --------------------------------------------------------------------------
reset_document
omc_fire PDFUtil.operation.changed "$OPERATION_PICKER_ID" encrypt
check_status "the handler succeeded" 0

check "the encrypt panel is visible" "1" "$(ui_visible "$GROUP_ENCRYPT_ID")"
check "the reduce panel is hidden"   "0" "$(ui_visible "$GROUP_REDUCE_ID")"
check "the placeholder is hidden"    "0" "$(ui_visible "$GROUP_PLACEHOLDER_ID")"

# The interesting property is exclusivity, and asserting it one panel at a time
# would miss a twentieth panel added later without a hide. Count instead.
#
# Counting the VISIBLE ones is not enough on its own, and this was caught by
# deleting the omc_hide call: an untouched panel reads empty rather than "0", so
# a switcher that shows the right panel and hides nothing still leaves exactly
# one panel reading "1". The count that has teeth is of panels explicitly
# hidden, because that is the call the switcher actually has to make - a panel
# left over from the previous operation stays on screen otherwise.
visible_panels=0
hidden_panels=0
total_panels=0
for _panel in $(pdfutil_eval 'printf "%s" "$SETTINGS_PANEL_IDS"'); do
    total_panels=$((total_panels + 1))
    case "$(ui_visible "$_panel")" in
        1) visible_panels=$((visible_panels + 1)) ;;
        0) hidden_panels=$((hidden_panels + 1)) ;;
    esac
done
check "the panel list was read"               "yes" "$([ "$total_panels" -gt 15 ] && echo yes || echo no)"
check "exactly one settings panel is visible" "1"   "$visible_panels"
check "and every other one was actively hidden" "$((total_panels - 1))" "$hidden_panels"

# --------------------------------------------------------------------------
section "every operation the picker offers resolves to a panel"
# --------------------------------------------------------------------------
# Walking the picker's own options rather than a list retyped here: an
# operation added to the UI and forgotten in panel_for_operation shows up as a
# placeholder, which is exactly the bug worth catching.
reset_document
picker_tags=$(operation_tags)
check "the picker's options were read" "yes" \
    "$([ "$(printf '%s\n' "$picker_tags" | /usr/bin/wc -w)" -gt 15 ] && echo yes || echo no)"

placeholders=""
for _op in $picker_tags; do
    _panel=$(pdfutil_call panel_for_operation "$_op")
    [ "$_panel" = "$GROUP_PLACEHOLDER_ID" ] && placeholders="$placeholders $_op"
done
check "no offered operation falls through to the placeholder" "" "$placeholders"

# The positive control for the check above: an operation that genuinely has no
# panel must still reach the placeholder, otherwise the assertion is vacuous.
check "an unknown operation does reach the placeholder" "$GROUP_PLACEHOLDER_ID" \
    "$(pdfutil_call panel_for_operation no-such-operation)"

# --------------------------------------------------------------------------
section "an unimplemented operation explains itself"
# --------------------------------------------------------------------------
reset_document
omc_fire PDFUtil.operation.changed "$OPERATION_PICKER_ID" no-such-operation
check "the placeholder is showing" "1" "$(ui_visible "$GROUP_PLACEHOLDER_ID")"
check "and it says so in words" "yes" \
    "$(contains "$(ui_value "$GROUP_PLACEHOLDER_ID")" "is not available yet")"

# --------------------------------------------------------------------------
section "notices are written where the panel can show them"
# --------------------------------------------------------------------------
# structure_notice is asserted by the older suite as a string. What it cannot
# assert is that the text reached the Text element belonging to that panel -
# a notice written to another panel's id is invisible to the user.
reset_document
for _op in reduce render text encrypt ocr; do
    omc_fire PDFUtil.operation.changed "$OPERATION_PICKER_ID" "$_op"
    _notice_id=$(pdfutil_call notice_id_for_operation "$_op")
    _expected=$(pdfutil_call structure_notice "$_op")
    check "$_op wrote its notice to its own panel" "$_expected" "$(ui_value "$_notice_id")"
done

# --------------------------------------------------------------------------
section "mode toggles gray out what their mode cannot use"
# --------------------------------------------------------------------------
reset_document

# Split: --every and --chapters are mutually exclusive and pdfutil rejects the
# pair outright, so the UI must never let both reach the builder.
omc_control 151 false
omc_fire PDFUtil.split.mode.changed 151 false
check "per-page split leaves the count field live" "1" "$(ui_enabled "$SPLIT_EVERY_ID")"
omc_fire PDFUtil.split.mode.changed 151 true
check "chapter split disables the count field" "0" "$(ui_enabled "$SPLIT_EVERY_ID")"

# Render: quality means nothing for a lossless format, transparency nothing for
# one that has no alpha.
reset_document
omc_fire PDFUtil.render.format.changed "$RND_FORMAT_ID" png
check "png has no quality setting"        "0" "$(ui_enabled "$RND_QUALITY_ID")"
check "png can be transparent"            "1" "$(ui_enabled "$RND_TRANSPARENT_ID")"
omc_fire PDFUtil.render.format.changed "$RND_FORMAT_ID" jpeg
check "jpeg has a quality setting"        "1" "$(ui_enabled "$RND_QUALITY_ID")"
check "jpeg cannot be transparent"        "0" "$(ui_enabled "$RND_TRANSPARENT_ID")"

# Metadata: the strip mode discards the five fields, so leaving them editable
# would invite the user to type something that is then thrown away.
reset_document
omc_fire PDFUtil.metadata.mode.changed "$META_STRIP_ID" false
check "the title field is editable when editing" "1" "$(ui_enabled "$META_TITLE_ID")"
omc_fire PDFUtil.metadata.mode.changed "$META_STRIP_ID" true
check "the title field is dead when stripping"   "0" "$(ui_enabled "$META_TITLE_ID")"

# Build-from-images: the two page-sizing modes use different rows.
reset_document
omc_fire PDFUtil.assemble.mode.changed "$ASSEMBLE_MODE_ID" dpi
check "the dpi row appears for the dpi mode"   "1" "$(ui_visible "$FP_DPI_ROW_ID")"
check "and the paper row goes away"            "0" "$(ui_visible "$FP_PAGE_SIZE_ROW_ID")"
omc_fire PDFUtil.assemble.mode.changed "$ASSEMBLE_MODE_ID" fit
check "the paper row is back for fit"          "1" "$(ui_visible "$FP_PAGE_SIZE_ROW_ID")"
check "and the dpi row is gone"                "0" "$(ui_visible "$FP_DPI_ROW_ID")"

# --------------------------------------------------------------------------
section "a mode's state is applied when its panel first appears, not only on change"
# --------------------------------------------------------------------------
# A control fires no action for the value it starts with. Every *.mode.changed
# handler therefore has a twin call inside apply_operation_panel, and forgetting
# one leaves a panel whose controls contradict its own toggles.
reset_document
omc_control 151 true
omc_fire PDFUtil.operation.changed "$OPERATION_PICKER_ID" split
check "opening the split panel already honors the chapters toggle" "0" \
    "$(ui_enabled "$SPLIT_EVERY_ID")"

reset_document
omc_control "$RND_FORMAT_ID" jpeg
omc_fire PDFUtil.operation.changed "$OPERATION_PICKER_ID" render
check "opening the render panel already honors the format" "0" \
    "$(ui_enabled "$RND_TRANSPARENT_ID")"

reset_document
omc_control "$META_STRIP_ID" true
omc_fire PDFUtil.operation.changed "$OPERATION_PICKER_ID" metadata
check "opening the metadata panel already honors the strip toggle" "0" \
    "$(ui_enabled "$META_TITLE_ID")"

# --------------------------------------------------------------------------
section "cumulative: no handler wrote to a view id the window does not declare"
# --------------------------------------------------------------------------
check "no undeclared ids" "" "$(ui_unknown_writes)"
check "no bare value write clobbered a table's rows" "" "$(ui_suspect_writes)"
check "the harness detected no misuse" "" "$(ui_errors)"

# The control for the three checks above: they are silently inert if the bundle
# declared no ids at all.
check "the id set was extracted" "yes" \
    "$([ -s "$OMCTEST_UI/known_ids.txt" ] && echo yes || echo no)"

omctest_end
