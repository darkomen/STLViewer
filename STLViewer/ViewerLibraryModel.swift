import SwiftUI
import AppKit
import Combine

@MainActor
final class ViewerLibraryModel: ObservableObject {
    @Published private(set) var libraryURL: URL?
    @Published private(set) var projects: [ViewerProject] = []
    @Published private(set) var ignoredCount = 0
    @Published private(set) var warnings: [String] = []
    @Published private(set) var isScanning = false
    @Published var errorText: String?
    @Published var selectedProjectID: String?

    private let bookmarkKey = "STLViewer.libraryBookmark.v1"

    init() {
        restoreLibrary()
    }

    func chooseLibrary() {
        let panel = NSOpenPanel()
        panel.title = "Selecciona la biblioteca de STL Manager"
        panel.message = "Elige la carpeta raíz (por ejemplo, ~/dev/Diseños), no _Inbox."
        panel.prompt = "Analizar biblioteca"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try url.bookmarkData(options: [.withSecurityScope],
                                            includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: bookmarkKey)
            libraryURL = url
            scan()
        } catch {
            errorText = "No se pudo guardar el permiso: \(error.localizedDescription)"
        }
    }

    private func restoreLibrary() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                              relativeTo: nil, bookmarkDataIsStale: &stale)
            libraryURL = url
            if stale {
                let updated = try url.bookmarkData(options: [.withSecurityScope],
                                                   includingResourceValuesForKeys: nil, relativeTo: nil)
                UserDefaults.standard.set(updated, forKey: bookmarkKey)
            }
            scan()
        } catch {
            errorText = "El acceso a la biblioteca ha caducado. Selecciónala de nuevo."
        }
    }

    func scan() {
        guard let root = libraryURL, !isScanning else { return }
        errorText = nil
        isScanning = true
        // Reservamos el acceso security-scoped hasta que termine el escaneo.
        let granted = root.startAccessingSecurityScopedResource()
        guard granted else {
            isScanning = false
            errorText = "macOS no ha concedido acceso a la biblioteca. Selecciónala de nuevo."
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let output = Result { try ViewerLibraryScanner.scan(library: root) }
            DispatchQueue.main.async { [weak self] in
                root.stopAccessingSecurityScopedResource()
                guard let self else { return }
                self.isScanning = false
                switch output {
                case .success(let info):
                    self.projects = info.projects
                    self.ignoredCount = info.ignoredCount
                    self.warnings = info.warnings
                    if self.selectedProjectID == nil { self.selectedProjectID = info.projects.first?.id }
                case .failure(let error):
                    self.errorText = error.localizedDescription
                }
            }
        }
    }

    func forgetLibrary() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        libraryURL = nil
        projects = []
        warnings = []
        selectedProjectID = nil
    }
}
