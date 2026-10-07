import Foundation

/// Datos de la sesión iniciada. Es el equivalente a lo que Android guarda en
/// `SharedPreferences` (`idUser`, `nameUser`, `correo`, `user`, `idBranche`, ...).
///
/// A diferencia de Android, **no se guarda la contraseña**: solo hace falta el
/// `userID` para consultar las citas.
nonisolated struct UserSession: Codable, Equatable, Sendable {
    let userID: String
    let fullName: String
    let phone: String
    let email: String
    let weight: String
    let branchID: String
    let branchName: String

    init(user: LoginUser, phone: String, branchID: String, branchName: String) {
        self.userID = user.id
        self.fullName = user.fullName
        self.phone = phone
        self.email = user.email
        self.weight = user.weight
        self.branchID = branchID
        self.branchName = branchName
    }
}

final class SessionStore {
    static let shared = SessionStore()

    private let defaults: UserDefaults
    private let key = "luminik.session.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var current: UserSession? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(UserSession.self, from: data)
    }

    func save(_ session: UserSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
