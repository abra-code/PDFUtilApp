# passwords.sh - passwords reach pdfutil on stdin, never in the argument list.
#
# A password in argv is visible to every process on the machine via `ps`. pdfutil
# offers --password-stdin forms for exactly this reason, and the app uses them
# everywhere. This case asserts the secret is absent from the command line, that
# the round trip actually works, and that the documented usage errors are refused
# before a destination is ever asked for.

reset_controls

# --- the secret is not in argv --------------------------------------------
OMC_ACTIONUI_VIEW_110_VALUE="hunter2"
OMC_ACTIONUI_VIEW_111_VALUE="hunter2"
joined="$(args_for encrypt)"
if contains "$joined" "hunter2"; then
    fail "the user password appears in the pdfutil argument list: $joined"
fi
contains "$joined" "stdin" || fail "encrypt should use a -stdin password form: $joined"

reset_controls
OMC_ACTIONUI_VIEW_122_VALUE="hunter2"
joined="$(args_for decrypt)"
if contains "$joined" "hunter2"; then
    fail "the decrypt password appears in the pdfutil argument list: $joined"
fi

# Only ONE password can come from stdin, so a run that sets both must not ask for
# two - pdfutil exits 1 on that.
reset_controls
OMC_ACTIONUI_VIEW_110_VALUE="userpw"; OMC_ACTIONUI_VIEW_111_VALUE="userpw"
OMC_ACTIONUI_VIEW_120_VALUE="ownerpw"; OMC_ACTIONUI_VIEW_121_VALUE="ownerpw"
joined="$(args_for encrypt)"
stdin_count="$(printf '%s\n' $joined | grep -c -- '-stdin' || true)"
[ "$stdin_count" -le 1 ] || fail "encrypt asked for more than one stdin password: $joined"

# --- the round trip works against the real binary --------------------------
reset_controls
OMC_ACTIONUI_VIEW_110_VALUE="s3cret"; OMC_ACTIONUI_VIEW_111_VALUE="s3cret"
build_pdfutil_args encrypt >/dev/null 2>&1
# Assigned on its own line, not as a `VAR=x run_pdfutil ...` prefix: the prefix
# form did not reach the function here, and a silently-unset password produces a
# plausible-looking run that encrypts nothing.
PDFUTIL_STDIN_PW="s3cret"
run_pdfutil "$FIX/text.pdf" "$TMP/enc.pdf" >/dev/null 2>&1
unset PDFUTIL_STDIN_PW
[ -f "$TMP/enc.pdf" ] || fail "encrypt produced no output"

# info REFUSES an encrypted document without a password, which is itself the
# proof that the encryption took. Asserting "encrypted: true" on the unprotected
# call would have passed vacuously - it never gets that far.
expect_grep_all "password-protected" "$PDFUTIL" info "$TMP/enc.pdf"
expect_grep_all "encrypted: true" "$PDFUTIL" info --password s3cret "$TMP/enc.pdf"

# ...and the content really needs the password.
expect_code 2 "$PDFUTIL" text "$TMP/enc.pdf"
expect_grep "PAGE-3-MARKER" "$PDFUTIL" text --password s3cret "$TMP/enc.pdf"

reset_controls
OMC_ACTIONUI_VIEW_122_VALUE="s3cret"
build_pdfutil_args decrypt >/dev/null 2>&1
PDFUTIL_STDIN_PW="s3cret"
run_pdfutil "$TMP/enc.pdf" "$TMP/dec.pdf" >/dev/null 2>&1
unset PDFUTIL_STDIN_PW
expect_grep_all "encrypted: false" "$PDFUTIL" info "$TMP/dec.pdf"

# --- the documented usage errors are refused in the UI, not by pdfutil -----
# An empty password is a usage error (exit 1), not a blank password, so the panel
# must catch it before a Save panel is shown.
load_handler_locals PDFUtil.start.batch.sh

reset_controls
[ -n "$(settings_problem decrypt)" ] || fail "an empty decrypt password should be refused"
reset_controls; OMC_ACTIONUI_VIEW_122_VALUE="pw"
expect_eq "" "$(settings_problem decrypt)" "a supplied decrypt password is fine"

# Set Password confirms each password twice; a mismatch must be caught here
# rather than after the user has named an output file.
reset_controls
OMC_ACTIONUI_VIEW_110_VALUE="one"; OMC_ACTIONUI_VIEW_111_VALUE="two"
[ -n "$(settings_problem encrypt)" ] || fail "mismatched user passwords should be refused"
reset_controls
OMC_ACTIONUI_VIEW_110_VALUE="same"; OMC_ACTIONUI_VIEW_111_VALUE="same"
expect_eq "" "$(settings_problem encrypt)" "matching passwords are fine"

# Encrypting with no password at all is refused too - it would produce a document
# with no protection while telling the user it was protected.
reset_controls
[ -n "$(settings_problem encrypt)" ] || fail "encrypt with no password at all should be refused"

# pdfutil really does treat an empty STDIN password as a usage error, which is
# the premise the check above rests on. The app uses the stdin form everywhere,
# so that is the form asserted; --password "" is a different code path and fails
# as a processing error (exit 2, wrong password) rather than a usage one.
printf '' | "$PDFUTIL" decrypt --password-stdin -o "$TMP/x.pdf" --force "$FIX/locked.pdf" >/dev/null 2>&1
expect_eq "1" "$?" "an empty stdin password is a usage error"
expect_code 2 "$PDFUTIL" decrypt --password "" -o "$TMP/x2.pdf" --force "$FIX/locked.pdf"
