import SwiftUI

/// A Game Settings row: fixed-width secondary label, then whatever control the
/// row needs. The label column's width lives here only — `SettingsRow.labelWidth`
/// is what the caption indent below a row is derived from, instead of the magic
/// 142 that used to be hardcoded at each site.
struct SettingsRow<Content: View>: View {
    static var labelWidth: CGFloat { 130 }
    static var spacing: CGFloat { 12 }
    /// Left inset that lines a caption up under the row's content.
    static var captionIndent: CGFloat { labelWidth + spacing }

    let title: String
    var alignment: VerticalAlignment = .firstTextBaseline
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: alignment, spacing: Self.spacing) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: Self.labelWidth, alignment: .leading)
            content
        }
    }
}
