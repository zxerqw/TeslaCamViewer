import SwiftUI

struct ErrorBanner: View {
    let error: AppError
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(error.errorDescription ?? "").font(.subheadline).bold()
            if let hint = error.recoverySuggestion {
                Text(hint).font(.caption)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.15))
        .foregroundStyle(.red)
        .cornerRadius(8)
        .padding(.horizontal)
    }
}
