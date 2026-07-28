# classify.sh - classify_file decides what each list entry IS.
#
# Stage 8 made the file list mixed-type, so this answer drives per-operation
# validation: PDFs for nearly everything, images for Build PDF from Images, and
# "other" for anything that is neither. Getting it wrong means handing pdfutil a
# file it will reject in words that describe the file rather than the choice.

expect_eq "pdf"   "$(classify_file "$FIX/text.pdf")"    "a real PDF"
expect_eq "pdf"   "$(classify_file "$FIX/image.pdf")"   "an image-only PDF is still a PDF"
expect_eq "pdf"   "$(classify_file "$FIX/locked.pdf")"  "an encrypted PDF is still a PDF"
expect_eq "image" "$(classify_file "$FIX/photo.png")"   "a PNG"
expect_eq "other" "$(classify_file "$FIX/notes.txt")"   "a text file is neither"

# The header decides, not the extension. A .pdf that is not one must not be
# classified as a PDF, or the run fails inside pdfutil instead of in validation.
expect_eq "other" "$(classify_file "$FIX/mislabelled.pdf")" "a text file named .pdf"

# A path that does not exist classifies as something, rather than emitting
# nothing and making the caller's arithmetic collapse.
[ -n "$(classify_file "$FIX/does-not-exist.pdf")" ] \
    || fail "classify_file returned empty for a missing file"

# Paths with spaces survive - the file list is full of them in practice.
cp "$FIX/text.pdf" "$TMP/a file with spaces.pdf"
expect_eq "pdf" "$(classify_file "$TMP/a file with spaces.pdf")" "a path containing spaces"
