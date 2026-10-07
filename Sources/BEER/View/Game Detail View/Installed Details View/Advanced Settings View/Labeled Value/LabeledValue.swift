import SwiftUI

struct LabeledValue: View {
    let key: String
    let value: String

    var body: some View {
        SettingsRow(title: key) {
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
    }
}
