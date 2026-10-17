import SwiftUI
import AppKit
import SceneKit
import QuickLookThumbnailing
import CryptoKit
import Combine
import ZIPFoundation

/// Miniaturas persistentes para proyectos gestionados. No escribe en colecciones protegidas.
@MainActor
final class ViewerThumbnailStore: ObservableObject {
    @Published private(set) var images: [String: NSImage] = [:]
    @Published private(set) var pending: Set<String> = []
    @Published private(set) var saveFailures: [String: String] = [:]
    private var attempted: Set<String> = []
    private let worker = DispatchQueue(label: "STLViewer.thumbnail.worker", qos: .utility)
    private let cache: URL

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cache = base.appendingPathComponent("STLViewer/Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    }

    func reset() {
        images = [:]
        attempted = []
        pending = []
        saveFailures = [:]
    }

    /// Actualiza únicamente el proyecto editado. El resto de miniaturas no desaparece.
    func refresh(_ project: ViewerProject, libraryURL: URL?) {
        attempted.remove(project.id)
        images.removeValue(forKey: project.id)
        // Evita lanzar dos trabajos si la primera generación aún está en curso.
        if !pending.contains(project.id) {
            request(project, libraryURL: libraryURL)
        }
    }

    func request(_ project: ViewerProject, libraryURL: URL?) {
        guard project.mode == .managed, !attempted.contains(project.id), !pending.contains(project.id), let root = libraryURL else { return }
        attempted.insert(project.id)
        pending.insert(project.id)
        let id = project.id
        let projectURL = project.url
        let cacheDir = cache
        worker.async { [weak self] in
            let outcome = Self.makeImage(projectURL: projectURL, library: root, cacheDir: cacheDir)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pending.remove(id)
                if let message = outcome.saveFailure { self.saveFailures[id] = message }
                if let data = outcome.data, let image = NSImage(data: data) {
                    self.images[id] = image
                    // Limita la caché en RAM (los PNG permanecen en disco).
                    if self.images.count > 100, let oldest = self.images.keys.first, oldest != id {
                        self.images.removeValue(forKey: oldest)
                    }
                }
            }
        }
    }

    /// Resultado seguro entre colas: el modelo no guarda imágenes de Quick Look que sean solo iconos.
    private struct PreviewOutcome: Sendable {
        let data: Data?
        let saveFailure: String?
    }

    nonisolated private static func makeImage(projectURL: URL, library: URL, cacheDir: URL) -> PreviewOutcome {
        let granted = library.startAccessingSecurityScopedResource()
        guard granted else { return PreviewOutcome(data: nil, saveFailure: "Sin acceso a la biblioteca") }
        defer { library.stopAccessingSecurityScopedResource() }

        let cover = projectURL.appendingPathComponent("images", isDirectory: true)
            .appendingPathComponent("stlviewer-preview.png")
        // Siempre priorizar la portada elegida o generada previamente.
        if let existing = try? Data(contentsOf: cover), NSBitmapImageRep(data: existing) != nil {
            return PreviewOutcome(data: existing, saveFailure: nil)
        }

        let models = projectURL.appendingPathComponent("models", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: models,
                         includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                         options: [.skipsHiddenFiles]) else {
            return PreviewOutcome(data: nil, saveFailure: nil)
        }
        // Orden estable: fotos existentes > portada 3MF > STL. No renderear si no es necesario.
        if let photo = projectImage(in: cover.deletingLastPathComponent()) {
            let outcome = persist(photo, to: cover)
            return outcome
        }

        let candidates = files.filter { ["stl", "3mf"].contains($0.pathExtension.lowercased()) }
            .sorted { a, b in a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending }

        for url in candidates {
            let png: Data?
            if url.pathExtension.lowercased() == "3mf" {
                // 3MF es un ZIP: preferimos sus previews reales, no iconos blancos de Finder.
                png = embedded3MFPreview(url)
            } else {
                png = ViewerSTLRenderer.renderBinarySTL(url)
            }
            guard let png, NSBitmapImageRep(data: png) != nil else { continue }
            return persist(png, to: cover)
        }
        return PreviewOutcome(data: nil, saveFailure: nil)
    }

    nonisolated private static func persist(_ png: Data, to cover: URL) -> PreviewOutcome {
        do {
            try FileManager.default.createDirectory(at: cover.deletingLastPathComponent(), withIntermediateDirectories: true)
            // No sobrescribir una portada creada previamente por el usuario.
            if !FileManager.default.fileExists(atPath: cover.path) {
                try png.write(to: cover, options: .atomic)
            }
            return PreviewOutcome(data: png, saveFailure: nil)
        } catch {
            return PreviewOutcome(data: png, saveFailure: "No se guardó images/stlviewer-preview.png: \(error.localizedDescription)")
        }
    }

    nonisolated private static func projectImage(in imagesDir: URL) -> Data? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: imagesDir,
                     includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return nil }
        let candidates = files.filter { ["png", "jpg", "jpeg", "heic", "webp"].contains($0.pathExtension.lowercased()) }
            .sorted { a, b in
                func score(_ url: URL) -> Int {
                    let name = url.deletingPathExtension().lastPathComponent.lowercased()
                    if name.contains("cover") || name.contains("portada") { return 0 }
                    if name.contains("preview") || name.contains("thumbnail") { return 1 }
                    return 2
                }
                let aScore = score(a), bScore = score(b)
                return aScore == bScore ? a.lastPathComponent < b.lastPathComponent : aScore < bScore
            }
        for file in candidates {
            guard let length = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
                  length > 0, length <= 12 * 1024 * 1024,
                  let data = try? Data(contentsOf: file),
                  let image = NSImage(data: data),
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else { continue }
            return png
        }
        return nil
    }

    nonisolated private static func embedded3MFPreview(_ file: URL) -> Data? {
        guard let archive = try? Archive(url: file, accessMode: .read, pathEncoding: nil) else { return nil }
        let entries = archive.filter { entry in
            let name = entry.path.lowercased()
            let ext = URL(fileURLWithPath: name).pathExtension
            return ["png", "jpg", "jpeg"].contains(ext)
                && (name.contains("thumbnail") || name.contains("preview") || name.contains("plate_"))
                && entry.uncompressedSize > 0 && entry.uncompressedSize <= 12 * 1024 * 1024
        }.sorted { a, b in
            func rank(_ name: String) -> Int {
                let n = name.lowercased()
                if n.contains("thumbnail") { return 0 }
                if n.contains("preview") { return 1 }
                return 2
            }
            return rank(a.path) < rank(b.path)
        }
        for entry in entries {
            var bytes = Data()
            do {
                _ = try archive.extract(entry) { part in bytes.append(part) }
                guard let image = NSImage(data: bytes), let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else { continue }
                return png
            } catch { continue }
        }
        return nil
    }

    nonisolated private static func quickLookPNG(_ url: URL) -> Data? {
        let semaphore = DispatchSemaphore(value: 0)
        let result = ThumbnailResult()
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 440, height: 330), scale: 2, representationTypes: [.thumbnail])
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            if let rep = representation, let bitmap = NSBitmapImageRep(data: rep.nsImage.tiffRepresentation ?? Data()) {
                result.lock.lock()
                result.data = bitmap.representation(using: .png, properties: [:])
                result.lock.unlock()
            }
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + 12) == .timedOut { return nil }
        result.lock.lock(); defer { result.lock.unlock() }
        return result.data
    }
}

private final class ThumbnailResult: @unchecked Sendable {
    let lock = NSLock()
    nonisolated(unsafe) var data: Data?

    nonisolated init() {}
}

/// Solo STL binario en v0.2: lectura por bloques, límite estricto de geometría.
private enum ViewerSTLRenderer {
    nonisolated static func renderBinarySTL(_ url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 84), header.count == 84 else { return nil }
        let count = header[80..<84].enumerated().reduce(UInt32(0)) { n, pair in n | (UInt32(pair.element) << (8 * pair.offset)) }
        guard count > 0 else { return nil }
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.uint64Value ?? 0
        // Evita confundir STL ASCII con STL binario y ficheros truncados.
        guard size >= 84 + UInt64(count) * 50 else { return nil }
        let maxTriangles: UInt32 = 90_000
        // No tomar uno de cada N triángulos: rompería la superficie y generaría agujeros.
        // Los archivos demasiado grandes se dejan sin render hasta añadir simplificación real.
        guard count <= maxTriangles else { return nil }
        let step: UInt32 = 1
        var vertices: [SCNVector3] = []
        vertices.reserveCapacity(Int(min(count, maxTriangles + 1)) * 3)
        var low = SCNVector3(CGFloat.greatestFiniteMagnitude, CGFloat.greatestFiniteMagnitude, CGFloat.greatestFiniteMagnitude)
        var high = SCNVector3(-CGFloat.greatestFiniteMagnitude, -CGFloat.greatestFiniteMagnitude, -CGFloat.greatestFiniteMagnitude)
        for index in 0..<count {
            guard let part = try? handle.read(upToCount: 50), part.count == 50 else { return nil }
            if index % step != 0 { continue }
            let bytes = [UInt8](part)
            for v in 0..<3 {
                let start = 12 + v * 12
                func number(_ offset: Int) -> Float {
                    let i = start + offset
                    let bits = UInt32(bytes[i]) | UInt32(bytes[i+1]) << 8 | UInt32(bytes[i+2]) << 16 | UInt32(bytes[i+3]) << 24
                    return Float(bitPattern: bits)
                }
                let x = number(0), y = number(4), z = number(8)
                guard x.isFinite, y.isFinite, z.isFinite else { return nil }
                vertices.append(SCNVector3(CGFloat(x), CGFloat(y), CGFloat(z)))
                low.x = min(low.x, CGFloat(x)); low.y = min(low.y, CGFloat(y)); low.z = min(low.z, CGFloat(z))
                high.x = max(high.x, CGFloat(x)); high.y = max(high.y, CGFloat(y)); high.z = max(high.z, CGFloat(z))
            }
        }
        guard vertices.count >= 3 else { return nil }
        let center = SCNVector3((low.x+high.x)/2,(low.y+high.y)/2,(low.z+high.z)/2)
        let length = max(high.x-low.x, max(high.y-low.y, high.z-low.z))
        guard length > 0, length.isFinite else { return nil }
        let scale = 2.0 / length
        let normalized = vertices.map { SCNVector3(($0.x-center.x)*scale, ($0.y-center.y)*scale, ($0.z-center.z)*scale) }
        let indices = Array(Int32(0)..<Int32(normalized.count))
        let source = SCNGeometrySource(vertices: normalized)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = NSColor(calibratedRed: 0.13, green: 0.34, blue: 0.72, alpha: 1)
        material.lightingModel = .blinn
        material.specular.contents = NSColor(calibratedWhite: 0.24, alpha: 1)
        material.shininess = 0.18
        material.isDoubleSided = true
        geometry.materials = [material]
        let scene = SCNScene()
        let model = SCNNode(geometry: geometry)
        scene.rootNode.addChildNode(model)
        scene.background.contents = NSColor(calibratedRed: 0.93, green: 0.95, blue: 0.98, alpha: 1)
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        // El modelo está normalizado a una dimensión máxima de 2.
        // Reducimos el campo para que ocupe buena parte de la tarjeta.
        camera.camera?.orthographicScale = 1.85
        camera.position = SCNVector3(3.7, 2.8, 4.4)
        camera.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(camera)
        let light = SCNNode()
        light.light = SCNLight()
        light.light?.type = .omni
        light.light?.intensity = 1050
        light.position = SCNVector3(2, 5, 6)
        scene.rootNode.addChildNode(light)
        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.color = NSColor(calibratedWhite: 0.62, alpha: 1)
        scene.rootNode.addChildNode(fill)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: 560, height: 420), antialiasingMode: .multisampling4X)
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

