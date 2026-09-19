import Foundation

@TaskLocal
var appThreadToken: AppThreadToken?

struct AppThreadToken: Sendable, Equatable {
    let pid: pid_t

    @inline(__always)
    init(pid: pid_t) {
        self.pid = pid
    }

    @inline(__always)
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.pid == rhs.pid
    }

    @inline(__always)
    func checkEquals(_ other: AppThreadToken?) {
        precondition(self == other)
    }
}
