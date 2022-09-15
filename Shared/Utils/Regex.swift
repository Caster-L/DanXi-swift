import Foundation

// implement a regex shortcut, usage: str ~= #"[regex expression]"#
extension String {
    /// If lhs content matches rhs regex, returns true
    static func ~= (lhs: String, rhs: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: rhs) else { return false }
        let range = NSRange(location: 0, length: lhs.utf16.count)
        return regex.firstMatch(in: lhs, options: [], range: range) != nil
    }
}
