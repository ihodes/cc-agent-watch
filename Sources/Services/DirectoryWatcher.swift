import Foundation

/// Watches a directory for filesystem changes using DispatchSource.
public final class DirectoryWatcher: Sendable {
    private let directoryPath: String
    private let onChange: @Sendable () -> Void
    private let source: DispatchSourceFileSystemObject
    private let fileDescriptor: Int32

    public init?(directoryPath: String, onChange: @escaping @Sendable () -> Void) {
        self.directoryPath = directoryPath
        self.onChange = onChange

        // Ensure directory exists
        try? FileManager.default.createDirectory(
            atPath: directoryPath,
            withIntermediateDirectories: true
        )

        let fd = open(directoryPath, O_EVTONLY)
        guard fd >= 0 else { return nil }
        self.fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .global(qos: .userInitiated)
        )
        self.source = source

        source.setEventHandler { [onChange] in
            onChange()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
    }

    deinit {
        source.cancel()
    }
}
