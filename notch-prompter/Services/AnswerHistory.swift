import Foundation
import SQLite3

/// One question and the answer shown for it.
struct AnswerRecord: Identifiable, Equatable {
    var id: Int64
    let sessionID: String
    let askedAt: Date
    let question: String
    var answer: String
    let model: String
    var latency: TimeInterval?
    /// True when a newer question replaced it before it finished.
    var interrupted: Bool
}

/// Every Call Assist answer, kept in a SQLite file on this Mac so a replaced
/// or earlier answer can be read again. Audio and the transcript are not
/// stored. One connection, used only from the main thread by its owner.
final class AnswerHistoryStore {
    private var db: OpaquePointer?

    static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Lafz Prompter", isDirectory: true)
            .appendingPathComponent("call-assist.sqlite")
    }

    init(url: URL = AnswerHistoryStore.defaultURL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            callAssistLog.error("could not open answer history at \(url.path, privacy: .public)")
            db = nil
            return
        }
        execute("""
        CREATE TABLE IF NOT EXISTS answers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            asked_at REAL NOT NULL,
            question TEXT NOT NULL,
            answer TEXT NOT NULL,
            model TEXT NOT NULL,
            latency REAL,
            interrupted INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS answers_session ON answers(session_id, asked_at);
        """)
    }

    deinit { sqlite3_close(db) }

    /// Adds a record and returns it with its new id.
    @discardableResult
    func insert(_ record: AnswerRecord) -> AnswerRecord {
        var saved = record
        run("""
            INSERT INTO answers (session_id, asked_at, question, answer, model, latency, interrupted)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """, [record.sessionID, record.askedAt.timeIntervalSince1970, record.question,
                  record.answer, record.model, record.latency, record.interrupted ? 1 : 0])
        saved.id = sqlite3_last_insert_rowid(db)
        return saved
    }

    func update(_ record: AnswerRecord) {
        run("UPDATE answers SET answer = ?, latency = ?, interrupted = ? WHERE id = ?",
            [record.answer, record.latency, record.interrupted ? 1 : 0, record.id])
    }

    /// The newest records first, across sessions.
    func recent(limit: Int = 200) -> [AnswerRecord] {
        query("SELECT id, session_id, asked_at, question, answer, model, latency, interrupted FROM answers ORDER BY asked_at DESC LIMIT ?", [limit])
    }

    func count() -> Int {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM answers", -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func deleteAll() {
        execute("DELETE FROM answers; VACUUM;")
    }

    // MARK: SQLite plumbing

    private func execute(_ sql: String) {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            callAssistLog.error("answer history: \(String(cString: sqlite3_errmsg(self.db)), privacy: .public)")
            return
        }
    }

    private func run(_ sql: String, _ values: [Any?]) {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return logError() }
        bind(values, to: statement)
        if sqlite3_step(statement) != SQLITE_DONE { logError() }
    }

    private func query(_ sql: String, _ values: [Any?]) -> [AnswerRecord] {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { logError(); return [] }
        bind(values, to: statement)
        var records: [AnswerRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            records.append(AnswerRecord(
                id: sqlite3_column_int64(statement, 0),
                sessionID: text(statement, 1),
                askedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                question: text(statement, 3),
                answer: text(statement, 4),
                model: text(statement, 5),
                latency: sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 6),
                interrupted: sqlite3_column_int(statement, 7) != 0))
        }
        return records
    }

    /// SQLite copies bound text with this destructor value.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func bind(_ values: [Any?], to statement: OpaquePointer?) {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case let text as String: sqlite3_bind_text(statement, index, text, -1, Self.transient)
            case let number as Double: sqlite3_bind_double(statement, index, number)
            case let number as Int: sqlite3_bind_int64(statement, index, Int64(number))
            case let number as Int64: sqlite3_bind_int64(statement, index, number)
            default: sqlite3_bind_null(statement, index)
            }
        }
    }

    private func text(_ statement: OpaquePointer?, _ column: Int32) -> String {
        sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
    }

    private func logError() {
        callAssistLog.error("answer history: \(String(cString: sqlite3_errmsg(self.db)), privacy: .public)")
    }
}
