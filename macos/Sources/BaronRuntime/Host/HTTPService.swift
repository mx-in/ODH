import BaronCore
import Foundation

/// `host.http.fetch`. Each plugin has its own ephemeral session with cookies off, so no plugin sees another's
/// state or Safari's. Permission checks on hosts and redirects come with task-006. Design: 03-host-api-and-ipc.md#httpfetch
public final class HTTPService: HostService, @unchecked Sendable {
    public let namespace = "http"
    public struct Limits: Sendable {
        public var defaultTimeout: Double = 30
        public var maximumTimeout: Double = 60
        public var maximumBody = 20 * 1024 * 1024
        public var maximumRedirects = 5
        public init() {}
    }

    private let limits: Limits
    private let configuration: URLSessionConfiguration
    private let lock = NSLock()
    private var sessions: [String: URLSession] = [:]
    private var requests: [String: Task<JSONValue, Error>] = [:]
    private let redirects = SessionDelegate()
    private let policy: NetworkPolicy?

    /// `configuration` lets tests stub the network; it is copied and made ephemeral and cookie-free.
    /// Without a `policy` every host is allowed (tests of the service itself).
    public init(limits: Limits = Limits(), configuration: URLSessionConfiguration = .ephemeral, policy: NetworkPolicy? = nil) {
        self.limits = limits
        self.configuration = configuration
        self.policy = policy
        redirects.maximum = limits.maximumRedirects
    }

    public func call(_ method: String, _ arguments: HostArguments, plugin: RuntimePlugin) async throws -> JSONValue {
        switch method {
        case "fetch": return try await fetch(arguments, plugin: plugin)
        case "cancel":
            let key = "\(plugin.id)#\(Int(try arguments.number(0)))"
            lock.withLock { requests.removeValue(forKey: key) }?.cancel()
            return .null
        default: throw arguments.unknownMethod()
        }
    }

    private func session(for plugin: RuntimePlugin) -> URLSession {
        lock.withLock {
            if let session = sessions[plugin.id] { return session }
            let config = configuration.copy() as! URLSessionConfiguration
            config.httpShouldSetCookies = false
            config.httpCookieAcceptPolicy = .never
            config.httpCookieStorage = nil
            config.urlCache = nil
            let session = URLSession(configuration: config, delegate: redirects, delegateQueue: nil)
            sessions[plugin.id] = session
            return session
        }
    }

    private func fetch(_ arguments: HostArguments, plugin: RuntimePlugin) async throws -> JSONValue {
        let text = try arguments.string(0)
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil else {
            throw HostError("invalid_argument", "fetch needs an http or https URL, not \(text)", data: .object(["path": .string("/0")]))
        }
        if let refusal = await policy?.check(url, for: plugin) { throw refusal }
        let init_ = try arguments.object(1)
        var request = URLRequest(url: url)
        request.httpMethod = init_["method"]?.stringValue?.uppercased() ?? "GET"
        guard ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE"].contains(request.httpMethod!) else {
            throw HostError("invalid_argument", "Unsupported method \(request.httpMethod!)", data: .object(["path": .string("/1/method")]))
        }
        if case .object(let headers)? = init_["headers"] {
            for (name, value) in headers { if let value = value.stringValue { request.setValue(value, forHTTPHeaderField: name) } }
        }
        switch init_["body"] {
        case .string(let body)?: request.httpBody = Data(body.utf8)
        case .object(let wrapped)?:
            guard let base64 = wrapped["$bytes"]?.stringValue, let data = Data(base64Encoded: base64) else { throw arguments.invalid(1, "an init whose body is text or bytes") }
            request.httpBody = data
        default: break
        }
        if case .number(let ms)? = init_["timeout"] {
            request.timeoutInterval = min(max(ms / 1000, 0.001), limits.maximumTimeout)
        } else {
            request.timeoutInterval = limits.defaultTimeout
        }
        let wantsBytes = init_["responseType"]?.stringValue == "bytes"
        let key = init_["requestID"].flatMap { if case .number(let n) = $0 { "\(plugin.id)#\(Int(n))" } else { nil } }

        let session = session(for: plugin)
        let delegate = redirects
        let maximumBody = limits.maximumBody
        let policy = self.policy
        let allow: SessionDelegate.RedirectCheck = { url in await policy?.check(url, for: plugin) }
        let task = Task { () throws -> JSONValue in
            let (body, http) = try await delegate.load(request, in: session, maximumBody: maximumBody, checkRedirect: allow)
            var headers: [String: JSONValue] = [:]
            for (name, value) in http.allHeaderFields {
                if let name = name as? String { headers[name.lowercased()] = .string("\(value)") }
            }
            let payload: JSONValue = wantsBytes ? .object(["$bytes": .string(body.base64EncodedString())]) : .string(String(decoding: body, as: UTF8.self))
            return .object(["status": .number(Double(http.statusCode)), "url": .string(http.url?.absoluteString ?? text), "headers": .object(headers), "body": payload])
        }
        if let key { lock.withLock { requests[key] = task } }
        defer { if let key { _ = lock.withLock { requests.removeValue(forKey: key) } } }
        do {
            return try await task.value
        } catch let error as HostError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .timedOut: throw HostError.timeout("The request to \(url.host ?? text) timed out")
            case .cancelled: throw HostError("network_error", "The request was cancelled", data: .object(["reason": .string("cancelled")]))
            case .httpTooManyRedirects: throw HostError("network_error", "More than \(limits.maximumRedirects) redirects", data: .object(["reason": .string("redirects")]))
            default: throw HostError("network_error", error.localizedDescription, data: .object(["reason": .string("\(error.code.rawValue)")]))
            }
        } catch is CancellationError {
            throw HostError("network_error", "The request was cancelled", data: .object(["reason": .string("cancelled")]))
        }
    }

    static func tooLarge(_ limit: Int) -> HostError {
        HostError("network_error", "The response is larger than \(limit / 1024 / 1024) MB", data: .object(["reason": .string("too_large")]))
    }
}

/// The session's delegate: collects each response in chunks, stopping past the size limit, and follows at
/// most `maximum` redirects per request.
final class SessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    /// Returns an error to refuse a redirect target.
    typealias RedirectCheck = @Sendable (URL) async -> HostError?

    private struct Load {
        var data = Data()
        var redirects = 0
        var maximumBody: Int
        var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>
        var tooLarge = false
        var checkRedirect: RedirectCheck
        var refusal: HostError?
    }

    private let lock = NSLock()
    private var loads: [Int: Load] = [:]
    var maximum = 5

    func load(_ request: URLRequest, in session: URLSession, maximumBody: Int, checkRedirect: @escaping RedirectCheck = { _ in nil }) async throws -> (Data, HTTPURLResponse) {
        let task = session.dataTask(with: request)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock { loads[task.taskIdentifier] = Load(maximumBody: maximumBody, continuation: continuation, checkRedirect: checkRedirect) }
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse) async -> URLSession.ResponseDisposition {
        let tooLarge = lock.withLock { () -> Bool in
            guard let load = loads[dataTask.taskIdentifier] else { return false }
            return response.expectedContentLength > Int64(load.maximumBody)
        }
        if tooLarge {
            lock.withLock { loads[dataTask.taskIdentifier]?.tooLarge = true }
            return .cancel
        }
        return .allow
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let over = lock.withLock { () -> Bool in
            guard var load = loads[dataTask.taskIdentifier] else { return false }
            load.data.append(data)
            load.tooLarge = load.data.count > load.maximumBody
            loads[dataTask.taskIdentifier] = load
            return load.tooLarge
        }
        if over { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        let (count, check) = lock.withLock { () -> (Int, RedirectCheck?) in
            loads[task.taskIdentifier]?.redirects += 1
            return (loads[task.taskIdentifier]?.redirects ?? 0, loads[task.taskIdentifier]?.checkRedirect)
        }
        if count > maximum {
            task.cancel()
            return nil
        }
        if let url = request.url, let refusal = await check?(url) {
            lock.withLock { loads[task.taskIdentifier]?.refusal = refusal }
            task.cancel()
            return nil
        }
        return request
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let load = lock.withLock({ loads.removeValue(forKey: task.taskIdentifier) }) else { return }
        if let refusal = load.refusal {
            load.continuation.resume(throwing: refusal)
        } else if load.tooLarge {
            load.continuation.resume(throwing: HTTPService.tooLarge(load.maximumBody))
        } else if load.redirects > maximum {
            load.continuation.resume(throwing: URLError(.httpTooManyRedirects))
        } else if let error {
            load.continuation.resume(throwing: error)
        } else if let response = task.response as? HTTPURLResponse {
            load.continuation.resume(returning: (load.data, response))
        } else {
            load.continuation.resume(throwing: HostError("network_error", "Not an HTTP response"))
        }
    }
}
