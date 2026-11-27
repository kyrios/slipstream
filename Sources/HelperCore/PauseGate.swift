import Foundation

/// An outside gate that may pause Slipstream (docs/worker.md, "The pause gate"). Something else on
/// the Mac, for example a daemon that knows whether the Mac is plugged in and nobody is using it,
/// writes a small text file; with the setting `gateFile` naming it, Slipstream pauses "Sofort"
/// while the file says `closed` and resumes when it says `open` again.
///
/// The file, replaced as a whole when it changes:
///
///     closed          line 1: open | closed
///     active away     line 2: why, words separated by spaces (empty when open)
///     1795812110      line 3: optional, when it last changed
///
/// Anything else, an empty file, or no file at all means no gate: Slipstream runs as without the
/// setting, so a broken gate never stops the Mac for good.
public enum PauseGate: Equatable, Sendable {
    case open
    case closed(reasons: [String])

    public static func parse(_ text: String) -> PauseGate? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first?.trimmingCharacters(in: .whitespaces) else { return nil }
        switch first {
        case "open":
            return .open
        case "closed":
            let reasons = lines.count > 1 ? lines[1].split(separator: " ").map(String.init) : []
            return .closed(reasons: reasons)
        default:
            return nil
        }
    }

    /// The gate in `file`, or nil for no gate (missing, unreadable, not a gate's words).
    public static func read(_ file: URL) -> PauseGate? {
        guard let data = try? Data(contentsOf: file), data.count < 4096,
              let text = String(data: data, encoding: .utf8) else { return nil }
        return parse(text)
    }

    public var isClosed: Bool {
        if case .closed = self { return true }
        return false
    }

    /// The menu's line while the setting is on: "Sperre: offen", "Sperre: geschlossen (in
    /// Benutzung, Akku)". The words the gate gives are German where they are known.
    public var menuLine: String {
        switch self {
        case .open:
            return "Sperre: offen"
        case .closed(let reasons):
            let words = reasons.map { Self.reasonWords[$0] ?? $0 }
            return "Sperre: geschlossen" + (words.isEmpty ? "" : " (\(words.joined(separator: ", ")))")
        }
    }

    /// What the app does about the gate. A pause the gate set lasts `hold` and is renewed an hour
    /// before it ends, so a long closed gate never lets the worker go; the worker keeps a
    /// suspended job up to 24 hours (docs/worker.md, "Pause").
    public enum Action: Equatable, Sendable {
        case none
        /// Pause now, until then, as the gate's pause.
        case pause(until: Date)
        /// A pause the user chose that lets the running job finish: stop it now, same end.
        case stopRunningJob(until: Date)
        /// The gate's pause is over.
        case resume
    }

    public static let hold: TimeInterval = 24 * 3600

    /// `gate`: the file's word (nil: no gate). `gatePaused`: the running pause is the gate's.
    /// `pausedUntil`, `mode`: the pause in effect, whoever set it. A pause the user chose stays
    /// when the gate opens; the gate only ends its own.
    public static func decide(gate: PauseGate?, gatePaused: Bool, pausedUntil: Date?, mode: PauseMode, now: Date) -> Action {
        guard let gate, gate.isClosed else {
            return gatePaused && pausedUntil != nil ? .resume : .none
        }
        guard let until = pausedUntil, until > now else { return .pause(until: now.addingTimeInterval(hold)) }
        if gatePaused {
            return until.timeIntervalSince(now) < hold - 3600 ? .pause(until: now.addingTimeInterval(hold)) : .none
        }
        return mode == .afterJob ? .stopRunningJob(until: until) : .none
    }

    static let reasonWords = [
        "active": "in Benutzung",
        "on-battery": "Akku",
        "away": "nicht zu Hause",
        "forced": "von Hand",
    ]
}
