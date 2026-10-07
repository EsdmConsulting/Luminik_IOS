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

private nonisolated struct MockService: LuminikServicing {
    var loginResult: Result<LoginUser, LuminikAPIError> = .success(LoginUser(id: "7", name: "Ana"))

    func fetchBranches() async throws -> [BranchDTO] { [] }
    func login(branchID: String, phone: String, password: String) async throws -> LoginUser {
        try loginResult.get()
    }
    func fetchQuotes(branchID: String, clientID: String) async throws -> [Quote] { [] }
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
