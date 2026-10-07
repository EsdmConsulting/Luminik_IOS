import Foundation

// MARK: - Tolerant decoding
//
// El backend PHP no es estricto con los tipos: un mismo campo puede llegar como
// texto, número o `null`. Estos helpers leen cualquiera de esos casos como `String`
// para que un cambio de tipo en el servidor no tire toda la pantalla.

extension KeyedDecodingContainer {
    nonisolated func flexibleString(_ key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value ? "1" : "0"
        }
        return nil
    }

    nonisolated func flexibleInt(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}

// MARK: - Envelope

/// Respuesta común de los servicios: `{ "Status": 1, "Message": "...", "Data": ... }`.
/// `Data` es opcional porque en errores el servidor puede omitirlo o mandarlo vacío.
nonisolated struct LuminikEnvelope<Payload: Decodable>: Decodable {
    let status: Int
    let message: String
    let data: Payload?

    private enum CodingKeys: String, CodingKey {
        case status = "Status"
        case message = "Message"
        case data = "Data"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = container.flexibleInt(.status) ?? 0
        message = container.flexibleString(.message) ?? ""
        data = try? container.decodeIfPresent(Payload.self, forKey: .data)
    }
}

// MARK: - servicioListSuc.php

nonisolated struct BranchDTO: Decodable, Equatable, Sendable {
    let id: String
    let name: String
    let letra: String
    let letraF: String
    let letraB: String

    private enum CodingKeys: String, CodingKey {
        case id, letra, letraF, letraB
        case name = "nombre"
    }

    init(id: String, name: String, letra: String = "", letraF: String = "", letraB: String = "") {
        self.id = id
        self.name = name
        self.letra = letra
        self.letraF = letraF
        self.letraB = letraB
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.flexibleString(.id) ?? ""
        name = container.flexibleString(.name) ?? ""
        letra = container.flexibleString(.letra) ?? ""
        letraF = container.flexibleString(.letraF) ?? ""
        letraB = container.flexibleString(.letraB) ?? ""
    }
}

// MARK: - serviciosLogin.php

nonisolated struct LoginUser: Decodable, Equatable, Sendable {
    let id: String
    let name: String
    let apePa: String
    let apeMa: String
    let weight: String
    let branchID: String
    let skinType: String
    let email: String

    private enum CodingKeys: String, CodingKey {
        case id, apePa, apeMa
        case name = "nombre"
        case weight = "peso"
        case branchID = "sucursal"
        case skinType = "tipoPiel"
        case email = "correo"
    }

    init(
        id: String,
        name: String,
        apePa: String = "",
        apeMa: String = "",
        weight: String = "",
        branchID: String = "",
        skinType: String = "",
        email: String = ""
    ) {
        self.id = id
        self.name = name
        self.apePa = apePa
        self.apeMa = apeMa
        self.weight = weight
        self.branchID = branchID
        self.skinType = skinType
        self.email = email
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.flexibleString(.id) ?? ""
        name = container.flexibleString(.name) ?? ""
        apePa = container.flexibleString(.apePa) ?? ""
        apeMa = container.flexibleString(.apeMa) ?? ""
        weight = container.flexibleString(.weight) ?? ""
        branchID = container.flexibleString(.branchID) ?? ""
        skinType = container.flexibleString(.skinType) ?? ""
        email = container.flexibleString(.email) ?? ""
    }

    /// Nombre completo sin los "null" que aparecen cuando falta un apellido.
    var fullName: String {
        [name, apePa, apeMa]
            .filter { !$0.isEmpty && $0.lowercased() != "null" }
            .joined(separator: " ")
    }
}

// MARK: - serviciosListCitas.php

nonisolated struct Quote: Decodable, Equatable, Sendable {
    let id: String
    let folio: String
    let clientID: String
    let contractID: String
    let appointmentDate: String
    let date: String
    let time: String
    let title: String
    let appointmentTime: String
    let description: String
    let endTime: String
    let branchID: String
    let kind: String
    let appointmentKind: String
    let totalMinutes: String
    let cabinNumber: String
    let status: String
    let confirmed: String
    let cabinName: String
    let advisorName: String
    let formattedContracts: String

    private enum CodingKeys: String, CodingKey {
        case id, folio, fecha, hora, title, descri, sucursal, tipo, tipoCita, timeTotal, numCabi, status, confirmada
        case nameCab, nameAse, contratosFormateados, idClien, idContrato, fechaCita, horaCita, horaFinCita
    }

    init(
        id: String = "",
        folio: String = "",
        clientID: String = "",
        contractID: String = "",
        appointmentDate: String = "",
        date: String = "",
        time: String = "",
        title: String = "",
        appointmentTime: String = "",
        description: String = "",
        endTime: String = "",
        branchID: String = "",
        kind: String = "",
        appointmentKind: String = "",
        totalMinutes: String = "",
        cabinNumber: String = "",
        status: String = "",
        confirmed: String = "",
        cabinName: String = "",
        advisorName: String = "",
        formattedContracts: String = ""
    ) {
        self.id = id
        self.folio = folio
        self.clientID = clientID
        self.contractID = contractID
        self.appointmentDate = appointmentDate
        self.date = date
        self.time = time
        self.title = title
        self.appointmentTime = appointmentTime
        self.description = description
        self.endTime = endTime
        self.branchID = branchID
        self.kind = kind
        self.appointmentKind = appointmentKind
        self.totalMinutes = totalMinutes
        self.cabinNumber = cabinNumber
        self.status = status
        self.confirmed = confirmed
        self.cabinName = cabinName
        self.advisorName = advisorName
        self.formattedContracts = formattedContracts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.flexibleString(.id) ?? ""
        folio = container.flexibleString(.folio) ?? ""
        clientID = container.flexibleString(.idClien) ?? ""
        contractID = container.flexibleString(.idContrato) ?? ""
        appointmentDate = container.flexibleString(.fechaCita) ?? ""
        date = container.flexibleString(.fecha) ?? ""
        time = container.flexibleString(.hora) ?? ""
        title = container.flexibleString(.title) ?? ""
        appointmentTime = container.flexibleString(.horaCita) ?? ""
        description = container.flexibleString(.descri) ?? ""
        endTime = container.flexibleString(.horaFinCita) ?? ""
        branchID = container.flexibleString(.sucursal) ?? ""
        kind = container.flexibleString(.tipo) ?? ""
        appointmentKind = container.flexibleString(.tipoCita) ?? ""
        totalMinutes = container.flexibleString(.timeTotal) ?? ""
        cabinNumber = container.flexibleString(.numCabi) ?? ""
        status = container.flexibleString(.status) ?? ""
        confirmed = container.flexibleString(.confirmada) ?? ""
        cabinName = container.flexibleString(.nameCab) ?? ""
        advisorName = container.flexibleString(.nameAse) ?? ""
        formattedContracts = container.flexibleString(.contratosFormateados) ?? ""
    }

    /// En Android `status == "3"` se muestra como "Cancelada".
    var isCancelled: Bool { status == "3" }
}
