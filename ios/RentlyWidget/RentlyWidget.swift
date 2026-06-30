import WidgetKit
import SwiftUI

// App Group shared with the Runner app. The Flutter side writes via
// HomeWidget.saveWidgetData under the keys w_matches / w_unread / w_likes / w_updated.
private let appGroupId = "group.com.eyalatiyawork.rentch"

// MARK: - Branding (teal / navy)

private enum Brand {
    static let teal = Color(red: 0.05, green: 0.65, blue: 0.62)   // #0FA69E-ish
    static let navy = Color(red: 0.06, green: 0.13, blue: 0.27)   // #0F2145-ish
    static let navyDeep = Color(red: 0.04, green: 0.09, blue: 0.20)
    static let card = Color.white.opacity(0.12)
}

// MARK: - Model

struct RentlyEntry: TimelineEntry {
    let date: Date
    let matches: Int
    let unread: Int
    let likes: Int
    let updated: String?
}

// MARK: - Data access

private func readActivity() -> RentlyEntry {
    let defaults = UserDefaults(suiteName: appGroupId)

    // home_widget stores ints; tolerate them being stored as String too.
    func intValue(_ key: String) -> Int {
        guard let defaults = defaults else { return 0 }
        if let n = defaults.object(forKey: key) as? Int { return n }
        if let s = defaults.string(forKey: key), let n = Int(s) { return n }
        return 0
    }

    return RentlyEntry(
        date: Date(),
        matches: intValue("w_matches"),
        unread: intValue("w_unread"),
        likes: intValue("w_likes"),
        updated: defaults?.string(forKey: "w_updated")
    )
}

// MARK: - Provider

struct RentlyProvider: TimelineProvider {
    func placeholder(in context: Context) -> RentlyEntry {
        RentlyEntry(date: Date(), matches: 3, unread: 2, likes: 7, updated: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (RentlyEntry) -> Void) {
        completion(readActivity())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RentlyEntry>) -> Void) {
        let entry = readActivity()
        // Refresh roughly every 30 minutes; the app also nudges WidgetKit on data writes.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Views

private struct StatTile: View {
    let value: Int
    let label: String
    let symbol: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Brand.teal)
            Text("\(value)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

struct RentlyWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: RentlyEntry

    private var background: some View {
        LinearGradient(
            colors: [Brand.navy, Brand.navyDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            background
            content
                .padding(family == .systemSmall ? 12 : 16)
        }
        // RTL: Hebrew content.
        .environment(\.layoutDirection, .rightToLeft)
        .widgetBackgroundCompat(background)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall:
            VStack(alignment: .leading, spacing: 8) {
                Text("Rently")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(Brand.teal)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    StatTile(value: entry.matches, label: "התאמות", symbol: "heart.fill")
                    StatTile(value: entry.unread, label: "הודעות", symbol: "bubble.left.fill")
                }
                StatTile(value: entry.likes, label: "לייקים", symbol: "hand.thumbsup.fill")
            }
        default:
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Rently")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundColor(Brand.teal)
                    Spacer()
                    Text("הסיכום שלך")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                HStack(spacing: 10) {
                    StatTile(value: entry.matches, label: "התאמות", symbol: "heart.fill")
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Brand.card))
                    StatTile(value: entry.unread, label: "הודעות", symbol: "bubble.left.fill")
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Brand.card))
                    StatTile(value: entry.likes, label: "לייקים", symbol: "hand.thumbsup.fill")
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Brand.card))
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// Compatibility helper: containerBackground is iOS 17+, older OSes draw it inline.
private extension View {
    @ViewBuilder
    func widgetBackgroundCompat<Background: View>(_ background: Background) -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(for: .widget) { background }
        } else {
            self
        }
    }
}

// MARK: - Widget

struct RentlyWidget: Widget {
    let kind: String = "RentlyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RentlyProvider()) { entry in
            RentlyWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Rently")
        .description("התאמות, הודעות ולייקים במבט אחד")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct RentlyWidgetBundle: WidgetBundle {
    var body: some Widget {
        RentlyWidget()
    }
}
