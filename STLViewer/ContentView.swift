import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: ViewerLibraryModel
    @StateObject private var thumbnails = ViewerThumbnailStore()
    @State private var search = ""
    @State private var selection: String?
    @State private var inspectorVisible = true
    @State private var viewMode = 0
    @State private var folderFilter: CatalogFilter = .all
    @State private var categoryFilter: String?
    @State private var quickPickerProject: ViewerProject?
    @State private var quickError: String?
    @State private var settingsPresented = false
    @State private var confirmForgetLibrary = false

    private enum CatalogFilter: String {
        case all, managed, collections
        var title: String {
            switch self {
            case .all: return "Tu biblioteca 3D"
            case .managed: return "Proyectos gestionados"
            case .collections: return "Colecciones protegidas"
            }
        }
    }

    private var allCategories: [(name: String, count: Int)] {
        let names = Set(library.projects.flatMap(\.categories)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return names.map { name in
            (name: name, count: library.projects.filter { project in
                project.categories.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .localizedCaseInsensitiveCompare(name) == .orderedSame }
            }.count)
        }
    }

    private var visibleProjects: [ViewerProject] {
        library.projects.filter { project in
            let matchesMode: Bool
            switch folderFilter {
            case .all: matchesMode = true
            case .managed: matchesMode = project.mode == .managed
            case .collections: matchesMode = project.mode == .readOnlyCollection
            }
            let matchesSearch = search.isEmpty || project.title.localizedCaseInsensitiveContains(search)
                || project.categories.contains { $0.localizedCaseInsensitiveContains(search) }
            let matchesCategory = categoryFilter.map { selected in project.categories.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(selected) == .orderedSame } } ?? true
            return matchesMode && matchesSearch && matchesCategory
        }
    }

    private let gridColumns = [GridItem(.adaptive(minimum: 230, maximum: 360), spacing: 18)]

    var body: some View {
        Group {
            if library.libraryURL == nil {
                welcome
            } else {
                mainLayout
            }
        }
        .onChange(of: library.libraryURL) { _, _ in thumbnails.reset() }
        .sheet(isPresented: $settingsPresented) {
            librarySettings
        }
        .alert("No se pudo analizar la biblioteca", isPresented: Binding(
            get: { library.errorText != nil },
            set: { if !$0 { library.errorText = nil } }
        )) {
            Button("Aceptar", role: .cancel) { }
        } message: {
            Text(library.errorText ?? "")
        }
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 76))
                .foregroundStyle(.blue.gradient)
            Text("Bienvenido a STLViewer")
                .font(.largeTitle.bold())
            Text("Explora tus proyectos de impresión 3D. En esta primera versión, el asistente analiza la estructura y los metadatos sin modificar los modelos.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 510)
            Button("Seleccionar biblioteca…") { library.chooseLibrary() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Text("Selecciona la misma carpeta que usas con STL Manager, por ejemplo ~/dev/Diseños")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var librarySettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.blue)
                    .frame(width: 48, height: 48)
                    .background(.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ajustes de STLViewer").font(.title2.bold())
                    Text("Gestiona la ubicación de tu biblioteca de diseños 3D.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Biblioteca actual", systemImage: "folder.fill")
                            .font(.headline)
                        Spacer()
                        if library.isScanning {
                            ProgressView().controlSize(.small)
                        } else if library.libraryURL != nil {
                            Label("Conectada", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    if let root = library.libraryURL {
                        Text(root.path)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        HStack(spacing: 16) {
                            Label("\(library.projects.filter { $0.mode == .managed }.count) proyectos", systemImage: "shippingbox")
                            Label("\(library.projects.filter { $0.mode == .readOnlyCollection }.count) colecciones protegidas", systemImage: "lock.shield")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        HStack {
                            Button("Mostrar en Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([root])
                            }
                            Button("Cambiar biblioteca…") {
                                library.chooseLibrary()
                            }
                            .disabled(library.isScanning)
                            Spacer()
                        }
                    } else {
                        Text("No hay ninguna biblioteca seleccionada.")
                            .foregroundStyle(.secondary)
                        Button("Seleccionar biblioteca…") {
                            library.chooseLibrary()
                        }
                    }
                }
                .padding(6)
            }

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("Cambiar la biblioteca no mueve ni modifica tus proyectos. Olvidarla elimina únicamente el acceso guardado en STLViewer, no los archivos del disco.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            HStack {
                Button("Olvidar biblioteca…", role: .destructive) {
                    confirmForgetLibrary = true
                }
                .disabled(library.libraryURL == nil || library.isScanning)
                Spacer()
                Button("Cerrar") { settingsPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 620)
        .confirmationDialog(
            "¿Olvidar la biblioteca de STLViewer?",
            isPresented: $confirmForgetLibrary,
            titleVisibility: .visible
        ) {
            Button("Olvidar biblioteca", role: .destructive) {
                library.forgetLibrary()
                settingsPresented = false
            }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("Solo se eliminará el acceso guardado en la aplicación. Los proyectos y sus archivos permanecerán intactos.")
        }
    }

    private var mainLayout: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 14) {
                Label("STLViewer", systemImage: "square.stack.3d.up.fill")
                    .font(.title2.bold())
                    .padding(.top, 12)
                if let root = library.libraryURL {
                    Text(root.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(root.path)
                }
                Divider()
                sidebarFilter("Biblioteca completa", systemImage: "square.grid.2x2", filter: .all)
                sidebarFilter("\(library.projects.filter { $0.mode == .managed }.count) proyectos", systemImage: "shippingbox", filter: .managed)
                sidebarFilter("\(library.projects.filter { $0.mode == .readOnlyCollection }.count) colecciones protegidas", systemImage: "lock.shield", filter: .collections)
                if !allCategories.isEmpty {
                    Divider()
                    HStack {
                        Label("Categorías", systemImage: "tag")
                            .font(.headline)
                        Spacer()
                        if categoryFilter != nil {
                            Button("Todas") { categoryFilter = nil }
                                .font(.caption).buttonStyle(.borderless)
                        }
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(allCategories, id: \.name) { entry in
                                Button {
                                    categoryFilter = categoryFilter == entry.name ? nil : entry.name
                                    search = ""
                                    folderFilter = .all
                                    selection = nil
                                } label: {
                                    HStack {
                                        Text(entry.name).lineLimit(1)
                                        Spacer()
                                        Text("\(entry.count)").foregroundStyle(.secondary)
                                    }
                                    .font(.subheadline)
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(categoryFilter == entry.name ? Color.accentColor.opacity(0.23) : Color.clear,
                                                in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(categoryFilter == entry.name ? .isSelected : [])
                            }
                        }
                    }.frame(maxHeight: 260)
                }
                Spacer()
                Divider()
                Button {
                    settingsPresented = true
                } label: {
                    Label("Ajustes de STLViewer", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 9)
                        .padding(.horizontal, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Biblioteca, ubicación y preferencias")
            }
            .padding(18)
            .navigationSplitViewColumnWidth(min: 215, ideal: 260, max: 310)
        } detail: {
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(categoryFilter.map { "Categoría: \($0)" } ?? folderFilter.title).font(.title.bold())
                        Text("\(visibleProjects.count) elementos · Biblioteca y proyectos")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Vista", selection: $viewMode) {
                        Label("Tarjetas", systemImage: "square.grid.2x2").tag(0)
                        Label("Lista", systemImage: "list.bullet").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 150)
                    if viewMode == 1 {
                        Button { inspectorVisible.toggle() } label: {
                            Label(inspectorVisible ? "Ocultar inspector" : "Mostrar inspector", systemImage: inspectorVisible ? "sidebar.right" : "sidebar.right")
                        }.help("Mostrar u ocultar la ficha lateral")
                    }
                    if categoryFilter != nil {
                        Button("Quitar filtro") { categoryFilter = nil }
                            .buttonStyle(.bordered)
                    }
                    Button { library.scan() } label: {
                        Label("Actualizar", systemImage: "arrow.clockwise")
                    }
                    .disabled(library.isScanning)
                }
                .padding(24)
                Divider()
                if library.isScanning {
                    ProgressView("Leyendo biblioteca y reglas…")
                        .padding(24)
                }
                if !library.warnings.isEmpty {
                    Label("\(library.warnings.count) avisos de metadatos. Algunos proyectos se muestran con su nombre de carpeta.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 24)
                        .padding(.top, 10)
                }
                if let issue = thumbnails.saveFailures.first {
                    Label("La miniatura se muestra, pero no se pudo guardar en images/. Revisa permisos de escritura. \(issue.value)", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 24)
                        .padding(.top, 10)
                        .textSelection(.enabled)
                }
                if visibleProjects.isEmpty && !library.isScanning {
                    ContentUnavailableView("No hay proyectos", systemImage: "shippingbox",
                                           description: Text("Prueba otra búsqueda o actualiza la biblioteca."))
                } else if viewMode == 0 {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 18) {
                            ForEach(visibleProjects) { project in
                                projectCard(project)
                            }
                        }
                        .padding(24)
                    }
                } else {
                    // GeometryReader proporciona el alto real desde el primer layout,
                    // incluso antes de que haya un proyecto seleccionado.
                    GeometryReader { available in
                        HSplitView {
                        List(visibleProjects, selection: $selection) { project in
                            HStack(spacing: 10) {
                                Image(systemName: project.mode == .managed ? "cube.transparent" : "lock.shield")
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(project.title)
                                        .fontWeight(.medium)
                                        .lineLimit(2)
                                        .help(project.title)
                                    Text(project.mode.title).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Text(project.modelCount.map { "\($0) archivos" } ?? "Colección")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .tag(project.id)
                            .contextMenu { quickMenu(project) }
                        }
                        .listStyle(.plain)
                        .frame(minWidth: 420, idealWidth: 650)
                        .frame(height: available.size.height)
                        .onChange(of: selection) { _, next in
                            if next != nil { inspectorVisible = true }
                        }
                        .onChange(of: visibleProjects.map(\.id)) { _, ids in
                            if let selection, !ids.contains(selection) { self.selection = nil }
                        }
                        if inspectorVisible {
                            if let project = visibleProjects.first(where: { $0.id == selection }) {
                                VStack(spacing: 0) {
                                    ProjectDetailView(project: project, libraryURL: library.libraryURL,
                                                      thumbnail: thumbnails.images[project.id], onClose: {
                                        library.scan()
                                        thumbnails.refresh(project, libraryURL: library.libraryURL)
                                    }, isInspector: true, onExpand: {
                                        selectedDetail = project
                                    })
                                    .id(project.id)
                                    .task(id: project.id) {
                                        thumbnails.request(project, libraryURL: library.libraryURL)
                                    }
                                }
                                .frame(minWidth: 380, idealWidth: 750, maxWidth: 960, maxHeight: available.size.height, alignment: .top)
                                .frame(height: available.size.height)
                            } else {
                                ContentUnavailableView("Selecciona un proyecto", systemImage: "sidebar.right",
                                    description: Text("Elige una fila para ver su README, archivos y configuración sin salir de la lista."))
                                    .frame(minWidth: 380, idealWidth: 750, maxWidth: 960)
                                    .frame(height: available.size.height)
                            }
                        }
                    }
                        .frame(width: available.size.width, height: available.size.height)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .searchable(text: $search, placement: .toolbar, prompt: "Buscar diseños o categorías")
            .sheet(item: $quickPickerProject) { project in
                QuickOrcaPicker(project: project, libraryURL: library.libraryURL)
            }
            .alert("No se pudo abrir en OrcaSlicer", isPresented: Binding(
                get: { quickError != nil },
                set: { if !$0 { quickError = nil } }
            )) {
                Button("Aceptar", role: .cancel) { }
            } message: {
                Text(quickError ?? "")
            }
            .sheet(item: $selectedDetail) { project in
                ProjectDetailView(project: project, libraryURL: library.libraryURL, thumbnail: thumbnails.images[project.id]) {
                    selectedDetail = nil
                    library.scan()
                    // Refrescar solo la portada de esta ficha. Nunca vaciar toda la cuadrícula.
                    thumbnails.refresh(project, libraryURL: library.libraryURL)
                }
            }
        }
    }

    private func sidebarFilter(_ title: String, systemImage: String, filter: CatalogFilter) -> some View {
        Button {
            folderFilter = filter
            categoryFilter = nil
            selection = nil
        } label: {
            Label(title, systemImage: systemImage)
                .fontWeight(folderFilter == filter ? .semibold : .regular)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(folderFilter == filter ? Color.accentColor.opacity(0.12) : .clear,
                            in: RoundedRectangle(cornerRadius: 9))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(folderFilter == filter ? .isSelected : [])
    }

    @State private var selectedDetail: ViewerProject?

    private func projectCard(_ project: ViewerProject) -> some View {
        Button { selectedDetail = project } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.07))
                    if let image = thumbnails.images[project.id] {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(9)
                    } else {
                        Image(systemName: project.mode == .managed ? "cube.transparent.fill" : "square.stack.3d.up")
                            .font(.system(size: 58, weight: .ultraLight))
                            .foregroundStyle(.blue.opacity(0.6))
                        if thumbnails.pending.contains(project.id) {
                            ProgressView().controlSize(.small)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                                .padding(12)
                        }
                    }
                    if project.mode == .readOnlyCollection {
                        Image(systemName: "lock.shield.fill")
                            .font(.title2).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(14)
                    }
                }
                .frame(height: 172)
                .task(id: project.id) { thumbnails.request(project, libraryURL: library.libraryURL) }
                VStack(alignment: .leading, spacing: 7) {
                    Text(project.title)
                        .font(.headline)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                    Text(project.mode.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let count = project.modelCount {
                        Text("\(count) elementos en models/")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if !project.categories.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(Array(project.categories.prefix(2)), id: \.self) { category in
                                Text(category)
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(Color.blue.opacity(0.09), in: Capsule())
                                    .lineLimit(1)
                            }
                            if project.categories.count > 2 {
                                Text("+\(project.categories.count - 2)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
                .padding(14)
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.09)))
        }
        .buttonStyle(.plain)
        .contextMenu { quickMenu(project) }
    }

    @ViewBuilder
    private func quickMenu(_ project: ViewerProject) -> some View {
        Button("Ver ficha", systemImage: "info.circle") { selectedDetail = project }
        Button("Mostrar en Finder", systemImage: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([project.url])
        }
        if project.mode == .managed {
            Divider()
            let files = QuickOrcaActions.models(in: project, libraryURL: library.libraryURL)
            if files.count == 1, let file = files.first {
                Button("Abrir en OrcaSlicer: \(file.lastPathComponent)", systemImage: "printer") {
                    quickOpen([file])
                }
            } else if (2...8).contains(files.count) {
                Menu("Abrir en OrcaSlicer") {
                    ForEach(files, id: \.path) { file in
                        Button(file.lastPathComponent) { quickOpen([file]) }
                    }
                    Divider()
                    Button("Elegir varios archivos…") { quickPickerProject = project }
                }
            } else if !files.isEmpty {
                Button("Elegir archivos para OrcaSlicer…", systemImage: "printer") {
                    quickPickerProject = project
                }
            } else {
                Text("Sin modelos compatibles con OrcaSlicer")
            }
        }
    }

    private func quickOpen(_ files: [URL]) {
        QuickOrcaActions.open(files, libraryURL: library.libraryURL) { message in
            quickError = message
        }
    }
}
