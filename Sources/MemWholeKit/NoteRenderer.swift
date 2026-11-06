import AppKit
import Markdown

/// A note's markdown as styled text, with where each search match landed in it.
public struct RenderedNote {
  public let text: NSAttributedString
  public let matches: [NSRange]
}

public enum NoteRenderer {
  private struct BlockContext {
    var indent: CGFloat = 0
    var marker: String?
    var spacing: CGFloat = 16
    var isQuote = false
  }

  private struct InlineStyle {
    var font: NSFont
    var isBold = false
    var isItalic = false
    var isCode = false
    var isStruck = false
    var isSecondary = false
    var link: URL?
  }

  private static let listIndent: CGFloat = 24
  private static let lineSpacing: CGFloat = 7.5
  private static let webSchemes: Set<String> = ["http", "https", "mailto"]

  /// Renders `source`, turning the text between `marks` into matches.
  public static func render(_ source: String, marks: (open: String, close: String)) -> RenderedNote {
    let document = Document(parsing: withoutFrontmatter(source), options: .disableSmartOpts)
    let output = NSMutableAttributedString()
    blocks(document.children, context: BlockContext(), marks: marks, into: output)
    if output.string.hasSuffix("\n") { output.deleteCharacters(in: NSRange(location: output.length - 1, length: 1)) }
    return RenderedNote(text: output, matches: extractMatches(from: output, marks: marks))
  }

  private static func withoutFrontmatter(_ source: String) -> String {
    let lines = source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else { return source }
    return lines[(end + 1)...].joined(separator: "\n")
  }

  private static func extractMatches(from output: NSMutableAttributedString, marks: (open: String, close: String)) -> [NSRange] {
    var matches: [NSRange] = []
    var open = output.mutableString.range(of: marks.open, options: .literal)

    while open.location != NSNotFound {
      output.deleteCharacters(in: open)
      let rest = NSRange(location: open.location, length: output.length - open.location)
      let close = output.mutableString.range(of: marks.close, options: .literal, range: rest)
      let end = close.location == NSNotFound ? output.length : close.location
      if close.location != NSNotFound { output.deleteCharacters(in: close) }
      if end > open.location { matches.append(NSRange(location: open.location, length: end - open.location)) }
      open = output.mutableString.range(of: marks.open, options: .literal)
    }

    return matches
  }

  // MARK: - Blocks

  private static func blocks(_ children: some Sequence<Markup>, context: BlockContext, marks: (open: String, close: String), into output: NSMutableAttributedString) {
    var context = context

    for child in children {
      block(child, context: context, marks: marks, into: output)
      context.marker = nil
    }
  }

  private static func block(_ markup: Markup, context: BlockContext, marks: (open: String, close: String), into output: NSMutableAttributedString) {
    switch markup {
    case let heading as Heading:
      let sizes: [CGFloat] = [20, 18, 16]
      let font = NSFont.systemFont(ofSize: sizes[min(heading.level, sizes.count) - 1])
      paragraph(heading.children, style: InlineStyle(font: font, isBold: true), context: context, spacingBefore: 12, into: output)
    case is Markdown.Paragraph:
      paragraph(markup.children, style: InlineStyle(font: bodyFont, isSecondary: context.isQuote), context: context, into: output)
    case let code as CodeBlock:
      codeBlock(code.code, context: context, into: output)
    case let table as Markdown.Table:
      codeBlock(tableText(table, marks: marks), context: context, into: output)
    case let list as UnorderedList:
      listItems(list.listItems.map { ($0, $0.checkbox.map(checkboxMarker) ?? "\u{2022}") }, context: context, marks: marks, into: output)
    case let list as OrderedList:
      let items = list.listItems.enumerated().map { offset, item in (item, "\(Int(list.startIndex) + offset).") }
      listItems(items, context: context, marks: marks, into: output)
    case is BlockQuote:
      var quote = context
      quote.indent += 16
      quote.isQuote = true
      blocks(markup.children, context: quote, marks: marks, into: output)
    case is ThematicBreak:
      rule(context: context, into: output)
    case let html as HTMLBlock:
      codeBlock(html.rawHTML, context: context, into: output)
    default:
      blocks(markup.children, context: context, marks: marks, into: output)
    }
  }

  private static func checkboxMarker(_ checkbox: Checkbox) -> String {
    checkbox == .checked ? "\u{2611}" : "\u{2610}"
  }

  private static func listItems(_ items: [(item: ListItem, marker: String)], context: BlockContext, marks: (open: String, close: String), into output: NSMutableAttributedString) {
    for (offset, entry) in items.enumerated() {
      var item = context
      item.indent += listIndent
      item.marker = entry.marker
      if offset < items.count - 1 { item.spacing = 6 }
      blocks(entry.item.children, context: item, marks: marks, into: output)
    }
  }

  private static func paragraph(_ children: some Sequence<Markup>, style: InlineStyle, context: BlockContext, spacingBefore: CGFloat = 0, into output: NSMutableAttributedString) {
    let start = output.length
    let layout = NSMutableParagraphStyle()
    layout.headIndent = context.indent
    layout.firstLineHeadIndent = context.indent
    layout.paragraphSpacing = context.spacing
    layout.paragraphSpacingBefore = spacingBefore
    layout.lineSpacing = lineSpacing

    if let marker = context.marker {
      layout.firstLineHeadIndent = context.indent - listIndent
      layout.tabStops = [NSTextTab(textAlignment: .left, location: context.indent)]
      output.append(NSAttributedString(string: marker + "\t", attributes: attributes(style)))
    }

    inlines(children, style: style, into: output)
    output.append(NSAttributedString(string: "\n", attributes: attributes(style)))
    output.addAttribute(.paragraphStyle, value: layout, range: NSRange(location: start, length: output.length - start))
  }

  /// A one-cell table, the only text block that holds several paragraphs together.
  private static func cell(context: BlockContext) -> NSTextTableBlock {
    let table = NSTextTable()
    table.numberOfColumns = 1
    let cell = NSTextTableBlock(table: table, startingRow: 0, rowSpan: 1, startingColumn: 0, columnSpan: 1)
    cell.setWidth(context.spacing, type: .absoluteValueType, for: .margin, edge: .maxY)
    cell.setWidth(context.indent, type: .absoluteValueType, for: .margin, edge: .minX)
    return cell
  }

  /// Code, tables and raw HTML: monospaced lines on a shaded panel.
  private static func codeBlock(_ code: String, context: BlockContext, into output: NSMutableAttributedString) {
    let panel = cell(context: context)
    panel.backgroundColor = .quaternarySystemFill
    panel.setWidth(8, type: .absoluteValueType, for: .padding)
    let layout = NSMutableParagraphStyle()
    layout.textBlocks = [panel]
    layout.lineSpacing = 4
    let text = code.hasSuffix("\n") ? code : code + "\n"
    output.append(NSAttributedString(string: text, attributes: [.font: codeFont(size: bodyFont.pointSize), .foregroundColor: NSColor.labelColor, .paragraphStyle: layout]))
  }

  private static func tableText(_ table: Markdown.Table, marks: (open: String, close: String)) -> String {
    let rows = [Array(table.head.cells)] + table.body.rows.map { Array($0.cells) }
    let cells = rows.map { row in row.map(\.plainText) }
    let visibleWidth = { (cell: String) in cell.replacing(marks.open, with: "").replacing(marks.close, with: "").count }
    let columns = cells.map(\.count).max() ?? 0
    let widths = (0..<columns).map { column in cells.compactMap { $0.indices.contains(column) ? visibleWidth($0[column]) : nil }.max() ?? 0 }
    return cells.map { row in
      row.enumerated().map { column, cell in cell + String(repeating: " ", count: widths[column] - visibleWidth(cell)) }
        .joined(separator: "  ")
    }.joined(separator: "\n")
  }

  private static func rule(context: BlockContext, into output: NSMutableAttributedString) {
    let line = cell(context: context)
    line.setBorderColor(.separatorColor)
    line.setWidth(1, type: .absoluteValueType, for: .border, edge: .maxY)
    let layout = NSMutableParagraphStyle()
    layout.textBlocks = [line]
    output.append(NSAttributedString(string: "\n", attributes: [.font: bodyFont, .paragraphStyle: layout]))
  }

  // MARK: - Inlines

  private static var bodyFont: NSFont { .systemFont(ofSize: 16) }

  private static func codeFont(size: CGFloat) -> NSFont {
    .monospacedSystemFont(ofSize: size - 1, weight: .regular)
  }

  private static func inlines(_ children: some Sequence<Markup>, style: InlineStyle, into output: NSMutableAttributedString) {
    for child in children { inline(child, style: style, into: output) }
  }

  private static func inline(_ markup: Markup, style: InlineStyle, into output: NSMutableAttributedString) {
    var nested = style

    switch markup {
    case let text as Markdown.Text:
      output.append(NSAttributedString(string: text.string, attributes: attributes(style)))
    case is Strong:
      nested.isBold = true
      inlines(markup.children, style: nested, into: output)
    case is Emphasis:
      nested.isItalic = true
      inlines(markup.children, style: nested, into: output)
    case is Strikethrough:
      nested.isStruck = true
      inlines(markup.children, style: nested, into: output)
    case let link as Markdown.Link:
      nested.link = webURL(link.destination)
      inlines(markup.children, style: nested, into: output)
    case let code as InlineCode:
      nested.isCode = true
      output.append(NSAttributedString(string: code.code, attributes: attributes(nested)))
    case is SoftBreak:
      output.append(NSAttributedString(string: " ", attributes: attributes(style)))
    case is LineBreak:
      output.append(NSAttributedString(string: "\u{2028}", attributes: attributes(style)))
    case let html as InlineHTML:
      output.append(NSAttributedString(string: html.rawHTML, attributes: attributes(style)))
    default:
      inlines(markup.children, style: style, into: output)
    }
  }

  /// Notes aren't trusted to launch things, so only web and mail links are clickable. Marks from a match in the URL are removed.
  private static func webURL(_ destination: String?) -> URL? {
    let cleaned = destination?.filter { ($0.asciiValue ?? 32) >= 32 }
    guard let url = cleaned.flatMap({ URL(string: $0) }), let scheme = url.scheme?.lowercased(), webSchemes.contains(scheme) else { return nil }
    return url
  }

  private static func attributes(_ style: InlineStyle) -> [NSAttributedString.Key: Any] {
    var font = style.isCode ? codeFont(size: style.font.pointSize) : style.font
    var traits = font.fontDescriptor.symbolicTraits
    if style.isBold { traits.insert(.bold) }
    if style.isItalic { traits.insert(.italic) }
    font = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize) ?? font
    var result: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: style.isSecondary ? NSColor.secondaryLabelColor : NSColor.labelColor]
    if style.isCode { result[.backgroundColor] = NSColor.quaternarySystemFill }
    if style.isStruck { result[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
    if let link = style.link { result[.link] = link }
    return result
  }
}
