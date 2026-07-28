// make-fixtures.swift - generate the deterministic fixtures the test suite
// exercises. Adapted from pdfutil's own generator, with two additions this app
// needs and the CLI does not: a standalone IMAGE (the file list accepts images
// as well as PDFs, and Build PDF from Images consumes them) and a file that is
// NEITHER, so classify_file's third answer can be tested. Run with the Swift
// interpreter:
//
//     swift Tests/make-fixtures.swift Tests/fixtures
//
// Fixtures are gitignored; only this generator is committed. No dates or other
// nondeterministic content is written into the PDFs.

import Foundation
import PDFKit
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift make-fixtures.swift <outdir>\n".utf8))
    exit(2)
}
let outDir = URL(fileURLWithPath: args[1], isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func out(_ name: String) -> URL { outDir.appendingPathComponent(name) }

let letter = CGRect(x: 0, y: 0, width: 612, height: 792)

// Draw a single CoreText line at a baseline point.
func drawLine(_ ctx: CGContext, _ text: String, x: CGFloat, y: CGFloat, size: CGFloat) {
    let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
    let attributed = NSAttributedString(string: text, attributes: [.font: font])
    let line = CTLineCreateWithAttributedString(attributed)
    ctx.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(line, ctx)
}

// text.pdf - 5 pages, one marker + one sentence each; "needle" only on page 3.
do {
    var box = letter
    guard let ctx = CGContext(out("text.pdf") as CFURL, mediaBox: &box, nil) else {
        fatalError("cannot create text.pdf")
    }
    let sentences = [
        "The quick brown fox jumps over the lazy dog.",
        "Sphinx of black quartz, judge my vow.",
        "This page hides a needle in the haystack.",
        "Pack my box with five dozen liquor jugs.",
        "How vexingly quick daft zebras jump.",
    ]
    for p in 0..<5 {
        ctx.beginPDFPage(nil)
        drawLine(ctx, "PAGE-\(p + 1)-MARKER", x: 72, y: 700, size: 24)
        drawLine(ctx, sentences[p], x: 72, y: 650, size: 18)
        ctx.endPDFPage()
    }
    ctx.closePDF()
}

// rotated.pdf - text.pdf with every page rotated 90 degrees.
do {
    guard let doc = PDFDocument(url: out("text.pdf")) else { fatalError("reopen text.pdf") }
    for i in 0..<doc.pageCount { doc.page(at: i)?.rotation = 90 }
    doc.write(to: out("rotated.pdf"))
}

// image.pdf - 2 image-only pages (a simulated 200 dpi scan, no text layer).
do {
    func raster(_ text: String) -> CGImage {
        let width = 1700, height = 2200
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let bitmap = CGContext(data: nil, width: width, height: height,
                                     bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            fatalError("cannot create bitmap context")
        }
        bitmap.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
        drawLine(bitmap, text, x: 120, y: 2000, size: 64)
        guard let image = bitmap.makeImage() else { fatalError("makeImage failed") }
        return image
    }
    var box = letter
    guard let ctx = CGContext(out("image.pdf") as CFURL, mediaBox: &box, nil) else {
        fatalError("cannot create image.pdf")
    }
    for text in ["OCRTEST HELLO 12345", "SECOND PAGE SCAN"] {
        ctx.beginPDFPage(nil)
        ctx.draw(raster(text), in: letter)
        ctx.endPDFPage()
    }
    ctx.closePDF()
}

// outline.pdf - text.pdf with a three-chapter outline.
do {
    guard let doc = PDFDocument(url: out("text.pdf")) else { fatalError("reopen text.pdf") }
    let root = PDFOutline()
    doc.outlineRoot = root
    func chapter(_ label: String, page idx: Int) {
        let node = PDFOutline()
        node.label = label
        if let page = doc.page(at: idx) {
            node.destination = PDFDestination(page: page, at: CGPoint(x: 0, y: 792))
        }
        root.insertChild(node, at: root.numberOfChildren)
    }
    chapter("Chapter 1", page: 0)
    chapter("Chapter 2", page: 2)
    chapter("Chapter 3", page: 4)
    doc.write(to: out("outline.pdf"))
}

// form.pdf - one page with a text field ("name") and a checkbox ("agree").
do {
    let data = NSMutableData()
    guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
        fatalError("cannot create data consumer")
    }
    var box = letter
    guard let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else {
        fatalError("cannot create form base context")
    }
    ctx.beginPDFPage(nil)
    drawLine(ctx, "Form fixture", x: 72, y: 720, size: 18)
    ctx.endPDFPage()
    ctx.closePDF()

    guard let doc = PDFDocument(data: data as Data), let page = doc.page(at: 0) else {
        fatalError("cannot build form base document")
    }
    let name = PDFAnnotation(bounds: CGRect(x: 72, y: 600, width: 200, height: 24),
                             forType: .widget, withProperties: nil)
    name.widgetFieldType = .text
    name.fieldName = "name"
    page.addAnnotation(name)

    let agree = PDFAnnotation(bounds: CGRect(x: 72, y: 560, width: 24, height: 24),
                              forType: .widget, withProperties: nil)
    agree.widgetFieldType = .button
    agree.widgetControlType = .checkBoxControl
    agree.fieldName = "agree"
    page.addAnnotation(agree)

    doc.write(to: out("form.pdf"))
}

// form-filled.pdf - a one-page form with the "name" text field pre-filled
// ("Alice"), so the flatten test can confirm the value burns into the page.
do {
    let data = NSMutableData()
    guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
        fatalError("cannot create data consumer")
    }
    var box = letter
    guard let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else {
        fatalError("cannot create form base context")
    }
    ctx.beginPDFPage(nil)
    drawLine(ctx, "Filled form fixture", x: 72, y: 720, size: 18)
    ctx.endPDFPage()
    ctx.closePDF()

    guard let doc = PDFDocument(data: data as Data), let page = doc.page(at: 0) else {
        fatalError("cannot build filled-form base document")
    }
    let name = PDFAnnotation(bounds: CGRect(x: 72, y: 600, width: 200, height: 24),
                             forType: .widget, withProperties: nil)
    name.widgetFieldType = .text
    name.fieldName = "name"
    name.widgetStringValue = "Alice"
    page.addAnnotation(name)

    doc.write(to: out("form-filled.pdf"))
}

// locked.pdf - text.pdf saved with a user and owner password.
do {
    guard let doc = PDFDocument(url: out("text.pdf")) else { fatalError("reopen text.pdf") }
    doc.write(to: out("locked.pdf"),
              withOptions: [.userPasswordOption: "test", .ownerPasswordOption: "owner"])
}

// photo.png - a standalone image. The file list is mixed-type as of Stage 8, so
// classify_file has to recognise this as "image" and Build PDF from Images has
// to be able to consume it. Deliberately WIDER than reduce's 2400 px cap so a
// document assembled from it is one the cap actually acts on.
do {
    let width = 3000, height = 2000
    let space = CGColorSpaceCreateDeviceRGB()
    guard let bitmap = CGContext(data: nil, width: width, height: height,
                                 bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("cannot create bitmap context for photo.png")
    }
    // A gradient rather than flat colour: a uniform image compresses to almost
    // nothing, which would make every size assertion about it meaningless.
    for band in 0..<60 {
        let t = CGFloat(band) / 60.0
        bitmap.setFillColor(CGColor(red: t, green: 1 - t, blue: 0.5, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: CGFloat(band) * CGFloat(height) / 60.0,
                           width: CGFloat(width), height: CGFloat(height) / 60.0 + 1))
    }
    drawLine(bitmap, "PHOTO FIXTURE", x: 200, y: CGFloat(height) / 2, size: 200)
    guard let image = bitmap.makeImage() else { fatalError("makeImage failed for photo.png") }
    guard let dest = CGImageDestinationCreateWithURL(
            out("photo.png") as CFURL, "public.png" as CFString, 1, nil) else {
        fatalError("cannot create photo.png")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("cannot write photo.png") }
}

// notes.txt - neither a PDF nor an image. classify_file must call this "other",
// and every operation must reject it by name rather than handing it to pdfutil.
do {
    try? Data("This is not a PDF and not an image.\n".utf8).write(to: out("notes.txt"))
}

// mislabelled.pdf - a text file wearing a .pdf extension. classify_file sniffs
// the header rather than trusting the name, and this is what proves it.
do {
    try? Data("Still not a PDF, whatever the extension says.\n".utf8)
        .write(to: out("mislabelled.pdf"))
}

FileHandle.standardError.write(Data("fixtures written to \(outDir.path)\n".utf8))
