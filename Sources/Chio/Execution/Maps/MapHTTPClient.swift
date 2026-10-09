import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Internal bounded transport. The delegate receives decompressed URLSession data;
/// Content-Length is only an early rejection, never the authoritative byte bound.
struct MapHTTPClient {
    enum Resource { case catalog, tile
        var limit: Int { self == .catalog ? 256 * 1_024 : 16 * 1_024 * 1_024 }
    }
    struct Response {
        let data: Data
        let headers: [String: String]
    }
    typealias Transport = @Sendable (URL, Resource) async throws -> Response

    static func fetch(_ url: URL, resource: Resource, timeout: TimeInterval = 20,
                      onTerminalAcknowledgement: @escaping @Sendable () -> Void = {}) async throws -> Response {
        guard timeout.isFinite, timeout > 0, timeout <= 20 else { throw MapTileLoader.LoadingError.invalidResponse }
        let transfer = Transfer(url: url, resource: resource, timeout: timeout,
                                onTerminalAcknowledgement: onTerminalAcknowledgement)
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
            var completed = false
            var cancelled = false
            var data = Data()
            var headers: [String: String] = [:]
            var redirects = 0
            var acceptedResponse = false
            var firstFailure: (any Error)?
        }
        private let lock = NSLock()
        private var state = State()
        let url: URL
        let resource: Resource
        let timeout: TimeInterval
        private let onTerminalAcknowledgement: @Sendable () -> Void

        init(url: URL, resource: Resource, timeout: TimeInterval,
             onTerminalAcknowledgement: @escaping @Sendable () -> Void) {
            self.url = url; self.resource = resource; self.timeout = timeout
            self.onTerminalAcknowledgement = onTerminalAcknowledgement
        }

        func start(_ continuation: CheckedContinuation<Response, any Error>) {
            lock.lock()
            if state.cancelled {
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
            request.setValue(resource == .catalog ? "application/json" : "application/vnd.mapbox-vector-tile, application/x-protobuf, application/octet-stream", forHTTPHeaderField: "Accept")
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
            state.cancelled = true
            lock.unlock()
            reject(CancellationError())
        }

        /// Rejection stops the real resource, but cannot release admission yet.
        /// The terminal delegate acknowledgement owns continuation completion.
        private func reject(_ error: any Error) {
            lock.lock()
            guard !state.completed else { lock.unlock(); return }
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
            guard !state.completed, let continuation = state.continuation else { lock.unlock(); return }
            state.completed = true
            state.continuation = nil
            let outcome: Result<Response, any Error>
            if let failure = state.firstFailure { outcome = .failure(failure) }
            else if state.cancelled { outcome = .failure(CancellationError()) }
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
            let allowed = resource == .catalog
                ? ["application/json", "text/json"]
                : ["application/vnd.mapbox-vector-tile", "application/x-protobuf", "application/protobuf", "application/octet-stream"]
            guard allowed.contains(mime) else {
                reject(MapTileLoader.LoadingError.unexpectedContentType); completionHandler(.cancel); return
            }
        }
        guard response.expectedContentLength <= Int64(resource.limit) else {
            reject(MapTileLoader.LoadingError.responseTooLarge); completionHandler(.cancel); return
        }
        lock.lock()
        if !state.completed, state.firstFailure == nil {
            state.acceptedResponse = true
            state.headers = response.allHeaderFields.reduce(into: [:]) { values, entry in
                values[String(describing: entry.key).lowercased()] = String(describing: entry.value)
            }
        }
        let completed = state.completed || state.firstFailure != nil
        lock.unlock()
        if completed { dataTask.cancel(); completionHandler(.cancel) }
        else { completionHandler(.allow) }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !state.completed, state.firstFailure == nil else { lock.unlock(); return }
        let overflow = data.count > resource.limit - state.data.count
        if !overflow { state.data.append(data) }
        lock.unlock()
        if overflow { reject(MapTileLoader.LoadingError.responseTooLarge) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error { finish(.failure(error)); return }
        lock.lock()
        let response = MapHTTPClient.Response(data: state.data, headers: state.headers)
        let accepted = state.acceptedResponse
        lock.unlock()
        finish(accepted ? .success(response) : .failure(MapTileLoader.LoadingError.invalidResponse))
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?) {
        finish(.failure(error ?? MapTileLoader.LoadingError.invalidResponse))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        let destination = request.url
        let allowed = destination.map { MapHTTPClient.sameOrigin($0, url) && $0.user == nil && $0.password == nil } ?? false
        lock.lock()
        state.redirects += 1
        let permitted = allowed && state.redirects <= 3 && !state.completed && state.firstFailure == nil
        lock.unlock()
        guard permitted else {
            reject(MapTileLoader.LoadingError.rejectedRedirect); completionHandler(nil); return
        }
        completionHandler(request)
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
