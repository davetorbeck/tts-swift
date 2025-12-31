import Foundation

enum KokoroLogger {
    static func log(title: String, result: (exitCode: Int32, stdout: String, stderr: String)) -> String {
        let output = format(title: title, result: result)
        print(output)
        return output
    }

    static func format(title: String, result: (exitCode: Int32, stdout: String, stderr: String)) -> String {
        var parts: [String] = []
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        parts.append("\(title) (exit \(result.exitCode))")
        if !stdout.isEmpty {
            parts.append("stdout:\n\(result.stdout)")
        }
        if !stderr.isEmpty {
            parts.append("stderr:\n\(result.stderr)")
        }
        return parts.joined(separator: "\n")
    }
}
