# password-handling.sh - how pdfutil itself treats passwords.
#
# The applet never puts a password in the argument list; it uses the
# --password-stdin forms everywhere, because argv is visible to every process on
# the machine through `ps`. That the app does so is asserted in its omctest
# suite. What is asserted HERE is the binary's own side of the arrangement: that
# the stdin forms work, that an empty one is a usage error rather than a blank
# password, and that a document really is unreadable without the key.
#
# Those are the premises the app's validation is built on. An empty decrypt
# password is refused in the panel precisely because pdfutil treats it as a
# usage error, and if that ever changed the refusal would be arbitrary.

E="$TMP/pw"
require mkdir -p "$E" || return

# A protected document, made by the binary rather than through the app.
enc="$E/encrypted.pdf"
printf 's3cret' | expect_ok "$PDFUTIL" encrypt --user-password-stdin -o "$enc" --force "$FIX/text.pdf"
[ -s "$enc" ] || { fail "could not produce an encrypted fixture - the rest of this case would test nothing"; return; }

# --- the document really is protected --------------------------------------
#
# `info` refusing without a password is itself the proof that encryption took.
# Asserting "encrypted: true" on the unprotected call would pass vacuously: it
# never gets that far.
expect_grep_all "password-protected" "$PDFUTIL" info "$enc"
expect_grep_all "encrypted: true"    "$PDFUTIL" info --password s3cret "$enc"

# ...and the content needs the key, not just the metadata.
expect_code 2 "$PDFUTIL" text "$enc"
expect_grep "PAGE-3-MARKER" "$PDFUTIL" text --password s3cret "$enc"

# --- the stdin forms round-trip --------------------------------------------
dec="$E/decrypted.pdf"
printf 's3cret' | expect_ok "$PDFUTIL" decrypt --password-stdin -o "$dec" --force "$enc"
expect_grep_all "encrypted: false" "$PDFUTIL" info "$dec"
expect_grep "PAGE-3-MARKER" "$PDFUTIL" text "$dec"

# --- an empty password is a usage error, not a blank password --------------
#
# This is the whole reason the panel refuses an empty field before showing a
# Save dialog. The app uses the stdin form everywhere, so that is the form
# pinned here; --password "" is a different code path and fails as a processing
# error (exit 2, wrong password) rather than a usage one. Both are asserted, so
# neither can be mistaken for the other.
printf '' | "$PDFUTIL" decrypt --password-stdin -o "$E/x.pdf" --force "$FIX/locked.pdf" >/dev/null 2>&1
expect_eq "1" "$?" "an empty stdin password is a usage error"
expect_code 2 "$PDFUTIL" decrypt --password "" -o "$E/x2.pdf" --force "$FIX/locked.pdf"

# A wrong password is a processing error too, and distinguishable from both.
expect_code 2 "$PDFUTIL" text --password definitelywrong "$enc"
