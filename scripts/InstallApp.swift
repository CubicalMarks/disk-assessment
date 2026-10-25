import Foundation
import Darwin

// Swap bundles without changing any file an existing app process has mapped.
// After the swap, the previous bundle stays in the unique .build staging folder.
do {
    guard CommandLine.arguments.count == 3 else { throw CocoaError(.fileReadInvalidFileName) }
    let staged = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
    let destination = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: destination.path) {
        let result = staged.path.withCString { source in
            destination.path.withCString { target in
                renameatx_np(AT_FDCWD, source, AT_FDCWD, target, UInt32(RENAME_SWAP))
            }
        }
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    } else {
        try FileManager.default.moveItem(at: staged, to: destination)
    }
} catch {
    FileHandle.standardError.write(Data("Cannot install app bundle: \(error.localizedDescription)\n".utf8))
    exit(1)
}
