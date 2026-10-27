import Foundation

/// Usa o `zip`/`unzip` que já vêm instalados em todo Mac.
enum Zip {
    static func extract(_ archive: URL, to directory: URL) throws {
        try run("/usr/bin/unzip", ["-q", "-o", archive.path, "-d", directory.path])
    }

    /// Compacta o conteúdo de `directory` (sem entradas de pasta, como o Word espera).
    static func compress(directory: URL, to archive: URL) throws {
        try run("/usr/bin/zip", ["-q", "-r", "-X", "-D", archive.path, "."], in: directory)
    }

    static func run(_ tool: String, _ arguments: [String], in directory: URL? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        if let directory {
            process.currentDirectoryURL = directory
        }
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        try process.run()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw DocxError.falhaAoCompactar(String(decoding: errorData, as: UTF8.self))
        }
    }
}
