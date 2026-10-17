import Foundation

enum ViewerFolderMode: String, Codable, Sendable {
    case managed
    case readOnlyCollection
    case excluded

    var title: String {
        switch self {
        case .managed: return "Proyecto gestionado"
        case .readOnlyCollection: return "Colección de solo lectura"
        case .excluded: return "Excluida"
        }
    }
}

struct ViewerProject: Identifiable, Sendable {
    let id: String
    let title: String
    let url: URL
    let mode: ViewerFolderMode
    let sourceURL: String?
    let categories: [String]
    let modelCount: Int?
    let hasReadme: Bool
    let summary: String
}

struct ViewerScanResult: Sendable {
    let projects: [ViewerProject]
    let ignoredCount: Int
    let warnings: [String]
}
