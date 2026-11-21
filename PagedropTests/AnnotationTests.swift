import AppKit
import PagedropCore
import PDFKit
import Testing

@Suite("Annotations")
struct AnnotationTests {
    @Test("Ink annotations contain the stroke")
    func inkAnnotation() throws {
        let points = [CGPoint(x: 10, y: 10), CGPoint(x: 40, y: 30), CGPoint(x: 60, y: 20)]

        let ink = try #require(AnnotationFactory.ink(through: points))

        #expect(ink.type == "Ink")
        #expect(ink.bounds.contains(CGPoint(x: 40, y: 30)))
        #expect(ink.bounds.minX <= 10)
        #expect(ink.paths?.count == 1)
    }

    @Test("An empty stroke produces nothing")
    func emptyInk() {
        #expect(AnnotationFactory.ink(through: []) == nil)
    }

    @Test("Notes keep their text and fit inside the page")
    func noteAnnotation() throws {
        let page = try #require(TestPDF.make(pageCount: 1).page(at: 0))

        let note = AnnotationFactory.note("Check this", at: CGPoint(x: 20, y: 80))
        page.addAnnotation(note)

        #expect(note.contents == "Check this")
        #expect(note.type == "FreeText")
        #expect(page.annotations.count == 1)
        #expect(note.bounds.maxY <= 80)
    }

    @Test("Annotations survive saving")
    func annotationsArePersisted() throws {
        let document = TestPDF.make(pageCount: 1)
        let page = try #require(document.page(at: 0))
        page.addAnnotation(AnnotationFactory.note("Hello", at: CGPoint(x: 10, y: 90)))

        let data = try #require(document.dataRepresentation())
        let reloaded = try #require(PDFDocument(data: data))

        #expect(reloaded.page(at: 0)?.annotations.first?.contents == "Hello")
    }
}
