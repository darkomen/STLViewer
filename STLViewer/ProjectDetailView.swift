import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Combine

/// Ficha de trabajo: consulta, apertura de modelos y edición solo de proyectos gestionados.
struct ProjectDetailView: View {
    let project: ViewerProject
    let libraryURL: URL?
    let thumbnail: NSImage?
    let onClose: () -> Void
    var isInspector: Bool = false
    var onExpand: (() -> Void)? = nil

    @State private var tab = 0
    @State private var treeVersion = 0
    @State private var readme = ""
    @State private var draftReadme = ""
    @State private var editingReadme = false
    @State private var folderName = ""
    @State private var categories = ""
    @State private var sourceURL = ""
    @State private var selectedCover: String = ""
    @State private var message: String?
    @State private var chooser: Bool = false
    @State private var orcaApp: URL?
    @State private var importingFiles = false
    @State private var importReport: ViewerProjectFileImporter.ImportReport?

    private var editable: Bool { project.mode == .managed }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: editable ? "shippingbox.fill" : "lock.shield.fill")
                    .font(.system(size: 30)).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text(project.title).font(.title2.bold()).lineLimit(1)
                    Text(project.mode.title).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if isInspector {
                    Button {
                        onExpand?()
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.borderless)
                    .help("Abrir ficha completa")
                    .accessibilityLabel("Abrir ficha completa")
                } else {
                    Button("Cerrar") { onClose() }.keyboardShortcut(.cancelAction)
                }
            }
            .padding(22)
            Divider()
            VStack(spacing: 0) {
                if isInspector {
                    HStack(spacing: 12) {
                        Group {
                            if let thumbnail {
                                Image(nsImage: thumbnail).resizable().scaledToFit()
                            } else {
                                Image(systemName: "cube.transparent.fill")
                                    .font(.system(size: 34)).foregroundStyle(.blue.opacity(0.65))
                            }
                        }
                        .frame(width: 94, height: 82)
                        .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.url.lastPathComponent).font(.subheadline.weight(.semibold)).lineLimit(2)
                            Text("\(project.modelCount ?? 0) archivos en models/")
                                .font(.caption).foregroundStyle(.secondary)
                            if !project.categories.isEmpty {
                                Text(project.categories.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.blue).lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                    Divider()
                }
                HStack(spacing: isInspector ? 0 : 20) {
                // Resumen visual del proyecto.
                if !isInspector {
                VStack(alignment: .leading, spacing: 14) {
                    Group {
                        if let thumbnail {
                            Image(nsImage: thumbnail).resizable().scaledToFit()
                        } else {
                            Image(systemName: "cube.transparent.fill")
                                .font(.system(size: 74)).foregroundStyle(.blue.opacity(0.7))
                        }
                    }
                    .frame(maxWidth: .infinity).frame(height: 210)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
                    Text(project.url.lastPathComponent).font(.headline)
                    Text(project.url.path).font(.caption.monospaced()).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Label("\(project.modelCount ?? 0) elementos en models/", systemImage: "cube")
                        .foregroundStyle(.secondary)
                    if !project.categories.isEmpty {
                        Text(project.categories.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.blue)
                    }
                    Spacer()
                }
                .frame(width: 275, alignment: .topLeading)
                Divider()
                }
                VStack(spacing: 0) {
                    Picker("Sección", selection: $tab) {
                        Text("README").tag(0)
                        Text("Archivos").tag(1)
                        Text("Configuración").tag(2)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 390)
                    .padding(.vertical, 14)
                    Divider()
                    Group {
                        if tab == 0 { readmeTab }
                        else if tab == 1 { filesTab }
                        else { settingsTab }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 18)
            }
        }
        .frame(minWidth: isInspector ? 380 : 960, idealWidth: isInspector ? 490 : 1140, minHeight: isInspector ? 420 : 620, idealHeight: isInspector ? 680 : 740)
        .onAppear { load() }
        .alert("STLViewer", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("Aceptar", role: .cancel) { }
        } message: { Text(message ?? "") }
        .sheet(isPresented: Binding(
            get: { importReport != nil },
            set: { if !$0 { importReport = nil } }
        )) {
            if let importReport {
                ImportCompleteSheet(report: importReport, projectURL: project.url,
                                    onDismiss: { self.importReport = nil },
                                    onShowFiles: {
                                        self.importReport = nil
                                        tab = 1
                                        treeVersion += 1
                                    })
            }
        }
        .fileImporter(isPresented: $chooser, allowedContentTypes: [.application], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let app = urls.first { orcaApp = app; openInOrcaSelected() }
        }
    }

    private var readmeTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Documentación del proyecto").font(.headline)
                Spacer()
                if editable {
                    if editingReadme {
                        Button("Cancelar") { editingReadme = false }
                        Button("Guardar README") { saveReadme() }.buttonStyle(.borderedProminent)
                    } else {
                        Button("Editar") { draftReadme = readme; editingReadme = true }
                    }
                }
            }
            if editingReadme {
                TextEditor(text: $draftReadme)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
            } else {
                ScrollView {
                    if readme.isEmpty {
                        ContentUnavailableView("Sin README", systemImage: "doc.text", description: Text("Este proyecto todavía no tiene documentación."))
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(readmeLines.enumerated()), id: \.offset) { _, block in
                                readmeBlock(block)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 8)
                    }
                }
            }
        }
        .padding(.top, 16)
    }

    // Presentación por bloques: evita que AttributedString(markdown: .full)
    // colapse los saltos de línea del README en un solo párrafo.
    private var readmeLines: [String] {
        readme.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    @ViewBuilder
    private func readmeBlock(_ raw: String) -> some View {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("### ") {
            Text(inlineMarkdown(String(line.dropFirst(4)))).font(.headline)
        } else if line.hasPrefix("## ") {
            Text(inlineMarkdown(String(line.dropFirst(3)))).font(.title3.bold())
        } else if line.hasPrefix("# ") {
            Text(inlineMarkdown(String(line.dropFirst(2)))).font(.title2.bold())
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("•").foregroundStyle(.secondary)
                Text(inlineMarkdown(String(line.dropFirst(2))))
                    .textSelection(.enabled)
            }
        } else if line == "---" || line == "***" {
            Divider()
        } else if line.hasPrefix("> ") {
            Text(inlineMarkdown(String(line.dropFirst(2))))
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
        } else if line.hasPrefix("```") {
            Text(line).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
        } else {
            Text(inlineMarkdown(line))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var filesTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label("Archivos del proyecto", systemImage: "folder")
                    .font(.headline)
                Spacer(minLength: 4)
                ViewThatFits(in: .horizontal) {
                    fileToolbarActions
                    HStack(spacing: 6) {
                        Button { reveal(project.url) } label: {
                            Label("Finder", systemImage: "folder")
                        }
                        if editable {
                            Button { chooseFilesToAdd() } label: {
                                Label("Añadir", systemImage: "plus")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(importingFiles)
                        }
                        Button { treeVersion += 1 } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("Actualizar archivos")
                    }
                }
            }
            Text("Despliega las carpetas con la flecha. Puedes abrir cada modelo directamente en OrcaSlicer.")
                .font(.caption).foregroundStyle(.secondary)
            if importingFiles {
                ProgressView("Copiando archivos y actualizando inventario…")
                    .padding(.vertical, 6)
            }
            ScrollView {
                ProjectFilesTree(projectURL: project.url, libraryURL: libraryURL,
                                 onOpenModel: { openInOrca($0) })
                    .id(treeVersion)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
            Text("Los modelos se abren desde su ubicación original; no se copian ni se mueven.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 16)
    }

    // Se comparte entre la ficha flotante y el inspector lateral.
    private var fileToolbarActions: some View {
        HStack(spacing: 8) {
            Button { reveal(project.url) } label: {
                Label("Mostrar en Finder", systemImage: "folder")
            }
            if editable {
                Button { chooseFilesToAdd() } label: {
                    Label("Añadir archivos…", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(importingFiles)
            }
            Button("Actualizar") { treeVersion += 1 }
        }
    }

    private var settingsTab: some View {
        Form {
            Section("Identidad del proyecto") {
                TextField("Nombre de la carpeta", text: $folderName)
                TextField("Categorías (separadas por comas)", text: $categories)
                TextField("URL de origen", text: $sourceURL)
                Button("Guardar nombre y metadatos") { saveSettings() }
                    .disabled(!editable)
            }
            Section("Portada") {
                Picker("Imagen del proyecto", selection: $selectedCover) {
                    Text("Seleccionar fotografía…").tag("")
                    ForEach(availableImages(), id: \.lastPathComponent) { url in
                        Text(url.lastPathComponent).tag(url.lastPathComponent)
                    }
                }
                Button("Usar como portada") { saveCover() }
                    .disabled(!editable || selectedCover.isEmpty)
                Button("Importar nueva portada…") { chooseCoverImage() }
                    .disabled(!editable)
                Text("Puedes escoger una imagen de images/ o importar una nueva. Se guarda como images/stlviewer-preview.png sin alterar modelos.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !editable {
                Label("Colección protegida: no se permite escribir ni renombrar archivos.", systemImage: "lock.shield")
            }
        }
        .formStyle(.grouped)
    }

    private func load() {
        folderName = project.url.lastPathComponent
        categories = project.categories.joined(separator: ", ")
        sourceURL = project.sourceURL ?? ""
        withAccess {
            let readmeURL = project.url.appendingPathComponent("README.md")
            if let attrs = try? FileManager.default.attributesOfItem(atPath: readmeURL.path),
               let size = attrs[.size] as? NSNumber, size.intValue <= 2_000_000 {
                readme = (try? String(contentsOf: readmeURL, encoding: .utf8)) ?? ""
            }
        }
        treeVersion += 1
    }

    private func withAccess(_ action: () -> Void) {
        guard let root = libraryURL, root.startAccessingSecurityScopedResource() else {
            message = "No hay permiso para acceder a la biblioteca. Vuelve a seleccionarla en STLViewer."
            return
        }
        defer { root.stopAccessingSecurityScopedResource() }
        action()
    }

    private func saveReadme() {
        guard editable else { return }
        withAccess {
            do {
                try draftReadme.write(to: project.url.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
                readme = draftReadme
                editingReadme = false
            } catch { message = error.localizedDescription }
        }
    }

    private func saveSettings() {
        guard editable else { return }
        withAccess {
            do {
                let fm = FileManager.default
                let metadataURL = project.url.appendingPathComponent(".stlmanager.json")
                var metadata: [String: Any] = [:]
                if fm.fileExists(atPath: metadataURL.path) {
                    let existing = try Data(contentsOf: metadataURL)
                    guard existing.count <= 4_000_000,
                          let obj = try JSONSerialization.jsonObject(with: existing) as? [String: Any] else {
                        throw NSError(domain: "STLViewer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Metadatos inválidos. No se modificarán."])
                    }
                    metadata = obj
                }
                metadata["categories"] = categories.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                metadata["source_url"] = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
                let newName = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !newName.isEmpty, newName != ".", newName != "..", !newName.contains("/"), !newName.hasPrefix("."), newName != "_Inbox" else {
                    throw NSError(domain: "STLViewer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Nombre de carpeta inválido."])
                }
                metadata["title"] = newName
                let parent = project.url.deletingLastPathComponent()
                let destination = parent.appendingPathComponent(newName, isDirectory: true)
                if destination != project.url && fm.fileExists(atPath: destination.path) {
                    throw NSError(domain: "STLViewer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Ya existe una carpeta con ese nombre."])
                }
                let payload = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
                // Guardar primero metadata; si falla el renombrado, no se pierde el archivo original.
                try payload.write(to: metadataURL, options: .atomic)
                if destination != project.url { try fm.moveItem(at: project.url, to: destination) }
                onClose()
            } catch { message = error.localizedDescription }
        }
    }

    /// Copia ficheros externos al proyecto y actualiza .stlmanager.json.
    /// El panel devuelve acceso a los archivos seleccionados; la copia no borra el origen.
    private func chooseFilesToAdd() {
        guard editable, !importingFiles, let root = libraryURL else { return }
        let panel = NSOpenPanel()
        panel.title = "Añadir archivos a \(project.title)"
        panel.message = "Puedes seleccionar varios archivos. STLViewer los clasificará automáticamente sin sobrescribir ninguno."
        panel.prompt = "Añadir archivos"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.begin { response in
            guard response == .OK, !panel.urls.isEmpty else { return }
            let sources = panel.urls
            let projectURL = project.url
            Task { @MainActor in
                importingFiles = true
                DispatchQueue.global(qos: .utility).async {
                    let result = Result {
                        try ViewerProjectFileImporter.addFiles(sources, to: projectURL, library: root)
                    }
                    DispatchQueue.main.async {
                        importingFiles = false
                        switch result {
                        case .success(let report):
                            treeVersion += 1
                            withAccess {
                                readme = (try? String(contentsOf: project.url.appendingPathComponent("README.md"), encoding: .utf8)) ?? readme
                            }
                            importReport = report
                        case .failure(let error):
                            message = "No se pudieron añadir los archivos: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }

    private func availableImages() -> [URL] {
        let dir = project.url.appendingPathComponent("images", isDirectory: true)
        return ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { ["png", "jpg", "jpeg", "heic", "webp"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Usamos NSOpenPanel para evitar conflictos entre dos .fileImporter
    /// cuando la ficha ya se presenta como una sheet.
    private func chooseCoverImage() {
        guard editable else { return }
        let panel = NSOpenPanel()
        panel.title = "Elegir una imagen de portada"
        panel.message = "Selecciona una imagen para este proyecto. Se guardará una copia PNG en images/."
        panel.prompt = "Usar imagen"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif, .bmp]
        panel.begin { response in
            guard response == .OK, let chosen = panel.url else { return }
            Task { @MainActor in
                importCover(from: chosen)
            }
        }
    }

    private func importCover(from source: URL) {
        guard editable else { return }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        withAccess {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
                let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                guard size > 0 && size <= 30_000_000 else {
                    throw NSError(domain: "STLViewer", code: 8, userInfo: [NSLocalizedDescriptionKey: "La imagen debe ocupar menos de 30 MB."])
                }
                guard let image = NSImage(contentsOf: source),
                      let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let data = bitmap.representation(using: .png, properties: [:]) else {
                    throw NSError(domain: "STLViewer", code: 9, userInfo: [NSLocalizedDescriptionKey: "No se pudo convertir esta imagen a PNG."])
                }
                let dir = project.url.appendingPathComponent("images", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try data.write(to: dir.appendingPathComponent("stlviewer-preview.png"), options: .atomic)
                onClose()
            } catch { message = error.localizedDescription }
        }
    }

    private func saveCover() {
        guard editable, !selectedCover.isEmpty else { return }
        withAccess {
            do {
                let source = project.url.appendingPathComponent("images/" + selectedCover)
                guard let image = NSImage(contentsOf: source),
                      let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let data = rep.representation(using: .png, properties: [:]) else {
                    throw NSError(domain: "STLViewer", code: 4, userInfo: [NSLocalizedDescriptionKey: "No se pudo convertir la imagen elegida."])
                }
                try data.write(to: project.url.appendingPathComponent("images/stlviewer-preview.png"), options: .atomic)
                onClose()
            } catch { message = error.localizedDescription }
        }
    }

    @State private var requestedOrcaFile: URL?

    private func openInOrca(_ url: URL) {
        requestedOrcaFile = url
        if orcaApp == nil {
            orcaApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.softfever3d.orca-slicer")
                ?? URL(fileURLWithPath: "/Applications/OrcaSlicer.app")
        }
        if let orcaApp, FileManager.default.fileExists(atPath: orcaApp.path) {
            openInOrcaSelected()
        } else {
            chooser = true
        }
    }

    private func openInOrcaSelected() {
        guard let file = requestedOrcaFile, let app = orcaApp else { return }
        withAccess {
            NSWorkspace.shared.open([file], withApplicationAt: app,
                                    configuration: NSWorkspace.OpenConfiguration(),
                                    completionHandler: { _, error in
                if let error { print("STLViewer: No se pudo abrir OrcaSlicer: \(error.localizedDescription)") }
            })
        }
    }

    private func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func isPrintable(_ url: URL) -> Bool {
        ["stl", "3mf", "step", "stp", "obj", "amf"].contains(url.pathExtension.lowercased())
    }

    private func symbol(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "stl", "3mf", "obj": return "cube.transparent"
        case "step", "stp": return "cube"
        case "png", "jpg", "jpeg", "heic": return "photo"
        case "md": return "doc.richtext"
        default: return "doc"
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }
}


/// Confirmación visual, independiente de NSAlert, con los destinos reales de los archivos.
private struct ImportCompleteSheet: View {
    let report: ViewerProjectFileImporter.ImportReport
    let projectURL: URL
    let onDismiss: () -> Void
    let onShowFiles: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(.green)
                    .symbolRenderingMode(.hierarchical)
                VStack(alignment: .leading, spacing: 5) {
                    Text(report.count == 1 ? "Archivo añadido" : "Archivos añadidos")
                        .font(.title2.bold())
                    Text("\(report.count) archivo(s) incorporado(s) a \(report.projectName)")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 12) {
                Label("Archivos incorporados", systemImage: "folder.badge.plus")
                    .font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(report.files) { file in
                            HStack(spacing: 10) {
                                Image(systemName: "doc.fill")
                                    .foregroundStyle(.blue)
                                Text(file.filename).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(file.directory + "/")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxHeight: 165)
                Divider()
                Label("Archivos originales conservados", systemImage: "doc.on.doc")
                    .foregroundStyle(.secondary)
                Label("Inventario .stlmanager.json actualizado", systemImage: "checkmark.seal")
                    .foregroundStyle(.secondary)
                Label("README.md actualizado", systemImage: "text.book.closed")
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
            HStack(spacing: 10) {
                Button("Mostrar en Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(report.files.map {
                        projectURL.appendingPathComponent($0.relativePath)
                    })
                }
                Button("Ver archivos") { onShowFiles() }
                Spacer()
                Button("Continuar") { onDismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}


// Explorador de árbol nativo: carga cada subcarpeta solo al desplegarla.
// No recorre la biblioteca completa ni escribe archivos.
private struct ProjectFilesTree: View {
    let projectURL: URL
    let libraryURL: URL?
    let onOpenModel: (URL) -> Void

    var body: some View {
        FileTreeFolder(url: projectURL, libraryURL: libraryURL,
                       level: 0, isRoot: true, initiallyExpanded: true,
                       onOpenModel: onOpenModel)
    }
}

private struct FileTreeFolder: View {
    let url: URL
    let libraryURL: URL?
    let level: Int
    let isRoot: Bool
    let initiallyExpanded: Bool
    let onOpenModel: (URL) -> Void

    @State private var expanded = false
    @State private var children: [URL] = []
    @State private var loaded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            if children.isEmpty && loaded {
                Text("Carpeta vacía")
                    .font(.caption).foregroundStyle(.tertiary)
                    .padding(.leading, 28)
            }
            ForEach(children, id: \.path) { child in
                if isDirectory(child) {
                    FileTreeFolder(url: child, libraryURL: libraryURL,
                                   level: level + 1, isRoot: false,
                                   initiallyExpanded: child.lastPathComponent == "models" && level == 0,
                                   onOpenModel: onOpenModel)
                } else {
                    HStack(spacing: 9) {
                        Image(systemName: icon(for: child))
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        Text(child.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(child.path)
                        Spacer(minLength: 8)
                        if isPrintable(child) {
                            Button("Abrir en OrcaSlicer") { onOpenModel(child) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        } else {
                            Button("Abrir") { NSWorkspace.shared.open(child) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isRoot ? "shippingbox" : "folder.fill")
                    .foregroundStyle(.blue)
                    .frame(width: 18)
                Text(isRoot ? url.lastPathComponent : url.lastPathComponent)
                    .fontWeight(isRoot ? .semibold : .regular)
                    .lineLimit(1)
            }
            .padding(.vertical, 4)
        }
        .onAppear {
            if initiallyExpanded { expanded = true }
            if expanded { loadIfNeeded() }
        }
        .onChange(of: expanded) { _, value in
            if value { loadIfNeeded() }
        }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        // La URL de biblioteca procede del panel elegido por el usuario.
        let active = libraryURL?.startAccessingSecurityScopedResource() ?? false
        defer { if active { libraryURL?.stopAccessingSecurityScopedResource() } }
        children = ((try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []
        )) ?? []).filter { item in
            !item.lastPathComponent.hasPrefix(".") && !isSymlink(item)
        }.sorted { a, b in
            if isDirectory(a) != isDirectory(b) { return isDirectory(a) }
            return a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
        }
    }

    private func isDirectory(_ file: URL) -> Bool {
        (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
    private func isSymlink(_ file: URL) -> Bool {
        (try? file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }
    private func isPrintable(_ file: URL) -> Bool {
        ["stl", "3mf", "step", "stp", "obj", "amf"].contains(file.pathExtension.lowercased())
    }
    private func icon(for file: URL) -> String {
        switch file.pathExtension.lowercased() {
        case "stl", "3mf", "obj", "step", "stp", "amf": return "cube.transparent"
        case "png", "jpg", "jpeg", "heic", "webp": return "photo"
        case "md": return "doc.richtext"
        default: return "doc"
        }
    }
}
