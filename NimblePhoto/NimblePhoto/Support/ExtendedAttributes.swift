import Foundation
import Darwin

/// Thin wrapper around the low-level xattr syscalls (getxattr/setxattr),
/// since Foundation has no direct API for reading/writing a named extended
/// attribute's raw bytes.
nonisolated enum ExtendedAttributes {
    enum XAttrError: Error {
        case readFailed(errno: Int32)
        case writeFailed(errno: Int32)
    }

    static func read(_ name: String, from path: String) throws -> Data? {
        let size = getxattr(path, name, nil, 0, 0, 0)
        if size == -1 {
            if errno == ENOATTR { return nil }
            throw XAttrError.readFailed(errno: errno)
        }
        if size == 0 { return Data() }
        var buffer = [UInt8](repeating: 0, count: size)
        let result = getxattr(path, name, &buffer, size, 0, 0)
        guard result != -1 else {
            if errno == ENOATTR { return nil }
            throw XAttrError.readFailed(errno: errno)
        }
        return Data(buffer[0..<result])
    }

    static func write(_ name: String, data: Data, to path: String) throws {
        let result = data.withUnsafeBytes { rawBuffer -> Int32 in
            setxattr(path, name, rawBuffer.baseAddress, rawBuffer.count, 0, 0)
        }
        guard result == 0 else {
            throw XAttrError.writeFailed(errno: errno)
        }
    }
}
