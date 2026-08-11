import Foundation
import Darwin

/// 프로세스 종료 유틸리티.
enum ProcessKiller {
    enum Result {
        case success
        case notPermitted   // 권한 없음 (예: 다른 사용자 소유)
        case noSuchProcess  // 이미 종료됨
        case failed(String)
    }

    /// SIGTERM(정상 종료) 또는 SIGKILL(강제 종료) 시그널을 보낸다.
    static func kill(pid: Int32, force: Bool) -> Result {
        let signal = force ? SIGKILL : SIGTERM
        let rc = Darwin.kill(pid, signal)
        if rc == 0 { return .success }

        switch errno {
        case EPERM: return .notPermitted
        case ESRCH: return .noSuchProcess
        default:    return .failed(String(cString: strerror(errno)))
        }
    }
}
