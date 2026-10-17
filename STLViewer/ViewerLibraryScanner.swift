import Foundation

// Escaneo deliberadamente superficial: no calcula SHA-256 ni recorre colecciones de 86 GB.
// No escribe ni mueve archivos del usuario.
enum ViewerLibraryScanner {
    private struct FolderRule: Decodable {
        let path: String
        let mode: ViewerFolderMode
    }
    private struct LibraryConfig: Decodable {
        let schema_version: Int
        let folder_rules: [FolderRule]
    }
    private struct ProjectMetadata: Decodable {
        let title: String?
        let source_url: String?
        let categories: [String]?
    }

    static func scan(library: URL) throws -> ViewerScanResult {
        let fm = FileManager.default
        let configURL = library.appendingPathComponent(".stlmanager/library.json")
        let rules: [FolderRule]
        if fm.fileExists(atPath: configURL.path) {
            let data = try readLimited(configURL, limit: 2_000_000)
            let config = try JSONDecoder().decode(LibraryConfig.self, from: data)
            guard config.schema_version == 1 else {
                throw ScanError.incompatibleLibrary
            }
            rules = config.folder_rules
        } else {
            rules = []
        }

        let urls = try fm.contentsOfDirectory(
            at: library,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        var projects: [ViewerProject] = []
        var warnings: [String] = []
        var ignored = 0
        for url in urls {
            let name = url.lastPathComponent
            if name.caseInsensitiveCompare("_Inbox") == .orderedSame || name.hasPrefix(".stlmanager") {
                ignored += 1
                continue
            }
            let attrs = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard attrs.isDirectory == true && attrs.isSymbolicLink != true else { continue }
            let mode = rules.first(where: { $0.path == name })?.mode ?? .managed
            if mode == .excluded {
                ignored += 1
                continue
            }

            if mode == .readOnlyCollection {
                projects.append(ViewerProject(
                    id: url.path, title: name, url: url, mode: mode,
                    sourceURL: nil, categories: [], modelCount: nil,
                    hasReadme: false,
                    summary: "Colección protegida. Su contenido no se ha recorrido ni modificado."
                ))
                continue
            }

            let metadataURL = url.appendingPathComponent(".stlmanager.json")
            var metadata: ProjectMetadata?
            if fm.fileExists(atPath: metadataURL.path) {
                do {
                    metadata = try JSONDecoder().decode(ProjectMetadata.self,
                        from: readLimited(metadataURL, limit: 4_000_000))
                } catch {
                    warnings.append("\(name): metadatos no legibles (\(error.localizedDescription))")
                }
            }
            let hasReadme = fm.fileExists(atPath: url.appendingPathComponent("README.md").path)
            // Solo contar ficheros inmediatamente dentro de models/. Sin leer la geometría.
            let modelsFolder = url.appendingPathComponent("models", isDirectory: true)
            let count = (try? fm.contentsOfDirectory(at: modelsFolder,
                includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]).count) ?? 0
            projects.append(ViewerProject(
                id: url.path,
                title: metadata?.title?.isEmpty == false ? metadata!.title! : name,
                url: url, mode: .managed,
                sourceURL: metadata?.source_url,
                categories: metadata?.categories ?? [],
                modelCount: count,
                hasReadme: hasReadme,
                summary: hasReadme ? "README disponible" : "Sin README"
            ))
        }
        return ViewerScanResult(projects: projects, ignoredCount: ignored, warnings: warnings)
    }

    private static func readLimited(_ url: URL, limit: Int64) throws -> Data {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attributes[.size] as? NSNumber, size.int64Value > limit {
            throw ScanError.largeMetadata(url.lastPathComponent)
        }
        return try Data(contentsOf: url)
    }

    enum ScanError: LocalizedError {
        case incompatibleLibrary
        case largeMetadata(String)
        var errorDescription: String? {
            switch self {
            case .incompatibleLibrary: return "Versión de .stlmanager/library.json no compatible. No se analizará la biblioteca."
            case .largeMetadata(let name): return "El archivo \(name) es demasiado grande para leerlo con seguridad."
            }
        }
    }
}
