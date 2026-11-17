import Foundation
import Darwin

/// One persistent nettop process for a single interface category.
final class NettopStream {
    private let scope: NetworkScope
    private let queue: DispatchQueue
    private var process: Process?
    private var parser = NettopParser()
    private var masterFD: Int32 = -1
    private var stdinWriteFD: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var quietFlush: DispatchWorkItem?
    private var restartWork: DispatchWorkItem?
    private var stopping = false

    var onSample: (([NettopRow]) -> Void)?
    var onStatus: ((String) -> Void)?

    init(scope: NetworkScope) {
        self.scope = scope
        self.queue = DispatchQueue(label: "app.networkmonitor.nettop.\(scope.rawValue)")
    }

    func start() {
        queue.async { [weak self] in
            guard let self, !self.stopping, self.process == nil else { return }
            self.spawn()
        }
    }

    func stop() {
        queue.sync {
            stopping = true
            restartWork?.cancel()
            restartWork = nil
            stopChild()
        }
    }

    private func spawn() {
        guard !stopping else { return }

        var master: Int32 = -1
        var slave: Int32 = -1
        var terminalSize = winsize(ws_row: 200, ws_col: 2000, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &terminalSize) == 0 else {
            failed("无法创建 nettop 输出通道")
            return
        }

        var terminal = termios()
        if tcgetattr(slave, &terminal) == 0 {
            cfmakeraw(&terminal)
            _ = tcsetattr(slave, TCSANOW, &terminal)
        }

        // nettop polls stdin. A pipe with no writer data keeps that poll blocked;
        // /dev/null would be permanently readable and can make nettop spin.
        var input: [Int32] = [-1, -1]
        guard pipe(&input) == 0 else {
            close(master)
            close(slave)
            failed("无法创建 nettop 输入通道")
            return
        }

        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        child.arguments = [
            "-n", "-x", "-d", "-P", "-L", "0", "-s", "2",
            "-t", scope.nettopType,
            "-J", "time,bytes_in,bytes_out"
        ]
        child.standardOutput = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        child.standardError = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        child.standardInput = FileHandle(fileDescriptor: input[0], closeOnDealloc: false)

        let flags = fcntl(master, F_GETFL, 0)
        if flags >= 0 { _ = fcntl(master, F_SETFL, flags | O_NONBLOCK) }

        masterFD = master
        stdinWriteFD = input[1]
        parser.reset()

        let source = DispatchSource.makeReadSource(fileDescriptor: master, queue: queue)
        source.setEventHandler { [weak self] in self?.readAvailable() }
        source.setCancelHandler { close(master) }
        readSource = source
        source.resume()

        child.terminationHandler = { [weak self, weak child] _ in
            guard let child else { return }
            self?.queue.async { [weak self] in
                self?.handleExit(child)
            }
        }

        do {
            try child.run()
            process = child
            close(slave)
            close(input[0])
            onStatus?("正在记录 · \(scope.title)")
        } catch {
            close(slave)
            close(input[0])
            process = nil
            teardown()
            failed("nettop 启动失败：\(error.localizedDescription)")
        }
    }

    private func readAvailable() {
        guard masterFD >= 0 else { return }
        var bytes = [UInt8](repeating: 0, count: 65_536)
        let count = Darwin.read(masterFD, &bytes, bytes.count)

        if count > 0 {
            let text = String(decoding: bytes.prefix(count), as: UTF8.self)
            let samples = parser.consume(text)
            for sample in samples { onSample?(sample) }
            scheduleQuietFlush()
        } else if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
            return
        } else if let child = process {
            handleExit(child)
        }
    }

    private func scheduleQuietFlush() {
        quietFlush?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let sample = self.parser.flush() else { return }
            self.onSample?(sample)
        }
        quietFlush = work
        queue.asyncAfter(deadline: .now() + .milliseconds(220), execute: work)
    }

    private func handleExit(_ child: Process) {
        guard let current = process, current === child else { return }
        process = nil
        teardown()
        guard !stopping else { return }
        failed("nettop 已退出，正在重试")
    }

    private func failed(_ message: String) {
        onStatus?(message)
        guard !stopping, restartWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.restartWork = nil
            self.spawn()
        }
        restartWork = work
        queue.asyncAfter(deadline: .now() + 4, execute: work)
    }

    private func stopChild() {
        let child = process
        process = nil
        child?.terminationHandler = nil
        if let child, child.isRunning {
            child.terminate()
            let deadline = Date().addingTimeInterval(0.35)
            while child.isRunning && Date() < deadline {
                usleep(20_000)
            }
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
        teardown()
    }

    private func teardown() {
        quietFlush?.cancel()
        quietFlush = nil

        if let source = readSource {
            readSource = nil
            source.cancel()
        } else if masterFD >= 0 {
            close(masterFD)
        }
        masterFD = -1

        if stdinWriteFD >= 0 {
            close(stdinWriteFD)
            stdinWriteFD = -1
        }
    }
}
