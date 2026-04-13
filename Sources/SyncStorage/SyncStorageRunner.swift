import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import os.log

#if os(macOS) || os(Linux) || os(Windows)

final class SyncStorageRunner {
    private static let syncStorageReleaseVersion = "v0.2.6"

    enum SyncStorageRunnerError: LocalizedError {
        case invalidConfiguration(String)
        case downloadFailed(String)
        case processStartFailed(String)
        case startupTimeout
        case unsupportedPlatform(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidConfiguration(let message):
                return "SyncStorageRunner: invalid configuration: \(message)"
            case .downloadFailed(let message):
                return "SyncStorageRunner: download failed: \(message)"
            case .processStartFailed(let message):
                return "SyncStorageRunner: process start failed: \(message)"
            case .startupTimeout:
                return "SyncStorageRunner: startup timeout"
            case .unsupportedPlatform(let message):
                return "SyncStorageRunner: unsupported platform: \(message)"
            }
        }
    }
    
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TestItAdapter", category: "SyncStorageRunner")
    
    private let port: Int
    private let baseURL: String
    private let privateToken: String
    private let configuredPath: String?
    
    private var testRunId: String
    
    private let workerPID: String
    private var isMaster: Bool = false
    private var isAlreadyInProgress: Bool = false
    private var isRunning: Bool = false
    private var isExternal: Bool = false
    
    private var process: Process?
    private var outputPipe: Pipe?
    
    private let apiResponseQueue = DispatchQueue.global(qos: .utility)
    
    private let startupTimeoutSeconds: TimeInterval = 30
    private let startupCheckIntervalSeconds: TimeInterval = 1
    private let postStartupDelaySeconds: TimeInterval = 2
    
    init(testRunId: String, port: Int, baseURL: String, privateToken: String, syncStoragePath: String?) throws {
        guard !testRunId.isEmpty, testRunId.lowercased() != "null" else {
            throw SyncStorageRunnerError.invalidConfiguration("testRunId is empty")
        }
        guard port > 0 && port <= 65535 else {
            throw SyncStorageRunnerError.invalidConfiguration("invalid port \(port)")
        }
        
        self.testRunId = testRunId
        self.port = port
        self.baseURL = baseURL
        self.privateToken = privateToken
        self.configuredPath = syncStoragePath
        self.workerPID = "worker-\(ProcessInfo.processInfo.processIdentifier)-\(Int64(Date().timeIntervalSince1970 * 1000))"
        
        // Configure generated API client.
        SyncStorageClientAPI.basePath = "http://127.0.0.1:\(port)"
        SyncStorageClientAPI.apiResponseQueue = apiResponseQueue
    }
    
    func start() -> Bool {
        if isRunning { return true }
        
        // If already running externally, connect and register.
        if !healthCheckOk() {
            Self.logger.info("SyncStorage already started externally, connecting")
            isRunning = true
            isExternal = true
            registerWorker()
            return true
        }
        
        do {
            let executablePath = try prepareExecutable()
            let args = buildArgs()
            Self.logger.info("Starting SyncStorage process: \(executablePath, privacy: .public)")
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = args
            process.currentDirectoryURL = URL(fileURLWithPath: (executablePath as NSString).deletingLastPathComponent)
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            self.process = process
            self.outputPipe = pipe
            
            try process.run()
            readOutputAsync(from: pipe)
            
            guard waitForStartup() else {
                Self.logger.error("SyncStorage failed to start within timeout")
                stop()
                return false
            }
            
            isRunning = true
            Self.logger.info("SyncStorage started successfully on port \(self.port)")
            Thread.sleep(forTimeInterval: postStartupDelaySeconds)
            registerWorker()
            return true
        } catch {
            Self.logger.error("Failed to start SyncStorage: \(error.localizedDescription, privacy: .public)")
            stop()
            return false
        }
    }
    
    func stop() {
        isRunning = false
        isAlreadyInProgress = false
        
        guard !isExternal else { return }
        guard let process else { return }
        
        if process.isRunning {
            process.terminate()
            // Best-effort wait
            _ = process.waitUntilExitTimeout(seconds: 5)
        }
        self.process = nil
        self.outputPipe = nil
    }
    
    func setWorkerStatus(_ status: String) {
        guard isRunning else { return }
        
        let req = SetWorkerStatusRequest(pid: workerPID, status: status, testRunId: testRunId)
        let ok = waitBool { done in
            _ = WorkersAPI.setWorkerStatusPost(setWorkerStatusRequest: req, apiResponseQueue: apiResponseQueue) { _, error in
                done(error == nil)
            }
        }
        if !ok {
            Self.logger.error("SyncStorage setWorkerStatus failed")
        }
    }
    
    func sendInProgressTestResult(autoTestExternalId: String, statusCode: String, startedOn: String) -> Bool {
        guard isRunning else { return false }
        guard isMaster else { return false }
        guard !isAlreadyInProgress else { return false }
        
        let startedOnDate = OpenISO8601DateFormatter().date(from: startedOn)
        let model = TestResultCutApiModel(
            autoTestExternalId: autoTestExternalId,
            statusCode: statusCode,
            statusType: String(describing: Converter.mapStatusType(status: statusCode)),
            startedOn: startedOnDate
        )
        
        let ok = waitBool { done in
            _ = TestResultsAPI.inProgressTestResultPost(
                testRunId: testRunId,
                testResultCutApiModel: model,
                apiResponseQueue: apiResponseQueue
            ) { _, error in
                done(error == nil)
            }
        }
        
        if ok {
            isAlreadyInProgress = true
            return true
        }
        
        Self.logger.error("SyncStorage in_progress_test_result failed")
        return false
    }
    
    func resetInProgressFlag() {
        isAlreadyInProgress = false
    }
    
    func updateTestRunId(_ testRunId: String) {
        self.testRunId = testRunId
    }
    
    func isMasterWorker() -> Bool { isMaster }
    
    // MARK: - Internals
    
    private func buildArgs() -> [String] {
        var args: [String] = []
        if !testRunId.isEmpty { args.append(contentsOf: ["--testRunId", testRunId]) }
        args.append(contentsOf: ["--port", String(port)])
        if !baseURL.isEmpty { args.append(contentsOf: ["--baseURL", baseURL]) }
        if !privateToken.isEmpty { args.append(contentsOf: ["--privateToken", privateToken]) }
        return args
    }
    
    private func registerWorker() {
        let req = RegisterRequest(
            pid: workerPID,
            testRunId: testRunId,
            baseUrl: baseURL,
            privateToken: privateToken
        )
        
        let resp: RegisterResponse? = waitResult { done in
            _ = WorkersAPI.registerPost(registerRequest: req, apiResponseQueue: apiResponseQueue) { data, error in
                if let error {
                    done(.failure(error))
                } else {
                    done(.success(data))
                }
            }
        }
        
        isMaster = resp?.isMaster ?? false
        if isMaster {
            Self.logger.info("SyncStorage master worker registered: \(self.workerPID, privacy: .public)")
        } else {
            Self.logger.info("SyncStorage worker registered: \(self.workerPID, privacy: .public)")
        }
    }
    
    private func waitForStartup() -> Bool {
        let deadline = Date().addingTimeInterval(startupTimeoutSeconds)
        while Date() < deadline {
            if healthCheckOk() {
                return true
            }
            Thread.sleep(forTimeInterval: startupCheckIntervalSeconds)
        }
        return false
    }
    
    private func healthCheckOk() -> Bool {
        let ok = waitBool { done in
            _ = HealthAPI.healthGet(apiResponseQueue: apiResponseQueue) { _, error in
                done(error == nil)
            }
        }
        return ok
    }
    
    private func waitBool(_ start: (@escaping (Bool) -> Void) -> Void) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var result = false
        start { ok in
            result = ok
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }
    
    private func waitResult<T>(_ start: (@escaping (Result<T?, Error>) -> Void) -> Void) -> T? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: T?
        start { res in
            switch res {
            case .success(let value):
                result = value
            case .failure:
                result = nil
            }
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }
    
    private func prepareExecutable() throws -> String {
        if let configuredPath, !configuredPath.isEmpty {
            if FileManager.default.fileExists(atPath: configuredPath) {
                return configuredPath
            }
            throw SyncStorageRunnerError.invalidConfiguration("TMS_SYNC_STORAGE_PATH does not exist: \(configuredPath)")
        }
        
        let fileName = try executableFileName()
        let cacheDir = (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent("build/.caches")
        try FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
        let targetPath = (cacheDir as NSString).appendingPathComponent(fileName)
        
        if FileManager.default.fileExists(atPath: targetPath) {
            setExecutableBitIfNeeded(path: targetPath)
            return targetPath
        }
        
        let downloadURL = "https://github.com/testit-tms/sync-storage-public/releases/download/\(Self.syncStorageReleaseVersion)/\(fileName)"
        try downloadFile(from: downloadURL, to: targetPath)
        setExecutableBitIfNeeded(path: targetPath)
        return targetPath
    }
    
    private func executableFileName() throws -> String {
        #if os(Windows)
        let osPart = "windows"
        #elseif os(macOS)
        let osPart = "darwin"
        #elseif os(Linux)
        let osPart = "linux"
        #else
        throw SyncStorageRunnerError.unsupportedPlatform("unknown OS")
        #endif
        
        let archPart: String
        #if arch(x86_64)
        archPart = "amd64"
        #elseif arch(arm64)
        archPart = "arm64"
        #else
        throw SyncStorageRunnerError.unsupportedPlatform("unsupported architecture")
        #endif
        
        var name = "syncstorage-\(Self.syncStorageReleaseVersion)-\(osPart)_\(archPart)"
        #if os(Windows)
        name += ".exe"
        #endif
        return name
    }
    
    private func downloadFile(from urlString: String, to targetPath: String) throws {
        guard let url = URL(string: urlString) else {
            throw SyncStorageRunnerError.downloadFailed("invalid url: \(urlString)")
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        var resultError: Error?
        var resultData: Data?
        var resultResponse: URLResponse?
        
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        URLSession.shared.dataTask(with: request) { data, response, error in
            resultData = data
            resultResponse = response
            resultError = error
            semaphore.signal()
        }.resume()
        
        semaphore.wait()
        
        if let error = resultError {
            throw SyncStorageRunnerError.downloadFailed(error.localizedDescription)
        }
        
        if let http = resultResponse as? HTTPURLResponse, http.statusCode != 200 {
            let body = resultData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            throw SyncStorageRunnerError.downloadFailed("HTTP \(http.statusCode): \(body)")
        }
        
        do {
            try (resultData ?? Data()).write(to: URL(fileURLWithPath: targetPath), options: .atomic)
        } catch {
            throw SyncStorageRunnerError.downloadFailed(error.localizedDescription)
        }
    }
    
    private func setExecutableBitIfNeeded(path: String) {
        #if os(Windows)
        // no-op
        #else
        do {
            var attrs = try FileManager.default.attributesOfItem(atPath: path)
            if let permissions = attrs[.posixPermissions] as? NSNumber {
                let current = permissions.intValue
                let desired = current | 0o111
                if desired != current {
                    attrs[.posixPermissions] = NSNumber(value: desired)
                    try FileManager.default.setAttributes(attrs, ofItemAtPath: path)
                }
            } else {
                try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: path)
            }
        } catch {
            // best-effort
        }
        #endif
    }
    
    private func readOutputAsync(from pipe: Pipe) {
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            if data.isEmpty { return }
            if let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                Self.logger.info("SyncStorage output: \(text, privacy: .public)")
            }
        }
    }
}

fileprivate extension Process {
    func waitUntilExitTimeout(seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        return !isRunning
    }
}

#else

// On platforms where launching a subprocess is not supported, provide a stub implementation
// that disables sync-storage without affecting the main adapter flow.
final class SyncStorageRunner {
    init(testRunId: String, port: Int, baseURL: String, privateToken: String, syncStoragePath: String?) throws {}
    func start() -> Bool { return false }
    func stop() {}
    func setWorkerStatus(_ status: String) {}
    func sendInProgressTestResult(autoTestExternalId: String, statusCode: String, startedOn: String) -> Bool { return false }
    func resetInProgressFlag() {}
    func updateTestRunId(_ testRunId: String) {}
    func isMasterWorker() -> Bool { return false }
}

#endif

