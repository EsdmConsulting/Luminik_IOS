import Foundation

nonisolated enum LuminikConfig {
    /// Misma URL base que usa la app de Android (`Constants.BASE_URL`).
    static let baseURL = URL(string: "https://luminikweb.com/Sistema/servicios/")!
}

nonisolated enum LuminikEndpoint: String {
    case branches = "servicioListSuc.php"
    case login = "serviciosLogin.php"
    case quotes = "serviciosListCitas.php"
}

nonisolated enum LuminikAPIError: LocalizedError, Equatable {
    case offline
    case timeout
    case network
    case server(statusCode: Int)
    case invalidResponse
    /// El servidor respondió bien pero rechazó la operación (por ejemplo, credenciales incorrectas).
    case rejected(message: String)

    var errorDescription: String? {
        switch self {
        case .offline:
            return "Sin conexión a internet. Revisa tu red e inténtalo de nuevo."
        case .timeout:
            return "El servidor tardó demasiado en responder. Inténtalo de nuevo."
        case .network:
            return "No se pudo conectar con el servidor. Inténtalo más tarde."
        case let .server(statusCode):
            return "El servidor respondió con un error (\(statusCode)). Inténtalo más tarde."
        case .invalidResponse:
            return "La respuesta del servidor no es válida."
        case let .rejected(message):
            return message.isEmpty ? "No se pudo completar la operación." : message
        }
    }
}

nonisolated protocol LuminikServicing: Sendable {
    /// `servicioListSuc.php`
    func fetchBranches() async throws -> [BranchDTO]
    /// `serviciosLogin.php`
    func login(branchID: String, phone: String, password: String) async throws -> LoginUser
    /// `serviciosListCitas.php`
    func fetchQuotes(branchID: String, clientID: String) async throws -> [Quote]
}

nonisolated struct LuminikAPI: LuminikServicing {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = LuminikConfig.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func fetchBranches() async throws -> [BranchDTO] {
        // En Android este servicio es un POST sin parámetros.
        let envelope: LuminikEnvelope<[BranchDTO]> = try await post(.branches, fields: nil)
        return envelope.data ?? []
    }

    func login(branchID: String, phone: String, password: String) async throws -> LoginUser {
        let envelope: LuminikEnvelope<LoginUser> = try await post(
            .login,
            fields: [
                ("idSucursal", branchID),
                ("telefono", phone),
                ("pass", password)
            ]
        )
        // Android solo considera válido el login cuando `Status == 1`.
        guard envelope.status == 1, let user = envelope.data, !user.id.isEmpty else {
            throw LuminikAPIError.rejected(message: envelope.message)
        }
        return user
    }

    func fetchQuotes(branchID: String, clientID: String) async throws -> [Quote] {
        let envelope: LuminikEnvelope<[Quote]> = try await post(
            .quotes,
            fields: [
                ("sucursal", branchID),
                ("idClien", clientID)
            ]
        )
        return envelope.data ?? []
    }

    // MARK: - Transport

    private func post<Payload: Decodable>(
        _ endpoint: LuminikEndpoint,
        fields: [(name: String, value: String)]?
    ) async throws -> LuminikEnvelope<Payload> {
        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint.rawValue))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let fields {
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = FormEncoder.encode(fields)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .dataNotAllowed, .networkConnectionLost:
                throw LuminikAPIError.offline
            case .timedOut:
                throw LuminikAPIError.timeout
            case .cancelled:
                throw CancellationError()
            default:
                throw LuminikAPIError.network
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LuminikAPIError.network
        }

        guard let http = response as? HTTPURLResponse else {
            throw LuminikAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw LuminikAPIError.server(statusCode: http.statusCode)
        }

        do {
            return try JSONDecoder().decode(LuminikEnvelope<Payload>.self, from: data)
        } catch {
            throw LuminikAPIError.invalidResponse
        }
    }
}

/// Codifica `application/x-www-form-urlencoded` escapando todo lo que no sea
/// ASCII "seguro", para que contraseñas con `&`, `+`, `=` o acentos lleguen intactas.
nonisolated enum FormEncoder {
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    static func encode(_ fields: [(name: String, value: String)]) -> Data {
        let body = fields
            .map { "\(escape($0.name))=\(escape($0.value))" }
            .joined(separator: "&")
        return Data(body.utf8)
    }
}
