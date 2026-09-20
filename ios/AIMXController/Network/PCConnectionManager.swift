import Foundation
import Network

/// Raw TCP client to the cheat-PC server (port 1212), mirroring the Android
/// `connectPC` / `startTcpReader` / `transmit*` logic in MainActivity.kt.
final class PCConnectionManager {
    static let tcpPort: UInt16 = 1212

    var onStatusChange: ((ConnectionState, String?) -> Void)?
    var onLog: ((String) -> Void)?

    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var pcIP = "192.168.1.100"

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "pc.tcp.connection")
    private let bufferQueue = DispatchQueue(label: "pc.tcp.buffer")
    private var receiveBuffer = Data()

    private var retryWork: DispatchWorkItem?
    private var connectTimeoutWork: DispatchWorkItem?
    private var reconnectAfterDrop: DispatchWorkItem?

    deinit {
        disconnect()
    }

    func setpcIP(_ ip: String) {
        pcIP = ip
    }

    // MARK: - Lifecycle

    /// Tracks the current connection generation to make async callbacks (timeout
    /// timers, state handlers, reconnects) immune to interleaving across
    /// disconnect/connect cycles.
    private var connectionEra: UInt64 = 0

    func disconnect() {
        retryWork?.cancel()
        connectTimeoutWork?.cancel()
        reconnectAfterDrop?.cancel()
        retryWork = nil
        connectTimeoutWork = nil
        reconnectAfterDrop = nil

        connectionEra += 1

        // Capture + cancel locally: `.failed`/`.cancelled` state handlers run on
        // the network queue and may call back concurrently from the UI thread.
        connection?.cancel()
        connection = nil
        bufferQueue.sync { receiveBuffer.removeAll() }

        setState(.disconnected, ip: nil)
    }

    func connect() {
        let ip = pcIP.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ip.isEmpty else {
            onLog?("Cannot connect: PC IP cannot be empty")
            return
        }

        disconnect()
        connectionEra += 1
        let era = connectionEra
        setState(.connecting, ip: nil)
        onLog?("Connecting to TCP: \(ip) ...")

        let connection = NWConnection(
            host: NWEndpoint.Host(ip),
            port: NWEndpoint.Port(rawValue: PCConnectionManager.tcpPort) ?? NWEndpoint.Port(rawValue: 1212)!,
            using: .tcpWithNoDelay()
        )
        self.connection = connection

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self = self, let connection = connection else { return }
            // Ignore events from superseded connections (a newer connect() won).
            guard self.connection === connection, self.connectionEra == era else { return }
            switch state {
            case .ready:
                self.connectTimeoutWork?.cancel()
                self.setReady()
            case .failed(let error):
                guard self.connectionState != .disconnected else { return }
                self.teardownAndReconnect(errorDescription: error.localizedDescription)
            case .cancelled:
                guard self.connectionState != .disconnected else { return }
                self.teardownAndReconnect(errorDescription: "Cancelled")
            default:
                break
            }
        }

        connection.start(queue: queue)

        // 5 s connect timeout, mirroring Android's 5000 ms socket.connect().
        let timeout = DispatchWorkItem { [weak self] in
            guard let self = self, self.connectionEra == era else { return }
            guard self.connectionState == .connecting else { return }
            self.onLog?("TCP connection timed out.")
            self.teardownAndReconnect(errorDescription: "Connect timed out")
        }
        connectTimeoutWork = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
    }

    func transmit(_ data: Data) {
        guard connectionState == .connected, let connection = connection else { return }
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.onLog?("Send error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.disconnect()
                }
            }
        })
    }

    // MARK: - Auto-connect

    /// Mirrors Android autoConnect(): LAN discovery + a 4 s retry loop while
    /// disconnected (only for a real IP, not the placeholder default).
    func autoConnect(withDiscovery discovery: @escaping () -> Void) {
        if connectionState == .connected { return }
        onLog?("Auto-connecting to cheat PC...")
        discovery()

        retryWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.retryLoop()
        }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    private func retryLoop() {
        guard let retryWork = retryWork else { return }
        if connectionState == .connected {
            retryWork.cancel()
            return
        }
        let ip = pcIP.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ip.isEmpty && ip != "192.168.1.100" {
            connect()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: retryWork)
    }

    // MARK: - Internals

    private func setReady() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.setState(.connected, ip: self.pcIP)
            self.onLog?("TCP link established @ \(self.pcIP)")
        }
        startReceiveLoop()
    }

    private func startReceiveLoop() {
        guard let connection = connection else { return }
        receiveLoop(connection: connection)
    }

    private func receiveLoop(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if isComplete {
                if self.connectionState == .connected {
                    self.onLog?("TCP link closed by server - attempting reconnection...")
                    self.teardownAndReconnect(errorDescription: "Closed by server")
                }
                return
            }
            if let data = data {
                bufferQueue.sync { self.receiveBuffer.append(data) }
                self.emitLines()
            }
            if let error = error {
                if self.connectionState == .connected {
                    self.onLog?("TCP read error: \(error.localizedDescription)")
                    self.teardownAndReconnect(errorDescription: error.localizedDescription)
                }
                return
            }
            if self.connection === connection {
                self.receiveLoop(connection: connection)
            }
        }
    }

    private func emitLines() {
        let lines: [String] = bufferQueue.sync { () -> [String] in
            var result: [String] = []
            while let newlineIndex = receiveBuffer.firstIndex(of: 0x0A) {
                let lineData = receiveBuffer[receiveBuffer.startIndex..<newlineIndex]
                receiveBuffer.removeSubrange(receiveBuffer.startIndex...newlineIndex)
                let line = String(decoding: lineData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty {
                    result.append(line)
                }
            }
            return result
        }
        for line in lines {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.onLog?("Recv: \(line)")
                self.onStatusChange?(.connected, self.pcIP)
            }
        }
    }

    private func teardownAndReconnect(errorDescription: String) {
        reconnectAfterDrop?.cancel()
        let era = connectionEra
        let wasConnected = connectionState == .connected

        if self.connectionEra == era {
            connection?.cancel()
            connection = nil
            bufferQueue.sync { receiveBuffer.removeAll() }
        }

        if wasConnected {
            setState(.disconnected, ip: nil)
            onLog?("TCP link lost: \(errorDescription)")

            // Wait 2 s before reconnecting, mirroring Android.
            let work = DispatchWorkItem { [weak self] in
                guard let self = self, self.connectionEra == era else { return }
                guard self.connectionState == .disconnected else { return }
                self.onLog?("Attempting reconnection...")
                self.connect()
            }
            reconnectAfterDrop = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
        } else {
            setState(.disconnected, ip: nil)
        }
    }

    private func setState(_ state: ConnectionState, ip: String?) {
        // stateUpdateHandler / receive callbacks run on the network queue; hop to
        // main so @Published mutations happen on the UI thread (otherwise SwiftUI
        // crashes on background thread drift once the link drops).
        if Thread.isMainThread {
            applyState(state, ip: ip)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.applyState(state, ip: ip)
            }
        }
    }

    private func applyState(_ state: ConnectionState, ip: String?) {
        if connectionState == state { return }
        connectionState = state
        onStatusChange?(state, ip)
    }
}

extension NWParameters {
    static func tcpWithNoDelay() -> NWParameters {
        let parameters = NWParameters.tcp
        if let tcpOptions = parameters.defaultProtocolStack.internetProtocol as? NWProtocolTCP.Options {
            tcpOptions.noDelay = true
        }
        return parameters
    }
}