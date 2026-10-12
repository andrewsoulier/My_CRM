import Foundation

public enum APIClientError: Error, LocalizedError {
    case notConfigured
    case invalidResponse
    case httpStatus(Int, String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Set the Mac CRM base URL and API token in Settings."
        case .invalidResponse:
            return "Invalid response from CRM server."
        case .httpStatus(let code, let body):
            return "CRM server error \(code): \(body)"
        }
    }
}

public struct APIClient: Sendable {
    public init() {}

    public func uploadLocation(_ sample: LocationSamplePayload) async throws -> LocationUploadResponse {
        try await post(path: "/api/location", body: sample)
    }

    public func fetchMessages(limit: Int = 50) async throws -> [CRMMessage] {
        struct Envelope: Codable { var messages: [CRMMessage] }
        let envelope: Envelope = try await get(path: "/api/messages?limit=\(limit)")
        return envelope.messages
    }

    public func health() async throws -> Bool {
        struct Health: Codable { var ok: Bool }
        let result: Health = try await get(path: "/health", authorized: false)
        return result.ok
    }

    private func get<T: Decodable>(path: String, authorized: Bool = true) async throws -> T {
        var request = try makeRequest(path: path, method: "GET", authorized: authorized)
        return try await send(request)
    }

    private func post<Body: Encodable, T: Decodable>(path: String, body: Body) async throws -> T {
        var request = try makeRequest(path: path, method: "POST", authorized: true)
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await send(request)
    }

    private func makeRequest(path: String, method: String, authorized: Bool) throws -> URLRequest {
        guard let base = AppConfig.baseURL else { throw APIClientError.notConfigured }
        guard let url = URL(string: path, relativeTo: base)?.absoluteURL else {
            throw APIClientError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if authorized {
            guard let token = AppConfig.apiToken, !token.isEmpty else {
                throw APIClientError.notConfigured
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIClientError.httpStatus(http.statusCode, body)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
