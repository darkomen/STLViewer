import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Acciones rápidas de OrcaSlicer para proyectos gestionados.
/// No modifica ni copia archivos de la biblioteca.
@MainActor
enum QuickOrcaActions {
    static let extensions: Set<String> = ["stl", "3mf", "obj", "step", "stp", "amf"]

    static func models(in project: ViewerProject, libraryURL: URL?) -> [URL] {
        guard project.mode == .managed, let libraryURL else { return [] }
        let granted = libraryURL.startAccessingSecurityScopedResource()
        guard granted else { return [] }
        defer { libraryURL.stopAccessingSecurityScopedResource() }

        let base = project.url.appendingPathComponent("models", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: base, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var found: [URL] = []
        for case let url as URL in enumerator {
            if found.count >= 5000 { break }
            guard extensions.contains(url.pathExtension.lowercased()) else { continue }
            let attrs = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard attrs?.isRegularFile == true, attrs?.isSymbolicLink != true else { continue }
            found.append(url)
        }
        return found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    static func appURL() -> URL? {
        let workspace = NSWorkspace.shared
        let candidates = [
            workspace.urlForApplication(withBundleIdentifier: "com.softfever3d.orca-slicer"),
            URL(fileURLWithPath: "/Applications/OrcaSlicer.app"),
            URL(fileURLWithPath: NSHomeDirectory() + "/Applications/OrcaSlicer.app")
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func open(_ files: [URL], libraryURL: URL?, onError: @escaping (String) -> Void) {
        guard !files.isEmpty, let libraryURL else { return }
        let app = appURL() ?? chooseApplication()
        guard let app else { return }

        let granted = libraryURL.startAccessingSecurityScopedResource()
        guard granted else {
            onError("No se ha podido acceder a la biblioteca. Vuelve a seleccionarla.")
            return
        }
        // Los archivos se pasan como URLs originales, sin moverlos ni copiarlos.
        NSWorkspace.shared.open(files, withApplicationAt: app,
                                configuration: NSWorkspace.OpenConfiguration()) { _, error in
            libraryURL.stopAccessingSecurityScopedResource()
            if let error {
                Task { @MainActor in onError(error.localizedDescription) }
            }
        }
    }

    static func chooseApplication() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Seleccionar OrcaSlicer"
        panel.message = "Elige OrcaSlicer.app para abrir los archivos seleccionados."
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}

struct QuickOrcaPicker: View {
    let project: ViewerProject
    let libraryURL: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var chosen: Set<URL> = []
    @State private var items: [URL] = []
    @State private var errorMessage: String?

    private var filtered: [URL] {
        items.filter { search.isEmpty || $0.lastPathComponent.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enviar archivos a OrcaSlicer").font(.title2.bold())
                    Text(project.title).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancelar") { dismiss() }
            }
            TextField("Buscar archivos…", text: $search)
                .textFieldStyle(.roundedBorder)
            HStack {
                Text("\(items.count) modelos compatibles · \(chosen.count) seleccionados")
                    .foregroundStyle(.secondary).font(.caption)
                Spacer()
                Button("Seleccionar visibles") { chosen.formUnion(filtered) }
                Button("Deseleccionar") { chosen.removeAll() }
            }
            List(filtered, id: \.path) { file in
                Toggle(isOn: Binding(
                    get: { chosen.contains(file) },
                    set: { selected in
                        if selected { chosen.insert(file) } else { chosen.remove(file) }
                    }
                )) {
                    HStack {
                        Image(systemName: "cube.transparent").foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.lastPathComponent)
                            Text(file.deletingLastPathComponent().lastPathComponent)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            HStack {
                Text("Los archivos originales no se modifican.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Abrir \(chosen.count) en OrcaSlicer") {
                    QuickOrcaActions.open(items.filter { chosen.contains($0) }, libraryURL: libraryURL) { error in
                        errorMessage = error
                    }
                    // Cierra tras solicitar apertura; si falta OrcaSlicer se pide su ubicación.
                    if errorMessage == nil { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(chosen.isEmpty)
            }
        }
        .padding(22)
        .frame(minWidth: 650, minHeight: 480)
        .onAppear { items = QuickOrcaActions.models(in: project, libraryURL: libraryURL) }
    }
}
