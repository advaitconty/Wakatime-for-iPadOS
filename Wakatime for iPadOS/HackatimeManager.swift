import Foundation

enum HackaTimeError: Error {
    case missingEnvVars
    case invalidURL(String)
    case noHTTPResponse
    case cannotDecodeSuccessText
}

struct Heartbeat: Codable {
    let type: String
    let time: Double
    let entity: String
    let language: String
}

enum WakaTimeError: Error, LocalizedError {
    case invalidURL(String)
    case jsonEncodingFailed(Error)
    case networkError(Error)
    case invalidResponse
    case apiError(statusCode: Int, responseBody: String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let urlString): return "The API URL '\(urlString)' is invalid."
        case .jsonEncodingFailed(let error): return "Failed to encode heartbeat data: \(error.localizedDescription)"
        case .networkError(let error): return "Network connection error: \(error.localizedDescription)"
        case .invalidResponse: return "The server returned an invalid response."
        case .apiError(let statusCode, let body):
            return "WakaTime API returned an error (Status: \(statusCode)): \(body ?? "No response body")"
        }
    }
}

func performHackaTimeCommand(_ command: String) async throws -> (pingStatusCode: Int, successText: String, api_key: String, api_url: String) {
    let pattern = "export\\s+([A-Z0-9_]+)=\\\"([^\\\"]+)\\\""  // hey you should know this is AI cus no one in the world actually knows regex
    let regex = try NSRegularExpression(pattern: pattern)
    let nsrange = NSRange(command.startIndex..<command.endIndex, in: command)
    var env: [String: String] = [:]
    regex.enumerateMatches(in: command, options: [], range: nsrange) { match, _, _ in
        guard
            let match = match,
            match.numberOfRanges == 3,
            let keyRange = Range(match.range(at: 1), in: command),
            let valueRange = Range(match.range(at: 2), in: command)
        else { return }
        let key = String(command[keyRange])
        let value = String(command[valueRange])
        env[key] = value
    }
    
    guard
        let apiKey = env["HACKATIME_API_KEY"],
        let apiURLString = env["HACKATIME_API_URL"],
        let successURLString = env["SUCCESS_URL"]
    else {
        throw HackaTimeError.missingEnvVars
    }
    
    guard let apiURL = URL(string: apiURLString) else {
        throw HackaTimeError.invalidURL(apiURLString)
    }
    
    let result = try await sendWakaTimeHeartbeat(apiKey: apiKey, apiURLString: apiURLString)
    
    let statusCode: Int
    if let statusRange = result.message.range(of: "Status: ") {
        let afterStatus = result.message[statusRange.upperBound...]
        if let endRange = afterStatus.range(of: ")") {
            let statusString = String(afterStatus[..<endRange.lowerBound])
            statusCode = Int(statusString) ?? 200
        } else {
            statusCode = 200
        }
    } else {
        statusCode = result.success ? 200 : 400
    }
    
    return (pingStatusCode: statusCode, successText: result.message, api_key: apiKey, api_url: apiURLString)
}

func sendWakaTimeHeartbeat(apiKey: String, apiURLString: String) async throws -> (success: Bool, message: String) {
    let fullAPIURLString = apiURLString.hasSuffix("/") ?
        apiURLString + "users/current/heartbeats" :
        apiURLString + "/users/current/heartbeats"
    
    guard let apiURL = URL(string: fullAPIURLString) else {
        throw WakaTimeError.invalidURL(fullAPIURLString)
    }

    let currentUnixTime = Date().timeIntervalSince1970
    let heartbeat = Heartbeat(type: "file", time: currentUnixTime, entity: "test.txt", language: "Text")
    let heartbeats = [heartbeat]

    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys

    guard let jsonData = try? encoder.encode(heartbeats) else {
        throw WakaTimeError.jsonEncodingFailed(NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to encode JSON"]))
    }

    var request = URLRequest(url: apiURL)
    request.httpMethod = "POST"
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")

    request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

    request.httpBody = jsonData

    do {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WakaTimeError.invalidResponse
        }

        let statusCode = httpResponse.statusCode
        let responseBody = String(data: data, encoding: .utf8) ?? ""

        if statusCode == 200 || statusCode == 201 || statusCode == 202 {
            return (true, "Heartbeat sent successfully (Status: \(statusCode)). Response: \(responseBody)")
        } else {
            throw WakaTimeError.apiError(statusCode: statusCode, responseBody: responseBody)
        }
    } catch let urlError as URLError {
        throw WakaTimeError.networkError(urlError)
    } catch {
        throw WakaTimeError.networkError(error)
    }
}
