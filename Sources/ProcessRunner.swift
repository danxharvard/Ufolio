import Foundation

/// Runs a system tool off the main thread and hands back its exit status and output.
enum ProcessRunner {
    struct Result {
        let status: Int32
        let output: String
        var succeeded: Bool { status == 0 }
    }

    static func run(_ tool: String, _ arguments: [String]) async throws -> Result {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            // Read before waiting, so a chatty tool can't fill the pipe and stall.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
        }.value
    }
}

/// Safety checks for folders Hush unpacks or copies in (extensions).
enum FolderSafety {
    /// Throws if the folder contains symbolic links (which could point an extension at your
    /// other files) or is unreasonably large.
    static func check(_ folder: URL, maxBytes: Int = 500_000_000, maxFiles: Int = 50_000) throws {
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .fileSizeKey]
        var inspectionError: Error?
        guard let walker = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: keys, options: [],
            errorHandler: { _, error in inspectionError = error; return false }
        ) else {
            throw ExtensionError("Ufolio couldn’t inspect this extension folder, so it wasn’t added.")
        }
        var total = 0, count = 0
        for case let url as URL in walker {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true { throw ExtensionError("This extension contains links to files outside itself, so Ufolio didn’t add it.") }
            let (sum, overflow) = total.addingReportingOverflow(values.fileSize ?? 0)
            guard !overflow else { throw ExtensionError("This extension is too large to add.") }
            total = sum
            count += 1
            if total > maxBytes || count > maxFiles { throw ExtensionError("This extension is too large to add.") }
        }
        if inspectionError != nil {
            throw ExtensionError("Ufolio couldn’t inspect every file in this extension folder, so it wasn’t added.")
        }
    }
}
