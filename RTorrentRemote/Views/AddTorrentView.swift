import SwiftUI
import Foundation
import UniformTypeIdentifiers

struct AddTorrentView: View {
    @ObservedObject var viewModel: TorrentListViewModel
    let availableLabels: [String]
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .magnet
    @State private var uri: String = ""
    @State private var selectedFileURL: URL?
    @State private var startImmediately = true
    @State private var label: String = ""
    @State private var directory: String = ""
    @State private var showingFileImporter = false
    @AppStorage(Preferences.deleteTorrentFileKey) private var deleteTorrentFile = true

    enum Mode: String, CaseIterable, Identifiable {
        case magnet = "Magnet / URL"
        case file = "Archivo .torrent"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Añadir torrent")
                .font(.title2.weight(.semibold))

            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            switch mode {
            case .magnet:
                TextField("magnet:?xt=urn:btih:… o https://…torrent", text: $uri)
                    .textFieldStyle(.roundedBorder)
            case .file:
                HStack {
                    Text(selectedFileURL?.lastPathComponent ?? "Ningún archivo seleccionado")
                        .foregroundStyle(selectedFileURL == nil ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer()
                    Button("Elegir…") { showingFileImporter = true }
                }
                Toggle("Mover el archivo .torrent a la papelera tras añadirlo", isOn: $deleteTorrentFile)
            }

            Picker("Etiqueta", selection: $label) {
                Text("Sin etiqueta").tag("")
                ForEach(availableLabels, id: \.self) { Text($0).tag($0) }
            }

            TextField("Carpeta de descarga (vacío = la predeterminada del servidor)", text: $directory)
                .textFieldStyle(.roundedBorder)

            Toggle("Empezar a descargar inmediatamente", isOn: $startImmediately)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Añadir") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
        }
        .padding(20)
        .frame(width: 460, height: 330)
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [UTType(filenameExtension: "torrent") ?? .data]) { result in
            if case .success(let url) = result {
                selectedFileURL = url
            }
        }
    }

    private var canSubmit: Bool {
        switch mode {
        case .magnet: return !uri.trimmingCharacters(in: .whitespaces).isEmpty
        case .file: return selectedFileURL != nil
        }
    }

    private func submit() {
        switch mode {
        case .magnet:
            viewModel.addTorrent(uri: uri, startImmediately: startImmediately, label: label, directory: directory)
        case .file:
            guard let url = selectedFileURL else { return }
            viewModel.addTorrentFile(at: url, startImmediately: startImmediately, label: label, directory: directory)
        }
        dismiss()
    }
}
