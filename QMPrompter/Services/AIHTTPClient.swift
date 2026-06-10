import Foundation

enum AIHTTPClient {
    static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        var request = request
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.assumesHTTP3Capable = false

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        configuration.timeoutIntervalForResource = max(request.timeoutInterval, 180)
        configuration.urlCache = nil
        configuration.waitsForConnectivity = true
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        if usesCompatibilityTLS(for: request.url) {
            configuration.tlsMaximumSupportedProtocolVersion = .TLSv12
        }

        let session = URLSession(configuration: configuration)
        defer {
            session.finishTasksAndInvalidate()
        }

        return try await session.data(for: request)
    }

    static func errorMessage(for error: Error, providerTitle: String, url: URL?) -> String {
        let requestURL = url?.absoluteString ?? "未知 URL"

        guard let urlError = error as? URLError else {
            return "\(providerTitle) 网络请求失败：\(error.localizedDescription)\n\(requestURL)"
        }

        var message = "\(providerTitle) 网络请求失败：\(urlError.localizedDescription)\n错误码：\(urlError.code.rawValue)\n\(requestURL)"
        let underlying = (urlError as NSError).userInfo[NSUnderlyingErrorKey] as? NSError

        if let underlying {
            message += "\n底层错误：\(underlying.domain) \(underlying.code) \(underlying.localizedDescription)"
        }

        if urlError.code == .secureConnectionFailed,
           let host = url?.host,
           isAigocodeHost(host) {
            message += "\n请切换手机网络、DNS/VPN，或改用服务器中转地址。"
        }

        return message
    }

    private static func usesCompatibilityTLS(for url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return isAigocodeHost(host)
    }

    private static func isAigocodeHost(_ host: String) -> Bool {
        let normalizedHost = host.lowercased()
        return normalizedHost == "api.aigocode.com" ||
            normalizedHost.hasSuffix(".aigocode.com") ||
            normalizedHost == "api.aigocode.app" ||
            normalizedHost.hasSuffix(".aigocode.app")
    }
}
