import Foundation

@MainActor
final class LoginViewModel {
    enum State: Equatable {
        case idle
        case loading
        case authenticated
        case failed(String)
    }

    enum Field: Hashable {
        case phone
        case password
    }

    var onStateChange: ((State) -> Void)?

    private(set) var state: State = .idle {
        didSet { onStateChange?(state) }
    }

    /// Disponible cuando `state == .authenticated`.
    private(set) var session: UserSession?

    private let branch: Branch
    private let service: LuminikServicing
    private let sessionStore: SessionStore

    init(
        branch: Branch,
        service: LuminikServicing = LuminikAPI(),
        sessionStore: SessionStore = .shared
    ) {
        self.branch = branch
        self.service = service
        self.sessionStore = sessionStore
    }

    /// Deja solo los dígitos y quita la lada de país (52) si viene con ella.
    static func normalizedPhone(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        if digits.count == 12, digits.hasPrefix("52") {
            return String(digits.dropFirst(2))
        }
        return digits
    }

    /// Devuelve los campos inválidos; vacío significa que se puede enviar.
    ///
    /// La contraseña solo se exige no vacía: el servidor es quien decide si es
    /// correcta, y en Android tampoco se impone un largo mínimo.
    func validate(phone: String, password: String) -> Set<Field> {
        var invalid = Set<Field>()
        if Self.normalizedPhone(phone).count != 10 {
            invalid.insert(.phone)
        }
        if password.isEmpty {
            invalid.insert(.password)
        }
        return invalid
    }

    func signIn(phone: String, password: String) async {
        guard state != .loading else { return }
        guard validate(phone: phone, password: password).isEmpty else {
            state = .failed("Revisa tu teléfono y tu contraseña.")
            return
        }

        state = .loading
        let normalizedPhone = Self.normalizedPhone(phone)
        do {
            let user = try await service.login(
                branchID: branch.id,
                phone: normalizedPhone,
                password: password
            )
            let newSession = UserSession(
                user: user,
                phone: normalizedPhone,
                branchID: branch.id,
                branchName: branch.name
            )
            sessionStore.save(newSession)
            session = newSession
            state = .authenticated
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
