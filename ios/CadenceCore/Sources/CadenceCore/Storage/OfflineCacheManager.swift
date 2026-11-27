import Foundation

public struct CachedTrackRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: String { track.id }
    public let track: Track
    public let filename: String
    public let bytes: Int64
    public let savedAt: Date
}

public actor OfflineCacheManager {
    private let directory: URL
    private let manifestURL: URL
    private var records: [String: CachedTrackRecord] = [:]

    public init(directory: URL? = nil) {
        let base = directory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CadenceOfflineAudio", isDirectory: true)
        self.directory = base
        self.manifestURL = base.appendingPathComponent("manifest.json")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: manifestURL),
           let decoded = try? JSONDecoder().decode([String: CachedTrackRecord].self, from: data) {
            self.records = decoded
        }
    }

    public func localFileURL(for trackId: String) -> URL? {
        guard let record = records[trackId] else { return nil }
        let file = directory.appendingPathComponent(record.filename)
        if FileManager.default.fileExists(atPath: file.path) {
            return file
        }
        records.removeValue(forKey: trackId)
        persistManifest()
        return nil
    }

    public func isDownloaded(_ trackId: String) -> Bool {
        localFileURL(for: trackId) != nil
    }

    public func allDownloaded() -> [CachedTrackRecord] {
        records.values.sorted { $0.savedAt > $1.savedAt }
    }

    public func totalBytes() -> Int64 {
        records.values.reduce(0) { $0 + $1.bytes }
    }

    public func download(track: Track, from remoteURL: URL, session: URLSession = .shared) async throws -> URL {
        if let existing = localFileURL(for: track.id) {
            return existing
        }
        let safeId = track.id.replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: "/", with: "_")
        let ext = remoteURL.pathExtension.isEmpty ? "m4a" : remoteURL.pathExtension
        let filename = "\(safeId).\(ext)"
        let destination = directory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: destination)

        if remoteURL.isFileURL {
            try FileManager.default.copyItem(at: remoteURL, to: destination)
        } else {
            let (tmpURL, response) = try await session.download(from: remoteURL)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                throw URLError(.badServerResponse)
            }
            try FileManager.default.moveItem(at: tmpURL, to: destination)
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: destination.path)
        let bytes = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        records[track.id] = CachedTrackRecord(
            track: track,
            filename: filename,
            bytes: bytes,
            savedAt: Date()
        )
        persistManifest()
        return destination
    }

    public func remove(trackId: String) {
        if let record = records.removeValue(forKey: trackId) {
            let file = directory.appendingPathComponent(record.filename)
            try? FileManager.default.removeItem(at: file)
            persistManifest()
        }
    }

    public func clearAll() {
        for record in records.values {
            let file = directory.appendingPathComponent(record.filename)
            try? FileManager.default.removeItem(at: file)
        }
        records.removeAll()
        persistManifest()
    }

    private func persistManifest() {
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: manifestURL, options: .atomic)
        }
    }
}
