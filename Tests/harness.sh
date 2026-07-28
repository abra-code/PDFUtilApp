# Tests/harness.sh - put the app's libraries, and a fake OMC runtime, into the
# caller's shell. Sourced once by test.sh before any case file runs.
#
# The app's handlers are not callable directly: they expect OMC to have exported
# window ids, control values and tool paths, and they end by doing something to a
# dialog that does not exist. What IS callable is the logic underneath - the
# argument builder, the classifier, the panel switch - provided the environment
# those functions read is present. This file manufactures that environment.
#
# The stubs in Tests/stubs record what the app TRIED to do instead of doing it,
# which is what makes the UI-facing behavior testable at all: with the display
# locked (or on any headless machine) the only observable of "the panel hid the
# query row" is the omc_dialog_control call that would have hidden it.

# Sourced by test.sh, which defines die(). Define a fallback so this file also
# fails loudly if it is ever sourced on its own.
command -v die >/dev/null 2>&1 || die() { echo "ERROR: $*" >&2; exit 1; }

[ -n "$APP" ]     || die "harness: APP is not set"
[ -n "$TMP" ]     || die "harness: TMP is not set"
[ -d "$SCRIPTS" ] || die "harness: no Scripts directory at $SCRIPTS"

export OMC_APP_BUNDLE_PATH="$APP"
export OMC_OMC_SUPPORT_PATH="$PWD/Tests/stubs"
export OMC_ACTIONUI_WINDOW_UUID=TEST-WINDOW
export OMC_CURRENT_COMMAND_GUID=TEST-GUID
export OMC_TEST_LOG="$PWD/$TMP/omc"
mkdir -p "$OMC_TEST_LOG" || die "harness: cannot create $OMC_TEST_LOG"

# The stubs ARE the observable for everything UI-facing: if one is missing or not
# executable, the app's calls fail silently and assertions about what the user
# was told pass or fail for the wrong reason.
for _s in omc_dialog_control alert omc_next_command pasteboard; do
    [ -x "$OMC_OMC_SUPPORT_PATH/$_s" ] \
        || die "harness: stub $OMC_OMC_SUPPORT_PATH/$_s is missing or not executable"
done

# The library is split by topic and each handler sources only the parts it needs.
# The harness sources all of it so any function can be called from any case.
for _lib in lib.PDFUtil.sh lib.PDFUtil.files.sh lib.PDFUtil.panels.sh \
            lib.PDFUtil.args.sh lib.PDFUtil.run.sh; do
    _p="$SCRIPTS/$_lib"
    [ -f "$_p" ] || die "harness: missing $_lib"
    # Checked, not assumed: a syntax error in a library makes every later
    # assertion fail with a symptom that has nothing to do with the cause.
    . "$_p" || die "harness: $_lib failed to source"
done

# Load the function definitions a handler keeps to itself. Single-caller logic
# deliberately does NOT live in a shared lib (it would make the lib bigger and its
# readers guess who calls it), so the only way to reach it is to read the marked
# block out of the handler and eval it - which runs the definitions without
# running the handler's body.
#
# The marker check is not decoration: if a handler is refactored and the markers
# disappear, this must fail loudly. Silently eval'ing nothing would leave every
# assertion below calling functions that do not exist, and a suite that tests
# nothing while reporting success is the failure mode worth engineering against.
load_handler_locals() {
    _h="$SCRIPTS/$1"
    [ -f "$_h" ] || die "harness: no handler $1"
    _b=$(awk '/^# --- handler-local functions ---/,/^# --- end handler-local functions ---/' "$_h")
    case "$_b" in
        *"() {"*) eval "$_b" || die "harness: the handler-local block in $1 failed to evaluate" ;;
        *) die "harness: no handler-local block in $1 - were its markers renamed?" ;;
    esac
}

# Put every control back to the value the UI DECLARES, not to empty.
#
# This distinction turned out to matter. Blanking everything simulates a window
# that cannot exist: toggle 76 ("Downsample images over:") ships isOn=true, so a
# real Reduce run emits `-r 150`, while a blanked one emits `-r 0` and behaves
# completely differently. Tests written against the blank state pass while
# describing something the user never sees.
#
# The defaults are read from Base.lproj/PDFUtil.json itself rather than restated
# here, so a default changed in the UI cannot drift away from the tests. Toggles
# take isOn, text fields take their declared text (a prompt is placeholder
# wording, not a value), and pickers take their first option's tag, which is what
# the control shows before anyone touches it.
command -v python3 >/dev/null 2>&1 \
    || die "harness: python3 is required to read the UI's declared control defaults"
_UI_JSON="$APP/Contents/Resources/Base.lproj/PDFUtil.json"
[ -f "$_UI_JSON" ] || die "harness: no UI definition at $_UI_JSON"

_CONTROL_DEFAULTS="$TMP/control-defaults.sh"
python3 - "$APP/Contents/Resources/Base.lproj/PDFUtil.json" > "$_CONTROL_DEFAULTS" <<'DEFAULTS'
import json, sys

doc = json.load(open(sys.argv[1]))
out = []


def walk(n):
    if isinstance(n, dict):
        i, t, p = n.get('id'), n.get('type'), n.get('properties', {})
        if isinstance(i, int):
            v = None
            if t == 'Toggle':
                v = 'true' if p.get('isOn') else 'false'
            elif t in ('TextField', 'SecureField', 'TextEditor'):
                v = p.get('text', '')
            elif t == 'Picker':
                for o in p.get('options', []):
                    if isinstance(o, dict) and 'tag' in o:
                        v = o['tag']
                        break
            if v is not None:
                out.append('OMC_ACTIONUI_VIEW_%d_VALUE=%s' % (i, json.dumps(str(v))))
        for x in n.values():
            walk(x)
    elif isinstance(n, list):
        for x in n:
            walk(x)


walk(doc)
print('\n'.join(sorted(set(out))))
DEFAULTS
_extract_rc=$?
[ "$_extract_rc" -eq 0 ] || die "harness: reading control defaults from $_UI_JSON failed (exit $_extract_rc)"
[ -s "$_CONTROL_DEFAULTS" ] || die "harness: no control defaults extracted from $_UI_JSON"
# Sanity-check one known control, so a parser that silently produces the wrong
# shape is caught here rather than by a confusing assertion later.
grep -q '^OMC_ACTIONUI_VIEW_76_VALUE=' "$_CONTROL_DEFAULTS" \
    || die "harness: control defaults look wrong - toggle 76 is missing from $_CONTROL_DEFAULTS"

reset_controls() {
    . "$_CONTROL_DEFAULTS" || die "harness: cannot re-apply control defaults"
    unset OMC_ACTIONUI_TABLE_10_COLUMN_3_ALL_ROWS
    : > "$OMC_TEST_LOG/dialog.log"
    : > "$OMC_TEST_LOG/alert.log"
    : > "$OMC_TEST_LOG/next.log"
}

# Echo the arguments the builder produced for an operation, space-joined.
args_for() { build_pdfutil_args "$1" >/dev/null 2>&1; printf '%s' "${PDFUTIL_ARGS[*]}"; }

# Return 0 when "$1" contains "$2". A function rather than an inline `case`
# because a case pattern's ")" terminates a $( ) command substitution in bash 3.2,
# which is a parse error rather than a wrong answer.
contains() {
    case "$1" in
        *"$2"*) return 0 ;;
        *) return 1 ;;
    esac
}
