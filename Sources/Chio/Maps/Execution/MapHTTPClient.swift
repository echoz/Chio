import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Internal bounded transport. The delegate receives decompressed URLSession data;
/// Content-Length is only an early rejection, never the authoritative byte bound.
struct MapHTTPClient {
    enum Resource {
        case catalog, tile

        var limit: Int {
            switch self {
            case .catalog: 256 * 1_024
            case .tile: 16 * 1_024 * 1_024
            }
        }

        var acceptHeaderValue: String {
            switch self {
            case .catalog: "application/json"
            case .tile: "application/vnd.mapbox-vector-tile, application/x-protobuf, application/octet-stream"
            }
        }

        var acceptedMIMETypes: [String] {
            switch self {
            case .catalog: ["application/json", "text/json"]
            case .tile: ["application/vnd.mapbox-vector-tile", "application/x-protobuf", "application/protobuf", "application/octet-stream"]
            }
        }
    }
    struct Response {
        let data: Data
        let headers: [String: String]
    }
    typealias Transport = @Sendable (URL, Resource) async throws -> Response

    static func fetch(_ url: URL, resource: Resource, timeout: TimeInterval = 20,
                      onTerminalAcknowledgement: @escaping @Sendable () -> Void = {},
                      beforeRedirectDecision: @escaping @Sendable (URLSessionTask) -> Void = { _ in }) async throws -> Response {
        guard timeout.isFinite, timeout > 0, timeout <= 20 else { throw MapTileLoader.LoadingError.invalidResponse }
        let transfer = Transfer(url: url, resource: resource, timeout: timeout,
                                onTerminalAcknowledgement: onTerminalAcknowledgement,
                                beforeRedirectDecision: beforeRedirectDecision)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { transfer.start($0) }
        } onCancel: { transfer.cancel() }
    }

    static func sameOrigin(_ first: URL, _ second: URL) -> Bool {
        func port(_ url: URL) -> Int { url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80) }
        return first.scheme?.lowercased() == second.scheme?.lowercased()
            && first.host?.lowercased() == second.host?.lowercased() && port(first) == port(second)
    }

    /// Foundation requires a Sendable delegate. All live ownership and callbacks
    /// are isolated by the lock; the delegate queue is additionally serial. The
    /// task/session references are used only for registration and teardown.
    fileprivate final class Transfer: NSObject {
        private struct State {
            var continuation: CheckedContinuation<Response, any Error>?
            var task: URLSessionDataTask?
            var session: URLSession?
            var isCompleted = false
            var isCancelled = false
            var data = Data()
            var headers: [String: String] = [:]
            var redirects = 0
            var hasAcceptedResponse = false
            var firstFailure: (any Error)?
        }
        private let lock = NSLock()
        private var state = State()
        let url: URL
        let resource: Resource
        let timeout: TimeInterval
        private let onTerminalAcknowledgement: @Sendable () -> Void
        private let beforeRedirectDecision: @Sendable (URLSessionTask) -> Void

        init(url: URL, resource: Resource, timeout: TimeInterval,
             onTerminalAcknowledgement: @escaping @Sendable () -> Void,
             beforeRedirectDecision: @escaping @Sendable (URLSessionTask) -> Void) {
            self.url = url; self.resource = resource; self.timeout = timeout
            self.onTerminalAcknowledgement = onTerminalAcknowledgement
            self.beforeRedirectDecision = beforeRedirectDecision
        }

        func start(_ continuation: CheckedContinuation<Response, any Error>) {
            lock.lock()
            if state.isCancelled {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            state.continuation = continuation
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.urlCredentialStorage = nil
            configuration.timeoutIntervalForRequest = timeout
            configuration.timeoutIntervalForResource = timeout
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
            request.setValue("Chio OpenMapTiles", forHTTPHeaderField: "User-Agent")
            request.setValue(resource.acceptHeaderValue, forHTTPHeaderField: "Accept")
            let task = session.dataTask(with: request)
            state.session = session
            state.task = task
            // Resume under the registration lock, so cancellation cannot happen
            // between registration and a later resume of a cancelled task.
            task.resume()
            lock.unlock()
        }

        func cancel() {
            lock.lock()
            state.isCancelled = true
            lock.unlock()
            reject(CancellationError())
        }

        /// Rejection stops the real resource, but cannot release admission yet.
        /// The terminal delegate acknowledgement owns continuation completion.
        private func reject(_ error: any Error) {
            lock.lock()
            guard !state.isCompleted else { lock.unlock(); return }
            if state.firstFailure == nil { state.firstFailure = error }
            let task = state.task, session = state.session
            lock.unlock()
            // Explicit cancellation is required on Linux: response disposition
            // alone may be ignored by FoundationNetworking.
            task?.cancel()
            session?.invalidateAndCancel()
        }

        private func finish(_ result: Result<Response, any Error>) {
            lock.lock()
            guard !state.isCompleted, let continuation = state.continuation else { lock.unlock(); return }
            state.isCompleted = true
            state.continuation = nil
            let outcome: Result<Response, any Error>
            if let failure = state.firstFailure { outcome = .failure(failure) }
            else if state.isCancelled { outcome = .failure(CancellationError()) }
            else { outcome = result }
            let task = state.task, session = state.session
            state.task = nil
            state.session = nil
            state.data = Data()
            lock.unlock()
            // Called only from terminal delegate acknowledgements.
            if case .failure = outcome { task?.cancel(); session?.invalidateAndCancel() }
            else { session?.finishTasksAndInvalidate() }
            onTerminalAcknowledgement()
            continuation.resume(with: outcome)
        }
    }
}

extension MapHTTPClient: Sendable {}
extension MapHTTPClient.Resource: Sendable {}
extension MapHTTPClient.Resource: Equatable {}
extension MapHTTPClient.Response: Sendable {}
extension MapHTTPClient.Transfer: @unchecked Sendable {}

extension MapHTTPClient.Transfer: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse else {
            reject(MapTileLoader.LoadingError.invalidResponse); completionHandler(.cancel); return
        }
        guard response.statusCode == 200 else {
            reject(MapTileLoader.LoadingError.httpStatus(response.statusCode)); completionHandler(.cancel); return
        }
        if let mime = response.mimeType?.lowercased() {
            guard resource.acceptedMIMETypes.contains(mime) else {
                reject(MapTileLoader.LoadingError.unexpectedContentType); completionHandler(.cancel); return
            }
        }
        guard response.expectedContentLength <= Int64(resource.limit) else {
            reject(MapTileLoader.LoadingError.responseTooLarge); completionHandler(.cancel); return
        }
        lock.lock()
        if !state.isCompleted, state.firstFailure == nil {
            state.hasAcceptedResponse = true
            state.headers = response.allHeaderFields.reduce(into: [:]) { values, entry in
                values[String(describing: entry.key).lowercased()] = String(describing: entry.value)
            }
        }
        let isResponseRejected = state.isCompleted || state.firstFailure != nil
        lock.unlock()
        if isResponseRejected { dataTask.cancel(); completionHandler(.cancel) }
        else { completionHandler(.allow) }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !state.isCompleted, state.firstFailure == nil else { lock.unlock(); return }
        let isOverflow = data.count > resource.limit - state.data.count
        if !isOverflow { state.data.append(data) }
        lock.unlock()
        if isOverflow { reject(MapTileLoader.LoadingError.responseTooLarge) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error { finish(.failure(error)); return }
        lock.lock()
        let response = MapHTTPClient.Response(data: state.data, headers: state.headers)
        let hasAcceptedResponse = state.hasAcceptedResponse
        lock.unlock()
        finish(hasAcceptedResponse ? .success(response) : .failure(MapTileLoader.LoadingError.invalidResponse))
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?) {
        finish(.failure(error ?? MapTileLoader.LoadingError.invalidResponse))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        beforeRedirectDecision(task)
        let destination = request.url
        let isDestinationAllowed = destination.map {
            let isSameOrigin = MapHTTPClient.sameOrigin($0, url)
            let hasNoCredentials = $0.user == nil && $0.password == nil
            return isSameOrigin && hasNoCredentials
        } ?? false
        lock.lock()
        // corelibs can deliver a queued redirect callback after cancellation.
        // cancel() independently stops the protocol and acknowledges completion;
        // its pending redirect handler must not re-enter the completed protocol.
        let taskState = task.state
        let hasTerminalTransfer = state.isCancelled || state.firstFailure != nil || state.isCompleted
        let hasTerminalTask = taskState == .canceling || taskState == .completed
        if hasTerminalTransfer || hasTerminalTask {
            #if canImport(FoundationNetworking)
            lock.unlock()
            return
            #else
            completionHandler(nil)
            lock.unlock()
            return
            #endif
        }
        state.redirects += 1
        let isWithinRedirectLimit = state.redirects <= 3
        let isRedirectPermitted = isDestinationAllowed && isWithinRedirectLimit
        if !isRedirectPermitted { state.firstFailure = MapTileLoader.LoadingError.rejectedRedirect }
        // Invoking the handler queues corelibs' redirect decision. Keep that
        // enqueue ordered before external cancellation can record its flag, and
        // before this rejection requests task/session cancellation. Reversing the
        // order makes HTTPURLProtocol's waiting-state guard trap on Linux.
        completionHandler(isRedirectPermitted ? request : nil)
        lock.unlock()
        if !isRedirectPermitted { reject(MapTileLoader.LoadingError.rejectedRedirect) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // System TLS trust remains supported; server credentials are never supplied.
        if challenge.protectionSpace.authenticationMethod == "NSURLAuthenticationMethodServerTrust" {
            completionHandler(.performDefaultHandling, nil)
        } else { completionHandler(.cancelAuthenticationChallenge, nil) }
    }
}
