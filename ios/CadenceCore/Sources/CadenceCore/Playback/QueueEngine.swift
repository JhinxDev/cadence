import Foundation

public enum RepeatMode: String, Codable, CaseIterable, Sendable {
    case off
    case all
    case one
}

public struct QueueEngine: Sendable {
    public private(set) var tracks: [Track] = []
    public private(set) var currentIndex: Int = 0
    public var isShuffled: Bool = false
    public var repeatMode: RepeatMode = .off
    public var isRadioActive: Bool = false
    public var radioSessionId: String?
    public var radioMode: RadioMode = .balanced

    public init() {}

    public var currentTrack: Track? {
        guard tracks.indices.contains(currentIndex) else { return nil }
        return tracks[currentIndex]
    }

    public var upNextTracks: [Track] {
        guard currentIndex + 1 < tracks.count else { return [] }
        return Array(tracks[(currentIndex + 1)...])
    }

    public mutating func load(
        tracks: [Track],
        startAt index: Int = 0,
        radioSessionId: String? = nil,
        radioMode: RadioMode = .balanced
    ) {
        self.tracks = tracks
        self.currentIndex = tracks.indices.contains(index) ? index : 0
        self.radioSessionId = radioSessionId
        self.isRadioActive = radioSessionId != nil
        self.radioMode = radioMode
    }

    public mutating func appendRadioTracks(_ more: [Track]) {
        let existingIds = Set(tracks.map(\.id))
        let fresh = more.filter { !existingIds.contains($0.id) }
        tracks.append(contentsOf: fresh)
    }

    public mutating func replaceUpcoming(with more: [Track], mode: RadioMode) {
        guard !tracks.isEmpty else {
            load(tracks: more, radioSessionId: radioSessionId, radioMode: mode)
            return
        }
        let head = Array(tracks.prefix(currentIndex + 1))
        let existingIds = Set(head.map(\.id))
        let filtered = more.filter { !existingIds.contains($0.id) }
        tracks = head + filtered
        self.radioMode = mode
    }

    public mutating func advance() -> Track? {
        guard !tracks.isEmpty else { return nil }
        if repeatMode == .one {
            return currentTrack
        }
        if isShuffled, tracks.count > 2 {
            let candidates = tracks.indices.filter { $0 != currentIndex }
            if let nextIdx = candidates.randomElement() {
                currentIndex = nextIdx
                return currentTrack
            }
        }
        if currentIndex + 1 < tracks.count {
            currentIndex += 1
            return currentTrack
        }
        if repeatMode == .all {
            currentIndex = 0
            return currentTrack
        }
        return nil
    }

    public mutating func previous() -> Track? {
        guard !tracks.isEmpty else { return nil }
        if currentIndex > 0 {
            currentIndex -= 1
        } else if repeatMode == .all {
            currentIndex = tracks.count - 1
        }
        return currentTrack
    }

    public mutating func jump(to index: Int) -> Track? {
        guard tracks.indices.contains(index) else { return nil }
        currentIndex = index
        return currentTrack
    }

    public mutating func removeUpcoming(atOffsets offsets: IndexSet) {
        let baseOffset = currentIndex + 1
        for offset in offsets.sorted(by: >) {
            let absolute = baseOffset + offset
            if tracks.indices.contains(absolute) {
                tracks.remove(at: absolute)
            }
        }
    }

    public mutating func moveUpcoming(from source: IndexSet, to destination: Int) {
        let baseOffset = currentIndex + 1
        var upcoming = Array(tracks[baseOffset...])
        let moving = source.sorted().map { upcoming[$0] }
        for index in source.sorted(by: >) {
            upcoming.remove(at: index)
        }
        let adjustedDest = min(max(0, destination - source.filter { $0 < destination }.count), upcoming.count)
        upcoming.insert(contentsOf: moving, at: adjustedDest)
        tracks = Array(tracks.prefix(baseOffset)) + upcoming
    }

    public mutating func markTrackSaved(extId: String, navidromeId: String) {
        for idx in tracks.indices where tracks[idx].id == extId {
            tracks[idx].inLibrary = true
            tracks[idx].isPreview = false
            tracks[idx].navidromeId = navidromeId
        }
    }

    public mutating func setStarred(trackId: String, starred: Bool) {
        for idx in tracks.indices where tracks[idx].id == trackId {
            tracks[idx].isStarred = starred
        }
    }

    public func shouldFetchMoreRadio(lowWatermark: Int = 4) -> Bool {
        guard isRadioActive, radioSessionId != nil else { return false }
        let remaining = (tracks.count - 1) - currentIndex
        return remaining <= lowWatermark
    }
}
