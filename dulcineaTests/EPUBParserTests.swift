import Testing
import Foundation
@testable import dulcinea

struct EPUBParserTests {

    // MARK: - NavParserDelegate Tests (EPUB3 NAV)

    @Test func navParser_parsesSimpleTOC() {
        let navXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
        <head><title>Navigation</title></head>
        <body>
        <nav epub:type="toc">
            <ol>
                <li><a href="chapter1.xhtml">Chapter 1</a></li>
                <li><a href="chapter2.xhtml">Chapter 2</a></li>
                <li><a href="chapter3.xhtml">Chapter 3</a></li>
            </ol>
        </nav>
        </body>
        </html>
        """

        let entries = parseNav(navXML)

        #expect(entries.count == 3)
        #expect(entries[0].title == "Chapter 1")
        #expect(entries[1].title == "Chapter 2")
        #expect(entries[2].title == "Chapter 3")
    }

    @Test func navParser_parsesNestedTOC() {
        let navXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
        <body>
        <nav epub:type="toc">
            <ol>
                <li>
                    <a href="part1.xhtml">Part 1</a>
                    <ol>
                        <li><a href="ch1.xhtml">Chapter 1</a></li>
                        <li><a href="ch2.xhtml">Chapter 2</a></li>
                    </ol>
                </li>
                <li><a href="part2.xhtml">Part 2</a></li>
            </ol>
        </nav>
        </body>
        </html>
        """

        let entries = parseNav(navXML)

        #expect(entries.count == 2)
        #expect(entries[0].title == "Part 1")
        #expect(entries[0].children.count == 2)
        #expect(entries[0].children[0].title == "Chapter 1")
        #expect(entries[0].children[1].title == "Chapter 2")
        #expect(entries[1].title == "Part 2")
    }

    @Test func navParser_ignoresNonTocNav() {
        let navXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
        <body>
        <nav epub:type="landmarks">
            <ol>
                <li><a href="cover.xhtml">Cover</a></li>
            </ol>
        </nav>
        <nav epub:type="toc">
            <ol>
                <li><a href="chapter1.xhtml">Chapter 1</a></li>
            </ol>
        </nav>
        </body>
        </html>
        """

        let entries = parseNav(navXML)

        #expect(entries.count == 1)
        #expect(entries[0].title == "Chapter 1")
    }

    @Test func navParser_handlesEmptyNav() {
        let navXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <body>
        <nav epub:type="toc">
            <ol></ol>
        </nav>
        </body>
        </html>
        """

        let entries = parseNav(navXML)

        #expect(entries.isEmpty)
    }

    @Test func navParser_trimsWhitespace() {
        let navXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
        <body>
        <nav epub:type="toc">
            <ol>
                <li><a href="ch1.xhtml">
                    Chapter 1: Introduction
                </a></li>
            </ol>
        </nav>
        </body>
        </html>
        """

        let entries = parseNav(navXML)

        #expect(entries.count == 1)
        #expect(entries[0].title == "Chapter 1: Introduction")
    }

    // MARK: - NCXParserDelegate Tests (EPUB2 NCX)

    @Test func ncxParser_parsesNavPoints() {
        let ncxXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
        <navMap>
            <navPoint id="np1" playOrder="1">
                <navLabel><text>Chapter 1</text></navLabel>
                <content src="chapter1.xhtml"/>
            </navPoint>
            <navPoint id="np2" playOrder="2">
                <navLabel><text>Chapter 2</text></navLabel>
                <content src="chapter2.xhtml"/>
            </navPoint>
        </navMap>
        </ncx>
        """

        let entries = parseNCX(ncxXML)

        #expect(entries.count == 2)
        #expect(entries[0].title == "Chapter 1")
        #expect(entries[1].title == "Chapter 2")
    }

    @Test func ncxParser_handlesEmptyNCX() {
        let ncxXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
        <navMap>
        </navMap>
        </ncx>
        """

        let entries = parseNCX(ncxXML)

        #expect(entries.isEmpty)
    }

    // MARK: - ContainerParserDelegate Tests

    @Test func containerParser_findsOPFPath() {
        let containerXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
            <rootfiles>
                <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
            </rootfiles>
        </container>
        """

        let opfPath = parseContainer(containerXML)

        #expect(opfPath == "OEBPS/content.opf")
    }

    @Test func containerParser_handlesAlternatePath() {
        let containerXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
            <rootfiles>
                <rootfile full-path="package.opf" media-type="application/oebps-package+xml"/>
            </rootfiles>
        </container>
        """

        let opfPath = parseContainer(containerXML)

        #expect(opfPath == "package.opf")
    }

    // MARK: - OPFParserDelegate Tests

    @Test func opfParser_extractsMetadata() {
        let opfXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
            <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:title>Test Book Title</dc:title>
                <dc:creator>Test Author</dc:creator>
                <dc:identifier>isbn:1234567890</dc:identifier>
                <dc:language>en</dc:language>
                <dc:publisher>Test Publisher</dc:publisher>
            </metadata>
            <manifest>
                <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
            </manifest>
            <spine>
                <itemref idref="ch1"/>
            </spine>
        </package>
        """

        let (metadata, manifest, spine) = parseOPF(opfXML)

        #expect(metadata.title == "Test Book Title")
        #expect(metadata.author == "Test Author")
        #expect(metadata.identifier == "isbn:1234567890")
        #expect(metadata.language == "en")
        #expect(metadata.publisher == "Test Publisher")
        #expect(manifest["ch1"] != nil)
        #expect(spine.contains("ch1"))
    }

    @Test func opfParser_extractsManifestWithProperties() {
        let opfXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
            <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:title>Test</dc:title>
            </metadata>
            <manifest>
                <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
                <item id="cover" href="cover.jpg" media-type="image/jpeg" properties="cover-image"/>
            </manifest>
            <spine></spine>
        </package>
        """

        let (_, manifest, _) = parseOPF(opfXML)

        #expect(manifest["nav"]?.properties?.contains("nav") == true)
        #expect(manifest["cover"]?.properties?.contains("cover-image") == true)
    }

    // MARK: - Helper Functions

    private func parseNav(_ xml: String) -> [TOCEntry] {
        guard let data = xml.data(using: .utf8) else { return [] }
        let parser = XMLParser(data: data)
        let delegate = NavParserDelegate()
        parser.delegate = delegate
        parser.parse()
        return delegate.tocEntries
    }

    private func parseNCX(_ xml: String) -> [TOCEntry] {
        guard let data = xml.data(using: .utf8) else { return [] }
        let parser = XMLParser(data: data)
        let delegate = NCXParserDelegate()
        parser.delegate = delegate
        parser.parse()
        return delegate.tocEntries
    }

    private func parseContainer(_ xml: String) -> String? {
        guard let data = xml.data(using: .utf8) else { return nil }
        let parser = XMLParser(data: data)
        let delegate = ContainerParserDelegate()
        parser.delegate = delegate
        parser.parse()
        return delegate.opfPath
    }

    private func parseOPF(_ xml: String) -> (EPUBMetadata, [String: ManifestItem], [String]) {
        guard let data = xml.data(using: .utf8) else {
            return (EPUBMetadata(title: "", author: "", identifier: "", language: "", publisher: nil, publishDate: nil, description: nil, coverImagePath: nil), [:], [])
        }
        let parser = XMLParser(data: data)
        let delegate = OPFParserDelegate()
        parser.delegate = delegate
        parser.parse()
        return (delegate.metadata, delegate.manifest, delegate.spine)
    }
}
