import Foundation
import SQLite3

// Provide SQLITE_TRANSIENT for sqlite3_bind_* destructor parameter
let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)


