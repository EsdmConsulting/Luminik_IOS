import Foundation

nonisolated enum LuminikConfig {
    /// Misma URL base que usa la app de Android (`Constants.BASE_URL`).
    static let baseURL = URL(string: "https://luminikweb.com/Sistema/servicios/")!
}

nonisolated enum LuminikEndpoint: String {
    case branches = "servicioListSuc.php"
    case login = "serviciosLogin.php"
    case quotes = "serviciosListCitas.php"
    /// Mismo script para los contratos del cliente y para los "contratos de una cita".
    case contracts = "serviciosContratosCliente.php"
    case contractServices = "serviciosContratoServiMs.php"
    case history = "servicioshistorialcitas.php"
    case quoteServices = "serviciosCitasServis.php"
    case cabins = "serviciosCabinas.php"
    case availableDates = "serviciosFechasDisponible.php"
    case availableHours = "serviciosHorarioaDisponible.php"
    case cancelQuote = "servicioscancelacion.php"
    case saveQuote = "serviciosguardarcita.php"
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
    /// `serviciosContratosCliente.php` (idSucursal, idCliente)
    func fetchContracts(branchID: String, clientID: String) async throws -> [Contract]
    /// `serviciosContratoServiMs.php`; `contractTypeCode` es el `tipoC` (ver `ContractKind.serviceTypeCode`).
    func fetchContractServices(
        branchID: String,
        contractTypeCode: String,
        contractID: String,
        clientID: String
    ) async throws -> [ContractService]
    /// `serviciosContratosCliente.php` con `idCita` (Android manda vacíos el resto de los campos).
    func fetchQuoteContractServices(quoteID: String) async throws -> [QuoteContractService]
    /// `servicioshistorialcitas.php`
    func fetchHistory(branchID: String, clientID: String) async throws -> [Quote]
    /// `serviciosCitasServis.php`
    func fetchQuoteServices(quoteID: String) async throws -> [QuoteService]
    /// `serviciosCabinas.php`
    func fetchCabins(branchID: String) async throws -> [Cabin]
    /// `serviciosFechasDisponible.php`; fechas en `dd-MM-yyyy`.
    func fetchAvailableDates(_ request: AvailableDatesRequest) async throws -> [String]
    /// `serviciosHorarioaDisponible.php`; `date` en `dd-MM-yyyy`.
    func fetchAvailableHours(
        cabinID: String,
        branchID: String,
        totalMinutes: Int,
        date: String
    ) async throws -> [String]
    /// `servicioscancelacion.php`
    func cancelQuote(quoteID: String, clientID: String, branchID: String, contractID: String) async throws
    /// `serviciosguardarcita.php`
    func saveQuote(_ request: SaveQuoteRequest) async throws
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

    func fetchContracts(branchID: String, clientID: String) async throws -> [Contract] {
        let envelope: ContractsResponse = try await postRaw(
            .contracts,
            fields: [
                ("idSucursal", branchID),
                ("idCliente", clientID)
            ]
        )
        return envelope.contracts
    }

    func fetchContractServices(
        branchID: String,
        contractTypeCode: String,
        contractID: String,
        clientID: String
    ) async throws -> [ContractService] {
        let envelope: LuminikEnvelope<[ContractService]> = try await post(
            .contractServices,
            fields: [
                ("idSucursal", branchID),
                ("tipoC", contractTypeCode),
                ("idContrato", contractID),
                ("idCliente", clientID)
            ]
        )
        return (envelope.data ?? []).map { $0.with(contractID: contractID) }
    }

    func fetchQuoteContractServices(quoteID: String) async throws -> [QuoteContractService] {
        let envelope: LuminikEnvelope<[QuoteContractService]> = try await post(
            .contracts,
            fields: [
                ("idCita", quoteID),
                ("folio", ""),
                ("idClien", ""),
                ("sucursal", ""),
                ("idContrato", "")
            ]
        )
        return envelope.data ?? []
    }

    func fetchHistory(branchID: String, clientID: String) async throws -> [Quote] {
        let envelope: LuminikEnvelope<[Quote]> = try await post(
            .history,
            fields: [
                ("idClien", clientID),
                ("sucursal", branchID)
            ]
        )
        return envelope.data ?? []
    }

    func fetchQuoteServices(quoteID: String) async throws -> [QuoteService] {
        let envelope: LuminikEnvelope<[QuoteService]> = try await post(
            .quoteServices,
            fields: [("idCita", quoteID)]
        )
        return envelope.data ?? []
    }

    func fetchCabins(branchID: String) async throws -> [Cabin] {
        let envelope: LuminikEnvelope<[Cabin]> = try await post(
            .cabins,
            fields: [("idSucursal", branchID)]
        )
        return envelope.data ?? []
    }

    func fetchAvailableDates(_ request: AvailableDatesRequest) async throws -> [String] {
        let envelope: LuminikDatesEnvelope = try await postRaw(
            .availableDates,
            fields: [
                ("idContrato", request.contractIDs.joined(separator: ",")),
                ("tipoContr", request.contractTypeCodes.joined(separator: ",")),
                ("pesoClient", request.clientWeight),
                ("idCabina", request.cabinID),
                ("idCliente", request.clientID),
                ("clientid", request.clientID),
                ("sucursal", request.branchID),
                ("duracion", String(request.durationMinutes)),
                ("tipcita", request.isValuation ? "1" : "0"),
                ("servi", request.serviceIDs.joined(separator: ","))
            ]
        )
        return envelope.dates
    }

    func fetchAvailableHours(
        cabinID: String,
        branchID: String,
        totalMinutes: Int,
        date: String
    ) async throws -> [String] {
        let envelope: LuminikEnvelope<[String]> = try await post(
            .availableHours,
            fields: [
                ("idCabina", cabinID),
                ("sucursal", branchID),
                ("timeTotal", String(totalMinutes)),
                ("fechaCita", date)
            ]
        )
        return envelope.data ?? []
    }

    func cancelQuote(quoteID: String, clientID: String, branchID: String, contractID: String) async throws {
        let envelope: LuminikEnvelope<EmptyPayload> = try await post(
            .cancelQuote,
            fields: [
                ("idCita", quoteID),
                ("idClient", clientID),
                ("idSucursal", branchID),
                ("idContra", contractID)
            ]
        )
        // Android no revisa `Status` al cancelar; aquí solo se rechazan los códigos que
        // la app de Android trata como error al guardar (0 y 2).
        if envelope.status == 0 || envelope.status == 2 {
            throw LuminikAPIError.rejected(message: envelope.message)
        }
    }

    func saveQuote(_ request: SaveQuoteRequest) async throws {
        let envelope: LuminikEnvelope<EmptyPayload> = try await post(
            .saveQuote,
            fields: [
                ("idClien", request.clientID),
                ("idContrato", request.contractIDs.joined(separator: ",")),
                ("fechaCita", request.date),
                ("horaCita", request.time),
                ("title", request.notes),
                ("sucursal", request.branchID),
                ("tipo", request.contractTypeCodes.joined(separator: ",")),
                ("tipoCita", request.isValuation ? "1" : "0"),
                ("timeTotal", String(request.durationMinutes)),
                ("numCabi", request.cabinID),
                ("servi", request.serviceIDs.joined(separator: ","))
            ]
        )
        // Android: `Status == 1` es éxito; 0 y 2 son error.
        guard envelope.status == 1 else {
            throw LuminikAPIError.rejected(message: envelope.message)
        }
    }

    // MARK: - Transport

    private func post<Payload: Decodable>(
        _ endpoint: LuminikEndpoint,
        fields: [(name: String, value: String)]?
    ) async throws -> LuminikEnvelope<Payload> {
        try await postRaw(endpoint, fields: fields)
    }

    /// POST que decodifica directamente el tipo pedido (para respuestas con forma propia).
    private func postRaw<Response: Decodable>(
        _ endpoint: LuminikEndpoint,
        fields: [(name: String, value: String)]?
    ) async throws -> Response {
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
            return try JSONDecoder().decode(Response.self, from: data)
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
