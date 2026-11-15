import WidgetKit
import SwiftUI

let appGroup = "group.com.github.homehoster.meine_notizen"

struct NoteEntry: TimelineEntry {
    let date: Date
    let items: [(label: String, id: String)]
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> NoteEntry { NoteEntry(date: Date(), items: [("Notiz", "x")]) }
    func getSnapshot(in context: Context, completion: @escaping (NoteEntry) -> ()) { completion(load()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NoteEntry>) -> ()) {
        completion(Timeline(entries: [load()], policy: .never))
    }
    func load() -> NoteEntry {
        let d = UserDefaults(suiteName: appGroup)
        var items: [(label: String, id: String)] = []
        for i in 0..<5 {
            let l = d?.string(forKey: "label_\(i)") ?? ""
            let id = d?.string(forKey: "id_\(i)") ?? ""
            if !l.isEmpty { items.append((l, id)) }
        }
        return NoteEntry(date: Date(), items: items)
    }
}

struct NoteWidgetView: View {
    var entry: NoteEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notizen").font(.caption).bold().foregroundColor(.teal)
            ForEach(entry.items, id: \.id) { item in
                Link(destination: URL(string: "notizapp://note/\(item.id)")!) {
                    Text(item.label).font(.footnote).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
    }
}

@main
struct NoteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NoteWidget", provider: Provider()) { entry in
            NoteWidgetView(entry: entry)
        }
        .configurationDisplayName("Notizen")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
