import Foundation

// MARK: - Stdio Transport

/// Env var names consumed by the stdio transport.
/// Mirrored in `Shared.Constants.EnvVar` for project-wide discoverability.
/// The MCP target has no dependencies, so the source-of-truth string lives here.
enum StdioTransportEnvVar {
    static let trace = "CUPERTINO_MCP_TRACE"
}

/// Transport implementation using standard input/output streams
/// This is the primary transport for Claude Desktop and CLI tools
public actor StdioTransport: MCPTransport {
    private let input: FileHandle
    private let output: FileHandle
    private var inputTask: Task<Void, Never>?
    private let messagesContinuation: AsyncStream<JSONRPCMessage>.Continuation
    private let _messages: AsyncStream<JSONRPCMessage>
    private var _isConnected: Bool = false
    private let traceEnabled: Bool

    public var messages: AsyncStream<JSONRPCMessage> {
        get async { _messages }
    }

    public var isConnected: Bool {
        get async { _isConnected }
    }

    public init(
        input: FileHandle = .standardInput,
        output: FileHandle = .standardOutput,
        traceEnabled: Bool? = nil
    ) {
        self.input = input
        self.output = output
        // why: read env once; ProcessInfo.environment returns a snapshot, repeated
        // lookups would be wasteful and obscure the policy decision site.
        self.traceEnabled = traceEnabled ?? Self.parseTraceFlag(
            ProcessInfo.processInfo.environment[StdioTransportEnvVar.trace]
        )

        var continuation: AsyncStream<JSONRPCMessage>.Continuation!
        _messages = AsyncStream { continuation = $0 }
        messagesContinuation = continuation
    }

    /// Parse the trace flag env value. Accepts "1", "true", "yes" (case-insensitive).
    static func parseTraceFlag(_ raw: String?) -> Bool {
        guard let raw else { return false }
        switch raw.lowercased() {
        case "1", "true", "yes":
            return true
        default:
            return false
        }
    }

    public func start() async throws {
        guard !_isConnected else {
            return
        }

        _isConnected = true

        // Start reading from stdin in background task
        inputTask = Task { [weak self] in
            await self?.readLoop()
        }
    }

    public func stop() async throws {
        guard _isConnected else {
            return
        }

        _isConnected = false
        inputTask?.cancel()
        inputTask = nil
        messagesContinuation.finish()
    }

    public func send(_ message: JSONRPCMessage) async throws {
        guard _isConnected else {
            throw TransportError.notConnected
        }

        do {
            let data = try message.encode()

            // Write newline-delimited JSON
            var outputData = data
            outputData.append(contentsOf: [0x0a]) // \n

            try output.write(contentsOf: outputData)

            // why: full message bodies leak tool args / responses into Claude
            // Desktop's persisted stderr logs; gate behind opt-in env flag.
            if traceEnabled, let messageStr = String(data: data, encoding: .utf8) {
                fputs("→ \(messageStr)\n", stderr)
            }
        } catch {
            throw TransportError.sendFailed(error.localizedDescription)
        }
    }

    // MARK: - Private Methods

    private func readLoop() async {
        var buffer = Data()

        do {
            // Use async bytes sequence (non-blocking, async iteration)
            for try await byte in input.bytes {
                guard _isConnected else {
                    break
                }

                buffer.append(byte)

                // Process complete lines (newline-delimited JSON)
                if byte == 0x0a { // \n
                    let lineData = Data(buffer.dropLast()) // Remove the newline

                    // Skip empty lines
                    if !lineData.isEmpty {
                        // Parse and emit message
                        do {
                            let message = try JSONRPCMessage.decode(from: lineData)

                            if traceEnabled, let messageStr = String(data: lineData, encoding: .utf8) {
                                fputs("← \(messageStr)\n", stderr)
                            }

                            messagesContinuation.yield(message)
                        } catch {
                            // why: kept ungated — decode errors are real diagnostics
                            // for misbehaving peers. The error description may echo a
                            // small fragment of malformed JSON, but malformed input is
                            // by definition not a valid request payload.
                            fputs("Error decoding message: \(error)\n", stderr)
                        }
                    }

                    // Clear buffer for next message
                    buffer.removeAll(keepingCapacity: true)
                }
            }
        } catch {
            // why: kept ungated — fatal transport failure must be observable.
            if _isConnected {
                fputs("Error reading stdin: \(error)\n", stderr)
            }
        }

        // Clean up when loop exits
        messagesContinuation.finish()
    }
}

// MARK: - FileHandle Extensions

extension FileHandle {
    /// Write data to the file handle
    func write(contentsOf data: Data) throws {
        #if canImport(Darwin)
        write(data)
        #else
        try write(contentsOf: data)
        #endif
    }
}
