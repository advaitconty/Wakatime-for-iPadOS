import Foundation

enum HackaTimeError: Error {
    case missingEnvVars
    case invalidURL(String)
    case noHTTPResponse
    case cannotDecodeSuccessText
}

func performHackaTimeCommand(_ command: String) async throws -> (pingStatusCode: Int, successText: String, api_key: String, api_url: String) {
    let pattern = "export\\s+([A-Z0-9_]+)=\\\"([^\\\"]+)\\\""  // matches export KEY="value"
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
    var request = URLRequest(url: apiURL)
    request.httpMethod = "GET"
    request.setValue(apiKey, forHTTPHeaderField: "Authorization")
    let (_, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
        throw HackaTimeError.noHTTPResponse
    }
    let statusCode = httpResponse.statusCode
    guard let successURL = URL(string: successURLString) else {
        throw HackaTimeError.invalidURL(successURLString)
    }
    let (data, _) = try await URLSession.shared.data(from: successURL)
    guard let successText = String(data: data, encoding: .utf8) else {
        throw HackaTimeError.cannotDecodeSuccessText
    }
    return (pingStatusCode: statusCode, successText: successText, api_key: apiKey, api_url: apiURLString)
}
