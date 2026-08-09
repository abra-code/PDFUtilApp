# output-shapes.sh - what pdfutil does with -o, and what it decides on its own.
#
# Three behaviors of the binary that the applet is built around. Each one is the
# reason a piece of code exists, so each one is pinned here: if pdfutil's
# behavior changes, the workaround becomes wrong and this is where that shows up
# rather than in a user's file.

O="$TMP/shapes"
require mkdir -p "$O" || return

# --- render's -o means two different things --------------------------------
#
# With ONE page selected, -o is a literal path and pdfutil appends nothing - so
# the app has to supply the extension itself, and jpeg is the odd one out
# because it produces .jpg. With several pages it is a PREFIX and pdfutil writes
# <prefix>-001.<ext>, which no Save As panel can express, which is why render
# routes to a folder chooser instead.
expect_ok "$PDFUTIL" render -p 1 --dpi 36 --force -o "$O/literal" "$FIX/text.pdf"
[ -f "$O/literal" ] || fail "render -p 1 did not write the literal path it was given"
if [ -f "$O/literal.png" ]; then
    fail "render -p 1 appended an extension after all - the app's naming workaround is now wrong"
fi

expect_ok "$PDFUTIL" render -p 1-2 --dpi 36 --force -o "$O/multi" "$FIX/text.pdf"
[ -f "$O/multi-001.png" ] || fail "render -p 1-2 did not use the -001 prefix form"

# --- frompages has three page geometries, and they are all different -------
#
# The app offers a three-way picker for this and must send --page-size for one
# mode, --dpi for another, and NOTHING for the third - pdfutil refuses the pair,
# so the absence of both flags is how "as large as the image says" is expressed.
# A mode that produced the same page as another would make that picker a lie, so
# all three are measured rather than only the default.
page_geometry() { # <pdf> -> e.g. 792x612
    "$PDFUTIL" info "$1" 2>&1 \
        | /usr/bin/awk '/^page 1: / { print $3; exit }'
}

# No flag: the page is as large as the image says it is. The fixture is 3000 px
# wide, so this is the mode the other two exist to avoid.
expect_ok "$PDFUTIL" frompages --force -o "$O/assembled-image.pdf" "$FIX/photo.png"
expect_eq "3000x2000" "$(page_geometry "$O/assembled-image.pdf")" "frompages with no sizing flag"

# --page-size fits the image to the named paper, and ORIENTS the page to the
# image: the fixture is landscape, so letter here means 792x612. Asserting
# 612x792 would be asserting a bug.
expect_ok "$PDFUTIL" frompages --page-size letter --force -o "$O/assembled.pdf" "$FIX/photo.png"
expect_eq "792x612" "$(page_geometry "$O/assembled.pdf")" "frompages --page-size letter"

# --dpi sizes the page from the image's pixel count instead.
expect_ok "$PDFUTIL" frompages --dpi 300 --force -o "$O/assembled-dpi.pdf" "$FIX/photo.png"
expect_eq "720x480" "$(page_geometry "$O/assembled-dpi.pdf")" "frompages --dpi 300"

# --- reduce never hands back something bigger ------------------------------
#
# The assembled fixture is a smooth gradient stored as Flate, already close to
# optimal - JPEG does not beat it, so reduce declines and returns the original.
# That is the guard working, not a failure, and the app's Optimize fallback
# logic in QuickPDF depends on it being observable as "not smaller".
expect_ok "$PDFUTIL" reduce --force -o "$O/assembled-small.pdf" "$O/assembled.pdf"
before=$(wc -c < "$O/assembled.pdf")
after=$(wc -c < "$O/assembled-small.pdf")
[ "$after" -le "$before" ] || fail "reduce returned a LARGER file ($before -> $after)"

# ...and on a document it can genuinely improve, it does. image.pdf is a real
# raster scan, which is the case reduce exists for. Without this half, the
# assertion above would still pass for a reduce that had stopped working.
expect_ok "$PDFUTIL" reduce --force -o "$O/scan-small.pdf" "$FIX/image.pdf"
sbefore=$(wc -c < "$FIX/image.pdf")
safter=$(wc -c < "$O/scan-small.pdf")
[ "$safter" -lt "$sbefore" ] || fail "reduce did not shrink a raster scan ($sbefore -> $safter)"
