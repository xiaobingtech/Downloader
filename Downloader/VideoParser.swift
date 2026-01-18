//
//  VideoParser.swift
//  Downloader
//
//  Created by fandong on 2026/1/18.
//

import Foundation

enum VideoParseError: Error {
    case invalidURL
    case networkError(Error)
    case noData
    case parseError
    case videoNotFound
}

struct VideoParser {
    static let shared = VideoParser()
    
    private let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1"
    
    /// Extract the first URL from a text string
    func extractURL(from text: String) -> URL? {
        // Simple regex to find http/https links
        // Stops at whitespace or end of string
        let pattern = "https?://[-a-zA-Z0-9+&@#/%?=~_|!:,.;]*[-a-zA-Z0-9+&@#/%=~_|]"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }
        
        if let urlRange = Range(match.range, in: text) {
            let urlString = String(text[urlRange])
            return URL(string: urlString)
        }
        
        return nil
    }
    
    /// Parse a generic URL, delegating to specific parsers if matched
    func parse(url: URL) async throws -> URL {
        if let host = url.host, host.contains("douyin.com") {
            return try await parseDouyin(url: url)
        }
        // Default: return the original URL (assume it's a direct link if not matched)
        return url
    }
    
    /// Parse Douyin URL to get the direct video link
    func parseDouyin(url: URL) async throws -> URL {
        // 1. Resolve redirect to get the full URL and ID
        let resolvedURL: URL
        if url.host?.contains("v.douyin.com") == true {
             resolvedURL = try await resolveRedirect(url: url)
        } else {
             resolvedURL = url
        }
        
        // 2. Fetch HTML content
        let html = try await fetchHTML(url: resolvedURL)
        
        // 3. Extract JSON data from window._ROUTER_DATA
        guard let jsonData = extractRouterData(from: html) else {
            throw VideoParseError.parseError
        }
        
        // 4. Parse JSON to find video URI
        guard let videoURI = extractVideoURI(from: jsonData) else {
            throw VideoParseError.videoNotFound
        }
        
        // 5. Construct final URL
        // http://www.iesdouyin.com/aweme/v1/play/?video_id={videoId}&ratio=1080p&line=0
        var components = URLComponents()
        components.scheme = "http"
        components.host = "www.iesdouyin.com"
        components.path = "/aweme/v1/play/"
        components.queryItems = [
            URLQueryItem(name: "video_id", value: videoURI),
            URLQueryItem(name: "ratio", value: "1080p"),
            URLQueryItem(name: "line", value: "0")
        ]
        
        guard let finalURL = components.url else {
            throw VideoParseError.parseError
        }
        
        return finalURL
    }
    
    // MARK: - Private Helpers
    
    private func resolveRedirect(url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        
        return try await withCheckedThrowingContinuation { continuation in
            let session = URLSession(configuration: .default)
            let task = session.dataTask(with: request) { _, response, error in
                if let error = error {
                    continuation.resume(throwing: VideoParseError.networkError(error))
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse,
                   let finalURL = httpResponse.url {
                    continuation.resume(returning: finalURL)
                } else {
                    continuation.resume(returning: url)
                }
            }
            task.resume()
        }
    }
    
    private func fetchHTML(url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw VideoParseError.noData
        }
        return html
    }
    
    private func extractRouterData(from html: String) -> Any? {
        // pattern: window._ROUTER_DATA\s*=\s*(.*?)\<\/script>
        // Note: In Swift string literals, backslashes must be escaped.
        // We need `\s` in regex, so we write `\\s` in string.
        // `<` and `/` do not need escaping in Swift strings, but `/` handles closing script tag.
        let pattern = "window\\._ROUTER_DATA\\s*=\\s*(.*?)\\<\\/script>"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range) else {
            return nil
        }
        
        if let jsonRange = Range(match.range(at: 1), in: html) {
            let jsonString = String(html[jsonRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let data = jsonString.data(using: String.Encoding.utf8) {
                return try? JSONSerialization.jsonObject(with: data, options: [])
            }
        }
        
        return nil
    }
    
    private func extractVideoURI(from json: Any) -> String? {
        // Path: loaderData -> video_(id)/page -> videoInfoRes -> item_list -> [0] -> video -> play_addr -> uri
        
        guard let dict = json as? [String: Any],
              let loaderData = dict["loaderData"] as? [String: Any] else {
            return nil
        }
        
        // Find the key that starts with "video_" and ends with "/page"
        // Or simply iterate to find the structure
        
        for (_, value) in loaderData {
             if let pageData = value as? [String: Any],
                let videoInfoRes = pageData["videoInfoRes"] as? [String: Any],
                let itemList = videoInfoRes["item_list"] as? [[String: Any]],
                let firstItem = itemList.first,
                let video = firstItem["video"] as? [String: Any],
                let playAddr = video["play_addr"] as? [String: Any],
                let uri = playAddr["uri"] as? String {
                 return uri
             }
        }
        
        return nil
    }
}
