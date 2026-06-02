import Testing
import Foundation
@testable import dulcinea

struct OPDSTests {

    // MARK: - OPDSEntry Tests

    @Test func downloadLink_findsEpubLink() {
        let entry = OPDSEntry(
            id: "1",
            title: "Test Book",
            summary: nil,
            authors: [],
            published: nil,
            updated: Date(),
            links: [
                OPDSLink(href: "/cover.jpg", type: "image/jpeg", rel: "http://opds-spec.org/image", title: nil),
                OPDSLink(href: "/book.epub", type: "application/epub+zip", rel: "http://opds-spec.org/acquisition", title: nil),
                OPDSLink(href: "/next", type: "application/atom+xml", rel: "next", title: nil)
            ],
            categories: nil
        )

        let downloadLink = entry.downloadLink

        #expect(downloadLink != nil)
        #expect(downloadLink?.href == "/book.epub")
    }

    @Test func downloadLink_returnsNil_whenNoEpubLink() {
        let entry = OPDSEntry(
            id: "1",
            title: "Test Book",
            summary: nil,
            authors: [],
            published: nil,
            updated: Date(),
            links: [
                OPDSLink(href: "/cover.jpg", type: "image/jpeg", rel: "http://opds-spec.org/image", title: nil)
            ],
            categories: nil
        )

        #expect(entry.downloadLink == nil)
    }

    @Test func coverImageLink_findsImageLink() {
        let entry = OPDSEntry(
            id: "1",
            title: "Test Book",
            summary: nil,
            authors: [],
            published: nil,
            updated: Date(),
            links: [
                OPDSLink(href: "/cover.jpg", type: "image/jpeg", rel: "http://opds-spec.org/image", title: nil),
                OPDSLink(href: "/book.epub", type: "application/epub+zip", rel: "http://opds-spec.org/acquisition", title: nil)
            ],
            categories: nil
        )

        let coverLink = entry.coverImageLink

        #expect(coverLink != nil)
        #expect(coverLink?.href == "/cover.jpg")
    }

    @Test func coverImageLink_findsThumbnailLink() {
        let entry = OPDSEntry(
            id: "1",
            title: "Test Book",
            summary: nil,
            authors: [],
            published: nil,
            updated: Date(),
            links: [
                OPDSLink(href: "/thumb.jpg", type: "image/jpeg", rel: "http://opds-spec.org/image/thumbnail", title: nil)
            ],
            categories: nil
        )

        let coverLink = entry.coverImageLink

        #expect(coverLink != nil)
        #expect(coverLink?.href == "/thumb.jpg")
    }

    @Test func authorNames_joinsMultipleAuthors() {
        let entry = OPDSEntry(
            id: "1",
            title: "Test Book",
            summary: nil,
            authors: [
                OPDSAuthor(name: "Alice Smith", uri: nil),
                OPDSAuthor(name: "Bob Jones", uri: nil)
            ],
            published: nil,
            updated: Date(),
            links: [],
            categories: nil
        )

        #expect(entry.authorNames == "Alice Smith, Bob Jones")
    }

    @Test func authorNames_singleAuthor() {
        let entry = OPDSEntry(
            id: "1",
            title: "Test Book",
            summary: nil,
            authors: [OPDSAuthor(name: "Alice Smith", uri: nil)],
            published: nil,
            updated: Date(),
            links: [],
            categories: nil
        )

        #expect(entry.authorNames == "Alice Smith")
    }

    @Test func authorNames_emptyWhenNoAuthors() {
        let entry = OPDSEntry(
            id: "1",
            title: "Test Book",
            summary: nil,
            authors: [],
            published: nil,
            updated: Date(),
            links: [],
            categories: nil
        )

        #expect(entry.authorNames == "")
    }

    // MARK: - OPDSLink Tests

    @Test func isAcquisition_trueForAcquisitionRel() {
        let link = OPDSLink(
            href: "/book.epub",
            type: "application/epub+zip",
            rel: "http://opds-spec.org/acquisition/open-access",
            title: nil
        )

        #expect(link.isAcquisition == true)
    }

    @Test func isAcquisition_falseForOtherRel() {
        let link = OPDSLink(
            href: "/next",
            type: "application/atom+xml",
            rel: "next",
            title: nil
        )

        #expect(link.isAcquisition == false)
    }

    @Test func isNavigation_trueForAtomXml() {
        let link = OPDSLink(
            href: "/catalog/fiction",
            type: "application/atom+xml;profile=opds-catalog",
            rel: "subsection",
            title: "Fiction"
        )

        #expect(link.isNavigation == true)
    }

    @Test func isNavigation_falseForEpub() {
        let link = OPDSLink(
            href: "/book.epub",
            type: "application/epub+zip",
            rel: "http://opds-spec.org/acquisition",
            title: nil
        )

        #expect(link.isNavigation == false)
    }

    // MARK: - OPDSCatalog Tests

    @Test func catalog_newInitGeneratesUUID() {
        let catalog1 = OPDSCatalog(name: "Test", url: "https://example.com")
        let catalog2 = OPDSCatalog(name: "Test", url: "https://example.com")

        #expect(catalog1.id != catalog2.id)
    }

    @Test func catalog_initWithIdPreservesUUID() {
        let originalId = UUID()
        let catalog = OPDSCatalog(
            id: originalId,
            name: "Test",
            url: "https://example.com",
            isEnabled: false,
            lastUpdated: Date()
        )

        #expect(catalog.id == originalId)
        #expect(catalog.isEnabled == false)
    }

    @Test func catalog_requiresAuthentication_trueWhenCredentialsSet() {
        let catalog = OPDSCatalog(
            name: "Private",
            url: "https://example.com",
            username: "user",
            password: "pass"
        )

        #expect(catalog.requiresAuthentication == true)
    }

    @Test func catalog_requiresAuthentication_falseWhenNoCredentials() {
        let catalog = OPDSCatalog(name: "Public", url: "https://example.com")

        #expect(catalog.requiresAuthentication == false)
    }

    @Test func catalog_requiresAuthentication_falseWhenOnlyUsername() {
        let catalog = OPDSCatalog(
            name: "Partial",
            url: "https://example.com",
            username: "user",
            password: nil
        )

        #expect(catalog.requiresAuthentication == false)
    }
}
