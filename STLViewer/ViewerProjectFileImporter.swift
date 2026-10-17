import Foundation
import CryptoKit

/// Importador incremental para proyectos que ya existen en STLViewer.
/// Es deliberadamente independiente de SwiftUI para ejecutarse fuera del hilo principal.
enum ViewerProjectFileImporter {

    struct ImportedFile: Sendable, Identifiable {
        let relativePath: String
        var id: String { relativePath }
        var filename: String { (relativePath as NSString).lastPathComponent }
        var directory: String { (relativePath as NSString).deletingLastPathComponent }
    }

    struct ImportReport: Sendable {
        let projectName: String
        let files: [ImportedFile]
        let readmeUpdated: Bool
        var count: Int { files.count }
    }

    private nonisolated static let sectionStart = "<!-- STLVIEWER-IMPORTED-FILES-START -->"
    private nonisolated static let sectionEnd = "<!-- STLVIEWER-IMPORTED-FILES-END -->"

    /// Inserta los archivos en el apartado `## Archivos` existente, sin regenerar
    /// el documento ni alterar las notas. Migra asimismo las entradas que la
    /// v0.3.5 colocó en un bloque auxiliar al final del README.
    private nonisolated static func updatingReadme(_ original: String, paths: [String], title: String) -> String {
        var base = original
        var previousImported: [String] = []
        if let start = base.range(of: sectionStart),
           let end = base.range(of: sectionEnd, range: start.upperBound..<base.endIndex) {
            let previousBody = String(base[start.upperBound..<end.lowerBound])
            for line in previousBody.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("- `"), trimmed.hasSuffix("`"), trimmed.count >= 5 {
                    previousImported.append(String(trimmed.dropFirst(3).dropLast()))
                }
            }
            // Retirar el bloque antiguo completo, incluido el salto anterior,
            // para no dejar un apartado duplicado al final del documento.
            base.removeSubrange(start.lowerBound..<end.upperBound)
            base = base.trimmingCharacters(in: .newlines)
        }

        let candidates = previousImported + paths
        var unique: [String] = []
        var known: Set<String> = []
        for path in candidates {
            if known.insert(path).inserted { unique.append(path) }
        }

        // Las listas Markdown y las secciones deben conservar su disposición.
        // Usamos líneas en lugar de una conversión a Markdown que reconstruiría
        // o alteraría los encabezados y notas escritos por el usuario.
        var lines = base.components(separatedBy: "\n")
        func heading(_ line: String) -> (level: Int, name: String)? {
            let t = line.trimmingCharacters(in: .whitespaces)
            let hashes = t.prefix(while: { $0 == "#" }).count
            guard (1...6).contains(hashes), t.count > hashes,
                  t[t.index(t.startIndex, offsetBy: hashes)] == " " else { return nil }
            let raw = t.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
            let name = raw.replacingOccurrences(of: "#", with: "")
                .trimmingCharacters(in: .whitespaces)
            return (hashes, name)
        }

        let sectionIndex = lines.firstIndex(where: {
            guard let h = heading($0) else { return false }
            return h.name.compare("Archivos", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        })
        if let sectionIndex, let sectionHeading = heading(lines[sectionIndex]) {
            // Insertar antes de otra subsección; si no hay subsecciones,
            // incorporar al final del apartado, sin tocar la documentación posterior.
            var boundary = lines.count
            for index in (sectionIndex + 1)..<lines.count {
                if let next = heading(lines[index]) {
                    // No invadir apartados anidados que tengan otros contenidos.
                    if next.level >= sectionHeading.level { boundary = index; break }
                }
            }
            let current = lines[(sectionIndex + 1)..<boundary].joined(separator: "\n")
            let additions = unique.filter { path in
                // Comprobar la ruta literal evita volver a insertar entradas
                // ya enumeradas en el README original.
                !current.contains("`" + path + "`")
            }
            if !additions.isEmpty {
                let insertion = additions.map { "- `" + $0.replacingOccurrences(of: "`", with: "\\`") + "`" }
                // Suprimir solo las líneas vacías inmediatamente anteriores
                // al siguiente encabezado, conservando una separación limpia.
                var position = boundary
                while position > sectionIndex + 1 && lines[position - 1].isEmpty { position -= 1 }
                let separator = position < lines.count && lines[position].isEmpty ? [] : [""]
                lines.insert(contentsOf: insertion + separator, at: position)
            }
        } else {
            // Compatibilidad con README manuales sin el encabezado estándar.
            while lines.last == "" { lines.removeLast() }
            if !lines.isEmpty { lines.append("") }
            if lines.isEmpty { lines = ["# " + title, ""] }
            lines += ["## Archivos", ""]
            lines += unique.map { "- `" + $0.replacingOccurrences(of: "`", with: "\\`") + "`" }
        }
        while lines.last == "" { lines.removeLast() }
        return lines.joined(separator: "\n") + "\n"
    }

    enum FileImportError: LocalizedError {
        case noPermission
        case invalidProject
        case invalidSource(String)
        case collision(String)
        case invalidMetadata
        case verificationFailed(String)

        var errorDescription: String? {
            switch self {
            case .noPermission: return "macOS no ha concedido acceso a la biblioteca. Selecciónala de nuevo en STLViewer."
            case .invalidProject: return "No es una carpeta de proyecto gestionado válida."
            case .invalidSource(let name): return "El archivo seleccionado no es válido o es un enlace simbólico: \(name)"
            case .collision(let path): return "Ya existe un archivo con ese nombre en \(path). No se ha copiado nada."
            case .invalidMetadata: return "El archivo .stlmanager.json es inválido o demasiado grande. No se ha modificado nada."
            case .verificationFailed(let path): return "La copia no coincide con el archivo original: \(path)"
            }
        }
    }

    /// Clasificación compatible con STL Manager. Lo desconocido va a others/.
    private nonisolated static func targetFolder(for name: String) -> String {
        let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
        if ["stl", "3mf", "step", "stp", "obj", "amf", "ply", "gcode", "bgcode"].contains(ext) { return "models" }
        if ["f3d", "f3z", "scad", "blend", "3dm", "fcstd", "ipt", "iam", "sldprt", "sldasm", "dxf", "dwg"].contains(ext) { return "sources" }
        if ["png", "jpg", "jpeg", "heic", "webp", "gif", "bmp", "tif", "tiff", "svg"].contains(ext) { return "images" }
        return "others"
    }

    private nonisolated static func sha256(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var sha = SHA256()
        while true {
            let bytes = try handle.read(upToCount: 256 * 1024) ?? Data()
            if bytes.isEmpty { break }
            sha.update(data: bytes)
        }
        return sha.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Importación con prevalidación, comprobación hash y reversión de copias ante error.
    /// No renombra, mueve ni elimina los archivos originales.
    nonisolated static func addFiles(_ sourceURLs: [URL], to project: URL, library: URL) throws -> ImportReport {
        let fm = FileManager.default
        let rootAccess = library.startAccessingSecurityScopedResource()
        guard rootAccess else { throw FileImportError.noPermission }
        defer { library.stopAccessingSecurityScopedResource() }

        let root = library.standardizedFileURL.resolvingSymlinksInPath()
        let destProject = project.standardizedFileURL.resolvingSymlinksInPath()
        guard destProject.deletingLastPathComponent() == root,
              (try? destProject.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]))?.isDirectory == true,
              destProject.lastPathComponent != "_Inbox" else {
            throw FileImportError.invalidProject
        }

        // Comprobar otra vez las reglas en disco, aunque la UI estuviera desactualizada.
        // Fallar en cerrado si library.json está mal formado o es incompatible.
        let rulesURL = root.appendingPathComponent(".stlmanager/library.json")
        if fm.fileExists(atPath: rulesURL.path) {
            let ruleAttributes = try fm.attributesOfItem(atPath: rulesURL.path)
            guard ((ruleAttributes[.size] as? NSNumber)?.int64Value ?? 0) <= 2_000_000,
                  let rulesData = try? Data(contentsOf: rulesURL),
                  let config = try? JSONSerialization.jsonObject(with: rulesData) as? [String: Any],
                  (config["schema_version"] as? Int) == 1,
                  let rules = config["folder_rules"] as? [[String: Any]] else {
                throw FileImportError.invalidProject
            }
            if rules.contains(where: {
                ($0["path"] as? String) == destProject.lastPathComponent &&
                ($0["mode"] as? String) != "managed"
            }) {
                throw FileImportError.invalidProject
            }
        }

        let metadataURL = destProject.appendingPathComponent(".stlmanager.json")
        var metadata: [String: Any] = [:]
        if fm.fileExists(atPath: metadataURL.path) {
            let values = try fm.attributesOfItem(atPath: metadataURL.path)
            guard ((values[.size] as? NSNumber)?.int64Value ?? 0) <= 4_000_000 else { throw FileImportError.invalidMetadata }
            let data = try Data(contentsOf: metadataURL)
            guard let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw FileImportError.invalidMetadata
            }
            metadata = existing
        }

        var planned: [(source: URL, destination: URL, relative: String)] = []
        var seen: Set<String> = []
        for source in sourceURLs {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  !source.lastPathComponent.hasPrefix("."),
                  source.lastPathComponent != ".stlmanager.json" else {
                throw FileImportError.invalidSource(source.lastPathComponent)
            }
            let category = targetFolder(for: source.lastPathComponent)
            let relative = category + "/" + source.lastPathComponent
            let destination = destProject.appendingPathComponent(relative)
            guard seen.insert(relative.lowercased()).inserted,
                  !fm.fileExists(atPath: destination.path) else {
                throw FileImportError.collision(relative)
            }
            planned.append((source, destination, relative))
        }
        guard !planned.isEmpty else { return ImportReport(projectName: project.lastPathComponent, files: [], readmeUpdated: false) }

        // Validar README ANTES de copiar para no reemplazar documentos ilegibles.
        let readmeURL = destProject.appendingPathComponent("README.md")
        let hadReadme = fm.fileExists(atPath: readmeURL.path)
        let originalReadmeData: Data? = hadReadme ? try Data(contentsOf: readmeURL) : nil
        guard (originalReadmeData?.count ?? 0) <= 2_000_000,
              let originalReadme = originalReadmeData.flatMap({ String(data: $0, encoding: .utf8) }) ?? (hadReadme ? nil : "") else {
            throw FileImportError.invalidMetadata
        }
        let updatedReadme = updatingReadme(originalReadme, paths: planned.map(\.relative), title: destProject.lastPathComponent)
        let readmeData = Data(updatedReadme.utf8)
        let originalMetadataData: Data? = fm.fileExists(atPath: metadataURL.path) ? try Data(contentsOf: metadataURL) : nil
        var inventory = metadata["files"] as? [[String: String]] ?? []
        var copied: [URL] = []
        var metadataWritten = false
        do {
            for item in planned {
                let srcAccess = item.source.startAccessingSecurityScopedResource()
                defer { if srcAccess { item.source.stopAccessingSecurityScopedResource() } }
                try fm.createDirectory(at: item.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: item.source, to: item.destination)
                copied.append(item.destination)
                let sourceHash = try sha256(item.source)
                let copiedHash = try sha256(item.destination)
                guard sourceHash == copiedHash else { throw FileImportError.verificationFailed(item.relative) }
                inventory.append(["path": item.relative, "sha256": copiedHash])
            }
            metadata["schema_version"] = metadata["schema_version"] ?? 1
            metadata["id"] = metadata["id"] ?? UUID().uuidString
            metadata["title"] = metadata["title"] ?? project.lastPathComponent
            metadata["categories"] = metadata["categories"] ?? [String]()
            metadata["files"] = inventory.sorted { ($0["path"] ?? "") < ($1["path"] ?? "") }
            let output = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            // README e inventario son parte de una sola operación lógica.
            // Guardamos primero el inventario; si falla la escritura del README,
            // podemos restaurar el JSON original en el bloque catch.
            try output.write(to: metadataURL, options: .atomic)
            metadataWritten = true
            try readmeData.write(to: readmeURL, options: .atomic)
        } catch {
            if metadataWritten {
                if let originalMetadataData { try? originalMetadataData.write(to: metadataURL, options: .atomic) }
                else { try? fm.removeItem(at: metadataURL) }
            }
            // El README se escribe de forma atómica como última operación.
            // Si esa escritura falla, el documento anterior sigue intacto.
            for destination in copied.reversed() { try? fm.removeItem(at: destination) }
            throw error
        }
        return ImportReport(projectName: destProject.lastPathComponent,
                            files: planned.map { ImportedFile(relativePath: $0.relative) },
                            readmeUpdated: true)
    }
}
