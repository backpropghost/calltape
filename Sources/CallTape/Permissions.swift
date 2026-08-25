import Foundation
import AVFoundation
import Contacts
import AppKit
import SQLite3

/// Thin wrappers around the OS permission prompts CallTape needs, plus helpers
/// to send the user to the right System Settings pane.
enum Permissions {

    static var microphoneGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func requestMicrophone(_ completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    static var contactsGranted: Bool {
        CNContactStore.authorizationStatus(for: .contacts) == .authorized
    }

    static func requestContacts(_ completion: @escaping (Bool) -> Void) {
        CNContactStore().requestAccess(for: .contacts) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    /// Full Disk Access has no query API, so we test it the way other apps do: try to
    /// actually open and read the call-history database. If TCC is blocking us the
    /// query fails, even though the file looks readable on disk.
    static var callLogReadable: Bool {
        var db: OpaquePointer?
        let uri = "file:\(Enrichment.callDBPath())?mode=ro"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return false
        }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        let ok = sqlite3_prepare_v2(db, "SELECT Z_PK FROM ZCALLRECORD LIMIT 1;", -1, &stmt, nil) == SQLITE_OK
        sqlite3_finalize(stmt)
        return ok
    }

    static func openSettings(_ pane: Pane) {
        if let url = URL(string: pane.urlString) { NSWorkspace.shared.open(url) }
    }

    enum Pane {
        case microphone, contacts, fullDiskAccess
        var urlString: String {
            let base = "x-apple.systempreferences:com.apple.preference.security"
            switch self {
            case .microphone:     return "\(base)?Privacy_Microphone"
            case .contacts:       return "\(base)?Privacy_Contacts"
            case .fullDiskAccess: return "\(base)?Privacy_AllFiles"
            }
        }
    }
}
