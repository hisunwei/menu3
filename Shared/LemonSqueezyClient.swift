import Foundation

struct LemonSqueezyActivationResult {
    let activated: Bool
    let instanceID: String?
    let errorMessage: String?
}

struct LemonSqueezyValidationResult {
    let valid: Bool
    let errorMessage: String?
}

final class LemonSqueezyClient {
    static let shared = LemonSqueezyClient()

    private let activateURL = URL(string: "https://api.lemonsqueezy.com/v1/licenses/activate")!
    private let validateURL = URL(string: "https://api.lemonsqueezy.com/v1/licenses/validate")!

    private init() {}

    func activateLicense(licenseKey: String, instanceName: String) async throws -> LemonSqueezyActivationResult {
        var request = URLRequest(url: activateURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = formEncodedBody([
            "license_key": licenseKey,
            "instance_name": instanceName
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            return LemonSqueezyActivationResult(activated: false, instanceID: nil, errorMessage: nil)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            return LemonSqueezyActivationResult(activated: false, instanceID: nil, errorMessage: nil)
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let activated = json?["activated"] as? Bool ?? false
        let errorMessage = json?["error"] as? String

        let instanceID: String?
        if let instance = json?["instance"] as? [String: Any] {
            if let raw = instance["id"] {
                instanceID = String(describing: raw)
            } else if let raw = instance["instance_id"] {
                instanceID = String(describing: raw)
            } else {
                instanceID = nil
            }
        } else {
            instanceID = nil
        }

        return LemonSqueezyActivationResult(
            activated: activated,
            instanceID: instanceID,
            errorMessage: errorMessage
        )
    }

    func validateLicense(licenseKey: String, instanceID: String?) async throws -> LemonSqueezyValidationResult {
        var request = URLRequest(url: validateURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        var params: [String: String] = ["license_key": licenseKey]
        if let instanceID, !instanceID.isEmpty {
            params["instance_id"] = instanceID
        }
        request.httpBody = formEncodedBody(params)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            return LemonSqueezyValidationResult(valid: false, errorMessage: nil)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            return LemonSqueezyValidationResult(valid: false, errorMessage: nil)
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let valid = json?["valid"] as? Bool ?? false
        let errorMessage = json?["error"] as? String
        return LemonSqueezyValidationResult(valid: valid, errorMessage: errorMessage)
    }

    private func formEncodedBody(_ params: [String: String]) -> Data? {
        let query = params
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
        return query.data(using: .utf8)
    }
}
