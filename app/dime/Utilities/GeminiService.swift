//
//  GeminiService.swift
//  dime
//

import Foundation
import UIKit

// MARK: - Receipt Scan Result

struct ReceiptScanResult: Codable {
    let amount: Double?
    let merchant: String?
    let date: String?
    let category: String?
    let isIncome: Bool?
}

// MARK: - Gemini API Response Models

struct GeminiResponse: Codable {
    let candidates: [GeminiCandidate]?
}

struct GeminiCandidate: Codable {
    let content: GeminiContent?
}

struct GeminiContent: Codable {
    let parts: [GeminiPart]?
}

struct GeminiPart: Codable {
    let text: String?
}

// MARK: - Error Types

enum GeminiError: LocalizedError {
    case imageConversionFailed
    case missingAPIKey
    case invalidURL
    case requestFailed(Int)
    case noContent
    case parsingFailed

    var errorDescription: String? {
        switch self {
        case .imageConversionFailed: return "Could not process the image"
        case .missingAPIKey: return "Gemini API key not set"
        case .invalidURL: return "Invalid API URL"
        case .requestFailed(let code): return "API request failed (\(code))"
        case .noContent: return "No content in response"
        case .parsingFailed: return "Could not parse receipt data"
        }
    }
}

// MARK: - Gemini Service

class GeminiService {
    static func scanReceipt(image: UIImage) async throws -> ReceiptScanResult {
        // Downscale large images to reduce payload
        let processedImage = resizeImageIfNeeded(image, maxDimension: 1024)

        guard let imageData = processedImage.jpegData(compressionQuality: 0.7) else {
            throw GeminiError.imageConversionFailed
        }
        let base64String = imageData.base64EncodedString()

        let apiKey = Constants.geminiAPIKey
        guard !apiKey.isEmpty, apiKey != "YOUR_GEMINI_API_KEY_HERE" else {
            throw GeminiError.missingAPIKey
        }

        let urlString =
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
        guard let url = URL(string: urlString) else {
            throw GeminiError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let prompt = """
            Analyze this receipt/bill image and extract the following information.
            Return a JSON object with these fields:
            - "amount": the total amount as a number (just the number, no currency symbol)
            - "merchant": the store/merchant name as a string
            - "date": the transaction date in "yyyy-MM-dd" format, or null if not visible
            - "category": suggest one category from: Food, Transport, Groceries, Shopping, Entertainment, Healthcare, Utilities, Subscriptions, Rent, Education, or Other
            - "isIncome": false for expenses, true for income (most receipts are expenses)

            If you cannot determine a field, set it to null.
            Return ONLY the JSON object, no other text.
            """

        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    [
                        "inline_data": [
                            "mime_type": "image/jpeg",
                            "data": base64String,
                        ]
                    ],
                ]
            ]],
            "generationConfig": [
                "responseMimeType": "application/json"
            ],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.requestFailed(0)
        }

        guard httpResponse.statusCode == 200 else {
            throw GeminiError.requestFailed(httpResponse.statusCode)
        }

        let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)

        guard let text = geminiResponse.candidates?.first?.content?.parts?.first?.text else {
            throw GeminiError.noContent
        }

        guard let jsonData = text.data(using: .utf8) else {
            throw GeminiError.parsingFailed
        }

        let result = try JSONDecoder().decode(ReceiptScanResult.self, from: jsonData)
        return result
    }

    static func scanBatchTransactions(image: UIImage) async throws -> [ReceiptScanResult] {
        let processedImage = resizeImageIfNeeded(image, maxDimension: 1024)

        guard let imageData = processedImage.jpegData(compressionQuality: 0.7) else {
            throw GeminiError.imageConversionFailed
        }
        let base64String = imageData.base64EncodedString()

        let apiKey = Constants.geminiAPIKey
        guard !apiKey.isEmpty, apiKey != "YOUR_GEMINI_API_KEY_HERE" else {
            throw GeminiError.missingAPIKey
        }

        let urlString =
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
        guard let url = URL(string: urlString) else {
            throw GeminiError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let prompt = """
            Analyze this screenshot of bank/payment transaction records.
            Extract ALL visible transactions and return a JSON array.
            Each element should have these fields:
            - "amount": the transaction amount as a number (just the number, no currency symbol)
            - "merchant": the merchant/payee name as a string (clean up the name, remove prefixes like "SALES:" or codes)
            - "date": the transaction date in "yyyy-MM-dd" format, or null if not visible
            - "category": suggest one category from: Food, Transport, Groceries, Shopping, Entertainment, Healthcare, Utilities, Subscriptions, Rent, Education, or Other
            - "isIncome": false for expenses, true for income

            If the image contains only a single receipt/bill, return an array with one element.
            If you cannot determine a field, set it to null.
            Return ONLY the JSON array, no other text.
            """

        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    [
                        "inline_data": [
                            "mime_type": "image/jpeg",
                            "data": base64String,
                        ]
                    ],
                ]
            ]],
            "generationConfig": [
                "responseMimeType": "application/json"
            ],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.requestFailed(0)
        }

        guard httpResponse.statusCode == 200 else {
            throw GeminiError.requestFailed(httpResponse.statusCode)
        }

        let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)

        guard let text = geminiResponse.candidates?.first?.content?.parts?.first?.text else {
            throw GeminiError.noContent
        }

        guard let jsonData = text.data(using: .utf8) else {
            throw GeminiError.parsingFailed
        }

        // Try to parse as array first, then fall back to single object
        if let results = try? JSONDecoder().decode([ReceiptScanResult].self, from: jsonData) {
            return results
        } else if let single = try? JSONDecoder().decode(ReceiptScanResult.self, from: jsonData) {
            return [single]
        }

        throw GeminiError.parsingFailed
    }

    static func parseVoiceInput(text: String, categoryNames: [String]) async throws -> [ReceiptScanResult] {
        let apiKey = Constants.geminiAPIKey
        guard !apiKey.isEmpty, apiKey != "YOUR_GEMINI_API_KEY_HERE" else {
            throw GeminiError.missingAPIKey
        }

        let urlString =
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
        guard let url = URL(string: urlString) else {
            throw GeminiError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayStr = dateFormatter.string(from: Date.now)

        let categoriesStr = categoryNames.joined(separator: ", ")

        let prompt = """
            You are a transaction parser. Parse the following voice input into one or more transactions.
            Today's date is \(todayStr).

            Voice input: "\(text)"

            Available categories: [\(categoriesStr)]

            Rules:
            - Return a JSON array of transactions (even if there is only one).
            - Each transaction object has these fields:
              - "amount": number (required, the transaction amount)
              - "merchant": string or null (a short note/description for the transaction)
              - "date": string in "yyyy-MM-dd" format or null. Convert relative dates: "today" = \(todayStr), "yesterday" = yesterday's date, etc. If no date mentioned, use null.
              - "category": string or null. Match to one of the available categories. If no match, use null.
              - "isIncome": boolean. true for income, false for expense. Default is false (expense).
            - If the input mentions multiple items with amounts (e.g. "lunch 45, taxi 12, coffee 18"), create separate transactions for each.
            - Extract the amount from numbers in the input.
            - Use the descriptive words as the merchant/note.
            - Return ONLY the JSON array, no other text.
            """

        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt]
                ]
            ]],
            "generationConfig": [
                "responseMimeType": "application/json"
            ],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.requestFailed(0)
        }

        guard httpResponse.statusCode == 200 else {
            throw GeminiError.requestFailed(httpResponse.statusCode)
        }

        let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)

        guard let responseText = geminiResponse.candidates?.first?.content?.parts?.first?.text else {
            throw GeminiError.noContent
        }

        guard let jsonData = responseText.data(using: .utf8) else {
            throw GeminiError.parsingFailed
        }

        // Try to parse as array first, then fall back to single object
        if let results = try? JSONDecoder().decode([ReceiptScanResult].self, from: jsonData) {
            return results
        } else if let single = try? JSONDecoder().decode(ReceiptScanResult.self, from: jsonData) {
            return [single]
        }

        throw GeminiError.parsingFailed
    }

    private static func resizeImageIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard max(size.width, size.height) > maxDimension else { return image }

        let scale: CGFloat
        if size.width > size.height {
            scale = maxDimension / size.width
        } else {
            scale = maxDimension / size.height
        }

        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
