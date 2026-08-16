import Foundation

/// A join code, and the link that carries it.
///
/// The code goes in the link's fragment. Browsers never send a fragment to a
/// server, so a code that gets opened on the web leaves no copy of itself in
/// anybody's access log.
struct Invite: Equatable {
    let code: String

    /// Grouped in fives, which is how people read a code aloud.
    var formattedCode: String {
        let clean = code.uppercased().filter(\.isLetterOrDigit)
        guard clean.count == 10 else { return clean }
        let middle = clean.index(clean.startIndex, offsetBy: 5)
        return "\(clean[..<middle])-\(clean[middle...])"
    }

    var url: URL {
        URL(string: "https://splitfree.dev/join#\(code)")!
    }
}

extension Character {
    var isLetterOrDigit: Bool { isLetter || isNumber }
}
