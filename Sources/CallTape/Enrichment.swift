import Foundation
import SQLite3
import Contacts

/// Turns a raw recording into a labeled one: finds the matching call (Apple's log
/// for cellular, WhatsApp's own database for WhatsApp), resolves the caller's name
/// from Contacts, and writes a JSON sidecar next to the audio.
enum Enrichment {

    enum Source { case cellular, whatsapp }

    struct CallMeta {
        var number: String?
        var direction: String?     // "incoming" / "outgoing" / nil
        var duration: Double?
        var logDate: Date?
        var isVideo: Bool?         // WhatsApp: voice vs video call
    }

    // MARK: Paths

    static func callDBPath() -> String {
        FileManager.default.homeDirectoryForCurrentUser.path
            + "/Library/Application Support/CallHistoryDB/CallHistory.storedata"
    }
    static func whatsAppDBPath() -> String {
        FileManager.default.homeDirectoryForCurrentUser.path
            + "/Library/Group Containers/group.net.whatsapp.WhatsApp.shared/CallHistory.sqlite"
    }
    static func whatsAppLIDDBPath() -> String {
        FileManager.default.homeDirectoryForCurrentUser.path
            + "/Library/Group Containers/group.net.whatsapp.WhatsApp.shared/LID.sqlite"
    }

    /// SQLite wants a copy of bound text (the string may be freed before the step).
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func openRO(_ path: String) -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open_v2("file:\(path)?mode=ro", &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            sqlite3_close(db); return nil
        }
        return db
    }

    // MARK: Apple call log

    static func currentMaxPK() -> Int64 {
        guard let db = openRO(callDBPath()) else { return 0 }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        var pk: Int64 = 0
        if sqlite3_prepare_v2(db, "SELECT COALESCE(MAX(Z_PK), 0) FROM ZCALLRECORD;", -1, &stmt, nil) == SQLITE_OK,
           sqlite3_step(stmt) == SQLITE_ROW {
            pk = sqlite3_column_int64(stmt, 0)
        }
        sqlite3_finalize(stmt)
        return pk
    }

    private static func matchCellular(afterPK baseline: Int64, near start: Date) -> CallMeta? {
        guard let db = openRO(callDBPath()) else { return nil }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        let sql = "SELECT ZDATE, ZADDRESS, ZDURATION, ZORIGINATED FROM ZCALLRECORD WHERE Z_PK > ? ORDER BY Z_PK DESC LIMIT 15;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_int64(stmt, 1, baseline)
        defer { sqlite3_finalize(stmt) }

        var best: (CallMeta, TimeInterval)?
        while sqlite3_step(stmt) == SQLITE_ROW {
            let logDate = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(stmt, 0))
            var number = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            number = number.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            let duration = sqlite3_column_double(stmt, 2)
            let direction = sqlite3_column_int64(stmt, 3) == 1 ? "outgoing" : "incoming"
            let diff = abs(logDate.timeIntervalSince(start))
            if diff < 120, best == nil || diff < best!.1 {
                best = (CallMeta(number: number, direction: direction, duration: duration, logDate: logDate), diff)
            }
        }
        return best?.0
    }

    // MARK: WhatsApp call log

    private static func matchWhatsApp(near start: Date) -> CallMeta? {
        guard let db = openRO(whatsAppDBPath()) else { return nil }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        // Direction lives in ZWAAGGREGATECALLEVENT (ZINCOMING/ZVIDEO/ZMISSED), linked
        // to the call event by timestamp. The participant JID gives the number when
        // it is a real "@s.whatsapp.net" address (recent 1:1 calls often store an
        // opaque "@lid" instead, which we reject).
        let sql = """
        SELECT e.ZDATE, e.ZDURATION, a.ZINCOMING, a.ZVIDEO, p.ZJIDSTRING
        FROM ZWACDCALLEVENT e
        LEFT JOIN ZWAAGGREGATECALLEVENT a ON ABS(a.ZFIRSTDATE - e.ZDATE) < 2
        LEFT JOIN ZWACDCALLEVENTPARTICIPANT p ON p.Z1PARTICIPANTS = e.Z_PK
        ORDER BY e.Z_PK DESC LIMIT 20;
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        var best: (CallMeta, TimeInterval)?
        while sqlite3_step(stmt) == SQLITE_ROW {
            let logDate = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(stmt, 0))
            let duration = sqlite3_column_double(stmt, 1)
            let direction = sqlite3_column_type(stmt, 2) == SQLITE_NULL ? nil
                : (sqlite3_column_int64(stmt, 2) == 1 ? "incoming" : "outgoing")
            let isVideo = sqlite3_column_type(stmt, 3) == SQLITE_NULL ? nil
                : (sqlite3_column_int64(stmt, 3) == 1)
            let jid = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
            let number = jid.flatMap(numberFromJID)
            let diff = abs(logDate.timeIntervalSince(start))
            if diff < 120, best == nil || diff < best!.1 {
                best = (CallMeta(number: number, direction: direction, duration: duration,
                                 logDate: logDate, isVideo: isVideo), diff)
            }
        }
        return best?.0
    }

    private static func numberFromJID(_ jid: String) -> String? {
        // "<digits>@s.whatsapp.net" is already a phone number. "@lid" is an opaque
        // linked-device ID that maps to a real number in LID.sqlite. "@g.us" (group)
        // has no single number.
        if jid.hasSuffix("@s.whatsapp.net") {
            let digits = (jid.split(separator: "@").first.map(String.init) ?? "").filter(\.isNumber)
            return digits.isEmpty ? nil : "+\(digits)"
        }
        if jid.hasSuffix("@lid") { return phoneForLID(jid) }
        return nil
    }

    /// Resolve WhatsApp's opaque "<id>@lid" to a real phone number via LID.sqlite.
    private static func phoneForLID(_ lid: String) -> String? {
        guard let db = openRO(whatsAppLIDDBPath()) else { return nil }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        let sql = "SELECT ZPHONENUMBER FROM ZWAZACCOUNT WHERE ZIDENTIFIER = ? AND ZPHONENUMBER IS NOT NULL LIMIT 1;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, lid, -1, transient)
        if sqlite3_step(stmt) == SQLITE_ROW, let text = sqlite3_column_text(stmt, 0) {
            let digits = String(cString: text).filter(\.isNumber)
            return digits.isEmpty ? nil : "+\(digits)"
        }
        return nil
    }

    // MARK: Contacts

    /// Resolve a display name for a phone number. Tries Apple's fuzzy match first,
    /// then a last-digits fallback across all contacts (handles country-code and
    /// formatting differences). Returns nil if Contacts isn't allowed or no match.
    static func contactName(for number: String?) -> String? {
        guard let number, !number.isEmpty,
              CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return nil }
        let store = CNContactStore()
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey,
                    CNContactNicknameKey, CNContactOrganizationNameKey,
                    CNContactPhoneNumbersKey] as [CNKeyDescriptor]

        let predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: number))
        if let match = try? store.unifiedContacts(matching: predicate, keysToFetch: keys).first,
           let name = displayName(match) {
            return name
        }

        // Fallback: compare the last 9 digits against every contact's numbers.
        let target = String(number.filter(\.isNumber).suffix(9))
        guard target.count >= 7 else { return nil }
        var found: String?
        let request = CNContactFetchRequest(keysToFetch: keys)
        try? store.enumerateContacts(with: request) { contact, stop in
            for phone in contact.phoneNumbers {
                if phone.value.stringValue.filter(\.isNumber).hasSuffix(target) {
                    found = displayName(contact)
                    stop.pointee = true
                    return
                }
            }
        }
        return found
    }

    /// Create a new contact with the given name and phone number.
    static func addContact(name: String, number: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let contact = CNMutableContact()
        contact.givenName = trimmed.isEmpty ? number : trimmed
        contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile,
                                               value: CNPhoneNumber(stringValue: number))]
        let store = CNContactStore()
        let request = CNSaveRequest()
        request.add(contact, toContainerWithIdentifier: nil)
        do { try store.execute(request); Log.info("Added contact for \(number)") }
        catch { Log.error("Add contact failed: \(error.localizedDescription)") }
    }

    /// Resolve name AND photo for a number in a single Contacts pass (used by the
    /// recordings list). Falls back to one last-9-digits enumeration on a miss.
    static func contactInfo(for number: String?) -> (name: String?, image: Data?) {
        guard let number, !number.isEmpty,
              CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return (nil, nil) }
        let store = CNContactStore()
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey,
                    CNContactOrganizationNameKey, CNContactThumbnailImageDataKey,
                    CNContactPhoneNumbersKey] as [CNKeyDescriptor]

        let predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: number))
        if let match = try? store.unifiedContacts(matching: predicate, keysToFetch: keys).first {
            return (displayName(match), match.thumbnailImageData)
        }
        let target = String(number.filter(\.isNumber).suffix(9))
        guard target.count >= 7 else { return (nil, nil) }
        var result: (String?, Data?) = (nil, nil)
        let request = CNContactFetchRequest(keysToFetch: keys)
        try? store.enumerateContacts(with: request) { contact, stop in
            for phone in contact.phoneNumbers where phone.value.stringValue.filter(\.isNumber).hasSuffix(target) {
                result = (displayName(contact), contact.thumbnailImageData)
                stop.pointee = true
                return
            }
        }
        return result
    }

    /// The contact's photo (thumbnail) for a phone number, if allowed and present.
    static func contactImageData(for number: String?) -> Data? {
        guard let number, !number.isEmpty,
              CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return nil }
        let store = CNContactStore()
        let keys = [CNContactThumbnailImageDataKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        let predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: number))
        if let match = try? store.unifiedContacts(matching: predicate, keysToFetch: keys).first,
           let data = match.thumbnailImageData {
            return data
        }
        // Last-9-digits fallback across all contacts.
        let target = String(number.filter(\.isNumber).suffix(9))
        guard target.count >= 7 else { return nil }
        var found: Data?
        let request = CNContactFetchRequest(keysToFetch: keys)
        try? store.enumerateContacts(with: request) { contact, stop in
            for phone in contact.phoneNumbers where phone.value.stringValue.filter(\.isNumber).hasSuffix(target) {
                found = contact.thumbnailImageData
                stop.pointee = true
                return
            }
        }
        return found
    }

    /// Best available human name: full name, then nickname, then organization.
    private static func displayName(_ contact: CNContact) -> String? {
        let full = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
        if !full.isEmpty { return full }
        if !contact.nickname.isEmpty { return contact.nickname }
        if !contact.organizationName.isEmpty { return contact.organizationName }
        return nil
    }

    // MARK: Sidecar

    private static func writeSidecar(for audioURL: URL, recStart: Date, recEnd: Date,
                                     meta: CallMeta?, contact: String?, source: Source) {
        let iso = ISO8601DateFormatter()
        var dict: [String: Any] = [
            "audio_file": audioURL.lastPathComponent,
            "recorded_start": iso.string(from: recStart),
            "recorded_end": iso.string(from: recEnd),
            "recorded_duration_seconds": Int(recEnd.timeIntervalSince(recStart)),
            "source": source == .whatsapp ? "whatsapp" : "cellular"
        ]
        if let meta {
            if let number = meta.number { dict["phone_number"] = number }
            if let direction = meta.direction { dict["direction"] = direction }
            if let duration = meta.duration { dict["call_log_duration_seconds"] = duration }
            if let logDate = meta.logDate { dict["call_log_date"] = iso.string(from: logDate) }
            if let isVideo = meta.isVideo { dict["call_type"] = isVideo ? "video" : "voice" }
        }
        dict["contact_name"] = contact ?? "(unknown)"

        let sidecar = audioURL.deletingPathExtension().appendingPathExtension("json")
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: sidecar)
        }
    }

    /// Write a sidecar right away with whatever we already know, so a recording is
    /// never left unlabeled if the app is quit before enrichment finishes. The
    /// slower `enrich` pass refines it afterwards.
    static func writeInitialSidecar(audioURL: URL, recStart: Date, recEnd: Date,
                                    baselinePK: Int64, source: Source) {
        let meta = source == .whatsapp ? matchWhatsApp(near: recStart)
                                       : matchCellular(afterPK: baselinePK, near: recStart)
        let contact = contactName(for: meta?.number)
        writeSidecar(for: audioURL, recStart: recStart, recEnd: recEnd, meta: meta, contact: contact, source: source)
    }

    /// Poll the relevant log (it lags behind the live call), resolve the name, and
    /// write the sidecar. Run off the main thread.
    static func enrich(audioURL: URL, recStart: Date, recEnd: Date, baselinePK: Int64,
                       source: Source, maxWait: TimeInterval) {
        var meta: CallMeta?
        let deadline = Date().addingTimeInterval(maxWait)
        repeat {
            meta = source == .whatsapp ? matchWhatsApp(near: recStart)
                                       : matchCellular(afterPK: baselinePK, near: recStart)
            if meta?.number != nil { break }
            Thread.sleep(forTimeInterval: 3)
        } while Date() < deadline

        let contact = contactName(for: meta?.number)
        writeSidecar(for: audioURL, recStart: recStart, recEnd: recEnd, meta: meta, contact: contact, source: source)
        Log.info("Enriched \(audioURL.lastPathComponent) [\(source == .whatsapp ? "whatsapp" : "cellular")]\(meta?.number == nil ? " (unmatched)" : "")")
        DispatchQueue.main.async { RecordingsStore.shared.reload() }
    }
}
