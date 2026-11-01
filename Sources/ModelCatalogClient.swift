import Foundation

struct RemoteModel: Equatable {
    var id: String
    var displayName: String?
}

struct ModelConnectionProbe {
    var modelCount: Int
    var elapsed: TimeInterval
}

enum ModelCatalogError: LocalizedError {
    case invalidEndpoint
    case http(Int, String)
    case malformedJSON
    case empty
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Base URL 无效，请检查模型配置。"
        case .http(let status, let body):
            return "模型列表接口返回 HTTP \(status)：\(body)"
        case .malformedJSON:
            return "模型列表接口返回了无法解析的 JSON。"
        case .empty:
            return "接口没有返回任何模型。"
        case .transport(let message):
            return "无法连接模型列表接口：\(message)"
        }
    }
}

/// Fetches the provider's model catalog through GET /models.
/// This is intentionally a separate client from PredictionClient:
/// listing models and asking for a prediction can use different formats.
enum ModelCatalogClient {
    static func fetch(model: ModelConfig,
                      apiKey: String?,
                      completion: @escaping (Result<[RemoteModel], Error>) -> Void) {
        guard let endpoint = model.modelsEndpoint else {
            completion(.failure(ModelCatalogError.invalidEndpoint))
            return
        }

        var url = endpoint
        if model.apiFormat == .anthropic,
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           components.queryItems == nil {
            components.queryItems = [URLQueryItem(name: "limit", value: "100")]
            url = components.url ?? url
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            if model.apiFormat == .anthropic {
                request.setValue(key, forHTTPHeaderField: "x-api-key")
            } else {
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
        }
        if model.apiFormat == .anthropic {
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration)
        session.dataTask(with: request) { data, response, error in
            defer { session.finishTasksAndInvalidate() }
            if let error {
                DispatchQueue.main.async {
                    completion(.failure(ModelCatalogError.transport(error.localizedDescription)))
                }
                return
            }
            guard let http = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    completion(.failure(ModelCatalogError.transport("空响应")))
                }
                return
            }
            guard let data, !data.isEmpty else {
                DispatchQueue.main.async {
                    completion(.failure(ModelCatalogError.transport("接口没有返回内容")))
                }
                return
            }
            if !(200...299).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    completion(.failure(ModelCatalogError.http(http.statusCode,
                                                              String(body.prefix(320)))))
                }
                return
            }
            do {
                let models = try parseModels(data: data)
                DispatchQueue.main.async {
                    completion(.success(models))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Connectivity/auth check with no inference and therefore no token
    /// consumption. It only performs GET /models, which is a metadata call.
    static func testConnection(model: ModelConfig,
                               apiKey: String?,
                               completion: @escaping (Result<ModelConnectionProbe, Error>) -> Void) {
        let started = Date()
        fetch(model: model, apiKey: apiKey) { result in
            switch result {
            case .success(let models):
                completion(.success(ModelConnectionProbe(modelCount: models.count,
                                                         elapsed: Date().timeIntervalSince(started))))
            case .failure(let error):
                // A 200 response with no model list is still a successful
                // connectivity check; only auth/transport failures matter.
                if let catalogError = error as? ModelCatalogError,
                   case .empty = catalogError {
                    completion(.success(ModelConnectionProbe(modelCount: 0,
                                                             elapsed: Date().timeIntervalSince(started))))
                    return
                }
                completion(.failure(error))
            }
        }
    }

    static func suggestions(for model: ModelConfig) -> [String] {
        if model.apiFormat == .anthropic {
            return ["claude-sonnet-4-5", "claude-opus-4-1", "claude-haiku-4-5"]
        }

        let host = URL(string: model.baseURL)?.host?.lowercased() ?? ""
        if host == "localhost" || host == "127.0.0.1" || host == "::1" {
            // Generic Ollama / LM Studio examples. The user can replace the
            // model id with anything their local server reports.
            return ["qwen2.5:7b", "llama3.2:3b", "deepseek-r1:7b"]
        }
        if host.contains("deepseek") {
            return ["deepseek-chat", "deepseek-reasoner"]
        }
        if host.contains("openrouter") {
            return ["openai/gpt-4o-mini", "anthropic/claude-sonnet-4-5", "google/gemini-2.0-flash"]
        }
        return ["gpt-4o-mini", "gpt-4o", "o3-mini"]
    }

    private static func parseModels(data: Data) throws -> [RemoteModel] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ModelCatalogError.malformedJSON
        }
        let rows = (object["data"] as? [[String: Any]])
            ?? (object["models"] as? [[String: Any]])
            ?? []
        var seen = Set<String>()
        var models: [RemoteModel] = []
        for row in rows {
            let id = (row["id"] as? String)
                ?? (row["name"] as? String)
                ?? (row["model"] as? String)
            guard let id else { continue }
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            let display = (row["display_name"] as? String) ?? (row["displayName"] as? String)
            models.append(RemoteModel(id: trimmed, displayName: display))
        }
        guard !models.isEmpty else { throw ModelCatalogError.empty }
        return models.sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }
}
