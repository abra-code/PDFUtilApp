# render-naming.sh - output naming, including the literal-path trap.
#
# render has two output modes and only one of them is a file. With several pages
# selected, -o is a PREFIX and pdfutil writes <prefix>-001.<ext>; with a single
# page it is a LITERAL PATH and pdfutil appends NOTHING. So the app has to supply
# the extension itself, and jpeg is the odd one out - it produces .jpg.

expect_eq ".png"  "$(render_suffix png)"   "png suffix"
expect_eq ".jpg"  "$(render_suffix jpeg)"  "jpeg produces .jpg, not .jpeg"
expect_eq ".tiff" "$(render_suffix tiff)"  "tiff suffix"
expect_eq ".heic" "$(render_suffix heic)"  "heic suffix"
expect_eq ".png"  "$(render_suffix nonsense)" "an unknown format falls back to png"

# The single-page form really does append nothing - the reason the above exists.
expect_ok "$PDFUTIL" render -p 1 --dpi 36 --force -o "$TMP/literal" "$FIX/text.pdf"
[ -f "$TMP/literal" ] || fail "render -p 1 did not write the literal path it was given"
if [ -f "$TMP/literal.png" ]; then
    fail "render -p 1 appended an extension after all - the naming workaround is now wrong"
fi

# ...and the multi-page form appends -001, so a Save As panel cannot express it.
expect_ok "$PDFUTIL" render -p 1-2 --dpi 36 --force -o "$TMP/multi" "$FIX/text.pdf"
[ -f "$TMP/multi-001.png" ] || fail "render -p 1-2 did not use the -001 prefix form"

# --- ensure_output_extension supplies what pdfutil will not -----------------
reset_controls
PDFUTIL_OUTPUT_KIND="pdf"
expect_eq "$TMP/x.pdf" "$(ensure_output_extension "$TMP/x.pdf")" "a .pdf name is left alone"
contains "$(ensure_output_extension "$TMP/noext")" ".pdf" \
    || fail "a pdf output with no extension should gain .pdf"
expect_eq "$TMP/X.PDF" "$(ensure_output_extension "$TMP/X.PDF")" "an uppercase .PDF counts"

# merged and assembled are PDFs too. Omitting them wrote a valid PDF with no
# suffix whenever the user typed over the Save panel's default name.
for kind in merged assembled; do
    PDFUTIL_OUTPUT_KIND="$kind"
    contains "$(ensure_output_extension "$TMP/typed-over")" ".pdf" \
        || fail "output kind '$kind' did not gain a .pdf extension"
done

PDFUTIL_OUTPUT_KIND="text"
contains "$(ensure_output_extension "$TMP/notes")" ".txt" \
    || fail "a text output should gain .txt"

# Images take their suffix from the format picker, so the answer changes with a
# control rather than being fixed per kind.
PDFUTIL_OUTPUT_KIND="images"
reset_controls; PDFUTIL_OUTPUT_KIND="images"; OMC_ACTIONUI_VIEW_170_VALUE=jpeg
contains "$(ensure_output_extension "$TMP/pic")" ".jpg" \
    || fail "a jpeg render should produce .jpg"
reset_controls; PDFUTIL_OUTPUT_KIND="images"; OMC_ACTIONUI_VIEW_170_VALUE=png
contains "$(ensure_output_extension "$TMP/pic")" ".png" \
    || fail "a png render should produce .png"
# The stem's existing image extension is replaced, not appended to, or a name
# typed as "Page.png" for a jpeg render becomes "Page.png.jpg".
reset_controls; PDFUTIL_OUTPUT_KIND="images"; OMC_ACTIONUI_VIEW_170_VALUE=jpeg
res="$(ensure_output_extension "$TMP/Page.png")"
if contains "$res" ".png.jpg"; then fail "image extension was doubled: $res"; fi

# --- unique_path never hands back a name that already exists ---------------
# The Save panel confirmed an overwrite for the name the user SAW. When the app
# changes that name, the confirmation no longer covers it.
: > "$TMP/taken.pdf"
u="$(unique_path "$TMP/taken.pdf")"
[ "$u" != "$TMP/taken.pdf" ] || fail "unique_path returned a path that already exists"
[ ! -e "$u" ] || fail "unique_path returned another existing path: $u"
expect_eq "$TMP/free.pdf" "$(unique_path "$TMP/free.pdf")" "an unused path is returned unchanged"
