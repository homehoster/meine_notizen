import WidgetKit
import SwiftUI

let appGroup = "group.com.github.homehoster.meine_notizen"

// Entspricht dem JSON, das die App unter "widget_notes" speichert:
// [{"id": "...", "title": "...", "preview": "...", "imagePath": "..."}]
struct WidgetNote: Decodable, Identifiable {
    let id: String
    let title: String
    let preview: String
}

struct NoteEntry: TimelineEntry {
    let date: Date
    let notes: [WidgetNote]
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> NoteEntry {
        NoteEntry(date: Date(), notes: [WidgetNote(id: "x", title: "Notiz", preview: "")])
    }

    func getSnapshot(in context: Context, completion: @escaping (NoteEntry) -> ()) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NoteEntry>) -> ()) {
        // Die App stößt die Aktualisierung selbst an (home_widget).
        completion(Timeline(entries: [load()], policy: .never))
    }

    func load() -> NoteEntry {
        let defaults = UserDefaults(suiteName: appGroup)
        guard
            let json = defaults?.string(forKey: "widget_notes"),
            let data = json.data(using: .utf8),
            let notes = try? JSONDecoder().decode([WidgetNote].self, from: data)
        else {
            return NoteEntry(date: Date(), notes: [])
        }
        return NoteEntry(date: Date(), notes: notes)
    }
}

extension View {
    @ViewBuilder
    func widgetBackground() -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(.background, for: .widget)
        } else {
            background(Color(.systemBackground))
        }
    }
}

struct NoteWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: NoteEntry

    private var limit: Int { family == .systemSmall ? 3 : 5 }

    private func url(for id: String) -> URL {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return URL(string: "notizapp://note/\(encoded)") ?? URL(string: "notizapp://home")!
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notizen").font(.caption).bold().foregroundColor(.teal)
            if entry.notes.isEmpty {
                Text("Noch keine Notizen").font(.footnote).foregroundColor(.secondary)
            }
            ForEach(entry.notes.prefix(limit)) { note in
                if family == .systemSmall {
                    // Kleines Widget unterstützt keine einzelnen Links.
                    Text(note.title).font(.footnote).lineLimit(1)
                } else {
                    Link(destination: url(for: note.id)) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(note.title).font(.footnote).bold().lineLimit(1)
                            let first = note.preview.components(separatedBy: "\n").first ?? ""
                            if !first.isEmpty {
                                Text(first).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
        .widgetURL(URL(string: "notizapp://home"))
        .widgetBackground()
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
