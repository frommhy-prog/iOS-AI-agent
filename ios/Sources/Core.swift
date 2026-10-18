import SwiftUI
import SQLite3

enum T {
    static let bg = Color(red: 0.055, green: 0.067, blue: 0.086)
    static let card = Color(red: 0.09, green: 0.106, blue: 0.133)
    static let line = Color(red: 0.137, green: 0.16, blue: 0.2)
    static let mint = Color(red: 0.24, green: 0.86, blue: 0.66)
    static let mute = Color(red: 0.545, green: 0.58, blue: 0.64)
}

typealias Row = [String: Any]

extension Dictionary where Key == String, Value == Any {
    func s(_ k: String) -> String { (self[k] as? String) ?? "" }
    func d(_ k: String) -> Double { (self[k] as? Double) ?? Double((self[k] as? Int64) ?? 0) }
    func i(_ k: String) -> Int { Int((self[k] as? Int64) ?? 0) }
}

final class DB {
    static let shared = DB()
    private var h: OpaquePointer?
    private let lock = NSRecursiveLock()
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init() {
        let dir = try! FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        sqlite3_open(dir.appendingPathComponent("agent.sqlite").path, &h)
        exec("""
        CREATE TABLE IF NOT EXISTS msg(id INTEGER PRIMARY KEY, role TEXT, text TEXT, ts REAL);
        CREATE TABLE IF NOT EXISTS doc(id INTEGER PRIMARY KEY, name TEXT, ts REAL);
        CREATE TABLE IF NOT EXISTS chunk(id INTEGER PRIMARY KEY, doc INTEGER, text TEXT, vec BLOB);
        CREATE TABLE IF NOT EXISTS task(id INTEGER PRIMARY KEY, title TEXT, instr TEXT, due REAL, use_model INTEGER, rep INTEGER, result TEXT, state INTEGER DEFAULT 0, notified INTEGER DEFAULT 0);
        CREATE TABLE IF NOT EXISTS skill(name TEXT PRIMARY KEY, desc TEXT, code TEXT, ts REAL);
        CREATE TABLE IF NOT EXISTS prompt(ver INTEGER PRIMARY KEY AUTOINCREMENT, body TEXT, ts REAL);
        CREATE TABLE IF NOT EXISTS kv(k TEXT PRIMARY KEY, v TEXT);
        """)
    }

    func exec(_ sql: String) {
        lock.lock(); defer { lock.unlock() }
        sqlite3_exec(h, sql, nil, nil, nil)
    }

    @discardableResult
    func run(_ sql: String, _ args: [Any?] = []) -> Int64 {
        lock.lock(); defer { lock.unlock() }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(h, sql, -1, &st, nil) == SQLITE_OK else { return -1 }
        defer { sqlite3_finalize(st) }
        bind(st, args)
        sqlite3_step(st)
        return sqlite3_last_insert_rowid(h)
    }

    func rows(_ sql: String, _ args: [Any?] = []) -> [Row] {
        lock.lock(); defer { lock.unlock() }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(h, sql, -1, &st, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(st) }
        bind(st, args)
        var out: [Row] = []
        while sqlite3_step(st) == SQLITE_ROW {
            var r: Row = [:]
            for i in 0..<sqlite3_column_count(st) {
                let name = String(cString: sqlite3_column_name(st, i))
                switch sqlite3_column_type(st, i) {
                case SQLITE_INTEGER: r[name] = sqlite3_column_int64(st, i)
                case SQLITE_FLOAT: r[name] = sqlite3_column_double(st, i)
                case SQLITE_TEXT: r[name] = String(cString: sqlite3_column_text(st, i))
                case SQLITE_BLOB:
                    let n = Int(sqlite3_column_bytes(st, i))
                    r[name] = n > 0 ? Data(bytes: sqlite3_column_blob(st, i), count: n) : Data()
                default: break
                }
            }
            out.append(r)
        }
        return out
    }

    private func bind(_ st: OpaquePointer?, _ args: [Any?]) {
        for (i, a) in args.enumerated() {
            let n = Int32(i + 1)
            switch a {
            case let v as Int: sqlite3_bind_int64(st, n, Int64(v))
            case let v as Int64: sqlite3_bind_int64(st, n, v)
            case let v as Double: sqlite3_bind_double(st, n, v)
            case let v as String: sqlite3_bind_text(st, n, v, -1, transient)
            case let v as Data: _ = v.withUnsafeBytes { sqlite3_bind_blob(st, n, $0.baseAddress, Int32(v.count), transient) }
            default: sqlite3_bind_null(st, n)
            }
        }
    }

    func kv(_ k: String) -> String? { rows("SELECT v FROM kv WHERE k=?", [k]).first?.s("v") }
    func setKV(_ k: String, _ v: String) { run("INSERT OR REPLACE INTO kv(k,v) VALUES(?,?)", [k, v]) }
}

enum Store {
    static var docs: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    static func dir(_ n: String) -> URL {
        let u = docs.appendingPathComponent(n)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static func copyIn(_ src: URL) -> URL? {
        let ok = src.startAccessingSecurityScopedResource()
        defer { if ok { src.stopAccessingSecurityScopedResource() } }
        let dst = dir("Inbox").appendingPathComponent(src.lastPathComponent)
        try? FileManager.default.removeItem(at: dst)
        do { try FileManager.default.copyItem(at: src, to: dst); return dst } catch { return nil }
    }
}
