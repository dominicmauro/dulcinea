import UIKit
import CoreText

struct PaginatedChapter {
    let chapterIndex: Int
    let pages: [PageContent]
}

struct PageContent: Identifiable {
    let id = UUID()
    let chapterIndex: Int
    let pageIndexInChapter: Int
    let text: String
    let range: NSRange
}

class TextPaginator {

    /// Paginates a chapter's text into screen-sized pages using Core Text.
    func paginate(
        text: String,
        title: String,
        pageSize: CGSize,
        fontSize: Double,
        fontFamily: FontFamily,
        lineSpacing: Double,
        chapterIndex: Int
    ) -> PaginatedChapter {
        let titleFont = resolveUIFont(family: fontFamily, size: fontSize + 4, weight: .semibold)
        let bodyFont = resolveUIFont(family: fontFamily, size: fontSize, weight: .regular)

        let bodyParagraphStyle = NSMutableParagraphStyle()
        bodyParagraphStyle.lineSpacing = lineSpacing * fontSize * 0.2

        let titleParagraphStyle = NSMutableParagraphStyle()
        titleParagraphStyle.lineSpacing = lineSpacing * fontSize * 0.2
        titleParagraphStyle.paragraphSpacing = 20

        let fullString = NSMutableAttributedString()

        // Title on the first page
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .paragraphStyle: titleParagraphStyle
        ]
        fullString.append(NSAttributedString(string: title + "\n", attributes: titleAttrs))

        // Body text
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .paragraphStyle: bodyParagraphStyle
        ]
        fullString.append(NSAttributedString(string: text, attributes: bodyAttrs))

        // Use CTFramesetter to split into pages
        let framesetter = CTFramesetterCreateWithAttributedString(fullString as CFAttributedString)

        var pages: [PageContent] = []
        var currentIndex = 0
        let totalLength = fullString.length
        var pageIndex = 0

        while currentIndex < totalLength {
            let path = CGPath(rect: CGRect(origin: .zero, size: pageSize), transform: nil)
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRangeMake(currentIndex, 0),
                path,
                nil
            )

            let visibleRange = CTFrameGetVisibleStringRange(frame)

            guard visibleRange.length > 0 else {
                break
            }

            let nsRange = NSRange(location: visibleRange.location, length: visibleRange.length)
            let pageText = (fullString.string as NSString).substring(with: nsRange)

            pages.append(PageContent(
                chapterIndex: chapterIndex,
                pageIndexInChapter: pageIndex,
                text: pageText,
                range: nsRange
            ))

            currentIndex = visibleRange.location + visibleRange.length
            pageIndex += 1
        }

        if pages.isEmpty {
            pages.append(PageContent(
                chapterIndex: chapterIndex,
                pageIndexInChapter: 0,
                text: title,
                range: NSRange(location: 0, length: 0)
            ))
        }

        return PaginatedChapter(chapterIndex: chapterIndex, pages: pages)
    }

    private func resolveUIFont(family: FontFamily, size: Double, weight: UIFont.Weight) -> UIFont {
        switch family {
        case .systemDefault:
            return UIFont.systemFont(ofSize: size, weight: weight)
        default:
            if let font = UIFont(name: family.fontName, size: size) {
                return font
            }
            return UIFont.systemFont(ofSize: size, weight: weight)
        }
    }
}
