import Foundation
import ScripCore

enum FixtureLoader {
    static func page(_ name: String) -> PageSnapshot {
        let url =
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: name, withExtension: "json")
        guard let url else {
            fatalError("Missing fixture \(name).json")
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(PageSnapshot.self, from: data)
        } catch {
            fatalError("Failed to decode \(name).json: \(error)")
        }
    }
}
