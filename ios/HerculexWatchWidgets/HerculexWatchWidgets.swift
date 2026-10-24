import SwiftUI
import WidgetKit

struct HerculexEntry: TimelineEntry {
    let date: Date
    let cache: WatchJSON
    let updatedAt: Date?
}

struct HerculexTimeline: TimelineProvider {
    func placeholder(in context: Context) -> HerculexEntry { HerculexEntry(date: .now, cache: [:], updatedAt: nil) }
    func getSnapshot(in context: Context, completion: @escaping (HerculexEntry) -> Void) { completion(load()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<HerculexEntry>) -> Void) {
        let entry = load()
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: entry.date))!
        let nextDay = HerculexEntry(date: midnight, cache: entry.cache, updatedAt: entry.updatedAt)
        completion(Timeline(entries: [entry, nextDay], policy: .after(min(midnight, Date().addingTimeInterval(15 * 60)))))
    }
    private func load() -> HerculexEntry {
        let disk = WatchDiskStore(name: "watch-widgets", shared: true)
        let timestamp = WatchProtocol.number(disk.read("updatedAt"))
        return HerculexEntry(date: .now, cache: WatchProtocol.json(disk.read("cache")),
                            updatedAt: timestamp > 0 ? Date(timeIntervalSince1970: timestamp / 1000) : nil)
    }
}

struct HerculexComplication: Widget {
    let metric: String
    let title: String
    let icon: String
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.ams.herculex.watch." + metric, provider: HerculexTimeline()) { entry in
            HerculexWidgetView(entry: entry, metric: metric, title: title, icon: icon)
                .containerBackground(Color.black.gradient, for: .widget)
        }
        .configurationDisplayName("Herculex · " + title)
        .description("Your Herculex " + title.lowercased() + " at a glance.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct HerculexWidgetView: View {
    let entry: HerculexEntry
    let metric: String
    let title: String
    let icon: String
    @Environment(\.widgetFamily) private var family
    private var macros: WatchJSON { WatchProtocol.json(entry.cache["macros"]) }
    private var stale: Bool { entry.updatedAt == nil || (entry.updatedAt.map { entry.date.timeIntervalSince($0) > 3600 } ?? true) }
    private var value: String {
        if metric == "rambler" { return "Log food" }
        if metric == "workout" { return "Start workout" }
        if metric == "cns" {
            let cns = WatchProtocol.json(entry.cache["cns"])
            return entry.updatedAt == nil ? "—" : "\(WatchProtocol.int(cns["readiness_pct"]))%"
        }
        if metric == "fasting" {
            let fast = WatchProtocol.payload(WatchProtocol.json(entry.cache["fasting"]))
            guard fast["hasActiveFast"] as? Bool == true else { return "No fast" }
            let elapsed = max(0, Int(entry.date.timeIntervalSince1970 - WatchProtocol.number(fast["startedAtEpochMs"]) / 1000))
            return "\(elapsed / 3600)h \(elapsed / 60 % 60)m"
        }
        if metric.hasPrefix("weekly") { return WatchProtocol.number(macros[metric]).formatted(.number.precision(.fractionLength(0))) }
        guard macros["day"] as? String == WatchProtocol.day(entry.date) else { return "—" }
        return WatchProtocol.number(macros[metric]).formatted(.number.precision(.fractionLength(0)))
    }
    private var route: String {
        if metric == "workout" { return "workouts" }
        if metric.hasPrefix("weekly") { return "volume" }
        return ["fasting", "cns", "rambler"].contains(metric) ? metric : "nutrition"
    }
    @ViewBuilder private var metricValue: some View {
        let fast = WatchProtocol.payload(WatchProtocol.json(entry.cache["fasting"]))
        if metric == "fasting", fast["hasActiveFast"] as? Bool == true {
            Text(Date(timeIntervalSince1970: WatchProtocol.number(fast["startedAtEpochMs"]) / 1000), style: .timer)
                .monospacedDigit()
        } else { Text(value) }
    }
    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label { HStack { Text(title); metricValue } } icon: { Image(systemName: icon) }
            case .accessoryCorner:
                metricValue.widgetLabel { Label(title, systemImage: icon) }
            case .accessoryCircular:
                VStack(spacing: 2) {
                    Image(systemName: icon).widgetAccentable()
                    metricValue.font(.caption.bold()).minimumScaleFactor(0.5).lineLimit(1)
                }.widgetLabel { Text(title) }
            default:
                VStack(alignment: .leading) {
                    Label(title, systemImage: icon).font(.caption).widgetAccentable()
                    metricValue.font(.headline)
                    if stale { Text("Cached · open to sync").font(.caption2).foregroundStyle(.secondary) }
                }
            }
        }
        .widgetURL(URL(string: "herculex://" + route))
        .accessibilityLabel(title + " " + value)
    }
}

@main
struct HerculexWatchWidgets: WidgetBundle {
    var body: some Widget {
        NutritionWidgets().body
        ActivityWidgets().body
    }
}

struct NutritionWidgets: WidgetBundle {
    var body: some Widget {
        HerculexComplication(metric: "calories", title: "Calories", icon: "flame.fill")
        HerculexComplication(metric: "protein", title: "Protein", icon: "p.circle.fill")
        HerculexComplication(metric: "carbs", title: "Carbs", icon: "leaf.fill")
        HerculexComplication(metric: "fats", title: "Fat", icon: "drop.fill")
        HerculexComplication(metric: "water_ml", title: "Water", icon: "waterbottle.fill")
    }
}

struct ActivityWidgets: WidgetBundle {
    var body: some Widget {
        HerculexComplication(metric: "fasting", title: "Fasting", icon: "timer")
        HerculexComplication(metric: "cns", title: "CNS", icon: "heart.fill")
        HerculexComplication(metric: "weekly_sets", title: "Weekly sets", icon: "number")
        HerculexComplication(metric: "weekly_tonnage", title: "Weekly volume", icon: "chart.bar.fill")
        HerculexComplication(metric: "rambler", title: "Rambler", icon: "mic.fill")
        WorkoutShortcutWidgets().body
    }
}

struct WorkoutShortcutWidgets: WidgetBundle {
    var body: some Widget {
        HerculexComplication(metric: "workout", title: "Workout", icon: "dumbbell.fill")
    }
}
