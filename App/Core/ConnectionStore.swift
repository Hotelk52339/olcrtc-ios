import Foundation

// MARK: - ConnectionStore
//
// Single source of truth for the saved connection list and the primary
// selection. Protocol-agnostic — stores `ConnectionRecord`s, not olcrtc
// records specifically. When other protocols (vless/xray/...) land,
// they reuse this store without changes.
//
// Persistence: UserDefaults JSON under `olcrtc_records_v2`. Encryption
// keys live in Keychain (never persisted to UserDefaults).

/// Protocol-agnostic store for saved connection records and the active primary
/// selection. Persists to UserDefaults JSON; encryption keys live in Keychain.
@MainActor
final class ConnectionStore: ObservableObject {
    @Published var connections: [ConnectionRecord] = [] {
        didSet { save() }
    }
    @Published var primaryID: UUID? {
        didSet { UserDefaults.standard.set(primaryID?.uuidString, forKey: "olcrtc_primary_id") }
    }

    /// #375: true when the last secret hydration hit a Keychain *read error* (as
    /// opposed to a genuinely-absent key) for at least one connection — the
    /// classic case is the device being locked before first unlock, so the
    /// `AfterFirstUnlockThisDeviceOnly` key can't be read yet and would otherwise
    /// be cached as "" (later surfacing as the misleading "key length 0"). The UI
    /// observes this to show "unlock the device and reopen", and the app
    /// re-hydrates on the next foreground (see `rehydrateSecrets`).
    @Published private(set) var secretsLocked = false

    /// Returns the explicit primary, or the first connection as implicit
    /// fallback (single-server case: that one is "primary" by default).
    var primary: ConnectionRecord? {
        if let id = primaryID, let r = connections.first(where: { $0.id == id }) {
            return r
        }
        return connections.first
    }

    /// #437: the live store, so an App Intent can read `primary` to connect. Weak —
    /// the real instance is retained by `App`'s `@StateObject`; throwaway
    /// test/preview instances overwrite it harmlessly. See `TunnelManager.shared`.
    @MainActor static weak var shared: ConnectionStore?

    init() {
        load()
        Self.shared = self   // #437
    }

    func add(_ r: ConnectionRecord) {
        connections.append(r)
        LogStore.shared.log(.connection, "+ added connection: \(r.displayName) [\(r.subtitle)]")
        if primaryID == nil {
            primaryID = r.id
            LogStore.shared.log(.connection, "★ primary set to \(r.displayName) (auto, first record)")
        }
    }

    func remove(at idx: IndexSet) {
        let removed = idx.compactMap { connections.indices.contains($0) ? connections[$0] : nil }
        connections.remove(atOffsets: idx)
        for r in removed {
            // Also drop the keychain entry — leaving it would leak the
            // encryption key indefinitely after the user thought they
            // deleted the connection.
            ConnectionSecretStore.remove(connectionID: r.id)
            LogStore.shared.log(.connection, "− removed connection: \(r.displayName)")
        }
        if let pid = primaryID, !connections.contains(where: { $0.id == pid }) {
            primaryID = connections.first?.id
            if let p = connections.first {
                LogStore.shared.log(.connection, "★ primary fallback → \(p.displayName)")
            }
        }
        // boc #469: a subscription could never be forgotten — its meta was only
        // ever written by import, so deleting all of its rows left the source
        // registered, and the next refresh (launch or pull) brought every node
        // back under fresh ids. Once no record of a source remains, forget it.
        for r in removed {
            // #470: the meta key and the records may hold the two link forms of
            // one list (`canonicalSource`), so both sides compare canonically.
            guard let source = r.subSourceURL else { continue }
            let canon = Self.canonicalSource(source)
            let keys = subscriptionMeta.keys.filter { Self.canonicalSource($0) == canon }
            guard !keys.isEmpty,
                  !connections.contains(where: { $0.subSourceURL.map(Self.canonicalSource) == canon })
            else { continue }
            for key in keys { subscriptionMeta[key] = nil }
            // #470 was: `\(source)` — the full link is a capability URL (see `sourceLabel`).
            LogStore.shared.log(.connection, "− forgot subscription \(Self.sourceLabel(source)): its last server was removed")
        }
        // eoc #469
    }

    func remove(id: UUID) {
        if let idx = connections.firstIndex(where: { $0.id == id }) {
            remove(at: IndexSet(integer: idx))
        }
    }

    func update(_ r: ConnectionRecord) {
        if let i = connections.firstIndex(where: { $0.id == r.id }) {
            // #472: every path that corrects a record goes through here — rotate
            // key, recover, reconfigure, the editor, a subscription refresh. If
            // the connection this record describes changed, the stored health
            // verdict measured something else; drop it rather than show it.
            let before = HealthCoordinator.fingerprint(connections[i])
            let after  = HealthCoordinator.fingerprint(r)
            if before != after { HealthCoordinator.shared.forget(recordID: r.id) }
            connections[i] = r
            // boc #470: `save()` never deletes a Keychain item for a secret that
            // is "" — on purpose: a Keychain READ failure (device locked before
            // first unlock) also leaves "" in memory, and a delete there would
            // wipe the real value. But an explicit `update` is a decision about
            // the whole record: a reconfigure away from wbstream (or with the
            // token field cleared) writes `wbToken: ""` and the server drops
            // `auth.token` — yet `hydrateSecrets` put the OLD token back on the
            // next launch, so the engine kept sending the credential the user had
            // removed. Blank the stored item to match. Only an item that holds a
            // value (never create an empty one), and never while the secrets are
            // known-unreadable. The key is left alone: "" is never a valid key,
            // so a blank one is always the locked-Keychain symptom, not a choice.
            if !secretsLocked, case .olcrtc(let p) = r.details {
                if p.socksPass.isEmpty,
                   let stored = ConnectionSecretStore.socksPass(for: r.id), !stored.isEmpty {
                    ConnectionSecretStore.setSocksPass(connectionID: r.id, pass: "")
                }
                if p.wbToken.isEmpty,
                   let stored = ConnectionSecretStore.wbToken(for: r.id), !stored.isEmpty {
                    ConnectionSecretStore.setWBToken(connectionID: r.id, token: "")
                }
            }
            // eoc #470
            LogStore.shared.log(.connection, "✎ updated connection: \(r.displayName)")
        }
    }

    func setPrimary(_ id: UUID) {
        primaryID = id
        if let r = connections.first(where: { $0.id == id }) {
            LogStore.shared.log(.connection, "★ primary → \(r.displayName)")
        }
    }

    // MARK: Subscriptions (#356)
    //
    // Re-importing the same olcrtc-sub:// link must diff against the records it
    // produced last time — add new nodes, update changed ones in place (keeping
    // their UUID/keychain entry and primary selection), drop nodes the source
    // no longer lists — instead of blind-appending duplicates (the #111 bug).
    // Records are tied to a source by `subSourceURL` and matched by `subNodeKey`.

    /// Per-source refresh bookkeeping, persisted alongside the connection list.
    /// `refreshInterval` is the `#refresh` interval (seconds) last seen for the
    /// source; `lastRefresh` is when we last imported it. Both feed `isRefreshDue`.
    /// #363 adds the surfaced group-level metadata (name + `#used`/`#available`
    /// quota + node count) so a group detail view can render it without re-fetch.
    /// Synthesised Codable: old metas decode the new fields as nil with no migration.
    struct SubscriptionMeta: Codable, Equatable {
        var refreshInterval: TimeInterval?
        var lastRefresh    : Date
        var name           : String?   // #363: global #name (group label)
        var used           : String?   // #363: global #used (e.g. "10mb/10gb")
        var available      : String?   // #363: global #available
        var serverCount    : Int?      // #363: number of nodes last imported
    }

    /// sourceURL → meta. Persisted under `olcrtc_sub_meta_v1`.
    @Published private(set) var subscriptionMeta: [String: SubscriptionMeta] = [:] {
        didSet { saveSubMeta() }
    }

    /// Pure diff used by `importSubscription` (and exercised directly in tests).
    /// `existing` is the current record list; `source` selects the records that
    /// belong to this subscription. Returns the records to insert, the updated
    /// versions of matched records (same id), and the ids to remove.
    struct SubscriptionDiff: Equatable {
        var toAdd   : [ConnectionRecord] = []
        var toUpdate: [ConnectionRecord] = []
        var toRemove: [UUID] = []
    }

    /// #470: one subscription, one identity. The same list reaches the app as an
    /// `olcrtc-sub://h/p` deep link AND as the `https://h/p` it is fetched from
    /// (App.swift keys a pasted https link on itself), and the two were separate
    /// sources: the second import added every node again and the group footer
    /// read "2 sources". Matching and the meta bookkeeping compare THIS form —
    /// the fetch URL, which `fetchURL(for:)` already derives the same way. What
    /// a record stores stays the caller's link, so nothing on disk is rewritten
    /// and every existing key still resolves.
    static func canonicalSource(_ source: String) -> String {
        guard var comps = URLComponents(string: source),
              comps.scheme?.lowercased() == "olcrtc-sub" else { return source }
        comps.scheme = "https"
        return comps.string ?? source
    }

    /// #470: what a log line may say about a subscription link. The link is a
    /// capability URL — whoever holds it downloads every node's key — and the
    /// connection log is exportable, so only the host is written (the refresh
    /// failure path always did this; the import and skip lines did not).
    private static func sourceLabel(_ source: String) -> String {
        URL(string: source)?.host ?? "<subscription link>"
    }

    static func diffSubscription(_ sub: OlcrtcSubscription,
                                 source: String,
                                 group: String,
                                 existing: [ConnectionRecord]) -> SubscriptionDiff {
        // Records previously imported from this source, keyed by node.
        // #470 was: `where r.subSourceURL == source` — the exact string, so the
        // https form of an olcrtc-sub:// list matched nothing and re-added it all.
        let canon = canonicalSource(source)
        var byKey: [String: ConnectionRecord] = [:]
        for r in existing where r.subSourceURL.map(canonicalSource) == canon {
            if let k = r.subNodeKey { byKey[k] = r }
        }
        var diff = SubscriptionDiff()
        var seen = Set<String>()
        for entry in sub.entries {
            let key = entry.nodeKey
            // De-dup within a single list too: keep the first occurrence.
            guard seen.insert(key).inserted else { continue }
            let params = connection(from: entry)
            // boc #470: `nodeKey` includes the encryption KEY, so a provider that
            // rotates it produced a miss — the same node was added again and the
            // record the user had been using (with its id, health history and
            // primary flag) was deleted by the removal loop below. Fall back to
            // the node's identity without the key; that IS the same node, and the
            // update branch replaces `details` with the new key anyway.
            var prior = byKey[key]
            if prior == nil,
               let (staleKey, match) = byKey.first(where: { k, r in
                   !seen.contains(k) && Self.sameNode(r, entry)
               }) {
                prior = match
                seen.insert(staleKey)   // the removal loop must skip it
            }
            // eoc #470
            if let prior {
                // Update in place: keep id (and thus keychain + primary), refresh
                // the protocol params, name, group, provenance, and #363 metadata.
                var updated = prior
                updated.name      = entry.recordName
                updated.groupName = group
                updated.details   = .olcrtc(params)
                updated.subSourceURL = source
                updated.subNodeKey   = key
                updated.subIP        = entry.ip          // #363
                updated.subComment   = entry.comment
                updated.subUsed      = entry.used
                updated.subAvailable = entry.available
                if updated != prior { diff.toUpdate.append(updated) }
            } else {
                var added = ConnectionRecord(
                    name: entry.recordName, groupName: group,
                    details: .olcrtc(params),
                    subSourceURL: source, subNodeKey: key)
                added.subIP        = entry.ip            // #363
                added.subComment   = entry.comment
                added.subUsed      = entry.used
                added.subAvailable = entry.available
                diff.toAdd.append(added)
            }
        }
        // Anything from this source not in the new list is removed.
        for (key, r) in byKey where !seen.contains(key) {
            diff.toRemove.append(r.id)
        }
        return diff
    }

    /// #470: the same node under a rotated key — carrier, transport, room and
    /// client id, i.e. `Entry.nodeKey` minus the key.
    private static func sameNode(_ record: ConnectionRecord, _ entry: OlcrtcSubscription.Entry) -> Bool {
        guard case .olcrtc(let p) = record.details else { return false }
        let e = entry.parsed
        return p.carrier == e.carrier && p.transport == e.transport
            && p.roomID == e.roomID && p.clientID == e.clientID
    }

    /// Builds the protocol params for a subscription entry (#355 sei params
    /// carried through; #356 dedup uses the result).
    private static func connection(from entry: OlcrtcSubscription.Entry) -> OlcrtcConnection {
        // #401: the Parsed → connection mapping (sei defaults 30/10/1200/1) now
        // lives in OlcrtcConnection.init(from:), shared with the import paths.
        OlcrtcConnection(from: entry.parsed)
    }

    /// Applies a (re-)import of `sub` fetched from `source`. Diffs against the
    /// existing records for that source so re-opening the same link updates in
    /// place instead of duplicating, then records the refresh bookkeeping.
    /// Returns the diff so the caller can report add/update/remove counts.
    @discardableResult
    func importSubscription(_ sub: OlcrtcSubscription, source: String) -> SubscriptionDiff {
        let group = sub.name ?? ConnectionRecord.defaultGroupName
        let diff  = Self.diffSubscription(sub, source: source, group: group, existing: connections)

        if !diff.toRemove.isEmpty {
            for id in diff.toRemove { ConnectionSecretStore.remove(connectionID: id) }
            connections.removeAll { diff.toRemove.contains($0.id) }
        }
        for updated in diff.toUpdate {
            if let i = connections.firstIndex(where: { $0.id == updated.id }) {
                connections[i] = updated
            }
        }
        for added in diff.toAdd { connections.append(added) }
        if primaryID == nil, let first = connections.first { primaryID = first.id }
        // Repair a dangling primary if the diff removed the selected record.
        if let pid = primaryID, !connections.contains(where: { $0.id == pid }) {
            primaryID = connections.first?.id
        }

        // #470: a twin key for the same list (its other link form) is THIS source
        // now — one meta, one refresh, one footer entry.
        let canon = Self.canonicalSource(source)
        for twin in subscriptionMeta.keys where twin != source && Self.canonicalSource(twin) == canon {
            subscriptionMeta[twin] = nil
        }
        subscriptionMeta[source] = SubscriptionMeta(
            refreshInterval: sub.refreshInterval, lastRefresh: Date(),
            name: sub.name, used: sub.used, available: sub.available,   // #363
            serverCount: sub.entries.count)

        // #470 was: `\(source)` — the whole link, into the exportable log.
        LogStore.shared.log(.connection,
            "⬇ subscription \(Self.sourceLabel(source)): +\(diff.toAdd.count) ~\(diff.toUpdate.count) −\(diff.toRemove.count)")
        return diff
    }

    /// #470: the meta for a source under either of its link forms (exact key
    /// first, then the canonical twin) — a group whose records still carry the
    /// deep-link form must find the meta an https re-import re-keyed.
    private func meta(for source: String) -> SubscriptionMeta? {
        if let exact = subscriptionMeta[source] { return exact }
        let canon = Self.canonicalSource(source)
        return subscriptionMeta.first { Self.canonicalSource($0.key) == canon }?.value
    }

    /// Whether a source is due for a refresh, given its stored `#refresh`
    /// interval and the time of the last import (#356). Unknown source or no
    /// interval → false (we never nag about a list that didn't ask for it).
    func isRefreshDue(source: String, now: Date = Date()) -> Bool {
        guard let meta = meta(for: source), let interval = meta.refreshInterval,   // #470: either link form
              interval > 0 else { return false }
        return now.timeIntervalSince(meta.lastRefresh) >= interval
    }

    // MARK: Refresh-due trigger (#362)
    //
    // #356 added `isRefreshDue` + the stored interval/lastRefresh but nothing
    // ever called them. #362 wires a trigger: on app launch and from a manual
    // pull-to-refresh, find the sources whose `#refresh` interval has elapsed
    // and silently re-fetch + re-import them (the diff dedups, so this updates
    // servers in place). The re-fetch is injectable for tests; it defaults to
    // SubscriptionFetcher.fetch.

    /// Every known subscription source whose `#refresh` interval has elapsed.
    func dueSources(now: Date = Date()) -> [String] {
        subscriptionMeta.keys.filter { isRefreshDue(source: $0, now: now) }
    }

    /// #411: whether any subscription source is known. The manual pull-to-refresh
    /// is offered (and its hint shown) only when this is true.
    var hasSubscriptions: Bool { !subscriptionMeta.isEmpty }

    /// Re-fetches + re-imports every refresh-due source (#362) — used by the
    /// launch auto-refresh. Returns the sources that refreshed successfully.
    @discardableResult
    func refreshDueSources(
        now: Date = Date(),
        fetch: (URL) async throws -> String = { try await SubscriptionFetcher.fetch(from: $0) }
    ) async -> [String] {
        await refresh(sources: dueSources(now: now), fetch: fetch)
    }

    /// #411: manual pull-to-refresh — re-fetch EVERY subscription source now,
    /// ignoring each source's `#refresh` interval (the user pulled, so refresh).
    @discardableResult
    func refreshAllSources(
        fetch: (URL) async throws -> String = { try await SubscriptionFetcher.fetch(from: $0) }
    ) async -> [String] {
        await refresh(sources: Array(subscriptionMeta.keys), fetch: fetch)
    }

    /// Re-fetches + re-imports the given subscription `sources`. Each source's
    /// canonical link is mapped to its HTTPS fetch URL the same way the initial
    /// import does (`olcrtc-sub://` → https swap; a plain https source is fetched
    /// as-is). A fetch/parse failure for one source is logged and skipped — it
    /// must not abort the others or surface a modal. Returns the sources that
    /// refreshed successfully.
    @discardableResult
    private func refresh(sources: [String],
                         fetch: (URL) async throws -> String) async -> [String] {
        var refreshed: [String] = []
        for source in sources {
            guard let fetchURL = Self.fetchURL(for: source) else {
                // #470 was: `\(source)` verbatim — host (and scheme, the usual
                // reason a fetch URL cannot be derived) only.
                LogStore.shared.log(.connection,
                    "⚠ subscription refresh: can't derive fetch URL for \(Self.sourceLabel(source)) (scheme \(URL(string: source)?.scheme ?? "?")) — skipped")
                continue
            }
            do {
                let body = try await fetch(fetchURL)
                let parsed = OlcrtcSubscription.parse(body)
                // boc #469: the manual import refuses a body with no server lines
                // (`emptySubscription`); this path fed one straight into the diff,
                // whose "remove what the source no longer lists" step then deleted
                // EVERY record of the source — and their Keychain keys. A captive
                // portal, a Cloudflare challenge, any HTTP 200 that is not the
                // subscription did exactly that on launch. An empty parse is not
                // an emptied subscription; it is a fetch that returned the wrong
                // thing.
                guard !parsed.entries.isEmpty else {
                    LogStore.shared.log(.connection,
                        "⚠ subscription refresh for \(fetchURL.host ?? source): the answer held no servers — kept the saved ones")
                    continue
                }
                // eoc #469
                importSubscription(parsed, source: source)
                refreshed.append(source)
            } catch {
                LogStore.shared.log(.connection,
                    "✗ subscription refresh failed for \(fetchURL.host ?? source): \(error.localizedDescription)")
            }
        }
        return refreshed
    }

    /// Maps a stored subscription `source` link to the HTTPS URL it is fetched
    /// from: `olcrtc-sub://` is scheme-swapped to https (same as the import
    /// path); a plain `https://` source is used directly. Anything else → nil.
    static func fetchURL(for source: String) -> URL? {
        guard let url = URL(string: source) else { return nil }
        switch url.scheme?.lowercased() {
        case "olcrtc-sub": return try? OlcrtcSubscription.httpsURL(from: url)
        case "https":      return url
        default:           return nil
        }
    }

    func grouped() -> [(group: String, items: [ConnectionRecord])] {
        Dictionary(grouping: connections, by: { $0.groupName })
            .sorted { $0.key < $1.key }
            .map { (group: $0.key, items: $0.value) }
    }

    /// #363: the (source, meta) for a group, if any of its records came from a
    /// subscription. Returns nil for a purely manual group so the UI shows no
    /// metadata section.
    ///
    /// #396 was: returned only the FIRST record's source + that one source's
    /// meta. But groups are keyed by `#name`, so two subscriptions sharing a
    /// `#name` land in one group — the footer then showed only one source's
    /// quota plus a `serverCount` that mismatched the listed rows. Now the
    /// returned info reflects ALL sources/records grouped under the name:
    ///   • `source` — the single source if there's one, else a "N sources" label;
    ///   • `serverCount` — the actual number of subscription-backed rows here
    ///     (not one source's stored count);
    ///   • `used`/`available` — joined across the distinct sources (server-
    ///     provided free text; can't be summed, so they're listed);
    ///   • `name` — the (shared) group name; `refreshInterval`/`lastRefresh` —
    ///     the soonest-due source (smallest interval, then earliest refresh).
    func subscriptionInfo(for items: [ConnectionRecord]) -> (source: String, meta: SubscriptionMeta)? {
        // Distinct sources backing this group, in first-seen order.
        // #470: distinct by canonical form — the deep-link and https spellings of
        // one list are one source, not "2 sources".
        var sources: [String] = []
        for r in items {
            if let s = r.subSourceURL,
               !sources.contains(where: { Self.canonicalSource($0) == Self.canonicalSource(s) }) {
                sources.append(s)
            }
        }
        let metas = sources.compactMap { meta(for: $0) }   // #470 was: subscriptionMeta[$0]
        guard let first = metas.first else { return nil }

        // Rows that actually came from a subscription — the real server count for
        // the group, independent of any single source's stored `serverCount`.
        let backedCount = items.filter { $0.subSourceURL != nil }.count

        if sources.count == 1 {
            // Single-source group: correct the count to the listed rows, keep the
            // rest of the stored meta as-is.
            var meta = first
            meta.serverCount = backedCount
            return (sources[0], meta)
        }

        // Multi-source group sharing a `#name`. Synthesise an aggregate meta.
        let usedParts      = metas.compactMap { $0.used }.filter { !$0.isEmpty }
        let availableParts = metas.compactMap { $0.available }.filter { !$0.isEmpty }
        // Soonest-due source drives the refresh display: smallest positive
        // interval first, then the earliest lastRefresh.
        let soonest = metas.min { a, b in
            let ia = a.refreshInterval ?? .greatestFiniteMagnitude
            let ib = b.refreshInterval ?? .greatestFiniteMagnitude
            if ia != ib { return ia < ib }
            return a.lastRefresh < b.lastRefresh
        }
        let aggregate = SubscriptionMeta(
            refreshInterval: soonest?.refreshInterval,
            lastRefresh:     soonest?.lastRefresh ?? first.lastRefresh,
            name:            first.name,
            used:            usedParts.isEmpty      ? nil : usedParts.joined(separator: ", "),
            available:       availableParts.isEmpty ? nil : availableParts.joined(separator: ", "),
            serverCount:     backedCount)
        // `source` is shown as a host label; with several, surface the count
        // instead of an arbitrary one.
        return (L10n.subMetaMultipleSources_fmt.formatted(sources.count), aggregate)
    }

    /// Sorted unique group names already in use. Used by the connection
    /// editor to suggest existing groups via a quick-pick menu.
    var allGroupNames: [String] {
        Array(Set(connections.map(\.groupName))).sorted()
    }

    // MARK: Persistence

    private static let v2Key      = "olcrtc_records_v2"
    /// #469: where an UNREADABLE records blob is parked before anything can
    /// overwrite it. Written once (the first failure's bytes are the originals).
    private static let v2BackupKey = "olcrtc_records_v2.unreadable"
    private static let subMetaKey = "olcrtc_sub_meta_v1"   // #356

    /// Saves the connection list to UserDefaults with the encryption key
    /// stripped from JSON — the key lives in Keychain instead. This runs
    /// from `didSet` on `connections`, so any in-memory mutation lands on
    /// disk with no key bytes.
    private func save() {
        let scrubbed = connections.map { record -> ConnectionRecord in
            var r = record
            if case .olcrtc(var p) = r.details {
                if !p.key.isEmpty {
                    ConnectionSecretStore.setKey(connectionID: r.id, key: p.key)
                }
                if !p.socksPass.isEmpty {
                    ConnectionSecretStore.setSocksPass(connectionID: r.id, pass: p.socksPass)
                }
                if !p.wbToken.isEmpty {   // #436
                    ConnectionSecretStore.setWBToken(connectionID: r.id, token: p.wbToken)
                }
                p.key       = ""
                p.socksPass = ""
                p.wbToken   = ""   // #436: never persisted to UserDefaults
                r.details = .olcrtc(p)
            }
            return r
        }
        if let data = try? JSONEncoder().encode(scrubbed) {
            UserDefaults.standard.set(data, forKey: Self.v2Key)
        }
    }

    private func load() {
        var list: [ConnectionRecord] = []
        if let data = UserDefaults.standard.data(forKey: Self.v2Key) {
            do {
                list = try JSONDecoder().decode([ConnectionRecord].self, from: data)
            } catch {
                LogStore.shared.log(.connection, "⚠ ConnectionStore: failed to decode saved connections: \(error.localizedDescription)")
                // boc #469: `connections = []` below fires didSet → save(), which
                // wrote the empty list straight over the only copy of the user's
                // connections — a decode failure was a wipe. Park the unreadable
                // bytes under a side key FIRST, once, so a later launch cannot
                // overwrite the originals with a second failure, and say so.
                // Recovery is then a newer build reading the old shape, not a
                // lost list.
                if UserDefaults.standard.data(forKey: Self.v2BackupKey) == nil {
                    UserDefaults.standard.set(data, forKey: Self.v2BackupKey)
                }
                LogStore.shared.log(.connection,
                    "⚠ ConnectionStore: kept the unreadable list under \(Self.v2BackupKey) (\(data.count) bytes) — nothing was deleted")
                // eoc #469
            }
        }

        // #375: hydrate secrets, tracking whether any read hit a Keychain ERROR
        // (device locked before first unlock) vs. a genuinely-absent key. On an
        // error we flag `secretsLocked` so the UI can prompt to unlock + reopen,
        // and `rehydrateSecrets()` (called on foreground) retries the read.
        var sawReadError = false
        connections = list.map { record in
            let (hydrated, readError) = Self.hydrateSecrets(record)
            if readError { sawReadError = true }
            return hydrated
        }
        secretsLocked = sawReadError

        if let s = UserDefaults.standard.string(forKey: "olcrtc_primary_id"),
           let uuid = UUID(uuidString: s) {
            primaryID = uuid
        }

        // #356: subscription refresh bookkeeping. Assigned directly (not via the
        // published setter inside `load()` semantics) — the didSet re-save is a
        // harmless no-op writing the same bytes back.
        // #470 was: `try?` with no log — a blob that failed to decode dropped
        // EVERY source silently: no auto-refresh, no footer, and the next import
        // re-saved a one-entry dictionary over the rest. Say so, and keep the
        // entries that still read (one bad meta must not take the others).
        if let data = UserDefaults.standard.data(forKey: Self.subMetaKey) {
            do {
                subscriptionMeta = try JSONDecoder().decode([String: SubscriptionMeta].self, from: data)
            } catch {
                LogStore.shared.log(.connection,
                    "⚠ ConnectionStore: failed to decode subscription meta: \(error.localizedDescription) — keeping the entries that still read")
                if let lenient = try? JSONDecoder().decode([String: Lenient<SubscriptionMeta>].self, from: data) {
                    subscriptionMeta = lenient.compactMapValues(\.value)
                }
            }
        }
    }

    /// #470: decodes to nil instead of failing the container it sits in, so a
    /// dictionary with one unreadable value still yields the readable ones.
    private struct Lenient<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) { value = try? T(from: decoder) }
    }

    /// Persists `subscriptionMeta` (#356). Runs from its `didSet`.
    private func saveSubMeta() {
        if let data = try? JSONEncoder().encode(subscriptionMeta) {
            UserDefaults.standard.set(data, forKey: Self.subMetaKey)
        }
    }

    /// #375: re-read every connection's secrets from Keychain and clear
    /// `secretsLocked` if the read now succeeds. Call on app foreground
    /// (`.scenePhase == .active`) so a key that was unreadable at a locked-device
    /// launch is hydrated before the user can hit Connect — turning a misleading
    /// "key length 0" into a working connection once the device is unlocked.
    ///
    /// Cheap no-op unless we're actually in the locked state: when nothing was
    /// locked the in-memory keys are already correct, so we skip the re-read (and
    /// the `connections` reassignment's `save()` round-trip) entirely.
    func rehydrateSecrets() {
        guard secretsLocked else { return }
        var sawReadError = false
        connections = connections.map { record in
            let (hydrated, readError) = Self.hydrateSecrets(record)
            if readError { sawReadError = true }
            return hydrated
        }
        secretsLocked = sawReadError
    }

    /// Hydrates a record's secrets from Keychain. The second tuple element is
    /// true when a read hit a genuine Keychain ERROR (`.failure`) rather than a
    /// missing key (`.success(nil)`) — #375: the locked-before-first-unlock case,
    /// where caching the resulting "" would later look like "key length 0". On an
    /// error we leave the existing in-memory value untouched (don't clobber a key
    /// hydrated by an earlier successful pass).
    private static func hydrateSecrets(_ record: ConnectionRecord) -> (ConnectionRecord, readError: Bool) {
        var r = record
        var readError = false
        if case .olcrtc(var p) = r.details {
            switch ConnectionSecretStore.keyResult(for: r.id) {
            case .success(let kc?): p.key = kc
            case .success(nil):     break          // genuinely absent — leave as-is
            case .failure:          readError = true   // locked / unreadable — retry on foreground
            }
            if let sp = ConnectionSecretStore.socksPass(for: r.id) { p.socksPass = sp }
            if let wt = ConnectionSecretStore.wbToken(for: r.id)  { p.wbToken   = wt }   // #436
            r.details = .olcrtc(p)
        }
        return (r, readError)
    }
}

