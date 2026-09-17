# PDFUtil
![PDFUtil Icon](Icon/PDF-macOS-256x256@1x.png)

A native macOS app for content and production work on PDFs: rasterize pages to images, OCR a scan, stamp a watermark, crop, split, merge, assemble a PDF from photos, pull text out, encrypt, and reduce file size. It is a GUI over the [pdfutil](https://github.com/abra-code/pdfutil) command-line tool, which is built on macOS's own PDF stack (PDFKit, Core Graphics, Vision). PDFUtil processes one file or a whole batch of files and folders in a single pass.

**Requires macOS 14.6 (Sonoma) or later.**

---

## Overview

PDFUtil presents a single window: pick an operation, adjust its settings, add PDFs or images (or drop folders, which are searched recursively), and press Save. A built-in Quick Look preview and an inspector let you look at any file in the list before processing it.

Where the result goes depends on the operation and on how many files are in the list. Anything that ends up as a single file gets a Save As dialog: one file in and one file out, and also Merge and Build PDF from Images, which collapse the whole list into one document. A batch of one-in-one-out results, or an operation that produces several files from one input, asks for a destination folder instead. No operation edits your input in place, and an existing file is never silently clobbered: results are either staged through a temporary file and moved into place, or written to a name that was probed to be free first.

---

## Requirements

| Requirement | Notes |
|---|---|
| macOS 14.6+ | Sonoma minimum |
| No external dependencies | The pdfutil engine is bundled in `Contents/Helpers/`; nothing to install |

---

## Operations

Nineteen operations, in the six groups the Operation menu uses.

### Size & Convert

| Operation | What it does |
|---|---|
| **Reduce File Size** | Recompress and downsample images through the macOS Quartz image filter. JPEG quality (default 85) and a DPI ceiling (default 150), plus an optional cap on the longest image edge, off by default. The DPI value is a ceiling, so images already below it are not downsampled and nothing is upscaled. Both toggles send their disabled value explicitly (`-r 0`, `-m 0`) rather than omitting the flag, because pdfutil's own defaults are 150 and 2400: an unchecked box that still capped would be lying. Reduce never grows a file, so when the rewrite comes out larger the original is kept byte for byte, structure included. |
| **Convert to Grayscale** | Convert every page to shades of gray using the system Gray Tone filter. |
| **Linearize (fast web view)** | Rewrite the file so a viewer can show the first page before the rest has downloaded. |
| **Convert to PDF/A** | Rewrite the document in archival form, embedding its fonts. Apple's writer does not verify conformance, so the app says so rather than claiming it. |

### Pages

| Operation | What it does |
|---|---|
| **Extract or Reorder** | Keep the listed pages in the listed order. Repeats and reordering both work. |
| **Delete Pages** | Remove a page range, keeping the rest of the document as it was. |
| **Rotate** | Rotate a page range by 90, 180, 270, or -90 degrees. Rotation is added to the page's current rotation, not set. |
| **Crop** | Change a page box (crop, media, art, bleed, or trim) either by insetting margins or by an absolute rectangle. |
| **Split** | Split into parts of N pages each, or one part per top-level outline chapter. |
| **Merge** | Join every PDF in the list into one document, in the list's order. New files are added at the end of the list, sorted by name among themselves, and the Up and Down buttons under the list move the selected file. |

### Content

| Operation | What it does |
|---|---|
| **Watermark** | Stamp text or an image with a position, rotation, and opacity, above or beneath the page content. Text-only annotation mode is offered as the structure-preserving alternative. |
| **Flatten** | Paint form fields and annotations into the page and remove the interactive objects. |
| **Edit Metadata** | Set Title, Author, Subject, Keywords, and Creator, or strip everything. A blank field leaves that attribute alone. |

### Security

| Operation | What it does |
|---|---|
| **Set Password** | Encrypt with a user and/or owner password, and choose what readers who open with the user password may do: printing, copying, changes, and page assembly. |
| **Remove Password** | Save an unlocked copy; the original is untouched. |

### Export

| Operation | What it does |
|---|---|
| **Export Page Images** | Rasterize pages to PNG, JPEG, TIFF, or HEIC at a chosen DPI, with an optional transparent background for the formats that support one. |
| **Extract Text** | Pull out an existing text layer, optionally separating pages with a form feed. |
| **OCR** | Recognize text with Vision and save it as a text file, or embed a searchable text layer in the PDF instead. The searchable mode is PDFKit's own OCR, a different engine, and the language, speed, DPI, and page-range settings do not apply to it: pdfutil refuses them rather than ignoring them, so the app grays those controls out and sends none of them. |

### Create

| Operation | What it does |
|---|---|
| **Build PDF from Images** | Turn every image in the list into a page, in the list's order. Page size is fitted to a standard paper size by default, or can be taken from each image's own DPI, or computed from a DPI you supply. An animated GIF or multi-page TIFF contributes one page per frame. |

Selecting a file and pressing the inspector button reports the file's details, `pdfutil info`, and the document outline when it has one.

---

## What survives, and what does not

Several pdfutil verbs redraw the document through a new PDF context. That is how they do their job, and it silently discards annotations, links, the outline, and form fields. The tool exits 0 either way, so nothing in the exit code tells you it happened. A user who watermarks a filled form and loses the form has been failed by the interface, not by the engine.

PDFUtil treats this as a first-class UI concern rather than a footnote:

- **Every operation panel carries a permanent notice.** For the operations that rewrite a PDF it says what is preserved and what is discarded; the rest say what that operation costs you or what it needs. It is always visible, not hidden in a tooltip.
- **Before a redraw operation runs**, the app checks whether your document actually has an outline or annotations to lose, and if it does, names them in an alert with Continue or Cancel. A document with nothing at risk is not interrupted.

The table below covers the seventeen operations that produce a PDF. It was checked against fixtures carrying an outline and form fields rather than taken on faith from the engine's help text, and it fills in the rows the help does not cover: `flatten` keeps the outline while removing the fields, and editing metadata leaves the document's structure alone.

| Operation | Structure |
|---|---|
| Reduce, Grayscale, Linearize, PDF/A | Redraws: annotations, links, outline, and form fields are lost |
| Watermark (burn-in) | Redraws; annotation mode preserves structure but is text-only |
| Build PDF from Images | Redraws any PDF in the list; use Merge to combine PDFs |
| Extract or Reorder | Page-level structure kept, outline not carried over |
| Delete Pages | Preserved; outline entries pointing at removed pages may dangle |
| Split, Merge | Page-level structure kept, outline not carried across parts or merged |
| Flatten | Outline kept; fields and annotations are painted in and removed by design |
| OCR (searchable) | Preserved |
| Rotate, Crop | Preserved: only page boxes and rotation change |
| Set Password, Remove Password, Edit Metadata | Preserved |

Two qualifications the table cannot carry in a cell:

- **Reduce is decided per file at run time.** When the rewrite would come out larger than the input, pdfutil discards it and keeps the original byte for byte, so the outline, annotations, and form fields survive. The pre-flight alert has to warn before knowing which way that will go, so it warns.
- **The row above is about page structure, not the Info dictionary.** No operation preserves Producer or the dates; see below.

Two behaviors inherited from PDFKit are worth knowing about, both measured rather than assumed:

- **Permission reporting is advisory.** Reading a file back, PDFKit's `accessPermissions` over-reports in both directions along the printing and changes axes: a file that denies high-resolution printing is reported as allowing it; one that allows only form filling or only page assembly is reported as allowing document changes; and one that allows changes while denying page assembly is reported as allowing assembly. Only the copying ladder reads back faithfully. The inspector shows what PDFKit says, so trust what you set in the Set Password panel over what you read back.
- **No operation preserves Producer or the dates.** PDFKit's writer resets them on every save, whatever you asked for. This is not specific to Edit Metadata; it applies to all seventeen operations that write a PDF, Rotate and Crop included. The one exception is a file Reduce declined to rewrite, which is returned untouched.

---

## Passwords

Passwords are confined to Set Password and Remove Password. No other operation takes one, and a password-protected PDF is refused up front with a message pointing at Remove Password, which unlocks it once. Making every operation carry a password field would mean re-entering a secret for every run and every batch, and putting it in the argv of verbs that have no stdin form.

pdfutil accepts at most one password on stdin, so the app spends that slot where it matters most: on Set Password it goes to the user password, or to the owner password when that is the only one entered, and on Remove Password to the single password. Those stay out of the argument list. An owner password entered alongside a user password has to take the inline flag, where `ps` can read it for the life of the call. Narrowing the exposure is the honest claim here, not eliminating it.

Three limits are the format's or the engine's, not the app's, and the Set Password panel states them rather than letting you discover them later:

- **128-bit AES (R4) is the ceiling.** For AES-256, use [QuickPDF](https://github.com/abra-code/QuickPDFApp).
- **Passwords must be ASCII**, and only their first 32 characters are stored by the R4 handler. The app checks for non-ASCII before asking you where to save, because the raw failure names no cause.
- **A password you cannot open the document with is unrecoverable**, so both password fields are typed twice and a mismatch refuses to run. Remove Password needs no confirmation, since it is checked against the file.

Permission flags are implication ladders rather than eight independent switches: `high-quality-printing` implies `printing`, `copying` implies `accessibility`, and `changes` implies `commenting` implies `forms`. The UI is therefore three menus and a toggle, which express every combination the engine can write, instead of eight checkboxes whose combinations collapse onto each other. The ladders belong to the engine, not to the app, so a handful of sets the format allows in principle, copying without accessibility extraction among them, are unreachable from either.

---

## PDFUtil or QuickPDF

[QuickPDF](https://github.com/abra-code/QuickPDFApp) is a sibling app built on [qpdf](https://github.com/qpdf/qpdf), which it bundles alongside the same pdfutil helper used here. It is not the same tool with a different name, and neither app subsumes the other.

**Reach for PDFUtil when the job is about content:** turning pages into images, OCR, stamping a text or image watermark with a position, rotation and opacity, cropping, assembling a PDF from photos, or extracting text. None of these have a qpdf equivalent QuickPDF exposes.

**Reach for QuickPDF when the job is structural:** AES-256 encryption, repairing a damaged file, lossless structural size reduction, correct linearization, or any size reduction that has to keep annotations and forms intact. PDFUtil cannot do these; its size-reducing operations all redraw.

The two apps deliberately overlap on one verb. qpdf cannot downsample images and skips the ICC and JPEG colorspaces that dominate scans, so QuickPDF bundles this same pdfutil binary and calls `reduce` for its image stage, with the same quality and DPI defaults. Either app will shrink a scan. QuickPDF then follows it with a structure-preserving qpdf pass, which PDFUtil has no equivalent of; PDFUtil in exchange exposes the edge cap and grayscale conversion, which QuickPDF does not.

---

## Bundled Helper

| Helper | Location | Purpose |
|---|---|---|
| [pdfutil](https://github.com/abra-code/pdfutil) | `Contents/Helpers/pdfutil` | Every operation in the app is a pdfutil verb; the bundle without it does nothing at all |

pdfutil links only OS-provided libraries, so embedding is a plain copy plus a codesign: no bundled dylibs and no `@rpath` fix-ups. The universal binary is roughly a megabyte, because it links the system PDF stack instead of vendoring its own. The flip side is that its behavior is tied to the OS, since PDFKit and Vision determine what it can do.

The binary is not committed to the repository (`Contents/Helpers/` is gitignored). `update_pdfutil.sh` builds it universal, deploys it into the bundle, and re-signs the app:

```bash
./update_pdfutil.sh                        # build, deploy, ad-hoc sign
./update_pdfutil.sh --skip-build           # reuse the already-deployed binary
./update_pdfutil.sh --identity="Developer ID Application: ..."
```

pdfutil is built from a sibling `../pdfutil` checkout (the script offers to clone it if missing) with its own `build.sh` (plain `swiftc`, system frameworks only). Point elsewhere with `--pdfutil-repo=PATH` or `$PDFUTIL_REPO`. See `./update_pdfutil.sh --help` for all options.

---

## Tests

There are two suites, split by what they test rather than by how they run.

```bash
appletbuilder test PDFUtil.app                  # the applet
./test.sh                                       # the embedded engine
PDFUTIL_APP=/Applications/PDFUtil.app ./test.sh # the engine in an installed bundle
```

**The applet - `appletbuilder test PDFUtil.app`.** Runs `Tests/*.test.sh` under OMC's omctest harness, which dispatches the real handlers against a mock window and records what they did to it. This is where the window, the file list, the Save button's routing, the runners, and the argument builder are tested. Every section starts from the control defaults declared in `PDFUtil.json`, so what the code sees is what a user's window holds.

**The engine - `./test.sh`.** Runs `Tests/cases/*.sh` against the embedded binary: that it is present, universal, signed, and self-contained, that every verb and flag the app emits exists, and the handful of pdfutil behaviors the app is deliberately built around. No case file may source a `lib.PDFUtil.*` library, and the runner fails if one does; anything that needs to know what the *app* would do belongs in the omctest suite.

The helper is **required** - it is the subject of `./test.sh`, so a missing binary is a hard error rather than a skip. Run `./update_pdfutil.sh` first on a fresh checkout, since `Contents/Helpers/` is gitignored. Fixtures are generated on first run by `Tests/make-fixtures.swift` (needs `swift`) and are gitignored; only the generator is committed. Both suites share them.

| Case | What it covers |
|---|---|
| `helpers.sh` | The binary is present, universal, self-contained (it links system libraries only), and signed, and every verb and flag the app emits exists. |
| `output-shapes.sh` | The output shapes the app has to compensate for: `render`'s two meanings for `-o` (a filename prefix for several pages, a literal path with no extension appended for exactly one), the three distinct page geometries `frompages` produces, and `reduce` declining to grow a file. |
| `password-handling.sh` | The stdin password forms, and what an empty or wrong password does. |

---

## Architecture

PDFUtil is an OMC 5.1 applet. The OMC framework handles the app lifecycle, the operation window, file and folder dialogs, drag-and-drop, and Quick Look. The UI is defined declaratively in `PDFUtil.json` (and `PDFUtilQuickLook.json` for the preview window) in ActionUI format. All business logic runs as shell scripts in `Contents/Resources/Scripts/`.

The Operation menu swaps a stack of per-operation `GroupBox` panels, one per operation, showing exactly one at a time. Command routing is declared in `Contents/Resources/Command.json`.

The library is split by concern:

| Library | Holds |
|---|---|
| `lib.PDFUtil.sh` | Control-ID constants, runtime tool paths, and the primitives used across unrelated areas: `classify_file`, the cached `pdfutil info` reader, and the locked-document check |
| `lib.PDFUtil.args.sh` | `build_pdfutil_args`, which translates the current UI state into a command line |
| `lib.PDFUtil.files.sh` | The file list: folder expansion, dedupe, and the table bridge |
| `lib.PDFUtil.panels.sh` | Panel switching and the structure-notice table |
| `lib.PDFUtil.run.sh` | Running the engine and staging its output |

Two invariants are asserted in code rather than left to habit, because getting either wrong destroys user data:

- **Every invocation that writes a file passes `-o`,** and refuses to run without a non-empty output path. pdfutil edits its input in place when `-o` is omitted, which would overwrite the user's original with no confirmation. There are three writing call sites (the shared runner plus the two that collapse the whole list into one document) and the check lives in each.
- **Every invocation that writes a file passes `--force`**, because those runners stage output through `mktemp`, which pre-creates the file that pdfutil would otherwise refuse to overwrite.

The read-only calls pass neither, because they produce no file: the inspector, the summary pane, the pre-flight's `info` probes, and the version check at launch.

Because the output type varies by operation (PDF, images, text, or a PDF built from images), the Save button does not run anything itself. `PDFUtil.start.batch` validates the list and the settings, runs the structure pre-flight, and then chains to whichever runner matches the operation's output shape and the number of inputs.

---

## Building and Signing

The app bundle runs as-is once the helper binary is in place. After changing scripts, UI JSON, or the helper, re-sign the bundle so the signature stays valid:

```bash
./codesign_applet.sh PDFUtil.app -                                  # ad-hoc (local use)
./codesign_applet.sh PDFUtil.app "Developer ID Application: ..."    # for distribution
```

Developer ID signing enables the hardened runtime and a timestamp; for distribution the app should then be notarized with `xcrun notarytool`.

---

## License

PDFUtil is licensed under the Apache License 2.0 - see [LICENSE](LICENSE).

The bundled [pdfutil](https://github.com/abra-code/pdfutil) helper is distributed under the Apache License 2.0; its license text ships beside the binary at `Contents/Helpers/pdfutil.LICENSE`. pdfutil links only system frameworks, so there are no statically linked third-party libraries to attribute.
