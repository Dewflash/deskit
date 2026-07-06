import AppKit
import SwiftUI

struct ColorSample: Equatable {
    let red: Int
    let green: Int
    let blue: Int

    init?(color: NSColor) {
        guard let srgb = color.usingColorSpace(.sRGB) else {
            return nil
        }

        red = Self.componentValue(from: srgb.redComponent)
        green = Self.componentValue(from: srgb.greenComponent)
        blue = Self.componentValue(from: srgb.blueComponent)
    }

    var hex: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    var plainHex: String {
        String(format: "%02X%02X%02X", red, green, blue)
    }

    var rgb: String {
        "rgb(\(red), \(green), \(blue))"
    }

    private static func componentValue(from component: CGFloat) -> Int {
        let scaled = (component * 255).rounded()
        return min(max(Int(scaled), 0), 255)
    }
}

@MainActor
final class ColorDropModel: ObservableObject {
    @Published private(set) var isPicking = false
    @Published private(set) var lastSample: ColorSample?
    @Published private(set) var lastCopiedValue: String?

    private let sampler = NSColorSampler()
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func pickColor() {
        guard !isPicking else {
            return
        }

        isPicking = true

        sampler.show { [weak self] color in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.isPicking = false

                guard let color else {
                    return
                }

                guard let sample = ColorSample(color: color) else {
                    NSSound.beep()
                    return
                }

                self.lastSample = sample
                self.copy(sample.hex)
            }
        }
    }

    func copy(_ value: String) {
        pasteboard.clearContents()
        guard pasteboard.setString(value, forType: .string) else {
            NSSound.beep()
            return
        }

        lastCopiedValue = value
    }
}

struct ColorDropModuleView: View {
    @ObservedObject var model: ColorDropModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            moduleHeader(title: "ColourDrop", subtitle: model.isPicking ? "Pick a screen color." : "Copy sampled color values.")

            Button {
                model.pickColor()
            } label: {
                Label(model.isPicking ? "Picking..." : "Pick Color", systemImage: "eyedropper")
                    .frame(minWidth: 150)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isPicking)

            if let sample = model.lastSample {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Last Color")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(red: Double(sample.red) / 255, green: Double(sample.green) / 255, blue: Double(sample.blue) / 255))
                            .frame(width: 72, height: 72)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.18)))

                        VStack(alignment: .leading, spacing: 8) {
                            copyButton(title: "HEX", value: sample.hex, systemImage: "number")
                            copyButton(title: "Plain HEX", value: sample.plainHex, systemImage: "number")
                            copyButton(title: "RGB", value: sample.rgb, systemImage: "slider.horizontal.3")
                        }
                    }
                }
            } else {
                Text("No color picked yet.")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func copyButton(title: String, value: String, systemImage: String) -> some View {
        Button {
            model.copy(value)
        } label: {
            Label("\(title) \(value)\(model.lastCopiedValue == value ? " (copied)" : "")", systemImage: systemImage)
                .frame(minWidth: 220, alignment: .leading)
        }
    }
}

enum TextCleanerAction {
    case plainText
    case fixPDFLines
    case smartClean
    case sentenceCase
    case titleCase
    case lowercase
    case uppercase
    case markdownQuote
    case markdownBulletList
    case commaSeparatedLineList
    case markdownBold
    case markdownItalic
    case markdownInlineCode
    case chatBold
    case chatItalic
    case chatMonospace
    case chatStrikethrough
    case copyOutput
}

@MainActor
final class TextCleanerModel: ObservableObject {
    @Published var input = ""
    @Published private(set) var output = ""
    @Published private(set) var status = "Paste or clean clipboard text."
    @Published private(set) var recentOutputs: [String]

    private let pasteboard: NSPasteboard
    private let defaults: UserDefaults
    private let recentOutputsKey = "deskit.text-cleaner.recentOutputs"

    init(pasteboard: NSPasteboard = .general, defaults: UserDefaults = .standard) {
        self.pasteboard = pasteboard
        self.defaults = defaults
        self.recentOutputs = defaults.stringArray(forKey: recentOutputsKey) ?? []
    }

    var canCleanClipboard: Bool {
        clipboardText?.isEmpty == false
    }

    func loadClipboardIfInputIsEmpty() {
        guard input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        loadClipboard()
    }

    func loadClipboard() {
        guard let text = clipboardText else {
            status = "Clipboard has no plain text."
            NSSound.beep()
            return
        }

        input = text
        output = text
        status = "Loaded clipboard text."
    }

    func cleanClipboard() {
        guard let text = clipboardText else {
            status = "Clipboard has no plain text."
            NSSound.beep()
            return
        }

        input = text
        let cleaned = TextCleaner.smartClean(text)
        output = cleaned
        copyCleanedOutput(cleaned, status: "Cleaned clipboard and copied result.")
    }

    func perform(_ action: TextCleanerAction) {
        switch action {
        case .plainText:
            transformAndCopy("Plain text copied.") { TextCleaner.normalizePlainText($0) }
        case .fixPDFLines:
            transformAndCopy("Fixed PDF line breaks and copied.") { TextCleaner.fixPDFLines($0) }
        case .smartClean:
            transformAndCopy("Smart clean copied.") { TextCleaner.smartClean($0) }
        case .sentenceCase:
            transformAndCopy("Sentence copied.") { TextCleaner.sentenceCase($0) }
        case .titleCase:
            transformAndCopy("Title case copied.") { TextCleaner.titleCase($0) }
        case .lowercase:
            transformAndCopy("Lowercase copied.") { $0.lowercased() }
        case .uppercase:
            transformAndCopy("Uppercase copied.") { $0.uppercased() }
        case .markdownQuote:
            transformAndCopy("Markdown quote copied.") { TextCleaner.markdownQuote($0) }
        case .markdownBulletList:
            transformAndCopy("Markdown bullet list copied.") { TextCleaner.markdownBulletList($0) }
        case .commaSeparatedLineList:
            transformAndCopy("Comma list copied.") { TextCleaner.commaSeparatedLineList($0) }
        case .markdownBold:
            transformAndCopy("Markdown bold copied.") { TextCleaner.markdownBold($0) }
        case .markdownItalic:
            transformAndCopy("Markdown italic copied.") { TextCleaner.markdownItalic($0) }
        case .markdownInlineCode:
            transformAndCopy("Markdown code copied.") { TextCleaner.markdownInlineCode($0) }
        case .chatBold:
            transformAndCopy("Chat bold copied.") { TextCleaner.chatBold($0) }
        case .chatItalic:
            transformAndCopy("Chat italic copied.") { TextCleaner.chatItalic($0) }
        case .chatMonospace:
            transformAndCopy("Chat monospace copied.") { TextCleaner.chatMonospace($0) }
        case .chatStrikethrough:
            transformAndCopy("Chat strikethrough copied.") { TextCleaner.chatStrikethrough($0) }
        case .copyOutput:
            copyOutput()
        }
    }

    func isActionDisabled(_ action: TextCleanerAction) -> Bool {
        switch action {
        case .copyOutput:
            return output.isEmpty
        default:
            return input.isEmpty
        }
    }

    func copyOutput() {
        guard !output.isEmpty else {
            status = "Nothing to copy yet."
            NSSound.beep()
            return
        }

        _ = copy(output, status: "Copied output.")
    }

    func copyRecentOutput(_ value: String) {
        guard recentOutputs.contains(value) else {
            status = "Recent item is no longer available."
            NSSound.beep()
            return
        }

        output = value
        _ = copy(value, status: "Copied recent output.")
    }

    func clear() {
        input = ""
        output = ""
        status = "Cleared."
    }

    private var clipboardText: String? {
        pasteboard.string(forType: .string)
    }

    private func transform(_ successStatus: String, _ cleaner: (String) -> String) {
        let cleaned = cleaner(input)
        output = cleaned
        status = successStatus
    }

    private func transformAndCopy(_ successStatus: String, _ cleaner: (String) -> String) {
        transform(successStatus, cleaner)
        copyCleanedOutput(output, status: successStatus)
    }

    private func copyCleanedOutput(_ value: String, status: String) {
        if copy(value, status: status) {
            addRecentOutput(value)
        }
    }

    private func copy(_ value: String, status: String) -> Bool {
        pasteboard.clearContents()

        guard pasteboard.setString(value, forType: .string) else {
            self.status = "Could not copy text."
            NSSound.beep()
            return false
        }

        self.status = status
        return true
    }

    private func addRecentOutput(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return
        }

        var updated = recentOutputs.filter { $0 != trimmed }
        updated.insert(trimmed, at: 0)
        recentOutputs = Array(updated.prefix(5))
        defaults.set(recentOutputs, forKey: recentOutputsKey)
    }
}

struct TextCleanerModuleView: View {
    @ObservedObject var model: TextCleanerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            moduleHeader(title: "TextCleaner", subtitle: model.status)

            TextEditor(text: $model.input)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(height: 120)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 8) {
                Button {
                    model.loadClipboard()
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }

                Button {
                    model.cleanClipboard()
                } label: {
                    Label("Clean Clipboard", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canCleanClipboard)

                Spacer()

                Button {
                    model.clear()
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
            }

            HStack(spacing: 8) {
                cleanButton("Plain Text", systemImage: "textformat", action: .plainText)
                cleanButton("PDF Lines", systemImage: "text.alignleft", action: .fixPDFLines)
                cleanButton("Smart Clean", systemImage: "wand.and.stars", action: .smartClean)
            }

            HStack(spacing: 8) {
                cleanButton("Sentence", systemImage: "textformat.abc", action: .sentenceCase)
                caseMenu
                markdownMenu
                chatMenu
            }

            outputPanel
            recentPanel
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            model.loadClipboardIfInputIsEmpty()
        }
    }

    private var caseMenu: some View {
        Menu {
            menuAction("Title Case", systemImage: "character.cursor.ibeam", action: .titleCase)
            menuAction("lowercase", systemImage: "textformat.size.smaller", action: .lowercase)
            menuAction("UPPERCASE", systemImage: "textformat.size.larger", action: .uppercase)
        } label: {
            Label("Case", systemImage: "textformat")
                .frame(minWidth: 96, maxWidth: .infinity)
        }
        .disabled(model.input.isEmpty)
    }

    private var markdownMenu: some View {
        Menu {
            menuAction("Quote", systemImage: "quote.bubble", action: .markdownQuote)
            menuAction("Bullet List", systemImage: "list.bullet", action: .markdownBulletList)
            menuAction("Comma List", systemImage: "text.badge.plus", action: .commaSeparatedLineList)
            Divider()
            menuAction("Bold", systemImage: "bold", action: .markdownBold)
            menuAction("Italic", systemImage: "italic", action: .markdownItalic)
            menuAction("Code", systemImage: "chevron.left.forwardslash.chevron.right", action: .markdownInlineCode)
        } label: {
            Label("Markdown", systemImage: "number")
                .frame(minWidth: 136, maxWidth: .infinity)
        }
        .disabled(model.input.isEmpty)
    }

    private var chatMenu: some View {
        Menu {
            menuAction("Bold", systemImage: "bold", action: .chatBold)
            menuAction("Italic", systemImage: "italic", action: .chatItalic)
            menuAction("Monospace", systemImage: "chevron.left.forwardslash.chevron.right", action: .chatMonospace)
            menuAction("Strikethrough", systemImage: "strikethrough", action: .chatStrikethrough)
        } label: {
            Label("Chat", systemImage: "message")
                .frame(minWidth: 96, maxWidth: .infinity)
        }
        .disabled(model.input.isEmpty)
    }

    private var outputPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Output")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if !model.output.isEmpty {
                    Button {
                        model.copyOutput()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)
                }
            }

            ScrollView {
                Text(model.output.isEmpty ? "Cleaned text will appear here." : model.output)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(model.output.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 110)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var recentPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent")
                .font(.caption)
                .foregroundStyle(.secondary)

            if model.recentOutputs.isEmpty {
                Text("Recent cleaned text will appear here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.recentOutputs, id: \.self) { value in
                        Button {
                            model.copyRecentOutput(value)
                        } label: {
                            Label(recentPreview(value), systemImage: "clock.arrow.circlepath")
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func cleanButton(_ title: String, systemImage: String, action: TextCleanerAction) -> some View {
        Button {
            model.perform(action)
        } label: {
            Label(title, systemImage: systemImage)
                .frame(minWidth: 120, maxWidth: .infinity)
        }
        .disabled(model.isActionDisabled(action))
    }

    private func menuAction(_ title: String, systemImage: String, action: TextCleanerAction) -> some View {
        Button {
            model.perform(action)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    private func recentPreview(_ value: String) -> String {
        let singleLine = value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")

        if singleLine.count <= 72 {
            return singleLine
        }

        return String(singleLine.prefix(72)) + "..."
    }
}

func moduleHeader(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        Text(title)
            .font(.title3.weight(.semibold))
        Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

enum TextCleaner {
    static func smartClean(_ text: String) -> String {
        let normalized = normalizePlainText(text)
        let lineFixed = fixPDFLines(normalized)

        if looksMostlyUppercase(lineFixed) {
            return sentenceCase(lineFixed)
        }

        return lineFixed
    }

    static func normalizePlainText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { normalizeInlineWhitespace(String($0)) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func fixPDFLines(_ text: String) -> String {
        let normalized = normalizePlainText(text)
        let lines = normalized.components(separatedBy: "\n")
        var paragraphs: [String] = []
        var current = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                appendParagraph(current, to: &paragraphs)
                current = ""
                continue
            }

            if isListItem(trimmed) {
                appendParagraph(current, to: &paragraphs)
                current = ""
                appendListItem(trimmed, to: &paragraphs)
                continue
            }

            if current.isEmpty {
                current = trimmed
            } else if shouldJoin(previous: current, next: trimmed) {
                current = join(previous: current, next: trimmed)
            } else {
                appendParagraph(current, to: &paragraphs)
                current = trimmed
            }
        }

        appendParagraph(current, to: &paragraphs)

        return paragraphs.joined(separator: "\n\n")
    }

    static func sentenceCase(_ text: String) -> String {
        let lowercased = text.lowercased()
        var result = ""
        var shouldCapitalize = true

        for scalar in lowercased.unicodeScalars {
            let character = Character(scalar)

            if shouldCapitalize && CharacterSet.letters.contains(scalar) {
                result.append(String(character).uppercased())
                shouldCapitalize = false
            } else {
                result.append(character)
            }

            if ".!?".unicodeScalars.contains(scalar) {
                shouldCapitalize = true
            }
        }

        return result
    }

    static func titleCase(_ text: String) -> String {
        let smallWords: Set<String> = ["a", "an", "and", "as", "at", "but", "by", "for", "in", "nor", "of", "on", "or", "per", "the", "to", "vs", "via"]
        let tokens = text.lowercased().split(separator: " ", omittingEmptySubsequences: false)

        return tokens.enumerated().map { index, token in
            let word = String(token)

            guard !word.isEmpty else {
                return word
            }

            if index > 0 && smallWords.contains(word) {
                return word
            }

            return capitalizeFirstLetter(word)
        }.joined(separator: " ")
    }

    static func markdownQuote(_ text: String) -> String {
        normalizePlainText(text)
            .components(separatedBy: "\n")
            .map { line in
                line.isEmpty ? ">" : "> \(line)"
            }
            .joined(separator: "\n")
    }

    static func markdownBulletList(_ text: String) -> String {
        meaningfulLines(from: text)
            .map { "- \($0)" }
            .joined(separator: "\n")
    }

    static func commaSeparatedLineList(_ text: String) -> String {
        meaningfulLines(from: text)
            .joined(separator: ", ")
    }

    static func markdownBold(_ text: String) -> String {
        wrapMeaningfulLines(text, prefix: "**", suffix: "**")
    }

    static func markdownItalic(_ text: String) -> String {
        wrapMeaningfulLines(text, prefix: "*", suffix: "*")
    }

    static func markdownInlineCode(_ text: String) -> String {
        meaningfulLines(from: text)
            .map { line in
                if line.contains("`") {
                    return "`` \(line) ``"
                }

                return "`\(line)`"
            }
            .joined(separator: "\n")
    }

    static func chatBold(_ text: String) -> String {
        wrapMeaningfulLines(text, prefix: "*", suffix: "*")
    }

    static func chatItalic(_ text: String) -> String {
        wrapMeaningfulLines(text, prefix: "_", suffix: "_")
    }

    static func chatMonospace(_ text: String) -> String {
        markdownInlineCode(text)
    }

    static func chatStrikethrough(_ text: String) -> String {
        wrapMeaningfulLines(text, prefix: "~", suffix: "~")
    }

    private static func normalizeInlineWhitespace(_ line: String) -> String {
        line
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func meaningfulLines(from text: String) -> [String] {
        normalizePlainText(text)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func wrapMeaningfulLines(_ text: String, prefix: String, suffix: String) -> String {
        meaningfulLines(from: text)
            .map { "\(prefix)\($0)\(suffix)" }
            .joined(separator: "\n")
    }

    private static func appendParagraph(_ paragraph: String, to paragraphs: inout [String]) {
        let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmed.isEmpty {
            paragraphs.append(trimmed)
        }
    }

    private static func appendListItem(_ item: String, to paragraphs: inout [String]) {
        guard let previous = paragraphs.last, previous.components(separatedBy: "\n").allSatisfy(isListItem) else {
            paragraphs.append(item)
            return
        }

        paragraphs[paragraphs.count - 1] = previous + "\n" + item
    }

    private static func shouldJoin(previous: String, next: String) -> Bool {
        guard !isListItem(previous), !isListItem(next) else {
            return false
        }

        if previous.hasSuffix("-") {
            return true
        }

        if let last = previous.last, ".!?;:".contains(last) {
            return false
        }

        return true
    }

    private static func join(previous: String, next: String) -> String {
        if previous.hasSuffix("-") {
            return String(previous.dropLast()) + next
        }

        return previous + " " + next
    }

    private static func isListItem(_ line: String) -> Bool {
        let bulletPrefixes = ["- ", "* ", "• ", "– ", "— "]

        if bulletPrefixes.contains(where: { line.hasPrefix($0) }) {
            return true
        }

        guard let first = line.first, first.isNumber else {
            return false
        }

        let prefix = line.prefix(while: { $0.isNumber })
        let remaining = line.dropFirst(prefix.count)

        return remaining.hasPrefix(". ") || remaining.hasPrefix(") ")
    }

    private static func looksMostlyUppercase(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard letters.count >= 12 else {
            return false
        }

        let uppercase = letters.filter { CharacterSet.uppercaseLetters.contains($0) }
        return Double(uppercase.count) / Double(letters.count) > 0.72
    }

    private static func capitalizeFirstLetter(_ word: String) -> String {
        guard let first = word.first else {
            return word
        }

        return first.uppercased() + word.dropFirst()
    }
}
