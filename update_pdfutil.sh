#!/bin/bash
# update_pdfutil.sh
# Build PDFUtil's embedded command-line helper and re-sign the applet.
#
# One helper lives in PDFUtil.app/Contents/Helpers:
#   * pdfutil - built by its sibling repo's build.sh (plain swiftc, system
#               frameworks only, universal by default). Every operation in the
#               app is a pdfutil verb, so this binary IS the application's
#               engine; the bundle without it does nothing at all.
#
# There is no static dependency chain to compile - no zlib, libjpeg, OpenSSL -
# which is what makes this substantially shorter than QuickPDF's equivalent.
# pdfutil builds in seconds, so it is rebuilt every run unless --skip-build.
#
# Built UNIVERSAL (arm64 + x86_64) to match the app, so nothing is thinned.
# Codesigning is delegated to codesign_applet.sh.
#
# The .app bundle is auto-detected from this script's directory.

set -uo pipefail

GREEN=$(printf '\033[92m'); RED=$(printf '\033[91m'); YELLOW=$(printf '\033[93m'); RESET=$(printf '\033[0m')

SIGNING_IDENTITY="-"
DO_BUILD="yes"
DO_CODESIGN="yes"

SCRIPT_DIR="$(cd "$(/usr/bin/dirname "$0")" >/dev/null 2>&1 && pwd)"
PDFUTIL_REPO="${PDFUTIL_REPO:-}"

while [ $# -gt 0 ]; do
    case "$1" in
        --pdfutil-repo=*) PDFUTIL_REPO="${1#*=}" ;;
        --skip-build) DO_BUILD="no" ;;
        --identity=*) SIGNING_IDENTITY="${1#*=}" ;;
        --no-codesign) DO_CODESIGN="no" ;;
        --help)
            echo "Usage: $0 [--pdfutil-repo=PATH] [--skip-build] [--identity=CERT] [--no-codesign]"
            echo
            echo "  --pdfutil-repo=PATH  pdfutil source repo (default: sibling ../pdfutil, or \$PDFUTIL_REPO)"
            echo "  --skip-build         reuse the already-deployed pdfutil binary"
            echo "  --identity=CERT      codesign identity passed to codesign_applet.sh ('-' = ad-hoc, default)"
            echo "  --no-codesign        skip the codesign_applet.sh step"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

fail() { echo "${RED}$*${RESET}" >&2; exit 1; }

# The pdfutil repo is missing: offer to git-clone it into the sibling location and
# continue. Interactive runs only - without a TTY (CI, piped stdin) this declines
# silently and the caller's fail() fires with the manual instructions.
# $1 = repo URL, $2 = destination dir.
offer_clone() {
    [ -t 0 ] || return 1
    printf "%s  %s not found. Clone %s\n  into %s now? [y/N] %s" \
        "$YELLOW" "$(/usr/bin/basename "$2")" "$1" "$2" "$RESET"
    IFS= read -r _ans
    case "$_ans" in [yY]|[yY][eE][sS]) ;; *) return 1 ;; esac
    /usr/bin/git clone "$1" "$2"
}

# Auto-detect the single .app bundle beside this script.
APP_BUNDLE=""
for _c in "$SCRIPT_DIR"/*.app; do [ -d "$_c" ] && { APP_BUNDLE="$_c"; break; }; done
[ -n "$APP_BUNDLE" ] || fail "No .app bundle found in $SCRIPT_DIR"
HELPERS_DIR="$APP_BUNDLE/Contents/Helpers"
RES_DIR="$APP_BUNDLE/Contents/Resources"

# Locate the pdfutil repo: env/flag override, then sibling dir, offering to clone
# it there when missing (only when a build is requested - --skip-build reuses the
# already-deployed binary).
#
# Kept relative to this script rather than absolute: this repo is intended to be
# public, so no path containing a username may be committed.
if [ -z "$PDFUTIL_REPO" ]; then
    for _cand in "$SCRIPT_DIR/../pdfutil"; do
        [ -f "$_cand/build.sh" ] && [ -d "$_cand/Sources" ] && { PDFUTIL_REPO="$(cd "$_cand" && pwd)"; break; }
    done
fi
if [ -z "$PDFUTIL_REPO" ] && [ "$DO_BUILD" = "yes" ]; then
    offer_clone "https://github.com/abra-code/pdfutil" "$(cd "$SCRIPT_DIR/.." && pwd)/pdfutil" \
        && [ -f "$SCRIPT_DIR/../pdfutil/build.sh" ] \
        && PDFUTIL_REPO="$(cd "$SCRIPT_DIR/../pdfutil" && pwd)"
fi

echo
echo "==== Updating $(basename "$APP_BUNDLE") (universal) ===="
echo "  pdfutil  : ${PDFUTIL_REPO:-<not located>}$([ "$DO_BUILD" = "no" ] && echo " (skipped - reusing embedded)")"
echo "  deploy to: $HELPERS_DIR"
echo

# --- 1. Build + embed the pdfutil helper ----------------------------------
# build.sh with no arg produces a universal (arm64 + x86_64) binary at
# build/pdfutil, ad-hoc signed. Copy it into Helpers with its LICENSE.
if [ "$DO_BUILD" = "yes" ]; then
    [ -n "$PDFUTIL_REPO" ] || fail "pdfutil repo not found (looked for build.sh + Sources); clone github.com/abra-code/pdfutil beside this repo or pass --pdfutil-repo=PATH"
    # Checked here as well as during auto-detection, because an explicit
    # --pdfutil-repo= skips that path entirely: without this a typo produced a
    # raw "cd: no such file" from the subshell before the real message.
    [ -f "$PDFUTIL_REPO/build.sh" ] || fail "no build.sh in $PDFUTIL_REPO - that does not look like a pdfutil checkout"
    ( cd "$PDFUTIL_REPO" && ./build.sh ) || fail "pdfutil build.sh failed"
    _built="$PDFUTIL_REPO/build/pdfutil"
    [ -x "$_built" ] || fail "pdfutil build produced no binary at $_built"
    # Confirm the fresh build really is universal before shipping it. A binary
    # thinned to the build machine's own arch runs fine here and fails on every
    # other Mac, which is the worst possible time to find out.
    _archs="$(/usr/bin/lipo -archs "$_built" 2>/dev/null)"
    case " $_archs " in
        *" arm64 "*) case " $_archs " in *" x86_64 "*) ;; *) fail "pdfutil is not universal (archs: $_archs)" ;; esac ;;
        *) fail "pdfutil is not universal (archs: $_archs)" ;;
    esac
    /bin/mkdir -p "$HELPERS_DIR" || fail "Could not create $HELPERS_DIR"
    /bin/cp -f "$_built" "$HELPERS_DIR/pdfutil" || fail "Could not copy pdfutil"
    /bin/chmod +x "$HELPERS_DIR/pdfutil"
    if [ -f "$PDFUTIL_REPO/LICENSE" ]; then
        /bin/cp -f "$PDFUTIL_REPO/LICENSE" "$HELPERS_DIR/pdfutil.LICENSE"
        /bin/rm -f "$RES_DIR/pdfutil.LICENSE"   # retire any copy left in Resources by older builds
    fi
    echo "  ${GREEN}Built${RESET} pdfutil (universal: $_archs)"
fi
[ -x "$HELPERS_DIR/pdfutil" ] || fail "No pdfutil at $HELPERS_DIR/pdfutil (build first, or drop --skip-build)."

# Sweep Finder droppings out of Helpers before signing.
/usr/bin/find "$HELPERS_DIR" -name ".DS_Store" -delete 2>/dev/null

# --- 2. Codesign ----------------------------------------------------------
# codesign_applet.sh is the sole signer and auto-discovers OMCApplet.entitlements
# beside the bundle.
#
# Contents/Helpers is a NESTED-CODE location, so codesign treats every loose file
# there - pdfutil.LICENSE included - as a subcomponent that must carry its own
# signature before the app can seal. The vendored codesign_applet.sh handles that
# in its phase 1 (loose non-Mach-O files in nested locations), so this script does
# NOT pre-sign anything itself. DEVELOPMENT-PLAN.md 11.2 still describes the
# pre-signing this script would once have needed; that instruction is obsolete.
if [ "$DO_CODESIGN" = "yes" ]; then
    [ -x "$SCRIPT_DIR/codesign_applet.sh" ] || fail "codesign_applet.sh not found beside this script"
    "$SCRIPT_DIR/codesign_applet.sh" "$APP_BUNDLE" "$SIGNING_IDENTITY" \
        || fail "codesign_applet.sh failed"
fi

# --- 3. Verify ------------------------------------------------------------
# Everything below runs the SIGNED, EMBEDDED binary, so it proves the thing the
# app will actually launch - not the thing that was built a moment ago.
PDFUTIL_BIN="$HELPERS_DIR/pdfutil"

# --version prints "pdfutil <ver>" and exits 0; that proves the binary loads
# (system frameworks linked, signature intact). Match the output, not just the
# exit code - a binary killed by the kernel for a bad signature also "exits".
if "$PDFUTIL_BIN" --version 2>/dev/null | /usr/bin/grep -q "^pdfutil "; then
    echo "  ${GREEN}Verify OK${RESET}: pdfutil launches ($("$PDFUTIL_BIN" --version 2>/dev/null))"
else
    fail "pdfutil did not report its version - build/link/sign failure."
fi

# Every verb the app can invoke. The app is a front end for these and nothing
# else, so a missing one is a dead menu entry rather than a degraded feature.
# Derived from the PDFUTIL_VERB assignments in Scripts/lib.PDFUtil.args.sh plus
# the direct calls in the runners; keep in step when an operation is added.
_missing=""
for _verb in crop decrypt encrypt flatten forms frompages info merge metadata \
             ocr outline pages reduce render rotate search split text watermark; do
    "$PDFUTIL_BIN" "$_verb" --help >/dev/null 2>&1 || _missing="$_missing $_verb"
done
[ -z "$_missing" ] || fail "pdfutil is missing verbs the app calls:$_missing - wrong or old build?"
echo "  ${GREEN}Verify OK${RESET}: all 19 verbs the app calls are present"

# Capability spot-checks: flags the app EMITS that older pdfutil builds do not
# accept. A verb existing is not enough - an embedded binary predating one of
# these makes the operation fail at runtime with "unknown option", which is
# exactly how a stale helper hid here before. Each entry is a real dependency in
# Scripts/lib.PDFUtil.args.sh, so add to this list when the app starts emitting a
# newly added flag.
_check_flag() {   # $1 = verb, $2 = flag, $3 = why the app needs it
    if "$PDFUTIL_BIN" "$1" --help 2>&1 | /usr/bin/grep -q -- "$2"; then
        return 0
    fi
    fail "embedded pdfutil's '$1' does not accept $2 ($3) - the helper predates it; rebuild without --skip-build."
}
_check_flag frompages --page-size "Build PDF from Images fits each image to a paper size"
_check_flag reduce    --max-edge  "Reduce caps the longest image edge, which is what makes its JPEG quality take effect"
_check_flag metadata  --strip     "Edit Metadata's Remove all metadata switch"
_check_flag search    --count     "Inspect counts matches so zero-match files say so"
echo "  ${GREEN}Verify OK${RESET}: the flags the app emits are all accepted"

echo
echo "  ${GREEN}Done.${RESET} $(basename "$APP_BUNDLE") is ready."
echo
