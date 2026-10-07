import Foundation
import Testing
@testable import LuminikV1

// MARK: - Helpers

/// Intercepta las peticiones de `URLSession` para probar `LuminikAPI` sin red.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func stubbedAPI() -> LuminikAPI {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return LuminikAPI(session: URLSession(configuration: configuration))
}

private func respond(
    _ request: URLRequest,
    status: Int = 200,
    json: String
) -> (HTTPURLResponse, Data) {
    let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    return (response, Data(json.utf8))
}

/// En `URLProtocol` el cuerpo llega como stream, no como `httpBody`.
private func bodyString(of request: URLRequest) -> String {
    if let body = request.httpBody {
        return String(decoding: body, as: UTF8.self)
    }
    guard let stream = request.httpBodyStream else { return "" }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        data.append(buffer, count: count)
    }
    return String(decoding: data, as: UTF8.self)
}

private nonisolated final class MockService: LuminikServicing, @unchecked Sendable {
    var loginResult: Result<LoginUser, LuminikAPIError> = .success(LoginUser(id: "7", name: "Ana"))
    var contracts: [Contract] = []
    var contractServices: [String: [ContractService]] = [:]
    var quotes: [Quote] = []
    var quoteServices: [String: [QuoteService]] = [:]
    var saveError: Error?
    var cancelError: Error?

    private(set) var calls: [String] = []
    private(set) var savedRequest: SaveQuoteRequest?

    func fetchBranches() async throws -> [BranchDTO] { [] }

    func login(branchID: String, phone: String, password: String) async throws -> LoginUser {
        try loginResult.get()
    }

    func fetchQuotes(branchID: String, clientID: String) async throws -> [Quote] { quotes }

    func fetchContracts(branchID: String, clientID: String) async throws -> [Contract] { contracts }

    func fetchContractServices(
        branchID: String,
        contractTypeCode: String,
        contractID: String,
        clientID: String
    ) async throws -> [ContractService] {
        (contractServices[contractID] ?? []).map { $0.with(contractID: contractID) }
    }

    func fetchQuoteContractServices(quoteID: String) async throws -> [QuoteContractService] { [] }

    func fetchHistory(branchID: String, clientID: String) async throws -> [Quote] { [] }

    func fetchQuoteServices(quoteID: String) async throws -> [QuoteService] { quoteServices[quoteID] ?? [] }

    func fetchCabins(branchID: String) async throws -> [Cabin] { [] }

    func fetchAvailableDates(_ request: AvailableDatesRequest) async throws -> [String] { [] }

    func fetchAvailableHours(cabinID: String, branchID: String, totalMinutes: Int, date: String) async throws -> [String] { [] }

    func cancelQuote(quoteID: String, clientID: String, branchID: String, contractID: String) async throws {
        calls.append("cancel:\(quoteID)")
        if let cancelError { throw cancelError }
    }

    func saveQuote(_ request: SaveQuoteRequest) async throws {
        calls.append("save")
        savedRequest = request
        if let saveError { throw saveError }
    }
}

// MARK: - Codificación y modelos

struct FormEncoderTests {
    @Test func escapesReservedCharacters() {
        let body = FormEncoder.encode([("pass", "p&ss+w=rd ñ")])
        #expect(String(decoding: body, as: UTF8.self) == "pass=p%26ss%2Bw%3Drd%20%C3%B1")
    }

    @Test func joinsFieldsInOrder() {
        let body = FormEncoder.encode([("sucursal", "1"), ("idClien", "42")])
        #expect(String(decoding: body, as: UTF8.self) == "sucursal=1&idClien=42")
    }
}

struct ModelDecodingTests {
    @Test func branchesAcceptNumericAndTextIDs() throws {
        let json = #"{"Status":1,"Message":"ok","Data":[{"id":1,"nombre":"Valle Oriente","letra":"V"},{"id":"2","nombre":"Paseo La Fe","letra":null}]}"#
        let envelope = try JSONDecoder().decode(LuminikEnvelope<[BranchDTO]>.self, from: Data(json.utf8))
        #expect(envelope.status == 1)
        #expect(envelope.data?.map(\.id) == ["1", "2"])
        #expect(envelope.data?.last?.letra == "")
    }

    @Test func envelopeToleratesMissingOrWrongData() throws {
        let json = #"{"Status":"0","Message":"Datos incorrectos","Data":[]}"#
        let envelope = try JSONDecoder().decode(LuminikEnvelope<LoginUser>.self, from: Data(json.utf8))
        #expect(envelope.status == 0)
        #expect(envelope.message == "Datos incorrectos")
        #expect(envelope.data == nil)
    }

    @Test func fullNameSkipsEmptyAndNullParts() {
        let user = LoginUser(id: "1", name: "Sarah", apePa: "Santos", apeMa: "null")
        #expect(user.fullName == "Sarah Santos")
    }

    @Test func quoteReadsAndroidFieldNames() throws {
        let json = #"{"id":"9","fechaCita":"02-09-2026","horaCita":"11:51:00","contratosFormateados":"B14","status":3}"#
        let quote = try JSONDecoder().decode(Quote.self, from: Data(json.utf8))
        #expect(quote.appointmentDate == "02-09-2026")
        #expect(quote.formattedContracts == "B14")
        #expect(quote.isCancelled)
    }
}

// MARK: - Presentación

@MainActor
struct PresentationTests {
    @Test func displayDateFormatsKnownLayouts() {
        #expect(AppointmentItem.displayDate("02-09-2026") == "02/SEPTIEMBRE/2026")
        #expect(AppointmentItem.displayDate("2026-09-19") == "19/SEPTIEMBRE/2026")
        #expect(AppointmentItem.displayDate("pronto") == "pronto")
    }

    @Test func branchMappingKeepsKnownLogos() {
        let valle = Branch(dto: BranchDTO(id: "1", name: "Valle Oriente"))
        #expect(valle.mark == "VO")
        #expect(valle.subtitle == "GALERÍAS VALLE ORIENTE")

        let laFe = Branch(dto: BranchDTO(id: "2", name: "Paseo La Fe"))
        #expect(laFe.mark == "PASEO | LA FE")

        let anahuac = Branch(dto: BranchDTO(id: "4", name: "Plaza Fiesta Anahuac"))
        #expect(anahuac.mark == "PLAZA\nFIESTA")
        #expect(anahuac.subtitle == "ANAHUAC")
        #expect(anahuac.id == "4")
    }
}

// MARK: - API

@Suite(.serialized)
struct LuminikAPITests {
    @Test func loginSendsFormBodyAndReturnsUser() async throws {
        var captured: URLRequest?
        StubURLProtocol.handler = { request in
            captured = request
            return respond(request, json: #"{"Status":1,"Message":"ok","Data":{"id":"7","nombre":"Ana","apePa":"Lopez","apeMa":"","correo":"ana@mail.com"}}"#)
        }

        let user = try await stubbedAPI().login(branchID: "1", phone: "8181360496", password: "p&ss+w=rd")

        #expect(user.id == "7")
        #expect(user.fullName == "Ana Lopez")
        #expect(captured?.httpMethod == "POST")
        #expect(captured?.url?.lastPathComponent == "serviciosLogin.php")
        #expect(bodyString(of: captured!) == "idSucursal=1&telefono=8181360496&pass=p%26ss%2Bw%3Drd")
    }

    @Test func loginRejectedSurfacesServerMessage() async {
        StubURLProtocol.handler = { request in
            respond(request, json: #"{"Status":0,"Message":"Usuario o contraseña incorrectos","Data":[]}"#)
        }

        await #expect(throws: LuminikAPIError.rejected(message: "Usuario o contraseña incorrectos")) {
            try await stubbedAPI().login(branchID: "1", phone: "8181360496", password: "x")
        }
    }

    @Test func quotesUseSucursalAndIdClienFields() async throws {
        var captured: URLRequest?
        StubURLProtocol.handler = { request in
            captured = request
            return respond(request, json: #"{"Status":1,"Message":"ok","Data":[{"id":"1","fechaCita":"02-09-2026","contratosFormateados":"B14"}]}"#)
        }

        let quotes = try await stubbedAPI().fetchQuotes(branchID: "3", clientID: "42")

        #expect(quotes.count == 1)
        #expect(captured?.url?.lastPathComponent == "serviciosListCitas.php")
        #expect(bodyString(of: captured!) == "sucursal=3&idClien=42")
    }

    @Test func branchesArePostedWithoutBody() async throws {
        var captured: URLRequest?
        StubURLProtocol.handler = { request in
            captured = request
            return respond(request, json: #"{"Status":1,"Message":"ok","Data":[{"id":"1","nombre":"Valle Oriente"}]}"#)
        }

        let branches = try await stubbedAPI().fetchBranches()

        #expect(branches.count == 1)
        #expect(captured?.httpMethod == "POST")
        #expect(captured?.url?.lastPathComponent == "servicioListSuc.php")
        #expect(bodyString(of: captured!).isEmpty)
    }

    @Test func httpErrorsBecomeServerErrors() async {
        StubURLProtocol.handler = { request in
            respond(request, status: 500, json: "")
        }

        await #expect(throws: LuminikAPIError.server(statusCode: 500)) {
            try await stubbedAPI().fetchBranches()
        }
    }
}

// MARK: - LoginViewModel

@MainActor
struct LoginViewModelTests {
    private let branch = Branch(id: "1", name: "VALLE ORIENTE", mark: "VO", subtitle: nil)

    private func makeStore() -> SessionStore {
        SessionStore(defaults: UserDefaults(suiteName: "luminik.tests.\(UUID().uuidString)")!)
    }

    @Test func validationFlagsBadPhoneAndEmptyPassword() {
        let viewModel = LoginViewModel(branch: branch, service: MockService(), sessionStore: makeStore())
        #expect(viewModel.validate(phone: "123", password: "") == [.phone, .password])
        #expect(viewModel.validate(phone: "(818) 136-0496", password: "x").isEmpty)
        #expect(viewModel.validate(phone: "+52 818 136 0496", password: "x").isEmpty)
    }

    @Test func successfulSignInStoresSessionWithoutPassword() async {
        let store = makeStore()
        let viewModel = LoginViewModel(branch: branch, service: MockService(), sessionStore: store)

        await viewModel.signIn(phone: "818 136 0496", password: "secreto")

        #expect(viewModel.state == .authenticated)
        #expect(store.current?.userID == "7")
        #expect(store.current?.phone == "8181360496")
        #expect(store.current?.branchID == "1")
    }

    @Test func rejectedSignInReportsMessageAndStoresNothing() async {
        let store = makeStore()
        let service = MockService(loginResult: .failure(.rejected(message: "Datos incorrectos")))
        let viewModel = LoginViewModel(branch: branch, service: service, sessionStore: store)

        await viewModel.signIn(phone: "8181360496", password: "mal")

        #expect(viewModel.state == .failed("Datos incorrectos"))
        #expect(store.current == nil)
    }
}

// MARK: - Servicios restantes: modelos

struct RemainingModelDecodingTests {
    @Test func contractsKeepAndroidOrderKindsAndCodes() throws {
        let json = #"""
        {"Status":1,"Message":"ok",
         "DataBotox":[{"id":"1","folio":"L","folioComple":"L362","total":1500,"fecha":"2026-01-02"}],
         "DataFaciales":[{"id":2,"folioComple":"HP336"}],
         "ContraBody":[{"id":"3","folioComple":"B14"}],
         "DataDepilacion":[{"id":"4","folioComple":"A108"}]}
        """#
        let response = try JSONDecoder().decode(ContractsResponse.self, from: Data(json.utf8))
        let contracts = response.contracts

        #expect(contracts.map(\.kind) == [.linfonik, .facial, .bodySculpts, .depilacion])
        #expect(contracts.map(\.kind.serviceTypeCode) == ["3", "2", "4", "1"])
        #expect(contracts.map(\.displayFolio) == ["L362", "HP336", "B14", "A108"])
        #expect(contracts.first?.total == "1500")
    }

    @Test func contractServicesReadLowercaseDataKey() throws {
        let json = #"{"Status":1,"Message":"ok","data":[{"idServiContra":"11","descri":"ESPALDA","nombreCli":"ANA","timeNor":"15","tipCont":"3","citas":"2"}]}"#
        let envelope = try JSONDecoder().decode(LuminikEnvelope<[ContractService]>.self, from: Data(json.utf8))
        let service = try #require(envelope.data?.first)

        #expect(service.idServiContra == "11")
        #expect(service.displayName == "ESPALDA-ANA")
        #expect(service.normalMinutes == 15)
        #expect(service.completedAppointments == 2)
    }

    @Test func datesUseFechasDisponibleKey() throws {
        let json = #"{"Status":1,"Message":"ok","Fechas Disponible":["07-10-2026","08-10-2026"]}"#
        let envelope = try JSONDecoder().decode(LuminikDatesEnvelope.self, from: Data(json.utf8))
        #expect(envelope.dates == ["07-10-2026", "08-10-2026"])
    }

    @Test func cabinReadsAndroidKeys() throws {
        let json = #"{"id":"3","nameCab":"CABINA 3","enfermera":"Luz","nameAse":"Marta"}"#
        let cabin = try JSONDecoder().decode(Cabin.self, from: Data(json.utf8))
        #expect(cabin == Cabin(id: "3", name: "CABINA 3", nurse: "Luz", advisorName: "Marta"))
    }

    @Test func displayTimeDropsSeconds() {
        #expect(ScheduleCalendarViewController.displayTime("09:30:00") == "09:30")
        #expect(ScheduleCalendarViewController.displayTime("9:30 AM") == "9:30 AM")
    }
}

// MARK: - Servicios restantes: API

@Suite(.serialized)
struct RemainingAPITests {
    @Test func contractServicesPostAndroidFieldsAndTagContract() async throws {
        var captured: URLRequest?
        StubURLProtocol.handler = { request in
            captured = request
            return respond(request, json: #"{"Status":1,"Message":"ok","data":[{"idServiContra":"11","descri":"ESPALDA"}]}"#)
        }

        let services = try await stubbedAPI().fetchContractServices(
            branchID: "1", contractTypeCode: "3", contractID: "55", clientID: "7"
        )

        #expect(services.first?.contractID == "55")
        #expect(captured?.url?.lastPathComponent == "serviciosContratoServiMs.php")
        #expect(bodyString(of: captured!) == "idSucursal=1&tipoC=3&idContrato=55&idCliente=7")
    }

    @Test func historyAndCabinsAndQuoteServicesUseTheirEndpoints() async throws {
        var paths: [String] = []
        var bodies: [String] = []
        StubURLProtocol.handler = { request in
            paths.append(request.url!.lastPathComponent)
            bodies.append(bodyString(of: request))
            return respond(request, json: #"{"Status":1,"Message":"ok","Data":[]}"#)
        }
        let api = stubbedAPI()

        _ = try await api.fetchHistory(branchID: "2", clientID: "7")
        _ = try await api.fetchCabins(branchID: "2")
        _ = try await api.fetchQuoteServices(quoteID: "90")

        #expect(paths == ["servicioshistorialcitas.php", "serviciosCabinas.php", "serviciosCitasServis.php"])
        #expect(bodies == ["idClien=7&sucursal=2", "idSucursal=2", "idCita=90"])
    }

    @Test func availableDatesJoinListsWithCommasAndInvertValuationFlag() async throws {
        var captured: URLRequest?
        StubURLProtocol.handler = { request in
            captured = request
            return respond(request, json: #"{"Status":1,"Message":"ok","Fechas Disponible":["07-10-2026"]}"#)
        }

        let dates = try await stubbedAPI().fetchAvailableDates(
            AvailableDatesRequest(
                contractIDs: ["55", "56"],
                contractTypeCodes: ["3", "2"],
                clientWeight: "60",
                cabinID: "4",
                clientID: "7",
                branchID: "1",
                durationMinutes: 35,
                isValuation: true,
                serviceIDs: ["11", "12"]
            )
        )

        #expect(dates == ["07-10-2026"])
        #expect(bodyString(of: captured!) == "idContrato=55%2C56&tipoContr=3%2C2&pesoClient=60&idCabina=4&idCliente=7&clientid=7&sucursal=1&duracion=35&tipcita=1&servi=11%2C12")
    }

    @Test func availableHoursReturnPlainStrings() async throws {
        var captured: URLRequest?
        StubURLProtocol.handler = { request in
            captured = request
            return respond(request, json: #"{"Status":1,"Message":"ok","Data":["09:30:00","10:00:00"]}"#)
        }

        let hours = try await stubbedAPI().fetchAvailableHours(cabinID: "4", branchID: "1", totalMinutes: 35, date: "07-10-2026")

        #expect(hours == ["09:30:00", "10:00:00"])
        #expect(bodyString(of: captured!) == "idCabina=4&sucursal=1&timeTotal=35&fechaCita=07-10-2026")
    }

    @Test func saveQuoteSucceedsOnlyWithStatusOne() async throws {
        var captured: URLRequest?
        StubURLProtocol.handler = { request in
            captured = request
            return respond(request, json: #"{"Status":1,"Message":"ok"}"#)
        }
        let request = SaveQuoteRequest(
            clientID: "7", contractIDs: ["55"], date: "07-10-2026", time: "09:30:00", notes: "primera vez",
            branchID: "1", contractTypeCodes: ["3"], isValuation: false, durationMinutes: 15, cabinID: "4",
            serviceIDs: ["11"]
        )

        try await stubbedAPI().saveQuote(request)

        #expect(captured?.url?.lastPathComponent == "serviciosguardarcita.php")
        #expect(bodyString(of: captured!) == "idClien=7&idContrato=55&fechaCita=07-10-2026&horaCita=09%3A30%3A00&title=primera%20vez&sucursal=1&tipo=3&tipoCita=0&timeTotal=15&numCabi=4&servi=11")

        StubURLProtocol.handler = { request in
            respond(request, json: #"{"Status":2,"Message":"Horario ocupado"}"#)
        }
        await #expect(throws: LuminikAPIError.rejected(message: "Horario ocupado")) {
            try await stubbedAPI().saveQuote(request)
        }
    }

    @Test func cancelQuoteRejectsStatusZeroAndTwoOnly() async throws {
        StubURLProtocol.handler = { request in
            respond(request, json: #"{"Status":1,"Message":"ok"}"#)
        }
        try await stubbedAPI().cancelQuote(quoteID: "90", clientID: "7", branchID: "1", contractID: "55")

        StubURLProtocol.handler = { request in
            respond(request, json: #"{"Status":0,"Message":"No se pudo cancelar"}"#)
        }
        await #expect(throws: LuminikAPIError.rejected(message: "No se pudo cancelar")) {
            try await stubbedAPI().cancelQuote(quoteID: "90", clientID: "7", branchID: "1", contractID: "55")
        }
    }
}

// MARK: - Flujo de agendar

@MainActor
struct AppointmentDraftTests {
    private let session = UserSession(
        user: LoginUser(id: "7", name: "Ana", weight: "60"),
        phone: "8181360496",
        branchID: "1",
        branchName: "VALLE ORIENTE"
    )

    private func facial(_ id: String, minutes: String = "20") -> ContractService {
        ContractService(idServiContra: id, descri: "FACIAL \(id)", timeNor: minutes, tipCont: "2", contractID: "55")
    }

    private func depilacion(_ id: String, citas: String, bancitavalo: String = "0") -> ContractService {
        ContractService(idServiContra: id, descri: "DEPI \(id)", citas: citas, timeNor: "10", tipCont: "1", bancitavalo: bancitavalo, contractID: "60")
    }

    @Test func normalServicesSumMinutesAndKeepNormalKind() {
        let draft = AppointmentDraft(session: session, service: MockService())
        #expect(draft.toggle(facial("1", minutes: "20")) == .added)
        #expect(draft.toggle(facial("2", minutes: "15")) == .added)
        #expect(draft.kind == .normal)
        #expect(draft.totalMinutes == 35)
        #expect(draft.serviceIDs == ["1", "2"])

        #expect(draft.toggle(facial("1")) == .removed)
        #expect(draft.toggle(facial("2")) == .removed)
        #expect(draft.kind == .none)
    }

    @Test func valuationLasts5MinutesAndCannotMixWithNormal() {
        let draft = AppointmentDraft(session: session, service: MockService())
        // 7 citas o más y sin valoración previa => cita de valoración.
        #expect(draft.toggle(depilacion("9", citas: "7")) == .added)
        #expect(draft.kind == .valuation)
        #expect(draft.isValuation)
        #expect(draft.totalMinutes == 5)

        #expect(draft.toggle(facial("1")) == .conflict)
        #expect(draft.toggle(depilacion("8", citas: "3")) == .conflict)
        #expect(draft.selectedServices.count == 1)
    }

    @Test func normalDepilacionCannotJoinAValuationRequiredOne() {
        let draft = AppointmentDraft(session: session, service: MockService())
        #expect(draft.toggle(depilacion("8", citas: "3")) == .added)
        #expect(draft.toggle(depilacion("9", citas: "8")) == .conflict)
    }

    @Test func requestsUseContractOrderAndServerFlags() {
        let draft = AppointmentDraft(session: session, service: MockService())
        let linfonik = Contract(id: "55", folioComplete: "L362", kind: .linfonik)
        let facialContract = Contract(id: "56", folioComplete: "HP336", kind: .facial)
        draft.select(linfonik, services: [facial("1")])
        draft.select(facialContract, services: [facial("2")])
        _ = draft.toggle(draft.availableServices[0])
        draft.cabin = Cabin(id: "4", name: "CABINA 4")
        draft.date = "07-10-2026"
        draft.time = "09:30:00"

        let dates = draft.makeDatesRequest()
        #expect(dates?.contractIDs == ["55", "56"])
        #expect(dates?.contractTypeCodes == ["3", "2"])
        #expect(dates?.clientWeight == "60")
        #expect(dates?.isValuation == false)

        let save = draft.makeSaveRequest()
        #expect(save?.cabinID == "4")
        #expect(save?.serviceIDs == ["1"])
    }

    @Test func deselectingContractRemovesItsServices() {
        let draft = AppointmentDraft(session: session, service: MockService())
        let contract = Contract(id: "55", kind: .facial)
        draft.select(contract, services: [facial("1")])
        _ = draft.toggle(draft.availableServices[0])
        #expect(draft.selectedServices.count == 1)

        draft.deselect(contract)
        #expect(draft.selectedServices.isEmpty)
        #expect(draft.kind == .none)
        #expect(draft.availableServices.isEmpty)
    }

    @Test func loadServicesHidesServicesAlreadyScheduledAndIgnoresCancelledQuotes() async throws {
        let service = MockService()
        service.contractServices["55"] = [facial("1"), facial("2"), facial("3")]
        service.quotes = [
            Quote(id: "90", contractID: "55", status: "1"),
            Quote(id: "91", contractID: "55", status: "3"),
            Quote(id: "92", contractID: "99", status: "1")
        ]
        service.quoteServices = [
            "90": [QuoteService(idServi: "1")],
            "91": [QuoteService(idServi: "2")],
            "92": [QuoteService(idServi: "3")]
        ]
        let draft = AppointmentDraft(session: session, service: service)
        try await draft.loadContracts()

        let available = try await draft.loadServices(for: Contract(id: "55", kind: .facial))

        // Solo el "1" está agendado en una cita vigente de este contrato.
        #expect(available.map(\.idServiContra) == ["2", "3"])
    }

    @Test func rescheduleSavesFirstAndThenCancelsThePreviousQuote() async throws {
        let service = MockService()
        let draft = AppointmentDraft(session: session, service: service)
        let quote = Quote(
            id: "90", title: "nota", kind: "3", appointmentKind: "0", totalMinutes: "35",
            cabinNumber: "4", cabinName: "CABINA 4", contractID: "55"
        )
        draft.prepareReschedule(
            quote: quote,
            services: [
                QuoteService(idServi: "11", idContrato: "55", descri: "ESPALDA"),
                QuoteService(idServi: "11", idContrato: "55", descri: "ESPALDA"),
                QuoteService(idServi: "12", idContrato: "55", descri: "CINTURA")
            ]
        )
        draft.date = "08-10-2026"
        draft.time = "10:00:00"

        try await draft.save()

        #expect(service.calls == ["save", "cancel:90"])
        #expect(service.savedRequest?.serviceIDs == ["11", "12"])
        #expect(service.savedRequest?.contractIDs == ["55"])
        #expect(service.savedRequest?.contractTypeCodes == ["3"])
        #expect(service.savedRequest?.durationMinutes == 35)
        #expect(service.savedRequest?.isValuation == false)
        #expect(service.savedRequest?.cabinID == "4")
        #expect(service.savedRequest?.notes == "nota")
    }

    @Test func failedSaveKeepsThePreviousQuote() async {
        let service = MockService()
        service.saveError = LuminikAPIError.rejected(message: "ocupado")
        let draft = AppointmentDraft(session: session, service: service)
        draft.prepareReschedule(
            quote: Quote(id: "90", kind: "3", appointmentKind: "0", totalMinutes: "15", cabinNumber: "4", cabinName: "C4", contractID: "55"),
            services: [QuoteService(idServi: "11", idContrato: "55")]
        )
        draft.date = "08-10-2026"
        draft.time = "10:00:00"

        await #expect(throws: LuminikAPIError.rejected(message: "ocupado")) {
            try await draft.save()
        }
        #expect(service.calls == ["save"])
    }

    @Test func previousQuoteNotCancelledIsReportedAfterSavingTheNewOne() async {
        let service = MockService()
        service.cancelError = LuminikAPIError.offline
        let draft = AppointmentDraft(session: session, service: service)
        draft.prepareReschedule(
            quote: Quote(id: "90", kind: "3", appointmentKind: "0", totalMinutes: "15", cabinNumber: "4", cabinName: "C4", contractID: "55"),
            services: [QuoteService(idServi: "11", idContrato: "55")]
        )
        draft.date = "08-10-2026"
        draft.time = "10:00:00"

        await #expect(throws: ScheduleError.previousQuoteNotCancelled) {
            try await draft.save()
        }
        #expect(service.calls == ["save", "cancel:90"])
    }

    @Test func incompleteDraftCannotBeSaved() async {
        let draft = AppointmentDraft(session: session, service: MockService())
        await #expect(throws: ScheduleError.incomplete) {
            try await draft.save()
        }
    }
}
