import Foundation

struct FinderTarget {
    let path: String
    let isDirectory: Bool

    static func resolve(_ path: String, allowed: Set<String>) throws -> FinderTarget {
        guard allowed.contains(path) else {
            throw AssessmentError.message("This item is not part of the current report.")
        }
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &directory) else {
            throw AssessmentError.message("This item has moved or no longer exists. Scan again to update the report.")
        }
        return FinderTarget(path: path, isDirectory: directory.boolValue)
    }
}
