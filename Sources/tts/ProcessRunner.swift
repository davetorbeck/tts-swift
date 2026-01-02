import Darwin
import Foundation

/// Utility for running external processes with real-time output streaming.
/// Provides two modes: regular pipe-based execution and PTY-based execution
/// for programs that require a terminal (like pip with progress bars).
enum ProcessRunner {

    // MARK: - Output Collection

    /// Thread-safe collector for accumulating process output from multiple streams.
    /// Marked @unchecked Sendable because we manually synchronize with NSLock.
    private final class OutputCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var stdoutData = Data()
        private var stderrData = Data()

        /// Appends data to the stdout buffer (thread-safe).
        func appendStdout(_ data: Data) {
            lock.lock()
            stdoutData.append(data)
            lock.unlock()
        }

        /// Appends data to the stderr buffer (thread-safe).
        func appendStderr(_ data: Data) {
            lock.lock()
            stderrData.append(data)
            lock.unlock()
        }

        /// Reads any remaining data from the handles and returns the complete output.
        /// Call this after the process exits to ensure all data is captured.
        /// - Parameters:
        ///   - stdoutHandle: The stdout file handle to drain.
        ///   - stderrHandle: The stderr file handle to drain.
        /// - Returns: A tuple containing the complete stdout and stderr as strings.
        func flush(stdoutHandle: FileHandle, stderrHandle: FileHandle) -> (
            stdout: String, stderr: String
        ) {
            lock.lock()
            // Drain any remaining buffered data from the pipes
            stdoutData.append(stdoutHandle.readDataToEndOfFile())
            stderrData.append(stderrHandle.readDataToEndOfFile())
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            lock.unlock()
            return (stdout, stderr)
        }
    }

    // MARK: - Pipe-based Execution

    /// Runs an executable with separate stdout/stderr pipes.
    /// Output is streamed in real-time to the console and the optional callback.
    /// - Parameters:
    ///   - executable: Full path to the executable (e.g., "/usr/bin/python3").
    ///   - arguments: Command-line arguments to pass.
    ///   - onOutput: Optional callback receiving output text and isStderr flag.
    /// - Returns: Exit code, complete stdout, and complete stderr.
    static func run(
        executable: String,
        arguments: [String],
        onOutput: (@Sendable (String, Bool) -> Void)? = nil
    ) -> (exitCode: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        // Create separate pipes for stdout and stderr
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return run(
            process: process, stdoutPipe: stdoutPipe, stderrPipe: stderrPipe, onOutput: onOutput)
    }

    /// Runs a pre-configured Process with the given pipes.
    /// This overload allows callers to customize the Process before execution.
    /// - Parameters:
    ///   - process: A configured Process object (with executableURL, arguments, environment, etc.).
    ///   - stdoutPipe: Pipe attached to process.standardOutput.
    ///   - stderrPipe: Pipe attached to process.standardError.
    ///   - onOutput: Optional callback for streaming output. Bool param is true for stderr.
    /// - Returns: Exit code, complete stdout, and complete stderr.
    static func run(
        process: Process,
        stdoutPipe: Pipe,
        stderrPipe: Pipe,
        onOutput: (@Sendable (String, Bool) -> Void)? = nil
    ) -> (exitCode: Int32, stdout: String, stderr: String) {
        let collector = OutputCollector()
        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading

        // Set up async handlers that fire when data becomes available.
        // These run on a background queue, hence the thread-safe collector.
        stdoutHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            collector.appendStdout(data)
            // Echo to console for real-time visibility
            FileHandle.standardOutput.write(data)
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                onOutput?(text, false)  // false = stdout
            }
        }

        stderrHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            collector.appendStderr(data)
            // Echo to console for real-time visibility
            FileHandle.standardError.write(data)
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                onOutput?(text, true)  // true = stderr
            }
        }

        do {
            try process.run()
            process.waitUntilExit()  // Blocks until process completes
        } catch {
            return (1, "", error.localizedDescription)
        }

        // Clean up handlers before flushing to avoid race conditions
        stdoutHandle.readabilityHandler = nil
        stderrHandle.readabilityHandler = nil

        // Collect any remaining buffered output
        let flushed = collector.flush(stdoutHandle: stdoutHandle, stderrHandle: stderrHandle)
        return (
            process.terminationStatus, flushed.stdout,
            flushed.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    // MARK: - PTY-based Execution

    /// Runs an executable using a pseudo-terminal (PTY).
    /// Use this for programs that require a TTY (e.g., pip with progress bars,
    /// programs that check isatty(), or interactive tools).
    /// - Parameters:
    ///   - executable: Full path to the executable.
    ///   - arguments: Command-line arguments to pass.
    ///   - onOutput: Optional callback for streaming output (isStderr is always false in PTY mode).
    /// - Returns: Exit code, complete output, and stderr (same as stdout in PTY mode).
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

    /// Runs a pre-configured Process using a pseudo-terminal.
    /// In PTY mode, stdout and stderr are merged into a single stream.
    /// - Parameters:
    ///   - process: A configured Process object.
    ///   - onOutput: Optional callback for streaming output.
    /// - Returns: Exit code and output (stdout and stderr are the same in PTY mode).
    static func runPTY(
        process: Process,
        onOutput: (@Sendable (String, Bool) -> Void)? = nil
    ) -> (exitCode: Int32, stdout: String, stderr: String) {
        // Create a pseudo-terminal pair (master/slave)
        // Master: what we read from / write to
        // Slave: what the child process uses as its terminal
        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1
        guard openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 else {
            return (1, "", "Failed to open PTY")
        }

        let masterHandle = FileHandle(fileDescriptor: masterFD, closeOnDealloc: true)
        let slaveHandle = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: true)

        // Connect all three standard streams to the slave PTY
        // This makes the child think it's running in a real terminal
        process.standardInput = slaveHandle
        process.standardOutput = slaveHandle
        process.standardError = slaveHandle

        let collector = OutputCollector()

        // Read from master to capture child's output
        masterHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            collector.appendStdout(data)
            // Echo to console for real-time visibility
            FileHandle.standardOutput.write(data)
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                onOutput?(text, false)  // PTY merges streams, so always false
            }
        }

        do {
            try process.run()
        } catch {
            masterHandle.readabilityHandler = nil
            return (1, "", error.localizedDescription)
        }

        // Close slave in parent process after fork.
        // The child process inherited its own copy and keeps it open.
        // This is required for proper EOF detection on the master.
        slaveHandle.closeFile()

        process.waitUntilExit()

        masterHandle.readabilityHandler = nil
        // In PTY mode, stdout and stderr are the same stream
        let flushed = collector.flush(stdoutHandle: masterHandle, stderrHandle: masterHandle)
        return (
            process.terminationStatus, flushed.stdout,
            flushed.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
