//
//  ContentView.swift
//  Wakatime for iPadOS
//
//  Created by Milind Contractor on 17/6/25.
//

import SwiftUI



struct ContentView: View {
    @State var selectedProject: String = ""
    @AppStorage("apikey") var apiKey: String = ""
    @AppStorage("wakatime-server") var serverUrl: String = ""
    @State var showHackatimeMacSetupPopup: Bool = false
    @Environment(\.dismiss) var dismiss
    @State var macQuickSetupText: String = ""
    @State var startProcessing: Bool = false
    @State var success: Bool = false
    @State var errorString: String?
    @State var showError: Bool = false
    @State var shoText: [String] = ["", ""]
    
    func performHackaTimeCommand(_ command: String) async throws -> (pingStatusCode: Int, successText: String, api_key: String, api_url: String) {
        let pattern = "export\\s+([A-Z0-9_]+)=\\\"([^\\\"]+)\\\""
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

    
    var commandBasedSetupPopup: some View {
        VStack {
            if !startProcessing {
                VStack {
                    HStack {
                        Image(systemName: "apple.terminal.on.rectangle")
                            .font(.system(size: 36, weight: .regular, design: .monospaced))
                        Text("Hackatime command-based setup")
                            .font(.title)
                            .fontWidth(.expanded)
                            .padding()
                    }
                    
                    Text("Paste your Hackatime setup key you have obtained from hackatime.hackclub.com in the text field below. Ensure the command you have copied is for macOS/Linux setup instructions and not for Windows. You can verify that you have copied the correct one by checking if it matches the formatting of the placeholder below.")
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                    
                    TextField("export HACKATIME_API_KEY=\"some-api-key\" && export HACKATIME_API_URL=\"https://hackatime.hackclub.com/api/hackatime/v1\"", text: $macQuickSetupText)
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                    
                    Button {
                        withAnimation {
                            startProcessing = true
                        }
                    } label: {
                        Label("Done", systemImage: "checkmark.circle")
                            .font(.system(size: 14, weight: .regular, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                    }
                    .buttonStyle(.bordered)
                    
                    if showError {
                        VStack {
                            HStack {
                                Image(systemName: "pc")
                                    .symbolRenderingMode(.multicolor)
                                    .font(.system(size: 104))
                                VStack {
                                    HStack {
                                        Text("Error!")
                                            .font(.system(size: 28, weight: .regular))
                                            .fontWidth(.expanded)
                                        Spacer()
                                    }
                                    HStack {
                                        Text("An error occured while trying to ping the server")
                                            .font(.system(size: 14, weight: .regular, design: .monospaced))
                                        Spacer()
                                    }
                                    if let error = errorString {
                                        HStack {
                                            Text("Error code: \(error)")
                                                .font(.system(size: 14, weight: .regular, design: .monospaced))
                                            Spacer()
                                        }
                                    }
                                }
                            }
                            Button {
                                withAnimation {
                                    showError = false
                                }
                                errorString = nil
                            } label: {
                                Label("Close", systemImage: "xmark.circle.fill")
                            }
                            .buttonStyle(.bordered)
                            .tint(.gray)
                        }
                        .padding()
                        .background(.red.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 10.0))
                        .transition(.push(from: .trailing))
                    }
                }
                .transition(.push(from: .trailing))
            } else {
                    if !success {
                        VStack {
                            ProgressView()
                                .padding()
                                .onAppear {
                                    Task {
                                        let cmd = macQuickSetupText
                                        do {
                                            let result = try await performHackaTimeCommand(cmd)
                                            print("Ping status code:", result.pingStatusCode)
                                            print("Success text:\n", result.successText)
                                            shoText[0] = String(result.pingStatusCode)
                                            shoText[1] = result.successText
                                            success = true
                                            apiKey = result.api_key
                                            serverUrl = result.api_url
                                        } catch {
                                            print("Error:", error)
                                            errorString = "\(error)"
                                            startProcessing = false
                                            showError = true
                                        }
                                    }
                                }
                            Text("Retreiving your API key, please wait...")
                                .font(.system(size: 14, weight: .regular, design: .monospaced))
                        }
                        .transition(.push(from: .trailing))
                    } else {
                        VStack {
                            Text(shoText[0])
                                .font(.system(size: 14, weight: .regular, design: .monospaced))
                            Text(shoText[1])
                                .font(.system(size: 14, weight: .regular, design: .monospaced))
                            Text("Your API key has been set up!")
                                .font(.system(size: 14, weight: .regular, design: .monospaced))
                            Button {
                                success = false
                                startProcessing = false
                                showHackatimeMacSetupPopup = false
                            } label: {
                                Text("Close")
                                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                            }
                            .tint(.gray)
                            .buttonStyle(.bordered)
                        }
                    }
            }
        }
        .padding([.leading, .trailing], 50)
    }
    
    
    
    var body: some View {
        VStack {
            Text("Wakatime for iPadOS")
                .font(.title)
                .fontWidth(.expanded)
                .padding()
                .contextMenu {
                    Button {
                        showHackatimeMacSetupPopup = true
                    } label: {
                        Label("Use Hackatime for macOS command", systemImage: "apple.terminal.on.rectangle")
                    }
                }
            
            TextField("Wakatime API Key", text: $serverUrl)
        }
        .padding()
        .sheet(isPresented: $showHackatimeMacSetupPopup) {
            commandBasedSetupPopup
        }
    }
}

#Preview {
    ContentView()
}
