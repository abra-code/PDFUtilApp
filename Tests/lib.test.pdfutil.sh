# Tests/lib.test.pdfutil.sh - PDFUtil's own test vocabulary, for omctest.
#
# Sourced after omctest.sh by every Tests/*.test.sh file. Holds the things the
# harness has no business knowing: where this applet keeps its state, how its
# table is shaped, and how to call into its libraries directly.
#
# This suite owns the applet. The remaining ./test.sh suite owns the embedded
# pdfutil binary - that it is present and complete, and the handful of its
# behaviors the applet is deliberately built around - and nothing there sources
# the applet's libraries any more.

# omc_control_defaults arrived in API 2. Without it a test would start from a
# blank window, which for this applet is not a window any user can reach.
if [ "${OMCTEST_API_VERSION:-0}" -lt 2 ]; then
    printf 'lib.test.pdfutil: needs omctest API 2 or newer, found %s\n' \
        "${OMCTEST_API_VERSION:-none}" >&2
    exit 1
fi

APP_SCRIPTS="$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts"
PDFUTIL_BIN="$OMC_APP_BUNDLE_PATH/Contents/Helpers/pdfutil"

# ---------------------------------------------------------------------------
# View ids, imported from the applet rather than restated
# ---------------------------------------------------------------------------

# lib.PDFUtil.sh writes them as NAME_ID=10 and TABLE_PATH_COLUMN=3. Two separate
# -e expressions, not one alternation: BSD sed has no \| and would match it
# literally, importing nothing while looking correct.
omctest_import_view_ids() { # <script ...>
    local script
    for script; do
        eval "$(/usr/bin/sed -n \
            -e 's/^\([A-Z][A-Z0-9_]*_ID\)=\([0-9][0-9]*\)$/\1=\2/p' \
            -e 's/^\([A-Z][A-Z0-9_]*_COLUMN\)=\([0-9][0-9]*\)$/\1=\2/p' \
            "$script")"
    done
}

omctest_import_view_ids "$APP_SCRIPTS/lib.PDFUtil.sh"

# Without this guard a renamed constant expands to the empty string, every
# omc_control writes OMC_ACTIONUI_VIEW__VALUE, and the file fails check by check
# with no hint why. With it, it fails once and says which name went missing.
for _required in TABLE_ID SUMMARY_VIEW_ID TABLE_PATH_COLUMN OPERATION_PICKER_ID \
                 RUN_BUTTON_ID REMOVE_BUTTON_ID GROUP_REDUCE_ID GROUP_PLACEHOLDER_ID; do
    eval "_value=\${$_required}"
    if [ -z "$_value" ]; then
        printf 'lib.test.pdfutil: %s did not import from lib.PDFUtil.sh\n' "$_required" >&2
        exit 1
    fi
done
unset _required _value

# ---------------------------------------------------------------------------
# Calling into the applet's libraries
# ---------------------------------------------------------------------------

# Run a library function in a subshell with all five libs loaded.
#
# The subshell keeps the libraries' own globals out of the test file and stops a
# function that calls exit from taking the whole file with it. Arguments are
# expanded by the CALLING shell, so a call that has to name one of the library's
# own constants needs pdfutil_eval instead.
pdfutil_call() { # <function> [argument ...]
    (
        . "$APP_SCRIPTS/lib.PDFUtil.sh" >/dev/null 2>&1
        . "$APP_SCRIPTS/lib.PDFUtil.files.sh" >/dev/null 2>&1
        . "$APP_SCRIPTS/lib.PDFUtil.panels.sh" >/dev/null 2>&1
        . "$APP_SCRIPTS/lib.PDFUtil.args.sh" >/dev/null 2>&1
        . "$APP_SCRIPTS/lib.PDFUtil.run.sh" >/dev/null 2>&1
        "$@"
    )
}

# As above, but the first argument is shell text evaluated INSIDE the subshell,
# so it can name the libraries' constants and arrays.
#
# Any further arguments become the eval'd text's own "$@". The shift is what
# makes that true and is not optional: without it the script text is still $1
# inside the subshell, so a text that says "$@" hands its own source code to
# whatever it is calling as the first argument - which fails as a missing input
# file, several layers away from the cause.
pdfutil_eval() { # <shell-text> [argument ...]
    local _text="$1"
    shift
    (
        . "$APP_SCRIPTS/lib.PDFUtil.sh" >/dev/null 2>&1
        . "$APP_SCRIPTS/lib.PDFUtil.files.sh" >/dev/null 2>&1
        . "$APP_SCRIPTS/lib.PDFUtil.panels.sh" >/dev/null 2>&1
        . "$APP_SCRIPTS/lib.PDFUtil.args.sh" >/dev/null 2>&1
        . "$APP_SCRIPTS/lib.PDFUtil.run.sh" >/dev/null 2>&1
        eval "$_text"
    )
}

# The argv build_pdfutil_args produced, space-joined, plus its verb.
#
# PDFUTIL_ARGS is a bash array; /bin/sh on macOS is bash 3.2, which has arrays
# even in POSIX mode, so this works in a test file that is otherwise plain sh.
pdfutil_args_for() { # <operation>
    pdfutil_eval "build_pdfutil_args \"$1\" >/dev/null 2>&1; printf '%s' \"\${PDFUTIL_ARGS[*]}\""
}

pdfutil_verb_for() { # <operation>
    pdfutil_eval "build_pdfutil_args \"$1\" >/dev/null 2>&1; printf '%s' \"\$PDFUTIL_VERB\""
}

pdfutil_kind_for() { # <operation>
    pdfutil_eval "build_pdfutil_args \"$1\" >/dev/null 2>&1; printf '%s' \"\$PDFUTIL_OUTPUT_KIND\""
}

# Did build_pdfutil_args accept the operation at all?
pdfutil_builds() { # <operation> -> yes | no
    export OMCTEST_PU_OP="$1"
    pdfutil_eval 'build_pdfutil_args "$OMCTEST_PU_OP" >/dev/null 2>&1 && echo yes || echo no'
}

# Is <exact-arg> one of the arguments built for <operation>?
#
# An element match, not a substring of the joined list. The difference is the
# whole point for the flags asserted here: " -o " as a substring is also found
# inside a watermark's text, and "-q 8" is a prefix of "-q 85", so a joined-string
# check answers a question nobody asked.
#
# The operation and the wanted argument travel as exported variables rather than
# being interpolated into the eval'd text, so a value containing a quote or a $
# cannot end up being parsed as shell.
pdfutil_has_arg() { # <operation> <exact-arg> -> yes | no
    export OMCTEST_PU_OP="$1" OMCTEST_PU_ARG="$2"
    pdfutil_eval '
        build_pdfutil_args "$OMCTEST_PU_OP" >/dev/null 2>&1
        for _arg in "${PDFUTIL_ARGS[@]}"; do
            if [ "$_arg" = "$OMCTEST_PU_ARG" ]; then echo yes; exit 0; fi
        done
        echo no'
}

# Run the argument list the builder produced against the real pdfutil, the way
# _exec_pdfutil does. Echoes the exit status.
#
# The join the argument checks alone cannot make: a list can be exactly what was
# intended and still be one the binary refuses.
#
# A REFUSED BUILD is reported as "build-refused", never as the binary's status.
# Without that, a builder that declined the operation left the previous
# operation's verb and arguments in place, the run succeeded on those, and the
# check said the operation ran - the loudest possible way to test nothing. It is
# a word rather than a number so it cannot be mistaken for an exit code.
pdfutil_run_built_args() { # <operation> <input> <output>
    export OMCTEST_PU_OP="$1" OMCTEST_PU_IN="$2" OMCTEST_PU_OUT="$3"
    pdfutil_eval '
        if ! build_pdfutil_args "$OMCTEST_PU_OP" >/dev/null 2>&1; then
            printf "build-refused"
            exit 0
        fi
        "$PDFUTIL" "$PDFUTIL_VERB" "${PDFUTIL_ARGS[@]}" --force \
            -o "$OMCTEST_PU_OUT" "$OMCTEST_PU_IN" "${PDFUTIL_TRAILING[@]}" \
            >/dev/null 2>&1
        printf "%s" "$?"'
}

# Load the functions a handler keeps to itself, without running the handler.
#
# Single-caller logic deliberately does not live in a shared lib, so the only
# way to reach it is to read the marked block out of the handler and eval it.
# The marker check is not decoration: if a refactor renames the markers this
# must fail loudly, because eval'ing nothing silently would leave every later
# assertion calling functions that do not exist - a suite that tests nothing
# while reporting success.
pdfutil_handler_locals() { # <handler-file-name> -> prints the block
    local handler="$APP_SCRIPTS/$1" block
    if [ ! -f "$handler" ]; then
        printf 'lib.test.pdfutil: no handler %s\n' "$1" >&2
        return 1
    fi
    block=$(/usr/bin/awk '/^# --- handler-local functions ---/,/^# --- end handler-local functions ---/' "$handler")
    case "$block" in
        *"() {"*) printf '%s' "$block" ;;
        *)
            printf 'lib.test.pdfutil: no handler-local block in %s - were its markers renamed?\n' "$1" >&2
            return 1
            ;;
    esac
}

# Call one of those handler-local functions, with the libs loaded too.
pdfutil_handler_call() { # <handler-file-name> <function> [argument ...]
    local handler="$1"; shift
    local block
    block=$(pdfutil_handler_locals "$handler") || return 1
    pdfutil_eval "$block
$(printf '%q ' "$@")"
}

# Dispatch a handler and echo what it printed.
#
# Needed for exactly one shape of command: PDFUtil.info runs under
# exe_script_file_with_output_window, so OMC shows its stdout to the user and it
# writes nothing to the window. There is no ui_value to read - the output IS the
# result.
#
# omctest appends every dispatch's output to handlers.log, so the observable is
# the slice this dispatch added. Measured as a byte offset rather than by
# truncating the log, which would throw away the diagnostics a failing run in
# the same file leaves behind.
run_capturing() { # <command-id>
    local before status
    before=$(/usr/bin/wc -c < "$OMCTEST_UI/handlers.log" 2>/dev/null || echo 0)
    omc_run "$1"
    status=$?
    /usr/bin/tail -c "+$((before + 1))" "$OMCTEST_UI/handlers.log" 2>/dev/null
    return "$status"
}

# ---------------------------------------------------------------------------
# The file list: table 10, and the env var the engine derives from it
# ---------------------------------------------------------------------------

# Rows are three tab-separated fields - badge, display name, path - and the
# path is the hidden third column.
file_list() { ui_rows "$TABLE_ID" | /usr/bin/cut -f "$TABLE_PATH_COLUMN"; }
file_list_names() { ui_rows "$TABLE_ID" | /usr/bin/cut -f 2; }
file_list_badges() { ui_rows "$TABLE_ID" | /usr/bin/cut -f 1; }
file_count() { ui_row_count "$TABLE_ID"; }

summary() { ui_value "$SUMMARY_VIEW_ID"; }

# Every operation the picker actually offers, one per line.
#
# Read out of the UI document rather than retyped here, so an operation added to
# the picker and forgotten everywhere else is caught by the checks that walk
# this list - which is the whole point of walking it.
operation_tags() {
    /usr/bin/python3 - "$OMC_APP_BUNDLE_PATH/Contents/Resources/Base.lproj/PDFUtil.json" \
                       "$OPERATION_PICKER_ID" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
wanted = int(sys.argv[2])
def walk(node):
    if isinstance(node, dict):
        if node.get("id") == wanted:
            for option in node.get("properties", {}).get("options", []):
                # {"section": ...} entries are headers: they carry no tag and
                # are never delivered to a handler.
                if isinstance(option, dict) and "tag" in option:
                    print(option["tag"])
            return
        for child in node.values():
            walk(child)
    elif isinstance(node, list):
        for child in node:
            walk(child)
walk(doc)
PY
}

# Does the first string contain the second? Answers yes or no, for check.
#
# A function rather than an inline `case`, and not by preference: a case
# pattern's ")" terminates a $( ) command substitution in bash 3.2, so the
# obvious one-liner is a PARSE ERROR rather than a wrong answer - and it fails
# inside the substitution, where the message is easy to miss and the check
# reports a mangled "actual" that looks like an applet bug. ./test.sh carries
# the same helper for the same reason.
contains() { # <haystack> <needle> -> yes | no
    case "$1" in
        *"$2"*) echo yes ;;
        *) echo no ;;
    esac
}

# Export the file list the way the engine would, from whatever the table now
# holds.
#
# The harness does not do this: it records what a handler wrote to the table,
# but does not feed it back as OMC_ACTIONUI_TABLE_<t>_COLUMN_<c>_ALL_ROWS on the
# next dispatch. Every handler in this applet that acts on more than the
# selected row reads the list through that variable, so without this bridge they
# would all see an empty list and pass for the wrong reason.
#
# Newline-joined, exactly like the engine - which is lossy for a name containing
# a newline, and is why the applet guards every row with [ -e ]. Reproducing the
# lossiness is the point; a lossless bridge would test a world the app never
# runs in.
sync_file_list() {
    local rows
    rows=$(file_list)
    omctest_setvar "OMC_ACTIONUI_TABLE_${TABLE_ID}_COLUMN_${TABLE_PATH_COLUMN}_ALL_ROWS" "$rows"
}

# Dispatch a handler that reads the whole file list, with that list exported the
# way the engine would export it at dispatch time.
run_with_list() { # <script-stem>
    sync_file_list
    omc_run "$1"
}

# Select a row by path: sets both the selected-cell variable the handlers read
# and the virtual window's selection.
select_file() { # <path>
    omc_table_cell "$TABLE_ID" "$TABLE_PATH_COLUMN" "$1"
}

clear_selection() {
    omc_table_cell "$TABLE_ID" "$TABLE_PATH_COLUMN" ""
}

# ---------------------------------------------------------------------------
# Pasteboard handoffs
# ---------------------------------------------------------------------------

# Both keys are global rather than per-window, so a value left behind by one
# test file would answer the next one's question. Clear them in reset_document.
pb_open_paths() { "$OMC_OMC_SUPPORT_PATH/pasteboard" PDFUTIL_OPEN_PATHS "$@"; }
pb_quicklook() { "$OMC_OMC_SUPPORT_PATH/pasteboard" PDFUTIL_QUICKLOOK_PATH "$@"; }

# Every handler that ends up reading the whole file list, whether it names the
# variable itself or reaches it through a library function it calls.
#
# The resolution is at function level, in Tests/helpers/file_list_readers.py,
# and neither cruder rule works. Grepping the handler files alone sees only the
# minority that name the variable - a reviewer deleted one handler's
# ENVIRONMENT_VARIABLES block from Command.json and the check stayed green.
# "Sources a library that mentions the variable" is the opposite error and
# returns nearly the whole bundle, because every handler sources the core lib.
handlers_reading_file_list() {
    "$OMCTEST_TESTS/helpers/file_list_readers.py" "$APP_SCRIPTS" \
        "OMC_ACTIONUI_TABLE_${TABLE_ID}_COLUMN_${TABLE_PATH_COLUMN}_ALL_ROWS"
}

# ---------------------------------------------------------------------------
# Resetting between sections
# ---------------------------------------------------------------------------

# Put the window back to how it opens: declared control defaults, no table rows,
# no selection, no leftover pasteboard handoff, no recorded window writes.
#
# The pasteboard clear is not optional. It lives in the per-login server and
# outlives the process, so a key left set by an earlier section silently seeds
# the next section's window with a file list it never asked for.
reset_document() {
    omc_control_defaults PDFUtil
    pb_open_paths set "" >/dev/null 2>&1
    pb_quicklook set "" >/dev/null 2>&1
    omc_object ""
    ui_reset
    alerts_reset
    alert_answers_reset
    # Chain history is cumulative across the whole file, so a section asserting
    # "the run did not start" would inherit an earlier section's legitimate run.
    chains_reset
    unset "OMC_ACTIONUI_TABLE_${TABLE_ID}_COLUMN_${TABLE_PATH_COLUMN}_ALL_ROWS"
}

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# Tests/fixtures is gitignored and generated by Tests/make-fixtures.swift, the
# same generator ./test.sh uses. Generate rather than restate: a second
# generator would be a second set of fixtures to keep in step.
ensure_fixtures() {
    local marker="$OMCTEST_FIXTURES/text.pdf"
    [ -f "$marker" ] && return 0
    if [ ! -f "$OMCTEST_TESTS/make-fixtures.swift" ]; then
        printf 'lib.test.pdfutil: no fixtures and no Tests/make-fixtures.swift to build them\n' >&2
        return 1
    fi
    if ! command -v swift >/dev/null 2>&1; then
        printf 'lib.test.pdfutil: fixtures are missing and swift is not available to generate them.\n' >&2
        printf '  Install the Xcode command line tools, or run ./test.sh once.\n' >&2
        return 1
    fi
    /bin/mkdir -p "$OMCTEST_FIXTURES" || return 1
    if ! swift "$OMCTEST_TESTS/make-fixtures.swift" "$OMCTEST_FIXTURES" >/dev/null 2>&1; then
        # A half-written fixture set is worse than none: it fails later, in
        # assertions that look like applet defects.
        /bin/rm -rf "$OMCTEST_FIXTURES"
        printf 'lib.test.pdfutil: fixture generation failed\n' >&2
        return 1
    fi
    return 0
}

# The engine and the binaries are preconditions, not things under test. Assert
# them where they are needed so the day one goes missing the failure names it,
# rather than surfacing as twenty unrelated assertion failures.
check_preconditions() {
    check_exists "fixture precondition: the pdfutil engine is embedded" "$PDFUTIL_BIN"
    check "fixture precondition: the fixtures are present" "yes" \
        "$(ensure_fixtures && echo yes || echo no)"
}
