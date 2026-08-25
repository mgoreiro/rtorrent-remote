import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarSection?
    let labels: [String]

    var body: some View {
        List(selection: $selection) {
            Section("Estado") {
                ForEach(TorrentFilter.allCases) { filter in
                    Label(filter.title, systemImage: filter.symbol)
                        .tag(SidebarSection.filter(filter))
                }
            }

            if !labels.isEmpty {
                Section("Etiquetas") {
                    ForEach(labels, id: \.self) { label in
                        Label(label, systemImage: "tag")
                            .tag(SidebarSection.label(label))
                    }
                }
            }

            Section("Extra") {
                Label("RSS", systemImage: "dot.radiowaves.up.forward")
                    .tag(SidebarSection.rss)
            }
        }
        .listStyle(.sidebar)
    }
}
