#!/bin/bash
# test.sh - tests for the PDFUtil app bundle.
#
# NOT a cross-tool suite. QuickPDFApp can run qpdf and pdfutil against each other
# and use `qpdf --check` as an independent structural opinion; there is one engine
# here, so that is not available. What this covers instead is everything the APP
# adds on top of pdfutil: the argument builder, the router, file classification,
# the structure pre-flight, output naming, password handling, and the operations
# end to end.
#
# The distinction matters for scope. Whether `pdfa` really emits conformant
# PDF/A-2B is pdfutil's question and pdfutil's suite answers it. Whether this app
# builds a command line that runs, routes it to the right runner, and never omits
# -o is this suite's question, and nothing else asks it.
#
# Bash, not sh: the app's libraries use bash arrays (PDFUTIL_ARGS), and the cases
# source them to drive the same code the app runs rather than reimplementing it.
#
# Deliberately NO `set -e`. A test runner is the worst possible place for it: it
# ends the run at the first command that returns non-zero, which in a suite is a
# routine event, and it does so silently - no FAIL line, later cases never run,
# and the result is indistinguishable from an ordinary failure. It also makes the
# obvious `out=$(tool ...); code=$?` unwritable. Failures are counted explicitly
# below instead.
#
# Every case file in Tests/cases/*.sh is sourced with access to the helpers and
# variables defined below.

# Setup failures are fatal and explicit. Without `set -e` nothing stops on its
# own, so every step that the rest of the run depends on is checked here rather
# than left to produce confusing symptoms twenty assertions later.
die() {
    echo "ERROR: $*" >&2
    exit 1
}

cd "$(dirname "$0")" || die "cannot cd to the script's directory"

# The app bundle under test. Override to test a bundle elsewhere, e.g. a staged
# copy or an installed /Applications/PDFUtil.app.
APP="${PDFUTIL_APP:-$PWD/PDFUtil.app}"
PDFUTIL="$APP/Contents/Helpers/pdfutil"
SCRIPTS="$APP/Contents/Resources/Scripts"
LIB="$SCRIPTS/lib.PDFUtil.sh"

FIX="Tests/fixtures"
TMP="Tests/tmp"

# The embedded binary is the SUBJECT of these tests, not a convenience, so a
# missing one is a hard error and never a silent skip. A suite that quietly tests
# nothing is worse than one that fails.
missing=""
[ -x "$PDFUTIL" ] || missing="$missing\n  pdfutil: $PDFUTIL"
[ -f "$LIB" ]     || missing="$missing\n  lib:     $LIB"
if [ -n "$missing" ]; then
    printf 'ERROR: the app bundle is not populated. Missing:%b\n' "$missing" >&2
    echo "" >&2
    echo "Contents/Helpers is gitignored, so a fresh checkout has no binary yet." >&2
    echo "Build and embed it first:   ./update_pdfutil.sh" >&2
    echo "Or point at another bundle: PDFUTIL_APP=/path/to/PDFUtil.app $0" >&2
    exit 1
fi

echo "app:     $APP"
echo "pdfutil: $("$PDFUTIL" --version 2>/dev/null | head -1)"

if [ ! -d "$FIX" ]; then
    if ! command -v swift >/dev/null 2>&1; then
        echo "ERROR: fixtures are missing and 'swift' is not available to generate them." >&2
        echo "       Install the Xcode command line tools, or copy in a $FIX directory." >&2
        exit 1
    fi
    echo "Generating fixtures..."
    mkdir -p "$FIX" || die "cannot create $FIX"
    if ! swift Tests/make-fixtures.swift "$FIX"; then
        rm -rf "$FIX"   # a half-written fixture set is worse than none
        die "fixture generation failed - see the swift output above"
    fi
fi
# Generated or pre-existing, the fixtures the cases name have to be there. A
# missing one otherwise surfaces as a pile of unrelated assertion failures.
for _f in text.pdf image.pdf outline.pdf form.pdf locked.pdf photo.png notes.txt mislabeled.pdf; do
    [ -s "$FIX/$_f" ] || die "fixture $FIX/$_f is missing or empty - delete $FIX and re-run to regenerate"
done

rm -rf "$TMP"    || die "cannot clear $TMP"
mkdir -p "$TMP"  || die "cannot create $TMP"

# Failures are counted in a FILE, not a shell variable. A pipeline stage is a
# subshell, so an assertion that fires inside one would increment a variable that
# vanishes when the subshell exits - the failure would be printed and then not
# counted, and the suite would exit 0. This cost a real debugging session in
# QuickPDFApp; the file-based counter is the fix.
FAILLOG="$TMP/failures"
FAILDETAIL="$TMP/failures.log"
: > "$FAILLOG"    || die "cannot write $FAILLOG"
: > "$FAILDETAIL" || die "cannot write $FAILDETAIL"

# Two files on purpose. $FAILLOG is one line per failure and exists only to be
# counted; $FAILDETAIL keeps the messages, so a run that fails leaves something
# readable behind instead of only a number - which matters when the run happened
# somewhere nobody was watching.
fail() {
    echo "FAIL: $*" >&2
    echo x >> "$FAILLOG"
    printf '%s\n' "$*" >> "$FAILDETAIL"
}

# Assertion helpers. Each reports and counts; none of them stop the run, so a
# case file always executes every assertion it contains.
expect_ok()   { if ! "$@" >/dev/null 2>&1; then fail "expected success: $*"; fi; }
expect_fail() { if "$@" >/dev/null 2>&1; then fail "expected failure: $*"; fi; }
expect_code() {
    want="$1"; shift
    if "$@" >/dev/null 2>&1; then got=0; else got=$?; fi
    if [ "$got" != "$want" ]; then fail "expected exit $want, got $got: $*"; fi
}
expect_eq() {
    if [ "$1" != "$2" ]; then fail "${3:-values differ}: want [$1], got [$2]"; fi
}
expect_grep() {
    pat="$1"; shift
    if ! "$@" 2>/dev/null | grep -q -- "$pat"; then fail "expected /$pat/ from: $*"; fi
}
expect_nogrep() {
    pat="$1"; shift
    if "$@" 2>/dev/null | grep -q -- "$pat"; then fail "unexpected /$pat/ from: $*"; fi
}

# As above but matching stdout AND stderr. Required whenever the interesting text
# is a diagnostic: pdfutil writes PDFKit and CoreGraphics log lines to stderr, and
# a stdout-only assertion against them passes vacuously.
expect_grep_all() {
    pat="$1"; shift
    if ! "$@" 2>&1 | grep -q -- "$pat"; then fail "expected /$pat/ in stdout+stderr from: $*"; fi
}
expect_nogrep_all() {
    pat="$1"; shift
    if "$@" 2>&1 | grep -q -- "$pat"; then fail "unexpected /$pat/ in stdout+stderr from: $*"; fi
}

# Put the app's own libraries and its fake OMC runtime into this shell. Sourcing
# it can fail (a missing lib, an unreadable stub); if it does, every case below
# would fail for the same reason, so stop here and say so once.
[ -f Tests/harness.sh ] || die "Tests/harness.sh is missing"
. Tests/harness.sh || die "Tests/harness.sh failed to load"
for _fn in build_pdfutil_args classify_file panel_for_operation reset_controls; do
    command -v "$_fn" >/dev/null 2>&1 \
        || die "the harness loaded but $_fn is not defined - the app's libraries did not source correctly"
done

# Sourced inside an `if` so a case that returns non-zero is REPORTED rather than
# killing the runner. A bare `. "$casefile"` under set -e ends the whole run at
# that line with no FAIL printed and every later case silently skipped - the
# suite exits 1 having tested a fraction of what it claims. That is the failure
# mode this project has hit for real, and it is indistinguishable from a pass if
# nobody reads the exit code.
#
# The count is checked afterwards too, so a case that vanishes cannot go unnoticed.
ran=0
for casefile in Tests/cases/*.sh; do
    echo "== $casefile =="
    # Each case runs in a SUBSHELL, for isolation rather than error handling:
    # a case cannot leak a stray variable into the next one, and a harness that
    # calls `exit` (the deliberate response to a missing handler block) takes
    # down only its own case, which is then reported.
    #
    # This works because failures are counted in a FILE: a subshell's variables
    # die with it, but its appends to $FAILLOG do not.
    if ! ( . "$casefile" ); then
        fail "$casefile exited non-zero - it stopped early, so its later assertions never ran"
    fi
    ran=$((ran + 1))
done

expected=$(ls Tests/cases/*.sh 2>/dev/null | wc -l | tr -d ' ')
if [ "$ran" != "$expected" ]; then
    fail "only $ran of $expected case files ran"
fi
if [ "$ran" -eq 0 ]; then
    fail "no case files found in Tests/cases - the suite tested nothing"
fi

FAILURES=$(wc -l < "$FAILLOG" | tr -d ' ')
if [ "$FAILURES" -gt 0 ]; then
    echo "" >&2
    echo "$FAILURES test(s) failed. Details in $FAILDETAIL:" >&2
    sed 's/^/  /' "$FAILDETAIL" >&2
    exit 1
fi
echo "All tests passed. ($ran case files)"
