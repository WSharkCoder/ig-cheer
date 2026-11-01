import Foundation

enum PredictionClientError: LocalizedError {
    case invalidEndpoint
    case noSchedule
    case badResponse(String)
    case http(Int, String)
    case malformedJSON
    case noPredictions
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "模型 Base URL 无效，请在「模型配置」中检查。"
        case .noSchedule:
            return "暂无可预测的 IG 赛程。"
        case .badResponse(let message):
            return "模型返回内容无法解析：\(message)。请检查 API 格式与 Base URL。"
        case .http(let status, let body):
            if status == 404 && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "模型接口路径不存在（HTTP 404）。请检查 API 格式与 Base URL；DeepSeek 的 Anthropic 格式应使用 https://api.deepseek.com/anthropic。"
            }
            return "模型接口返回 HTTP \(status)：\(body)"
        case .malformedJSON:
            return "模型没有返回有效的 JSON（可能被 max_tokens 截断，或模型返回了说明文字）。"
        case .noPredictions:
            return "模型没有返回可用的比分预测。"
        case .transport(let message):
            return "无法连接模型接口：\(message)"
        }
    }
}

enum PredictionClient {
    static func fetch(model: ModelConfig,
                      apiKey: String?,
                      matches: [ScheduleMatch],
                      completion: @escaping (Result<[ScorePrediction], Error>) -> Void) {
        guard !matches.isEmpty else {
            completion(.failure(PredictionClientError.noSchedule))
            return
        }
        guard let endpoint = model.endpoint else {
            completion(.failure(PredictionClientError.invalidEndpoint))
            return
        }

        let prompt = makePrompt(for: matches)
        var body: [String: Any] = [
            "model": model.model,
            "temperature": 0.2,
            // The expected answer is one short JSON object. Keeping this
            // bounded prevents a chatty model from spending tokens on prose.
            "max_tokens": 256
        ]
        // DeepSeek V4 enables thinking by default; its reasoning can consume
        // the entire small output budget before the JSON arrives. This is a
        // structured extraction, so use non-thinking mode.
        if isDeepSeek(model) {
            body["thinking"] = ["type": "disabled"]
        }

        switch model.apiFormat {
        case .openai:
            body["messages"] = [
                ["role": "system", "content": prompt.system],
                ["role": "user", "content": prompt.user]
            ]
        case .anthropic:
            // Anthropic Messages takes the system prompt as a top-level
            // field and requires max_tokens.
            body["system"] = prompt.system
            body["messages"] = [
                ["role": "user", "content": prompt.user]
            ]
        }

        guard let payload = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(PredictionClientError.malformedJSON))
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&request, model: model, apiKey: apiKey)
        request.httpBody = payload

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 45
        let session = URLSession(configuration: configuration)
        session.dataTask(with: request) { data, response, error in
            defer { session.finishTasksAndInvalidate() }
            if let error {
                DispatchQueue.main.async {
                    completion(.failure(PredictionClientError.transport(error.localizedDescription)))
                }
                return
            }
            guard let http = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    completion(.failure(PredictionClientError.badResponse("空响应")))
                }
                return
            }
            guard let data, !data.isEmpty else {
                DispatchQueue.main.async {
                    completion(.failure(PredictionClientError.badResponse("接口没有返回内容")))
                }
                return
            }
            if !(200...299).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    completion(.failure(PredictionClientError.http(http.statusCode,
                                                                  String(body.prefix(320)))))
                }
                return
            }
            do {
                let predictions = try parsePredictions(data: data,
                                                       format: model.apiFormat,
                                                       knownMatches: matches)
                DispatchQueue.main.async {
                    completion(.success(predictions))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    private static func makePrompt(for matches: [ScheduleMatch]) -> (system: String, user: String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "MM-dd"

        // Indexes replace long provider match ids, saving input and output
        // tokens and preventing a model from echoing a truncated UUID.
        let lines = matches.enumerated().map { index, match -> String in
            let opponent = match.opponent?.code ?? "TBD"
            let bestOf = [1, 3, 5].contains(match.bestOf) ? match.bestOf : 3
            let date = match.startDate.map { formatter.string(from: $0) } ?? "--"
            return "\(index)|\(opponent)|BO\(bestOf)|\(date)"
        }.joined(separator: "\n")

        let system = """
        Predict the LoL series score for IG. Input lines: index|opponent|BO|date. BO is 1, 3, or 5.
        Reply with JSON only: {"p":[{"m":0,"s":"3-1","c":64}]}
        s = IG score-opponent score, valid for the BO: winner reaches 1/2/3 wins for BO1/3/5.
        c = IG win probability 0-100. No markdown, no explanation.
        """
        return (system, "IG matches:\n\(lines)")
    }

    private static func isDeepSeek(_ model: ModelConfig) -> Bool {
        URL(string: model.baseURL)?.host?.lowercased() == "api.deepseek.com"
    }

    private static func authorize(_ request: inout URLRequest,
                                  model: ModelConfig,
                                  apiKey: String?) {
        guard let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else { return }
        switch model.apiFormat {
        case .openai:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
    }

    private static func parsePredictions(data: Data,
                                         format: ModelAPIFormat,
                                         knownMatches: [ScheduleMatch]) throws -> [ScorePrediction] {
        let content = try responseText(data: data, format: format)
        let cleaned = stripCodeFence(content)
        guard let open = cleaned.firstIndex(of: "{"),
              let close = cleaned.lastIndex(of: "}") else {
            throw PredictionClientError.malformedJSON
        }
        let jsonText = String(cleaned[open...close])
        guard let jsonData = jsonText.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw PredictionClientError.malformedJSON
        }

        let rows = (payload["p"] as? [[String: Any]])
            ?? (payload["predictions"] as? [[String: Any]])
            ?? []
        let predictions: [ScorePrediction] = rows.compactMap { row in
            let match: ScheduleMatch?
            if let index = intValue(row["m"]), index >= 0, index < knownMatches.count {
                match = knownMatches[index]
            } else if let matchID = (row["matchId"] as? String) ?? (row["matchID"] as? String) {
                match = knownMatches.first(where: { $0.id == matchID })
            } else {
                match = nil
            }
            guard let match else { return nil }

            let compactScore = parseScore(row["s"])
            let igScore = compactScore?.0
                ?? intValue(row["igScore"])
                ?? intValue(row["ig_score"])
                ?? 0
            let opponentScore = compactScore?.1
                ?? intValue(row["opponentScore"])
                ?? intValue(row["opponent_score"])
                ?? 0
            let confidence = min(100, max(0,
                intValue(row["c"]) ?? intValue(row["confidence"]) ?? 50))
            guard (0...5).contains(igScore), (0...5).contains(opponentScore),
                  igScore != opponentScore else { return nil }
            let prediction = ScorePrediction(matchID: match.id,
                                             igScore: igScore,
                                             opponentScore: opponentScore,
                                             confidence: confidence)
            guard prediction.isValid(for: match.bestOf) else { return nil }
            return prediction
        }
        guard !predictions.isEmpty else { throw PredictionClientError.noPredictions }
        return predictions
    }

    private static func responseText(data: Data, format: ModelAPIFormat) throws -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PredictionClientError.malformedJSON
        }

        if format == .openai,
           let choices = object["choices"] as? [[String: Any]],
           let first = choices.first,
           let message = first["message"] as? [String: Any],
           let content = text(from: message["content"]) {
            return content
        }
        if format == .anthropic, let content = text(from: object["content"]) {
            return content
        }

        // Some compatible gateways use the other shape; accept either one
        // rather than failing solely because of a format label mismatch.
        if let choices = object["choices"] as? [[String: Any]],
           let first = choices.first,
           let message = first["message"] as? [String: Any],
           let content = text(from: message["content"]) {
            return content
        }
        if let content = text(from: object["content"]) {
            return content
        }
        throw PredictionClientError.badResponse("缺少响应正文")
    }

    private static func text(from value: Any?) -> String? {
        if let string = value as? String { return string }
        if let blocks = value as? [[String: Any]] {
            let parts = blocks.compactMap { $0["text"] as? String }
            return parts.isEmpty ? nil : parts.joined(separator: "\n")
        }
        if let block = value as? [String: Any], let text = block["text"] as? String {
            return text
        }
        return nil
    }

    private static func parseScore(_ value: Any?) -> (Int, Int)? {
        if let string = value as? String {
            let parts = string.split(whereSeparator: { $0 == "-" || $0 == ":" })
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count == 2 { return (parts[0], parts[1]) }
        }
        if let array = value as? [Any], array.count == 2,
           let left = intValue(array[0]), let right = intValue(array[1]) {
            return (left, right)
        }
        if let object = value as? [String: Any],
           let left = intValue(object["ig"]), let right = intValue(object["opponent"]) {
            return (left, right)
        }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func stripCodeFence(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("```") {
            if let firstNewline = value.firstIndex(of: "\n") {
                value = String(value[value.index(after: firstNewline)...])
            }
            if value.hasSuffix("```") {
                value = String(value.dropLast(3))
            }
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
