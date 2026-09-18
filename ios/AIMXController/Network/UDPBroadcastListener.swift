import Foundation
import Darwin

/// Receives UDP broadcast "server alive" advertisements on port 1213,
/// mirroring Android `startUdpBroadcastListener()` in MainActivity.kt.
final class UDPBroadcastListener {
    private let listenQueue = DispatchQueue(label: "udp.broadcast.listener")
    private var socketFD: Int32 = -1
    private var isRunning = false

    /// onDatagram(sourceIP, trimmedText) is invoked on the listening queue.
    var onDatagram: ((String, String) -> Void)?

    func start() {
        stop()

        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return }
        socketFD = fd

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var broadcast: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &broadcast, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(1213).bigEndian
        addr.sin_addr.s_addr = INADDR_ANY.bigEndian

        let bound = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddrPtr in
                bind(fd, sockAddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            close(fd)
            socketFD = -1
            return
        }

        isRunning = true
        listenQueue.async { [weak self] in
            self?.receiveLoop(fd: fd)
        }
    }

    func stop() {
        isRunning = false
        if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
        }
    }

    private func receiveLoop(fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 1024)
        while isRunning {
            var sourceAddr = sockaddr_in()
            var sourceLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let received = withUnsafeMutablePointer(to: &sourceAddr) { addrPtr -> Int in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddrPtr in
                    buffer.withUnsafeMutableBytes { rawBuffer in
                        recvfrom(fd, rawBuffer.baseAddress, rawBuffer.count, 0, sockAddrPtr, &sourceLength)
                    }
                }
            }
            guard received > 0 else {
                if !isRunning { break }
                Thread.sleep(forTimeInterval: 0.05)
                continue
            }

            let text = String(decoding: buffer[0..<received], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.hasPrefix("#1_CONTROLLER_SERVER") || text.contains("SERVER_ALIVE") else { continue }

            let ip = ipv4String(from: sourceAddr)
            if let ip = ip {
                onDatagram?(ip, text)
            }
        }
    }

    private func ipv4String(from addr: sockaddr_in) -> String? {
        var inAddr = addr.sin_addr
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &inAddr, &buffer, socklen_t(INET_ADDRSTRLEN))
        return String(cString: buffer)
    }
}