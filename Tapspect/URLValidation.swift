import Foundation

/// Validates that a string is a well-formed HTTP or HTTPS URL with a host.
func isValidWebURL(_ string: String) -> Bool {
    guard let url = URL(string: string),
          let scheme = url.scheme?.lowercased(),
          (scheme == "http" || scheme == "https"),
          url.host != nil else {
        return false
    }
    return true
}

/// Resolves a dot-separated key path against a JSON dictionary.
/// Returns the value at the path, or nil if any key is missing or the structure doesn't match.
func resolveJSONKeyPath(_ keyPath: String, in json: [String: Any]) -> Any? {
    let keys = keyPath.split(separator: ".").map(String.init)
    var current: Any = json
    for key in keys {
        guard let dict = current as? [String: Any], let next = dict[key] else {
            return nil
        }
        current = next
    }
    return current
}

/// Pretty-prints a JSON string. Returns the original string if parsing fails.
func prettyFormatJSON(_ raw: String) -> String {
    guard let data = raw.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data),
          let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
          let str = String(data: pretty, encoding: .utf8) else {
        return raw
    }
    return str
}
