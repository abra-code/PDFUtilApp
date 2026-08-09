#!/bin/bash
# test.sh - engine tests for the pdfutil binary this app embeds.
#
# This suite covers the binary: that it is present, universal, signed and
# self-contained, that every verb and flag the app emits exists, and the handful
# of pdfutil behaviors the applet is deliberately built around - render's two
# meanings for -o, frompages fitting to the page rather than the image, reduce
# declining to grow a file, and how passwords are accepted and refused.
#
# It does NOT test the applet. Everything that was once here about the argument
# builder, the router, file classification, the structure pre-flight and output
# naming now lives in the omctest suite (Tests/*.test.sh, run by
# `appletbuilder test PDFUtil.app`), which dispatches the real handlers against a
# real window instead of sourcing the libraries and calling functions. That
# suite can do things this one structurally could not: run a handler, see what
# the window ended up showing, and check the ORDER of the refusals.
#
# The dividing line is enforced below rather than left to habit: no case file
# here may source the applet's libraries. A case that needs to know what the app
# would do with a value is an omctest case.
#
# The scope split is worth stating once. Whether `pdfa` really emits conformant
# PDF/A-2B is pdfutil's own question and pdfutil's own suite answers it. Whether
# THIS bundle ships a pdfutil that can be invoked the way the app invokes it is
# this suite's question, and nothing else asks it.
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

FIX="Tests/fixtures"
TMP="Tests/tmp"

# The embedded binary is the SUBJECT of these tests, not a convenience, so a
# missing one is a hard error and never a silent skip. A suite that quietly tests
# nothing is worse than one that fails.
missing=""
[ -x "$PDFUTIL" ] || missing="$missing\n  pdfutil: $PDFUTIL"
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

# Return 0 when "$1" contains "$2". A function rather than an inline `case`
# because a case pattern's ")" terminates a $( ) command substitution in bash
# 3.2, which is a parse error rather than a wrong answer.
contains() {
    case "$1" in
        *"$2"*) return 0 ;;
        *) return 1 ;;
    esac
}

# For a case file's own SETUP steps - a mkdir, writing a fixture - as opposed to
# the thing under test. Without `set -e` those run unchecked, and the negative
# helpers are the ones that then lie: expect_fail and expect_nogrep both pass
# when a command produces no output, which is exactly what happens when its
# input was never created. A failed setup would be reported as a passing
# assertion.
#
# Use as `require mkdir -p "$D" || return` - the `|| return` abandons the rest
# of the case, which is the honest response to setup that did not happen, and
# the subshell in the case loop keeps that contained.
require() {
    if ! "$@"; then
        fail "setup failed: $*"
        return 1
    fi
}

# The dividing line between this suite and the omctest one, enforced rather than
# documented. A case that sources a lib.PDFUtil.* library is testing the applet,
# and the applet is tested by `appletbuilder test PDFUtil.app` against a real
# window - where the control defaults are the ones PDFUtil.json declares,
# instead of whatever the case happened to export.
#
# Checked by asking whether the libraries' functions are DEFINED after the case
# ran, not by grepping for a source line. A grep only catches the spellings it
# was written for - the shape these cases historically used was `. "$LIB"`,
# naming a variable rather than the file, which a pattern looking for
# "lib.PDFUtil." on the source line misses entirely. Asking the shell what got
# defined cannot be out-spelled.
#
# It is a signpost for the next person adding a case, not a sandbox.
sourced_the_applet() {
    command -v build_pdfutil_args >/dev/null 2>&1 \
        || command -v classify_file >/dev/null 2>&1
}

# Sourced inside an `if` so a case that returns non-zero is REPORTED rather than
# killing the runner. A bare `. "$casefile"` under set -e ends the whole run at
# that line with no FAIL printed and every later case silently skipped - the
# suite exits 1 having tested a fraction of what it claims. That is the failure
# mode this project has hit for real, and it is indistinguishable from a pass if
# nobody reads the exit code.
#
# The count is checked afterwards too, so a case that vanishes cannot go unnoticed.
LEAKED="$TMP/.case-sourced-applet"
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
    #
    # The applet-library guard runs INSIDE that subshell, which is the only
    # place the definitions exist - they die with it, which is exactly why a
    # check after the fact would always find nothing.
    rm -f "$LEAKED"
    if ! ( . "$casefile"; sourced_the_applet && : > "$LEAKED"; true ); then
        fail "$casefile exited non-zero - it stopped early, so its later assertions never ran"
    fi
    if [ -e "$LEAKED" ]; then
        fail "$casefile sources the applet's libraries - applet logic belongs in the omctest suite (Tests/*.test.sh)"
    fi
    ran=$((ran + 1))
done
rm -f "$LEAKED"

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
