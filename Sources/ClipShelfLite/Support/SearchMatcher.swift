import Foundation

enum SearchMatcher {
    static func matches(_ item: ClipItem, query rawQuery: String) -> Bool {
        let query = normalize(rawQuery)
        guard !query.isEmpty else { return true }

        return searchableTexts(for: item).contains { text in
            let normalized = normalize(text)
            let pinyin = pinyinText(text)
            let initials = pinyinInitials(text)

            return normalized.contains(query)
                || pinyin.contains(query)
                || initials.contains(query)
                || isSubsequence(query, of: normalized)
                || isSubsequence(query, of: pinyin)
                || isSubsequence(query, of: initials)
                || fuzzyContains(query, in: normalized)
                || fuzzyContains(query, in: pinyin)
        }
    }

    private static func searchableTexts(for item: ClipItem) -> [String] {
        var values = [item.title]
        if let text = item.text {
            values.append(text)
        }
        values.append(contentsOf: item.filePaths)
        if let sourcePath = item.sourcePath {
            values.append(sourcePath)
        }
        return values
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func pinyinText(_ value: String) -> String {
        let mutable = NSMutableString(string: value) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        return normalize(mutable as String)
    }

    private static func pinyinInitials(_ value: String) -> String {
        let mutable = NSMutableString(string: value) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)

        return (mutable as String)
            .split { !$0.isLetter && !$0.isNumber }
            .compactMap(\.first)
            .map { String($0).lowercased() }
            .joined()
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        guard !needle.isEmpty else { return true }
        var iterator = haystack.makeIterator()

        for character in needle {
            var found = false
            while let next = iterator.next() {
                if next == character {
                    found = true
                    break
                }
            }
            if !found {
                return false
            }
        }

        return true
    }

    private static func fuzzyContains(_ query: String, in text: String) -> Bool {
        guard query.count >= 3, text.count >= query.count else { return false }
        if text.contains(query) { return true }

        let queryCharacters = Array(query)
        let textCharacters = Array(text)
        let distanceLimit = queryCharacters.count <= 5 ? 1 : 2
        let minLength = max(1, queryCharacters.count - distanceLimit)
        let maxLength = min(textCharacters.count, queryCharacters.count + distanceLimit)

        for length in minLength...maxLength {
            guard length <= textCharacters.count else { continue }
            for start in 0...(textCharacters.count - length) {
                let candidate = String(textCharacters[start..<(start + length)])
                if levenshtein(query, candidate, maxDistance: distanceLimit) <= distanceLimit {
                    return true
                }
            }
        }

        return false
    }

    private static func levenshtein(_ lhs: String, _ rhs: String, maxDistance: Int) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        var previous = Array(0...right.count)
        var current = Array(repeating: 0, count: right.count + 1)

        for (leftIndex, leftCharacter) in left.enumerated() {
            current[0] = leftIndex + 1
            var rowMinimum = current[0]

            for (rightIndex, rightCharacter) in right.enumerated() {
                let cost = leftCharacter == rightCharacter ? 0 : 1
                current[rightIndex + 1] = min(
                    previous[rightIndex + 1] + 1,
                    current[rightIndex] + 1,
                    previous[rightIndex] + cost
                )
                rowMinimum = min(rowMinimum, current[rightIndex + 1])
            }

            if rowMinimum > maxDistance {
                return rowMinimum
            }

            swap(&previous, &current)
        }

        return previous[right.count]
    }
}
