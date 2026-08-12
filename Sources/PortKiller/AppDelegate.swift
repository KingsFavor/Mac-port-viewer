import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()

    // 설정 (UserDefaults 영속)
    private let defaults = UserDefaults.standard
    private var showSystem: Bool {
        get { defaults.bool(forKey: "showSystemPorts") }
        set { defaults.set(newValue, forKey: "showSystemPorts") }
    }
    // 업데이트가 설치되면 유휴 상태에서 자동 재실행할지 (기본 ON)
    private var autoRelaunch: Bool {
        get { defaults.object(forKey: "autoRelaunchOnUpdate") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autoRelaunchOnUpdate") }
    }

    // 마지막 스캔 결과 (메뉴가 열려 있는 동안 액션에서 사용)
    private var lastScan: [PortProcess] = []

    // 자동 재실행 상태
    private var menuIsOpen = false
    private var relaunchScheduled = false
    private var autoRelaunchTimer: Timer?
    private var bundleWatchSource: DispatchSourceFileSystemObject?
    private var bundleWatchFD: Int32 = -1

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

        // 알림: accessory 앱이 활성 상태여도 배너가 뜨도록 delegate 지정 +
        //       권한을 시작 시점에 미리 요청해 첫 알림이 유실되지 않게 한다.
        if Bundle.main.bundleIdentifier != nil {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }

        // 지난 세션에서 이미 감지한 업데이트가 있으면 툴팁에 반영
        applyUpdateBadge()
        // 시작 직후 조용히 최신 버전 확인 (실패 시 무시)
        UpdateChecker.shared.checkIfDue { [weak self] in self?.applyUpdateBadge() }

        // brew 가 .app 을 교체하는 즉시 감지해 자동 재실행하기 위한 파일시스템 감시.
        startBundleWatch()
        // 감시가 이벤트를 놓치는 경우를 대비한 백스톱 주기 점검.
        // (메뉴 트래킹 중에는 기본 런루프 타이머가 멈추므로 자연히 메뉴 열림 중엔 동작하지 않음)
        autoRelaunchTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.maybeAutoRelaunch()
        }
        maybeAutoRelaunch()
    }

    /// 번들이 들어있는 디렉토리를 감시한다. brew 가 새 .app 을 이 안으로 옮기면
    /// 이벤트가 발생하고, 유휴 상태면 곧바로 자동 재실행으로 이어진다.
    private func startBundleWatch() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let parent = Bundle.main.bundleURL.deletingLastPathComponent().path
        let fd = open(parent, O_EVTONLY)
        guard fd >= 0 else { return }
        bundleWatchFD = fd
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        src.setEventHandler { [weak self] in self?.maybeAutoRelaunch() }
        src.setCancelHandler { [weak self] in
            if let fd = self?.bundleWatchFD, fd >= 0 { close(fd) }
            self?.bundleWatchFD = -1
        }
        src.resume()
        bundleWatchSource = src
    }

    // 메뉴가 열릴 때마다 최신 상태로 다시 그린다.
    func menuNeedsUpdate(_ menu: NSMenu) {
        // 메뉴를 열 때마다(간격 경과 시) 조용히 재확인 — 다음 열람부터 반영된다.
        UpdateChecker.shared.checkIfDue { [weak self] in self?.applyUpdateBadge() }
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        // 메뉴를 닫자마자(업그레이드 직후일 수 있음) 자동 재실행 여부 점검
        maybeAutoRelaunch()
    }

    /// 유휴 상태에서 디스크에 새 버전이 설치돼 있으면 조용히 재실행한다.
    private func maybeAutoRelaunch() {
        guard autoRelaunch, !menuIsOpen, !relaunchScheduled else { return }
        guard UpdateChecker.shared.pendingRestartVersion != nil else { return }

        relaunchScheduled = true
        // brew 가 번들 파일을 모두 옮길 시간을 잠깐 준 뒤, 여전히 유휴·설치됨이면 재실행.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            self.relaunchScheduled = false
            guard self.autoRelaunch, !self.menuIsOpen,
                  UpdateChecker.shared.pendingRestartVersion != nil else { return }
            self.relaunchApp()
        }
    }

    /// 업데이트 상태를 상태 아이콘 툴팁에 은은하게 반영한다.
    private func applyUpdateBadge() {
        switch UpdateChecker.shared.actionableUpdate {
        case .downloadable(let version, _):
            statusItem?.button?.toolTip = "Port Killer — 새 버전 \(version) 사용 가능"
        case .pendingRestart(let version):
            statusItem?.button?.toolTip = "Port Killer — \(version) 설치됨, 재실행하면 적용"
        case .upToDate, .failed:
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

        // 업데이트 설치 시 자동 재실행 토글
        let autoItem = NSMenuItem(title: "업데이트 설치되면 자동 재실행", action: #selector(toggleAutoRelaunch), keyEquivalent: "")
        autoItem.target = self
        autoItem.state = autoRelaunch ? .on : .off
        menu.addItem(autoItem)

        // 수동 업데이트 확인 (원할 때 즉시 · 결과는 알림으로)
        let checkUpdate = NSMenuItem(title: "업데이트 확인", action: #selector(checkForUpdatesNow), keyEquivalent: "")
        checkUpdate.target = self
        menu.addItem(checkUpdate)

        // 업데이트 안내 (있을 때만, 포트 목록 아래 · 종료 위에 은은하게)
        switch UpdateChecker.shared.actionableUpdate {
        case .downloadable(let version, _):
            menu.addItem(.separator())
            let item = NSMenuItem(title: "새 버전 \(version) 사용 가능", action: nil, keyEquivalent: "")
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

        case .pendingRestart(let version):
            // 이미 디스크에 설치됨 → 재실행하면 적용. 클릭 = 재실행.
            menu.addItem(.separator())
            let item = NSMenuItem(
                title: "재실행하여 \(version) 적용",
                action: #selector(relaunchApp),
                keyEquivalent: ""
            )
            item.target = self
            item.image = NSImage(systemSymbolName: "arrow.clockwise.circle.fill", accessibilityDescription: nil)
            menu.addItem(item)

        case .upToDate, .failed:
            break
        }

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Port Killer 종료", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func makePortItem(_ proc: PortProcess) -> NSMenuItem {
        let scopeIcon = proc.isLoopbackOnly ? "🏠" : "🌐"
        let title = "\(scopeIcon) \(proc.port)  ·  \(proc.command)  (PID \(proc.pid))"

        // 시작 시각: 메뉴엔 상대 시간을 은은하게 덧붙인다 (정확한 시각은 하위 메뉴에).
        let displayTitle: String
        if let started = proc.startedAt {
            displayTitle = "\(title)  ·  \(TimeFormat.relative(started))"
        } else {
            displayTitle = title
        }

        let item = NSMenuItem(title: displayTitle, action: nil, keyEquivalent: "")

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

    @objc private func toggleAutoRelaunch() {
        autoRelaunch.toggle()
        // 방금 켰고 이미 새 버전이 설치돼 있으면 점검(재실행은 메뉴 닫힌 뒤)
        if autoRelaunch { maybeAutoRelaunch() }
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
        // 사용자가 직접 누른 액션이므로 결과를 확실히 보여준다(결과 창).
        UpdateChecker.shared.checkNow { [weak self] result in
            guard let self else { return }
            self.applyUpdateBadge()
            self.presentUpdateResult(result)
        }
    }

    /// "업데이트 확인" 결과를 알림이 아닌 결과 창으로 확실하게 노출한다.
    /// (accessory 앱이라 앞으로 끌어와야 창이 보인다.)
    private func presentUpdateResult(_ result: UpdateChecker.CheckResult) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage

        switch result {
        case .downloadable(let version, let url):
            alert.messageText = "새 버전 \(version) 사용 가능"
            alert.informativeText = "현재 \(UpdateChecker.currentVersion) 버전을 사용 중입니다."
            alert.addButton(withTitle: "릴리즈 노트 보기")
            alert.addButton(withTitle: "업데이트 명령 복사 (brew)")
            alert.addButton(withTitle: "닫기")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                NSWorkspace.shared.open(url)
            case .alertSecondButtonReturn:
                setClipboard(UpdateChecker.brewUpgradeCommand)
            default:
                break
            }

        case .pendingRestart(let version):
            alert.messageText = "\(version) 이(가) 설치되어 있습니다"
            alert.informativeText = "실행 중인 앱은 아직 \(UpdateChecker.currentVersion) 입니다. 재실행하면 \(version) 이 적용됩니다."
            alert.addButton(withTitle: "지금 재실행")
            alert.addButton(withTitle: "나중에")
            if alert.runModal() == .alertFirstButtonReturn {
                relaunchApp()
            }

        case .upToDate(let current):
            alert.messageText = "최신 버전입니다"
            alert.informativeText = "현재 \(current) 버전이 가장 최신입니다."
            alert.addButton(withTitle: "확인")
            alert.runModal()

        case .failed:
            alert.alertStyle = .warning
            alert.messageText = "업데이트를 확인하지 못했습니다"
            alert.informativeText = "네트워크 연결을 확인한 뒤 다시 시도하세요."
            alert.addButton(withTitle: "확인")
            alert.runModal()
        }
    }

    // 알림 배너를 앱이 활성 상태일 때도 표시 (kill 결과 · 자동 업데이트 감지 등)
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    @objc private func openReleaseNotes() {
        if case .downloadable(_, let url) = UpdateChecker.shared.actionableUpdate {
            NSWorkspace.shared.open(url)
        }
    }

    /// 디스크에 설치된 최신 번들로 새 인스턴스를 띄우고 현재(옛 버전) 프로세스를 종료한다.
    @objc private func relaunchApp() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    @objc private func copyUpgradeCommand() {
        let cmd = UpdateChecker.brewUpgradeCommand
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
