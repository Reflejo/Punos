//
//  String+Misc.swift
//  Swifter
//
//  Copyright (c) 2014-2016 Damian Kołakowski. All rights reserved.
//

#if os(Linux)
    import Glibc
#else
    import Foundation
#endif

extension String {

    internal func split(separator: Character) -> [String] {
        return self.characters.split { $0 == separator }.map(String.init)
    }
    
    internal func split(maxSplit: Int = Int.max, separator: Character) -> [String] {
        return self.characters.split(maxSplit) { $0 == separator }.map(String.init)
    }
    
    internal func replace(old: Character, _ new: Character) -> String {
        var buffer = [Character]()
        self.characters.forEach { buffer.append($0 == old ? new : $0) }
        return String(buffer)
    }
    
    internal func unquote() -> String {
        var scalars = self.unicodeScalars;
        if scalars.first == "\"" && scalars.last == "\"" && scalars.count >= 2 {
            scalars.removeFirst();
            scalars.removeLast();
            return String(scalars)
        }
        return self
    }
    
    internal func trim() -> String {
        var scalars = self.unicodeScalars
        while let _ = scalars.first?.asWhitespace() { scalars.removeFirst() }
        while let _ = scalars.last?.asWhitespace() { scalars.removeLast() }
        return String(scalars)
    }
    
    internal static func fromUInt8(array: [UInt8]) -> String {
        // Apple changes the definition of String(data: .... ) every release so let's stay with 'fromUInt8(...)' wrapper.
        return array.reduce("", combine: { $0.0 + String(UnicodeScalar($0.1)) })
    }
    
    internal func removePercentEncoding() -> String {
        var scalars = self.unicodeScalars
        var output = ""
        var bytesBuffer = [UInt8]()
        while let scalar = scalars.popFirst() {
            if scalar == "%" {
                let first = scalars.popFirst()
                let secon = scalars.popFirst()
                if let first = first?.asAlpha(), secon = secon?.asAlpha() {
                    bytesBuffer.append(first*16+secon)
                } else {
                    if !bytesBuffer.isEmpty {
                        output.appendContentsOf(String.fromUInt8(bytesBuffer))
                        bytesBuffer.removeAll()
                    }
                    if let first = first { output.append(Character(first)) }
                    if let secon = secon { output.append(Character(secon)) }
                }
            } else {
                if !bytesBuffer.isEmpty {
                    output.appendContentsOf(String.fromUInt8(bytesBuffer))
                    bytesBuffer.removeAll()
                }
                output.append(Character(scalar))
            }
        }
        if !bytesBuffer.isEmpty {
            output.appendContentsOf(String.fromUInt8(bytesBuffer))
            bytesBuffer.removeAll()
        }
        return output
    }
}

extension UnicodeScalar {
    
    internal func asWhitespace() -> UInt8? {
        if self.value >= 9 && self.value <= 13 {
            return UInt8(self.value)
        }
        if self.value == 32 {
            return UInt8(self.value)
        }
        return nil
    }
    
    internal func asAlpha() -> UInt8? {
        if self.value >= 48 && self.value <= 57 {
            return UInt8(self.value) - 48
        }
        if self.value >= 97 && self.value <= 102 {
            return UInt8(self.value) - 87
        }
        if self.value >= 65 && self.value <= 70 {
            return UInt8(self.value) - 55
        }
        return nil
    }
}
