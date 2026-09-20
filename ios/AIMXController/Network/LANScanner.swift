import Foundation
import Darwin

/// Subnet scanner: probes 1..254 hosts on port 1212 to find cheat-PC servers,
/// mirroring Android `runLanDiscovery()` in MainActivity.kt
/// (chunks of 25, ~1.2 s pause per chunk, 180 ms connect timeout).
final class LANScanner {
    private let scanQueue = DispatchQueue(label: "lan.scan", qos: .userInitiated, attributes: .concurrent)
    private let stateQueue = DispatchQueue(label: "lan.scan.state")

    private var isScanning = false
    private var cancelled = false
    private var discovered: Set<String> = []

    @discardableResult
    func start(
        localIP: String,
        port: Int = 1212,
        onFound: @escaping (String) -> Void,
        onScanChange: @escaping (_ scanning: Bool) -> Void,
        onLog: @escaping (String) -> Void
    ) -> Bool {
        let shouldStart = stateQueue.sync { () -> Bool in
            if isScanning { return false }
            isScanning = true
            cancelled = false
            discovered = []
            return true
        }
        guard shouldStart, !localIP.isEmpty else { return false }

        DispatchQueue.main.async {
            onScanChange(true)
            onLog("Starting quick LAN scanner on port \(port)...")
        }

        let trimmed = localIP.hasSuffix(".") ? String(localIP.dropLast()) : localIP
        let prefix: String
        let lastDot = trimmed.lastIndex(of: ".")
        if let lastDot = lastDot {
            prefix = String(trimmed[trimmed.startIndex...lastDot])
        } else {
            prefix = ""
        }

        scanQueue.async { [weak self] in
            self?.scanRange(prefix: prefix, port: port, onFound: onFound, onScanChange: onScanChange, onLog: onLog)
        }
        return true
    }

    func cancel() {
        stateQueue.sync {
            cancelled = true
        }
    }

    // MARK: - Scanning

    private func scanRange(prefix: String, port: Int, onFound: @escaping (String) -> Void, onScanChange: @escaping (_ scanning: Bool) -> Void, onLog: @escaping (String) -> Void) {
        let range = Array(1...254)
        var foundHosts: [String] = []
        let chunks = stride(from: 0, to: range.count, by: 25).map { Array(range[$0..<min($0 + 25, range.count)]) }

        for chunk in chunks {
            let stop = stateQueue.sync { cancelled }
            if stop { break }

            let group = DispatchGroup()
            let syncQueue = DispatchQueue(label: "lan.scan.results")
            var chunkHits: [String] = []

            for suffix in chunk {
                let host = "\(prefix)\(suffix)"
                group.enter()
                scanQueue.async(group: group) {
                    if self.canConnect(host: host, port: port, timeout: 0.18) {
                        syncQueue.sync {
                            chunkHits.append(host)
                        }
                    }
                    group.leave()
                }
            }
            group.wait()

            var newHosts: [String] = []
            let hits = syncQueue.sync { chunkHits }
            let shouldStop = stateQueue.sync { () -> Bool in
                if cancelled { return true }
                for host in hits {
                    if !discovered.contains(host) {
                        discovered.insert(host)
                        newHosts.append(host)
                    }
                }
                return false
            }
            if shouldStop { break }

            if !newHosts.isEmpty {
                foundHosts.append(contentsOf: newHosts)
                DispatchQueue.main.async {
                    newHosts.forEach(onFound)
                }
            }
            Thread.sleep(forTimeInterval: 1.2)
        }

        let didCancel = stateQueue.sync { cancelled }
        DispatchQueue.main.async {
            if !didCancel {
                onLog(foundHosts.isEmpty
                      ? "No direct scan reply. Listening for UDP broadcast or enter manually."
                      : "Subnet scan done. Found \(foundHosts.count) active servers.")
            }
            onScanChange(false)
        }
    }

    /// Non-blocking TCP connect probe with a poll-based timeout.
    private func canConnect(host: String, port: Int, timeout: TimeInterval) -> Bool {
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_INET,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var resultPointer: UnsafeMutablePointer<addrinfo>?
        let getAddrResult = getaddrinfo(host, String(port), &hints, &resultPointer)
        guard getAddrResult == 0, let addrs = resultPointer else { return false }
        defer { freeaddrinfo(addrs) }

        func sockaddrPointer(_ addr: UnsafeMutablePointer<addrinfo>) -> UnsafePointer<sockaddr>? {
            guard let ai_addr = addr.pointee.ai_addr else { return nil }
            let immutable = UnsafePointer(ai_addr)
            return immutable.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 }
        }

        var addrIter: UnsafeMutablePointer<addrinfo>? = addrs
        while let current = addrIter {
            let fd = socket(current.pointee.ai_family, current.pointee.ai_socktype, current.pointee.ai_protocol)
            if fd < 0 {
                addrIter = current.pointee.ai_next
                continue
            }

            let currentFlags = fcntl(fd, F_GETFL, 0)
            fcntl(fd, F_SETFL, currentFlags | O_NONBLOCK)

            let connectResult = sockaddrPointer(current).map { sockPtr in
                connect(fd, sockPtr, current.pointee.ai_addrlen)
            } ?? -1

            var connected = false
            if connectResult == 0 {
                connected = true
            } else if errno == EINPROGRESS {
                var pollFD = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                let pollResult = poll(&pollFD, 1, Int32(timeout * 1000))
                if pollResult > 0 {
                    var soError: Int32 = 0
                    var len = socklen_t(MemoryLayout<Int32>.size)
                    getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &len)
                    connected = (soError == 0)
                }
            }
            close(fd)
            if connected { return true }

            addrIter = current.pointee.ai_next
        }
        return false
    }
}