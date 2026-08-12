import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()

    // 설정 (UserDefaults 영속)
    private let defaults = UserDefaults.standard
    private var showSystem: Bool {
        get { defaults.bool(forKey: "showSystemPorts") }
        set { defaults.set(newValue, forKey: "showSystemPorts") }
    }

    // 마지막 스캔 결과 (메뉴가 열려 있는 동안 액션에서 사용)
    private var lastScan: [PortProcess] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 메뉴바 전용 앱: Dock/앱 전환기에 표시하지 않음
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(
                systemSymbolName: "fish.fill",
                accessibilityDescription: "Port Killer"
            )
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Port Killer"
        }

        menu.delegate = self
        statusItem.menu = menu

        // 지난 세션에서 이미 감지한 업데이트가 있으면 툴팁에 반영
        applyUpdateBadge()
        // 시작 직후 조용히 최신 버전 확인 (실패 시 무시)
        UpdateChecker.shared.checkIfDue { [weak self] in self?.applyUpdateBadge() }
    }

    // 메뉴가 열릴 때마다 최신 상태로 다시 그린다.
    func menuNeedsUpdate(_ menu: NSMenu) {
        // 메뉴를 열 때마다(간격 경과 시) 조용히 재확인 — 다음 열람부터 반영된다.
        UpdateChecker.shared.checkIfDue { [weak self] in self?.applyUpdateBadge() }
        rebuildMenu()
    }

    /// 업데이트 유무를 상태 아이콘 툴팁에 은은하게 반영한다.
    private func applyUpdateBadge() {
        if let update = UpdateChecker.shared.availableUpdate {
            statusItem?.button?.toolTip = "Port Killer — 새 버전 \(update.version) 사용 가능"
        } else {
            statusItem?.button?.toolTip = "Port Killer"
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let all = PortScanner.scan()
        let visible = showSystem ? all : all.filter { !$0.isLikelySystem }
        lastScan = visible

        // 헤더
        let header = NSMenuItem(
            title: visible.isEmpty
                ? "열려 있는 개발 포트가 없습니다"
                : "개발 포트 \(visible.count)개 사용 중",
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // 포트 목록
        for proc in visible {
            menu.addItem(makePortItem(proc))
        }

        if !visible.isEmpty {
            menu.addItem(.separator())
        }

        // 새로고침
        let refresh = NSMenuItem(title: "새로고침", action: #selector(refreshClicked), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        // 시스템 포트 표시 토글
        let toggle = NSMenuItem(title: "시스템 · 백그라운드 포트 표시", action: #selector(toggleSystem), keyEquivalent: "")
        toggle.target = self
        toggle.state = showSystem ? .on : .off
        menu.addItem(toggle)

        // 수동 업데이트 확인 (원할 때 즉시 · 결과는 알림으로)
        let checkUpdate = NSMenuItem(title: "업데이트 확인", action: #selector(checkForUpdatesNow), keyEquivalent: "")
        checkUpdate.target = self
        menu.addItem(checkUpdate)

        // 업데이트 안내 (있을 때만, 포트 목록 아래 · 종료 위에 은은하게)
        if let update = UpdateChecker.shared.availableUpdate {
            menu.addItem(.separator())

            let item = NSMenuItem(title: "새 버전 \(update.version) 사용 가능", action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)

            let sub = NSMenu()
            let notes = NSMenuItem(title: "릴리즈 노트 보기", action: #selector(openReleaseNotes), keyEquivalent: "")
            notes.target = self
            sub.addItem(notes)

            let copyCmd = NSMenuItem(title: "업데이트 명령 복사 (brew)", action: #selector(copyUpgradeCommand), keyEquivalent: "")
            copyCmd.target = self
            sub.addItem(copyCmd)

            item.submenu = sub
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Port Killer 종료", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func makePortItem(_ proc: PortProcess) -> NSMenuItem {
        let scopeIcon = proc.isLoopbackOnly ? "🏠" : "🌐"
        let title = "\(scopeIcon) \(proc.port)  ·  \(proc.command)  (PID \(proc.pid))"

        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")

        // 시작 시각: 메뉴엔 상대 시간을 은은하게 (macOS 14+ 는 부제, 그 이하는 제목에 덧붙임)
        if let started = proc.startedAt {
            let rel = TimeFormat.relative(started)
            if #available(macOS 14.4, *) {
                item.subtitle = "\(rel) 시작"
            } else {
                item.title = "\(title)  ·  \(rel)"
            }
        }

        // 각 포트는 서브메뉴로 액션 제공
        let submenu = NSMenu()

        // 상세: 정확한 시작 시각 (비활성 헤더)
        if let started = proc.startedAt {
            let detail = NSMenuItem(
                title: "시작: \(TimeFormat.exact(started))  (\(TimeFormat.relative(started)))",
                action: nil,
                keyEquivalent: ""
            )
            detail.isEnabled = false
            submenu.addItem(detail)
            submenu.addItem(.separator())
        }

        let term = NSMenuItem(title: "종료 (SIGTERM)", action: #selector(killTerm(_:)), keyEquivalent: "")
        term.target = self
        term.representedObject = proc
        submenu.addItem(term)

        let force = NSMenuItem(title: "강제 종료 (SIGKILL)", action: #selector(killForce(_:)), keyEquivalent: "")
        force.target = self
        force.representedObject = proc
        submenu.addItem(force)

        submenu.addItem(.separator())

        let copyPort = NSMenuItem(title: "포트 번호 복사", action: #selector(copyPort(_:)), keyEquivalent: "")
        copyPort.target = self
        copyPort.representedObject = proc
        submenu.addItem(copyPort)

        let copyPid = NSMenuItem(title: "PID 복사", action: #selector(copyPid(_:)), keyEquivalent: "")
        copyPid.target = self
        copyPid.representedObject = proc
        submenu.addItem(copyPid)

        item.submenu = submenu
        return item
    }

    // MARK: - Actions

    @objc private func refreshClicked() {
        rebuildMenu()
    }

    @objc private func toggleSystem() {
        showSystem.toggle()
        rebuildMenu()
    }

    @objc private func killTerm(_ sender: NSMenuItem) {
        guard let proc = sender.representedObject as? PortProcess else { return }
        performKill(proc, force: false)
    }

    @objc private func killForce(_ sender: NSMenuItem) {
        guard let proc = sender.representedObject as? PortProcess else { return }
        performKill(proc, force: true)
    }

    private func performKill(_ proc: PortProcess, force: Bool) {
        let result = ProcessKiller.kill(pid: proc.pid, force: force)
        switch result {
        case .success:
            Notifier.show(
                title: "포트 \(proc.port) 정리됨",
                body: "\(proc.command) (PID \(proc.pid)) 프로세스를 종료했습니다."
            )
        case .notPermitted:
            Notifier.show(
                title: "종료 권한 없음",
                body: "\(proc.command) (PID \(proc.pid)) 는 현재 사용자 권한으로 종료할 수 없습니다."
            )
        case .noSuchProcess:
            Notifier.show(
                title: "이미 종료됨",
                body: "PID \(proc.pid) 프로세스가 이미 종료되었습니다."
            )
        case .failed(let message):
            Notifier.show(
                title: "종료 실패",
                body: "\(proc.command) (PID \(proc.pid)): \(message)"
            )
        }
    }

    @objc private func copyPort(_ sender: NSMenuItem) {
        guard let proc = sender.representedObject as? PortProcess else { return }
        setClipboard(String(proc.port))
    }

    @objc private func copyPid(_ sender: NSMenuItem) {
        guard let proc = sender.representedObject as? PortProcess else { return }
        setClipboard(String(proc.pid))
    }

    private func setClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    // MARK: - Update actions

    @objc private func checkForUpdatesNow() {
        UpdateChecker.shared.checkNow { [weak self] result in
            self?.applyUpdateBadge()
            switch result {
            case .updateAvailable(let version, _):
                Notifier.show(
                    title: "새 버전 \(version) 사용 가능",
                    body: "메뉴에서 릴리즈 노트 보기 또는 업데이트 명령 복사를 선택하세요."
                )
            case .upToDate(let current):
                Notifier.show(
                    title: "최신 버전입니다",
                    body: "현재 \(current) 버전을 사용 중입니다."
                )
            case .failed:
                Notifier.show(
                    title: "업데이트 확인 실패",
                    body: "네트워크 연결을 확인한 뒤 다시 시도하세요."
                )
            }
        }
    }

    @objc private func openReleaseNotes() {
        guard let update = UpdateChecker.shared.availableUpdate else { return }
        NSWorkspace.shared.open(update.url)
    }

    @objc private func copyUpgradeCommand() {
        let cmd = "brew upgrade --cask port-killer"
        setClipboard(cmd)
        Notifier.show(
            title: "업데이트 명령 복사됨",
            body: "터미널에 붙여넣어 실행하세요: \(cmd)"
        )
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
