# helpers.sh - the embedded binary is present, universal, signed, and complete.
#
# Everything else in this suite assumes the helper works. If it does not, dozens
# of cases fail with confusing symptoms, so check the foundation first and say so
# plainly.

expect_grep "^pdfutil " "$PDFUTIL" --version

# Universal, or the app runs on this Mac and fails on the other kind.
archs="$(/usr/bin/lipo -archs "$PDFUTIL" 2>/dev/null)"
contains "$archs" "arm64"  || fail "embedded pdfutil is missing the arm64 slice (archs: $archs)"
contains "$archs" "x86_64" || fail "embedded pdfutil is missing the x86_64 slice (archs: $archs)"

# Signed. Contents/Helpers is a nested-code location, so an unsigned helper stops
# the whole bundle sealing rather than just failing on its own.
expect_ok /usr/bin/codesign --verify --strict "$PDFUTIL"

# Self-contained: only OS-provided libraries. A dependency dylib would have to be
# embedded and rpath-fixed, and the design's whole "embedding is a plain copy"
# claim would be wrong.
# otool on a universal binary interleaves per-architecture header lines ending in
# ":", so match the dependency lines positively (indented, a path, a version in
# parentheses) rather than trying to exclude everything that is not one.
nonsystem="$(/usr/bin/otool -L "$PDFUTIL" \
    | grep -E '^[[:space:]]+/.*\(compatibility version' \
    | grep -vE '^[[:space:]]+(/usr/lib/|/System/Library/)' || true)"
if [ -n "$nonsystem" ]; then
    fail "embedded pdfutil links a non-system library - embedding is no longer a plain copy: $nonsystem"
fi

# Every verb the app can invoke. Derived from the PDFUTIL_VERB assignments in
# lib.PDFUtil.args.sh plus the direct calls in the runners; a missing one is a
# dead menu entry, not a degraded feature.
for verb in crop decrypt encrypt flatten forms frompages info linearize merge \
            metadata ocr outline pages pdfa reduce render rotate search split \
            text watermark; do
    expect_ok "$PDFUTIL" "$verb" --help
done

# Flags the app EMITS that older builds do not accept. A verb existing is not
# enough: the bundle once shipped a helper that had `frompages` but not
# `--page-size`, and the operation failed at runtime with "unknown option".
expect_grep "--page-size" "$PDFUTIL" frompages --help
expect_grep "--max-edge"  "$PDFUTIL" reduce --help
expect_grep "--strip"     "$PDFUTIL" metadata --help
expect_grep "--count"     "$PDFUTIL" search --help
expect_grep "--searchable" "$PDFUTIL" ocr --help
expect_grep "--annotation" "$PDFUTIL" watermark --help
