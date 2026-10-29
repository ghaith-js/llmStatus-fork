import Foundation
import Security

/// Checks a website: HTTP status, response time, optional keyword, TLS certificate expiry.
/// A failure is checked again once a few seconds later, so a single dropped request does not alert.
enum WebsiteChecker {
    /// No cache and no cookies: every check hits the server.
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    static func check(_ site: WebsiteMonitor) async -> CheckResult {
        let first = await attempt(site)
        guard first.status.severity >= 3 else { return first }
        try? await Task.sleep(for: .seconds(3))
        return await attempt(site)
    }

    private static func attempt(_ site: WebsiteMonitor) async -> CheckResult {
        guard let url = site.parsedURL else {
            return CheckResult(status: .critical, summary: "Invalid URL", items: [CheckItem(name: "URL", status: .critical, value: "Invalid")])
        }
        var request = URLRequest(url: url)
        request.setValue("LLMStatus-Monitor/1.0", forHTTPHeaderField: "User-Agent")
        let recorder = TLSRecorder()
        let start = Date()
        do {
            let (data, response) = try await session.data(for: request, delegate: recorder)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            return evaluate(code: code, ms: ms, body: data, certificateExpiry: recorder.expiry, site: site)
        } catch {
            return failure(error)
        }
    }

    static func evaluate(code: Int, ms: Int, body: Data, certificateExpiry: Date?, site: WebsiteMonitor,
                         now: Date = Date()) -> CheckResult {
        var items: [CheckItem] = []
        let httpStatus: ServiceStatus = code >= 500 || code == 0 ? .critical : code >= 400 ? .majorOutage : .operational
        items.append(CheckItem(name: "HTTP", status: httpStatus, value: "\(code)"))
        items.append(CheckItem(name: "Response time", status: ms > site.slowMs ? .degraded : .operational, value: "\(ms) ms"))

        let keyword = site.keyword.trimmingCharacters(in: .whitespaces)
        if !keyword.isEmpty {
            let page = String(decoding: body, as: UTF8.self)
            let found = page.localizedCaseInsensitiveContains(keyword)
            items.append(CheckItem(name: "Keyword", status: found ? .operational : .majorOutage,
                                   value: found ? "Found" : "\"\(keyword)\" missing"))
        }

        if let expiry = certificateExpiry {
            let days = Int(floor(expiry.timeIntervalSince(now) / 86400))
            let status: ServiceStatus = days < 0 ? .critical : days < 7 ? .majorOutage : days < 14 ? .degraded : .operational
            items.append(CheckItem(name: "Certificate", status: status,
                                   value: days < 0 ? "Expired" : "Expires in \(days) d"))
        }
        return CheckResult(status: CheckResult.worst(items), summary: "\(code) · \(ms) ms", items: items)
    }

    /// Without a connection on this Mac, nothing is known about the site: unknown, not down.
    static func failure(_ error: Error) -> CheckResult {
        let code = (error as? URLError)?.code
        let offline: Set<URLError.Code> = [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed]
        if let code, offline.contains(code) {
            return CheckResult(status: .unknown, summary: "No connection on this Mac")
        }
        let reason: String
        switch code {
        case .timedOut: reason = "Timed out"
        case .cannotFindHost, .dnsLookupFailed: reason = "Host not found (DNS)"
        case .cannotConnectToHost: reason = "Connection refused"
        case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid, .secureConnectionFailed:
            reason = "TLS certificate invalid"
        default: reason = error.localizedDescription
        }
        return CheckResult(status: .critical, summary: reason, items: [CheckItem(name: "Connection", status: .critical, value: reason)])
    }
}

/// Reads the leaf certificate's expiry while letting the system validate the chain as usual.
private final class TLSRecorder: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private(set) var expiry: Date?

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust,
           let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first {
            expiry = Self.notAfter(leaf)
        }
        return (.performDefaultHandling, nil)
    }

    private static func notAfter(_ certificate: SecCertificate) -> Date? {
        let key = kSecOIDX509V1ValidityNotAfter
        guard let values = SecCertificateCopyValues(certificate, [key] as CFArray, nil) as? [CFString: Any],
              let entry = values[key] as? [CFString: Any],
              let seconds = (entry[kSecPropertyKeyValue] as? NSNumber)?.doubleValue else { return nil }
        return Date(timeIntervalSinceReferenceDate: seconds)
    }
}
