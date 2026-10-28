import Foundation

public struct PendingDelivery: Codable, Equatable, Sendable {
    public var session: Session
    public var codexUnreadScopes: Set<String> = []
    public var codexUnreadRevision: String?
    public init(session: Session) { self.session = session }
}

public struct SessionViewReceipt: Equatable, Sendable {
    public enum Evidence: String, Sendable { case claudeFocusedSession, claudeRemoteReadTransition, claudeVisibleSession, grokViewedSession, codexReadTransition, codexOpenedSession, codexAlreadyRead }
    public var sessionKey: String
    public var revision: String
    public var viewedAt: Date
    public var evidence: Evidence
    public init(sessionKey: String, revision: String, viewedAt: Date, evidence: Evidence) {
        self.sessionKey = sessionKey; self.revision = revision; self.viewedAt = viewedAt; self.evidence = evidence
    }
}

/// Pending entries survive app restarts and new turns. Island navigation is never a receipt.
public struct DeliveryInbox: Codable, Equatable, Sendable {
    public private(set) var pending: [String: PendingDelivery] = [:]
    public private(set) var acknowledged: [String: String] = [:]
    public init() {}
    @discardableResult public mutating func record(_ session: Session) -> Bool {
        guard session.state.shouldAlert, !session.revision.isEmpty,
              acknowledged[session.id] != session.alertKey else { return false }
        if let existing = pending[session.id] {
            guard existing.session.alertKey != session.alertKey,
                  session.updatedAt >= existing.session.updatedAt else { return false }
        }
        pending[session.id] = PendingDelivery(session: session)
        return true
    }
    /// Metadata can arrive before its transcript; enriching a pending item never marks it read.
    public mutating func refreshContent(from sessions: [Session]) {
        for session in sessions {
            guard var entry = pending[session.id], entry.session.alertKey == session.alertKey else { continue }
            entry.session.title = session.title; entry.session.summary = session.summary
            entry.session.directory = session.directory; entry.session.source = session.source
            entry.session.sourcePath = session.sourcePath; entry.session.remote = session.remote
            pending[session.id] = entry
        }
    }
    @discardableResult public mutating func acknowledge(_ receipt: SessionViewReceipt, now: Date = .now) -> Bool {
        guard let entry = pending[receipt.sessionKey], entry.session.revision == receipt.revision,
              receipt.viewedAt >= entry.session.updatedAt, receipt.viewedAt <= now.addingTimeInterval(2) else { return false }
        let expectedAgent: Agent
        switch receipt.evidence {
        case .claudeFocusedSession, .claudeRemoteReadTransition, .claudeVisibleSession: expectedAgent = .claude
        case .grokViewedSession: expectedAgent = .grok
        case .codexReadTransition, .codexOpenedSession, .codexAlreadyRead: expectedAgent = .codex
        }
        guard entry.session.agent == expectedAgent else { return false }
        acknowledged[receipt.sessionKey] = entry.session.alertKey
        pending.removeValue(forKey: receipt.sessionKey)
        return true
    }
    /// An absent ID is not sufficient: first witness this delivery as unread in the same scope.
    public mutating func observeCodex(_ snapshot: CodexReadSnapshot, now: Date = .now) {
        for key in Array(pending.keys) {
            guard var entry = pending[key], entry.session.agent == .codex,
                  snapshot.modifiedAt >= entry.session.updatedAt else { continue }
            let previous = entry.codexUnreadScopes
            for (scope, unread) in snapshot.unreadByScope where snapshot.scopeMatches(scope, session: entry.session) && unread.contains(entry.session.sessionID) {
                entry.codexUnreadScopes.insert(scope)
                if snapshot.publishedTurn(for: entry.session) == entry.session.revision { entry.codexUnreadRevision = entry.session.revision }
            }
            pending[key] = entry
            let confirmedRead = previous.contains { scope in
                guard let unread = snapshot.unreadByScope[scope] else { return false }
                return !unread.contains(entry.session.sessionID)
            }
            let published = snapshot.publishedTurn(for: entry.session)
            let sameDelivery = published == entry.session.revision || (published == nil && entry.codexUnreadRevision == entry.session.revision)
            // The desktop keeps an authoritative unread set for its known UI threads.
            // If a delivery was read before our first poll, there is no transition to witness.
            // Corroborate that state with the exact published turn and a known matching host.
            let hasHost = snapshot.unreadByScope.keys.contains { snapshot.scopeMatches($0, session: entry.session) }
            let alreadyRead = snapshot.knownUIThreadIDs.contains(entry.session.sessionID) && hasHost &&
                published == entry.session.revision &&
                !snapshot.unreadByScope.values.contains { $0.contains(entry.session.sessionID) }
            if (confirmedRead && sameDelivery) || alreadyRead {
                _ = acknowledge(SessionViewReceipt(sessionKey: key, revision: entry.session.revision,
                    viewedAt: snapshot.modifiedAt, evidence: alreadyRead ? .codexAlreadyRead : .codexReadTransition), now: now)
            }
        }
    }
}

public struct CodexReadSnapshot: Sendable {
    public var unreadByScope: [String: Set<String>]
    public var modifiedAt: Date
    public var publishedTurnByThread: [String: String]
    public var publishedTurnBySession: [String: String] = [:]
    public var knownUIThreadIDs: Set<String> = []
    public var sourceAppIsForeground: Bool
    public init(unreadByScope: [String: Set<String>], modifiedAt: Date, publishedTurnByThread: [String: String] = [:], sourceAppIsForeground: Bool = false) {
        self.unreadByScope = unreadByScope; self.modifiedAt = modifiedAt; self.publishedTurnByThread = publishedTurnByThread
        self.sourceAppIsForeground = sourceAppIsForeground
    }
    public func scopeMatches(_ scope: String, session: Session) -> Bool {
        let host = String(scope.split(separator: "/", maxSplits: 1).last ?? "")
        if let remote = session.remote {
            guard remote.kind == .ssh, let hostID = remote.hostID else { return false }
            return host == hostID || host.hasPrefix(hostID + ":")
        }
        return host == "local" || host.hasPrefix("local:")
    }
    public func publishedTurn(for session: Session) -> String? {
        publishedTurnBySession[session.id] ?? (session.remote == nil ? publishedTurnByThread[session.sessionID] : nil)
    }
    public static func parse(_ root: [String: Any], modifiedAt: Date) -> Self? {
        guard let state = root["electron-thread-read-state-v1"] as? [String: Any],
              state["version"] as? Int == 1,
              let identities = state["unreadByIdentity"] as? [String: [String: Any]] else { return nil }
        var scopes: [String: Set<String>] = [:]
        for (identity, hosts) in identities {
            for (host, value) in hosts {
                guard let ids = value as? [String] else { continue }
                scopes[identity + "/" + host] = Set(ids)
            }
        }
        var snapshot = Self(unreadByScope: scopes, modifiedAt: modifiedAt)
        let atoms = root["electron-persisted-atom-state"] as? [String: Any] ?? [:]
        let prefix = "thread-reference-capability:"
        for (key, value) in atoms where key.hasPrefix(prefix) && value as? Bool == true {
            let id = String(key.dropFirst(prefix.count))
            if UUID(uuidString: id) != nil { snapshot.knownUIThreadIDs.insert(id) }
        }
        return snapshot
    }
}

public enum CompactIslandLayout {
    public static func width(mode: StatusBarMode, physicalNotchWidth: Double = 0, configuration: StatusBarConfiguration = .defaults) -> Double {
        configuration.resolvedWidth(for: mode, physicalNotchWidth: physicalNotchWidth)
    }
}
