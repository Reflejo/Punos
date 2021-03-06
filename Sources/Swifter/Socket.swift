//
//  Socket.swift
//  Swifter
//
//  Copyright (c) 2014-2016 Damian Kołakowski. All rights reserved.
//

#if os(Linux)
    import Glibc
#else
    import Foundation
#endif

/* Low level routines for POSIX sockets */

internal enum SocketError: ErrorType {
    case SocketCreationFailed(String)
    case SocketSettingReUseAddrFailed(String)
    case SocketSettingIPV6OnlyFailed(String)
    case BindFailed(String)
    case ListenFailed(String)
    case WriteFailed(String)
    case GetPeerNameFailed(String)
    case ConvertingPeerNameFailed
    case GetNameInfoFailed(String)
    case AcceptFailed(String)
    case RecvFailed(String)
}

internal class Socket: Hashable, Equatable {
    
    internal class func tcpSocketForListen(port: in_port_t, maxPendingConnection: Int32 = SOMAXCONN) throws -> Socket {
        
        #if os(Linux)
            let socketFileDescriptor = socket(AF_INET6, Int32(SOCK_STREAM.rawValue), 0)
        #else
            let socketFileDescriptor = socket(AF_INET6, SOCK_STREAM, 0)
        #endif
        
        if socketFileDescriptor == -1 {
            throw SocketError.SocketCreationFailed(Socket.descriptionOfLastError())
        }
        
        var sockoptValueYES: Int32 = 1
        var sockoptValueNO: Int32 = 0
        
        // Allow reuse of local addresses:
        //
        if setsockopt(socketFileDescriptor, SOL_SOCKET, SO_REUSEADDR, &sockoptValueYES, socklen_t(sizeof(Int32))) == -1 {
            let details = Socket.descriptionOfLastError()
            Socket.release(socketFileDescriptor)
            throw SocketError.SocketSettingReUseAddrFailed(details)
        }
        
        // Accept also IPv4 connections (note that this means we must bind to
        // in6addr_any — binding to in6addr_loopback will effectively rule out
        // IPv4 addresses):
        //
        if setsockopt(socketFileDescriptor, IPPROTO_IPV6, IPV6_V6ONLY, &sockoptValueNO, socklen_t(sizeof(Int32))) == -1 {
            let details = Socket.descriptionOfLastError()
            Socket.release(socketFileDescriptor)
            throw SocketError.SocketSettingIPV6OnlyFailed(details)
        }
        
        Socket.setNoSigPipe(socketFileDescriptor)
        
        #if os(Linux)
            var addr = sockaddr_in6()
            addr.sin6_family = sa_family_t(AF_INET6)
            addr.sin6_port = Socket.htonsPort(port)
            addr.sin6_addr = in6addr_any
        #else
            var addr = sockaddr_in6()
            addr.sin6_len = __uint8_t(sizeof(sockaddr_in6))
            addr.sin6_family = sa_family_t(AF_INET6)
            addr.sin6_port = Socket.htonsPort(port)
            addr.sin6_addr = in6addr_any
        #endif
        
        var bind_addr = sockaddr()
        memcpy(&bind_addr, &addr, Int(sizeof(sockaddr_in6)))
        
        if bind(socketFileDescriptor, &bind_addr, socklen_t(sizeof(sockaddr_in6))) == -1 {
            let details = Socket.descriptionOfLastError()
            Socket.release(socketFileDescriptor)
            throw SocketError.BindFailed(details)
        }
        
        if listen(socketFileDescriptor, maxPendingConnection) == -1 {
            let details = Socket.descriptionOfLastError()
            Socket.release(socketFileDescriptor)
            throw SocketError.ListenFailed(details)
        }
        return Socket(socketFileDescriptor: socketFileDescriptor)
    }
    
    internal let socketFileDescriptor: Int32
    
    internal init(socketFileDescriptor: Int32) {
        self.socketFileDescriptor = socketFileDescriptor
    }
    
    internal var hashValue: Int { return Int(self.socketFileDescriptor) }
    
    internal func release() {
        Socket.release(self.socketFileDescriptor)
    }
    
    internal func shutdwn() {
        Socket.shutdwn(self.socketFileDescriptor)
    }
    
    internal func acceptClientSocket() throws -> Socket {
        var addr = sockaddr()        
        var len: socklen_t = 0
        let clientSocket = accept(self.socketFileDescriptor, &addr, &len)
        if clientSocket == -1 {
            throw SocketError.AcceptFailed(Socket.descriptionOfLastError())
        }
        Socket.setNoSigPipe(clientSocket)
        return Socket(socketFileDescriptor: clientSocket)
    }
    
    internal func writeUTF8(string: String) throws {
        try writeUInt8([UInt8](string.utf8))
    }
    
    internal func writeUTF8AndCRLF(string: String) throws {
        try writeUTF8(string + "\r\n")
    }
    
    internal func writeUInt8(data: [UInt8]) throws {
        try data.withUnsafeBufferPointer {
            var sent = 0
            while sent < data.count {
                #if os(Linux)
                    let s = send(self.socketFileDescriptor, $0.baseAddress + sent, data.count - sent, Int32(MSG_NOSIGNAL))
                #else
                    let s = write(self.socketFileDescriptor, $0.baseAddress + sent, data.count - sent)
                #endif
                if s <= 0 {
                    throw SocketError.WriteFailed(Socket.descriptionOfLastError())
                }
                sent += s
            }
        }
    }
    
    internal func readOneByte() throws -> UInt8 {
        var buffer = [UInt8](count: 1, repeatedValue: 0)
        let next = recv(self.socketFileDescriptor, &buffer, buffer.count, 0)
        if next <= 0 {
            throw SocketError.RecvFailed(Socket.descriptionOfLastError())
        }
        return buffer[0]
    }
    
    internal func readNumBytes(count: Int) throws -> [UInt8] {
        var ret = [UInt8]()
        while ret.count < count {
            let maxBufferSize = 2048
            let remainingExpectedBytes = count - ret.count
            let bufferSize = min(remainingExpectedBytes, maxBufferSize)
            var buffer = [UInt8](count: bufferSize, repeatedValue: 0)
            let numBytesReceived = recv(self.socketFileDescriptor, &buffer, buffer.count, 0)
            if numBytesReceived <= 0 {
                throw SocketError.RecvFailed(Socket.descriptionOfLastError())
            }
            ret.appendContentsOf(buffer)
        }
        return ret
    }
    
    internal static let CR = UInt8(13)
    internal static let NL = UInt8(10)
    
    internal func readLine() throws -> String {
        var characters: String = ""
        var n: UInt8 = 0
        repeat {
            n = try self.readOneByte()
            if n > Socket.CR { characters.append(Character(UnicodeScalar(n))) }
        } while n != Socket.NL
        return characters
    }
    
    internal func peername() throws -> String {
        var addr = sockaddr(), len: socklen_t = socklen_t(sizeof(sockaddr))
        if getpeername(self.socketFileDescriptor, &addr, &len) != 0 {
            throw SocketError.GetPeerNameFailed(Socket.descriptionOfLastError())
        }
        var hostBuffer = [CChar](count: Int(NI_MAXHOST), repeatedValue: 0)
        if getnameinfo(&addr, len, &hostBuffer, socklen_t(hostBuffer.count), nil, 0, NI_NUMERICHOST) != 0 {
            throw SocketError.GetNameInfoFailed(Socket.descriptionOfLastError())
        }
        guard let name = String.fromCString(hostBuffer) else {
            throw SocketError.ConvertingPeerNameFailed
        }
        return name
    }
    
    internal class func descriptionOfLastError() -> String {
        return String.fromCString(UnsafePointer(strerror(errno))) ?? "Error: \(errno)"
    }
    
    internal class func setNoSigPipe(socket: Int32) {
        #if os(Linux)
            // There is no SO_NOSIGPIPE in Linux (nor some other systems). You can instead use the MSG_NOSIGNAL flag when calling send(),
            // or use signal(SIGPIPE, SIG_IGN) to make your entire application ignore SIGPIPE.
        #else
            // Prevents crashes when blocking calls are pending and the app is paused ( via Home button ).
            var no_sig_pipe: Int32 = 1
            setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &no_sig_pipe, socklen_t(sizeof(Int32)))
        #endif
    }
    
    private class func shutdwn(socket: Int32) {
        #if os(Linux)
            shutdown(socket, Int32(SHUT_RDWR))
        #else
            Darwin.shutdown(socket, SHUT_RDWR)
        #endif
    }
    
    internal class func release(socket: Int32) -> Int32 {
        #if os(Linux)
            shutdown(socket, Int32(SHUT_RDWR))
        #else
            Darwin.shutdown(socket, SHUT_RDWR)
        #endif
        return close(socket)
    }
    
    private class func htonsPort(port: in_port_t) -> in_port_t {
        #if os(Linux)
            return htons(port)
        #else
            let isLittleEndian = Int(OSHostByteOrder()) == OSLittleEndian
            return isLittleEndian ? _OSSwapInt16(port) : port
        #endif
    }
}

internal func ==(socket1: Socket, socket2: Socket) -> Bool {
    return socket1.socketFileDescriptor == socket2.socketFileDescriptor
}
