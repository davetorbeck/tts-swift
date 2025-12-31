import Foundation
import Darwin

enum ProcessRunner {
    private final class OutputCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var stdoutData = Data()
        private var stderrData = Data()

        func appendStdout(_ data: Data) {
            lock.lock()
            stdoutData.append(data)
            lock.unlock()
        }

        func appendStderr(_ data: Data) {
            lock.lock()
            stderrData.append(data)
            lock.unlock()
        }

        func flush(stdoutHandle: FileHandle, stderrHandle: FileHandle) -> (stdout: String, stderr: String) {
            lock.lock()
            stdoutData.append(stdoutHandle.readDataToEndOfFile())
            stderrData.append(stderrHandle.readDataToEndOfFile())
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            lock.unlock()
            return (stdout, stderr)
        }
    }

    static func run(
        executable: String,
        arguments: [String],
        onOutput: (@Sendable (String, Bool) -> Void)? = nil
    ) -> (exitCode: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return run(process: process, stdoutPipe: stdoutPipe, stderrPipe: stderrPipe, onOutput: onOutput)
    }

    static func run(
        process: Process,
        stdoutPipe: Pipe,
        stderrPipe: Pipe,
        onOutput: (@Sendable (String, Bool) -> Void)? = nil
    ) -> (exitCode: Int32, stdout: String, stderr: String) {
        let collector = OutputCollector()
        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading

        stdoutHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            collector.appendStdout(data)
            FileHandle.standardOutput.write(data)
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                onOutput?(text, false)
            }
        }

        stderrHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            collector.appendStderr(data)
            FileHandle.standardError.write(data)
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                onOutput?(text, true)
            }
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (1, "", error.localizedDescription)
        }

        stdoutHandle.readabilityHandler = nil
        stderrHandle.readabilityHandler = nil
        let flushed = collector.flush(stdoutHandle: stdoutHandle, stderrHandle: stderrHandle)
        return (process.terminationStatus, flushed.stdout, flushed.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func runPTY(
        executable: String,
        arguments: [String],
        onOutput: (@Sendable (String, Bool) -> Void)? = nil
    ) -> (exitCode: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        return runPTY(process: process, onOutput: onOutput)
    }

    static func runPTY(
        process: Process,
        onOutput: (@Sendable (String, Bool) -> Void)? = nil
    ) -> (exitCode: Int32, stdout: String, stderr: String) {
        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1
        guard openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 else {
            return (1, "", "Failed to open PTY")
        }

        let masterHandle = FileHandle(fileDescriptor: masterFD, closeOnDealloc: true)
        let slaveHandle = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: true)

        process.standardInput = slaveHandle
        process.standardOutput = slaveHandle
        process.standardError = slaveHandle

        let collector = OutputCollector()
        masterHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            collector.appendStdout(data)
            FileHandle.standardOutput.write(data)
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                onOutput?(text, false)
            }
        }

        do {
            try process.run()
        } catch {
            masterHandle.readabilityHandler = nil
            return (1, "", error.localizedDescription)
        }

        // Close slave in parent; child keeps it open.
        slaveHandle.closeFile()

        process.waitUntilExit()

        masterHandle.readabilityHandler = nil
        let flushed = collector.flush(stdoutHandle: masterHandle, stderrHandle: masterHandle)
        return (process.terminationStatus, flushed.stdout, flushed.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
