import SwiftUI

struct EventRowView: View {
    let event: TeslaEvent

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(timeString).font(.subheadline).foregroundStyle(.primary)
                if let meta = event.eventMetadata {
                    if let reason = meta.reason { Text(reason).font(.caption).foregroundStyle(.secondary) }
                    if let city = meta.city { Text(city).font(.caption).foregroundStyle(.secondary) }
                }
                Text("\(event.availableAngles.count) 路 · \(segmentsLabel)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var thumbnail: some View {
        Group {
            if let url = event.thumbnailURL,
               let data = try? Data(contentsOf: url),
               let img = UIImage(data: data) {
                Image(uiImage: img).resizable().aspectRatio(16/9, contentMode: .fit)
            } else {
                Color.gray.opacity(0.2)
                    .aspectRatio(16/9, contentMode: .fit)
                    .overlay(Image(systemName: "video").foregroundStyle(.secondary))
            }
        }
        .frame(width: 96)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: event.startTime)
    }

    private var segmentsLabel: String {
        let secs = event.totalDuration.seconds
        if secs < 60 { return "\(Int(secs))s" }
        let m = Int(secs) / 60, s = Int(secs) % 60
        return "\(m)m\(s > 0 ? "\(s)s" : "")"
    }
}
