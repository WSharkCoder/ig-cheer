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
            return "模型返回内容无法解析：\(message)"
        case .http(let status, let body):
            return "模型接口返回 HTTP \(status)：\(body)"
        case .malformedJSON:
            return "模型没有返回有效的 JSON。"
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

        let matchLines = matches.map { match -> String in
            let opponent = match.opponent?.code ?? "TBD"
            let stage = DisplayFormat.stage(match.stage)
            let bestOf = match.bestOf > 0 ? "BO\(match.bestOf)" : "BO3"
            return "- matchId=\(match.id) | IG vs \(opponent) | \(stage) | \(bestOf) | \(match.startTime)"
        }.joined(separator: "\n")

        let system = """
        你是英雄联盟（LoL）赛前分析模型。请只基于给定赛程，给出 Invictus Gaming（IG）每场比赛的比分预测。
        要求：
        1. IG 的比分在前，对手比分在后，必须符合 BO 赛制的获胜条件。
        2. confidence 是 IG 获胜概率，0-100 的整数。
        3. 只输出一个 JSON 对象，不要 Markdown，不要解释。
        JSON 结构：{"predictions":[{"matchId":"原样返回","igScore":2,"opponentScore":1,"confidence":64}]}
        """
        let user = """
        请预测以下 IG 比赛：
        \(matchLines)
        """

        let body: [String: Any] = [
            "model": model.model,
            "temperature": 0.3,
            "max_tokens": 900,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]
        ]
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(PredictionClientError.malformedJSON))
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
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
                let predictions = try parsePredictions(data: data, knownMatches: matches)
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

    private static func parsePredictions(data: Data,
                                         knownMatches: [ScheduleMatch]) throws -> [ScorePrediction] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw PredictionClientError.badResponse("缺少 choices[0].message.content")
        }

        let cleaned = stripCodeFence(content)
        guard let open = cleaned.firstIndex(of: "{"),
              let close = cleaned.lastIndex(of: "}") else {
            throw PredictionClientError.malformedJSON
        }
        let jsonText = String(cleaned[open...close])
        guard let jsonData = jsonText.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let rows = payload["predictions"] as? [[String: Any]] else {
            throw PredictionClientError.malformedJSON
        }

        let knownIDs = Set(knownMatches.map(\.id))
        let predictions: [ScorePrediction] = rows.compactMap { row in
            guard let matchID = (row["matchId"] as? String) ?? (row["matchID"] as? String),
                  knownIDs.contains(matchID) else { return nil }
            let igScore = intValue(row["igScore"]) ?? intValue(row["ig_score"]) ?? 0
            let opponentScore = intValue(row["opponentScore"]) ?? intValue(row["opponent_score"]) ?? 0
            let confidence = min(100, max(0, intValue(row["confidence"]) ?? 50))
            guard (0...5).contains(igScore), (0...5).contains(opponentScore),
                  igScore != opponentScore else { return nil }
            return ScorePrediction(matchID: matchID,
                                   igScore: igScore,
                                   opponentScore: opponentScore,
                                   confidence: confidence)
        }
        guard !predictions.isEmpty else { throw PredictionClientError.noPredictions }
        return predictions
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
