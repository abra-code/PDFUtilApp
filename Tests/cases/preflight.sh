# preflight.sh - the structure pre-flight, and the alert it raises.
#
# Several operations reach their result by REDRAWING the page content, which
# discards annotations, links, the outline and form fields. The section notices
# say so permanently; the pre-flight is the extra step that only fires when THIS
# document actually has something to lose. Both halves matter: a warning that
# fires on every file is one people learn to dismiss.

# The redraw set, measured rather than assumed (see the table in start.batch).
load_handler_locals PDFUtil.start.batch.sh

for op in reduce linearize pdfa frompages; do
    if ! operation_redraws "$op"; then fail "$op should be in the redraw set"; fi
done
for op in extract delete rotate crop merge metadata decrypt encrypt text render; do
    if operation_redraws "$op"; then fail "$op does not redraw and must not warn"; fi
done

# Watermark is the one that depends on a control: burn-in redraws, --annotation
# does not. Unset means the toggle's declared isOn, which is off.
reset_controls
if ! operation_redraws watermark; then fail "burn-in watermark redraws and must warn"; fi
reset_controls; OMC_ACTIONUI_VIEW_166_VALUE=true
if operation_redraws watermark; then fail "annotation watermark preserves structure and must not warn"; fi

# flatten is deliberately absent: removing the fields is what the user asked for,
# so warning about it would be warning that the operation worked.
if operation_redraws flatten; then fail "flatten must not warn - removing fields is the point"; fi

# --- what the document actually has to lose --------------------------------
# text.pdf has neither an outline nor annotations; outline.pdf has an outline;
# form.pdf has fields. `info` reports fields as annotations, which is why the
# wording never claims to know which it found.
# It ECHOES what it found and says nothing when there is nothing - it does not
# return a status - so the assertions are about the string.
expect_eq "" "$(pdf_structure_at_risk "$FIX/text.pdf")" \
    "a plain document has nothing at risk"
risk_outline="$(pdf_structure_at_risk "$FIX/outline.pdf")"
contains "$risk_outline" "outline" \
    || fail "a document with an outline should report one: [$risk_outline]"
risk_form="$(pdf_structure_at_risk "$FIX/form.pdf")"
contains "$risk_form" "annotations" \
    || fail "form fields are reported as annotations by info: [$risk_form]"

# An unreadable document answers "nothing", deliberately: a guard should not
# block work over a question it could not answer.
expect_eq "" "$(pdf_structure_at_risk "$FIX/notes.txt")" \
    "an unreadable file must not trip the pre-flight"

# The phrase the alert is built from takes what was FOUND, not a path, and has
# to name it or the user cannot judge whether they care.
phrase="$(structure_risk_phrase "$risk_outline")"
[ -n "$phrase" ] || fail "structure_risk_phrase said nothing for [$risk_outline]"
contains "$phrase" "outline" || fail "the phrase does not mention the outline: $phrase"
# Every input yields SOME phrase, including one the case table does not know.
# The caller only reaches it when something was found, so the catch-all exists so
# an unexpected value still produces a readable sentence rather than
# "\"report.pdf\" has ." - assert that rather than an empty string.
for found in "outline annotations" "outline" "annotations" "" "something new"; do
    p="$(structure_risk_phrase "$found")"
    [ -n "$p" ] || fail "structure_risk_phrase returned nothing for [$found]"
done

# --- every redraw operation carries a permanent notice ---------------------
# The pre-flight is conditional; the notice is not. An operation that silently
# discards structure with no notice is the exact hazard this design exists for.
for op in reduce linearize pdfa frompages watermark flatten; do
    n="$(structure_notice "$op")"
    [ -n "$n" ] || fail "$op has no structure notice"
    contains "$n" "outline" || fail "$op's notice does not mention the outline: $n"
done

# The two Stage 10 notices must also steer, not just warn.
contains "$(structure_notice linearize)" "QuickPDF" \
    || fail "the linearize notice should point at the tool with the better hint table"
contains "$(structure_notice pdfa)" "veraPDF" \
    || fail "the PDF/A notice should say conformance is unverified"

# Read-only Inspect writes nothing, so its notice says that rather than warning
# about structure it cannot damage.
contains "$(structure_notice inspect)" "Read-only" \
    || fail "the inspect notice should say it is read-only"
