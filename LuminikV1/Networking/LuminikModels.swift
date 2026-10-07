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
        /// `serviciosContratoServiMs.php` devuelve la lista como `data` (minúscula).
        case dataLowercase = "data"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = container.flexibleInt(.status) ?? 0
        message = container.flexibleString(.message) ?? ""
        data = (try? container.decodeIfPresent(Payload.self, forKey: .data))
            ?? (try? container.decodeIfPresent(Payload.self, forKey: .dataLowercase))
    }
}

/// Respuesta sin datos útiles (cancelar y guardar cita solo traen `Status` y `Message`).
nonisolated struct EmptyPayload: Decodable, Sendable {}

/// `serviciosFechasDisponible.php` manda las fechas en la llave `"Fechas Disponible"`.
nonisolated struct LuminikDatesEnvelope: Decodable {
    let status: Int
    let message: String
    let dates: [String]

    private enum CodingKeys: String, CodingKey {
        case status = "Status"
        case message = "Message"
        case dates = "Fechas Disponible"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = container.flexibleInt(.status) ?? 0
        message = container.flexibleString(.message) ?? ""
        dates = (try? container.decodeIfPresent([String].self, forKey: .dates)) ?? []
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

// MARK: - serviciosContratosCliente.php (contratos del cliente)

/// Tipo de contrato. El servidor los manda en cuatro listas distintas y Android les
/// pone el nombre y el código `tipoC` que piden los demás servicios.
nonisolated enum ContractKind: String, CaseIterable, Sendable {
    case linfonik = "Linfonik"
    case facial = "Facial"
    case bodySculpts = "BodySculpts"
    case depilacion = "Depilación"

    /// `String.getTipoC()` de Android.
    var serviceTypeCode: String {
        switch self {
        case .depilacion: return "1"
        case .facial: return "2"
        case .linfonik: return "3"
        case .bodySculpts: return "4"
        }
    }
}

nonisolated struct Contract: Equatable, Sendable, Identifiable {
    let id: String
    let folio: String
    let folioExi: String
    let folioComplete: String
    let total: String
    let date: String
    let kind: ContractKind

    init(
        id: String,
        folio: String = "",
        folioExi: String = "",
        folioComplete: String = "",
        total: String = "",
        date: String = "",
        kind: ContractKind
    ) {
        self.id = id
        self.folio = folio
        self.folioExi = folioExi
        self.folioComplete = folioComplete
        self.total = total
        self.date = date
        self.kind = kind
    }

    /// Folio a mostrar: Android usa `folioComple`.
    var displayFolio: String { folioComplete.isEmpty ? folio : folioComplete }
}

/// Elemento crudo de `DataBotox` / `DataFaciales` / `ContraBody` / `DataDepilacion`.
nonisolated struct ContractDTO: Decodable, Equatable, Sendable {
    let id: String
    let folio: String
    let folioExi: String
    let folioComple: String
    let total: String
    let fecha: String

    private enum CodingKeys: String, CodingKey {
        case id, folio, folioExi, folioComple, total, fecha
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.flexibleString(.id) ?? ""
        folio = container.flexibleString(.folio) ?? ""
        folioExi = container.flexibleString(.folioExi) ?? ""
        folioComple = container.flexibleString(.folioComple) ?? ""
        total = container.flexibleString(.total) ?? ""
        fecha = container.flexibleString(.fecha) ?? ""
    }

    func contract(kind: ContractKind) -> Contract {
        Contract(
            id: id,
            folio: folio,
            folioExi: folioExi,
            folioComplete: folioComple,
            total: total,
            date: fecha,
            kind: kind
        )
    }
}

nonisolated struct ContractsResponse: Decodable, Sendable {
    let status: Int
    let message: String
    let linfonik: [ContractDTO]
    let facial: [ContractDTO]
    let bodySculpts: [ContractDTO]
    let depilacion: [ContractDTO]

    private enum CodingKeys: String, CodingKey {
        case status = "Status"
        case message = "Message"
        case linfonik = "DataBotox"
        case facial = "DataFaciales"
        case bodySculpts = "ContraBody"
        case depilacion = "DataDepilacion"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = container.flexibleInt(.status) ?? 0
        message = container.flexibleString(.message) ?? ""
        linfonik = (try? container.decodeIfPresent([ContractDTO].self, forKey: .linfonik)) ?? []
        facial = (try? container.decodeIfPresent([ContractDTO].self, forKey: .facial)) ?? []
        bodySculpts = (try? container.decodeIfPresent([ContractDTO].self, forKey: .bodySculpts)) ?? []
        depilacion = (try? container.decodeIfPresent([ContractDTO].self, forKey: .depilacion)) ?? []
    }

    /// Mismo orden que Android: Linfonik, Facial, BodySculpts y Depilación.
    var contracts: [Contract] {
        linfonik.map { $0.contract(kind: .linfonik) }
            + facial.map { $0.contract(kind: .facial) }
            + bodySculpts.map { $0.contract(kind: .bodySculpts) }
            + depilacion.map { $0.contract(kind: .depilacion) }
    }
}

// MARK: - serviciosContratoServiMs.php (servicios de un contrato)

nonisolated struct ContractService: Decodable, Equatable, Hashable, Sendable {
    let idServiContra: String
    let folio: String
    let id: String
    let idServi: String
    let descri: String
    let citas: String
    let idArea: String
    let area: String
    let timeNor: String
    let timeCam: String
    let timeExt: String
    let cance: String
    let timesp: String
    let tipCont: String
    let nombreCli: String
    let sevaloro: String
    let bancitavalo: String
    /// No viene en el JSON: la app lo agrega al elegir el contrato (igual que Android).
    var contractID: String

    private enum CodingKeys: String, CodingKey {
        case idServiContra, folio, id, idServi, descri, citas, idArea, area, timeNor, timeCam, timeExt
        case cance, timesp, tipCont, nombreCli, sevaloro, bancitavalo
    }

    init(
        idServiContra: String,
        folio: String = "",
        id: String = "",
        idServi: String = "",
        descri: String = "",
        citas: String = "",
        idArea: String = "",
        area: String = "",
        timeNor: String = "",
        timeCam: String = "",
        timeExt: String = "",
        cance: String = "",
        timesp: String = "",
        tipCont: String = "",
        nombreCli: String = "",
        sevaloro: String = "",
        bancitavalo: String = "",
        contractID: String = ""
    ) {
        self.idServiContra = idServiContra
        self.folio = folio
        self.id = id
        self.idServi = idServi
        self.descri = descri
        self.citas = citas
        self.idArea = idArea
        self.area = area
        self.timeNor = timeNor
        self.timeCam = timeCam
        self.timeExt = timeExt
        self.cance = cance
        self.timesp = timesp
        self.tipCont = tipCont
        self.nombreCli = nombreCli
        self.sevaloro = sevaloro
        self.bancitavalo = bancitavalo
        self.contractID = contractID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        idServiContra = container.flexibleString(.idServiContra) ?? ""
        folio = container.flexibleString(.folio) ?? ""
        id = container.flexibleString(.id) ?? ""
        idServi = container.flexibleString(.idServi) ?? ""
        descri = container.flexibleString(.descri) ?? ""
        citas = container.flexibleString(.citas) ?? ""
        idArea = container.flexibleString(.idArea) ?? ""
        area = container.flexibleString(.area) ?? ""
        timeNor = container.flexibleString(.timeNor) ?? ""
        timeCam = container.flexibleString(.timeCam) ?? ""
        timeExt = container.flexibleString(.timeExt) ?? ""
        cance = container.flexibleString(.cance) ?? ""
        timesp = container.flexibleString(.timesp) ?? ""
        tipCont = container.flexibleString(.tipCont) ?? ""
        nombreCli = container.flexibleString(.nombreCli) ?? ""
        sevaloro = container.flexibleString(.sevaloro) ?? ""
        bancitavalo = container.flexibleString(.bancitavalo) ?? ""
        contractID = ""
    }

    func with(contractID: String) -> ContractService {
        var copy = self
        copy.contractID = contractID
        return copy
    }

    /// Minutos normales del servicio (`timeNor`).
    var normalMinutes: Int { Int(timeNor) ?? 0 }
    /// Citas ya realizadas (`citas`).
    var completedAppointments: Int { Int(citas) ?? 0 }
    var valuationBlocked: Bool { (Int(bancitavalo) ?? 0) == 0 }

    /// Texto de la lista: Android muestra `descri-nombreCli`.
    var displayName: String {
        nombreCli.isEmpty ? descri : "\(descri)-\(nombreCli)"
    }
}

// MARK: - serviciosCitasServis.php (servicios de una cita)

nonisolated struct QuoteService: Decodable, Equatable, Sendable {
    let id: String
    let folio: String
    let idServi: String
    let sucursal: String
    let idCliente: String
    let idContrato: String
    let horaCita: String
    let tipo: String
    let fechaCita: String
    let fecha: String
    let hora: String
    let status: String
    let descri: String
    let confirmada: String

    private enum CodingKeys: String, CodingKey {
        case id, folio, idServi, sucursal, idCliente, idContrato, horaCita, tipo, fechaCita, fecha, hora
        case status, descri, confirmada
    }

    init(
        id: String = "",
        folio: String = "",
        idServi: String = "",
        sucursal: String = "",
        idCliente: String = "",
        idContrato: String = "",
        horaCita: String = "",
        tipo: String = "",
        fechaCita: String = "",
        fecha: String = "",
        hora: String = "",
        status: String = "",
        descri: String = "",
        confirmada: String = ""
    ) {
        self.id = id
        self.folio = folio
        self.idServi = idServi
        self.sucursal = sucursal
        self.idCliente = idCliente
        self.idContrato = idContrato
        self.horaCita = horaCita
        self.tipo = tipo
        self.fechaCita = fechaCita
        self.fecha = fecha
        self.hora = hora
        self.status = status
        self.descri = descri
        self.confirmada = confirmada
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.flexibleString(.id) ?? ""
        folio = container.flexibleString(.folio) ?? ""
        idServi = container.flexibleString(.idServi) ?? ""
        sucursal = container.flexibleString(.sucursal) ?? ""
        idCliente = container.flexibleString(.idCliente) ?? ""
        idContrato = container.flexibleString(.idContrato) ?? ""
        horaCita = container.flexibleString(.horaCita) ?? ""
        tipo = container.flexibleString(.tipo) ?? ""
        fechaCita = container.flexibleString(.fechaCita) ?? ""
        fecha = container.flexibleString(.fecha) ?? ""
        hora = container.flexibleString(.hora) ?? ""
        status = container.flexibleString(.status) ?? ""
        descri = container.flexibleString(.descri) ?? ""
        confirmada = container.flexibleString(.confirmada) ?? ""
    }
}

// MARK: - serviciosContratosCliente.php con `idCita` (LUMServicesQuotesData en Android)

nonisolated struct QuoteContractService: Decodable, Equatable, Sendable {
    let id: String
    let folio: String
    let idServi: String
    let sucursal: String
    let idClien: String
    let idContrato: String
    let tipo: String
    let tipoCita: String
    let descri: String

    private enum CodingKeys: String, CodingKey {
        case id, folio, idServi, sucursal, idClien, idContrato, tipo, tipoCita, descri
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.flexibleString(.id) ?? ""
        folio = container.flexibleString(.folio) ?? ""
        idServi = container.flexibleString(.idServi) ?? ""
        sucursal = container.flexibleString(.sucursal) ?? ""
        idClien = container.flexibleString(.idClien) ?? ""
        idContrato = container.flexibleString(.idContrato) ?? ""
        tipo = container.flexibleString(.tipo) ?? ""
        tipoCita = container.flexibleString(.tipoCita) ?? ""
        descri = container.flexibleString(.descri) ?? ""
    }
}

// MARK: - serviciosCabinas.php

nonisolated struct Cabin: Decodable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let nurse: String
    let advisorName: String

    private enum CodingKeys: String, CodingKey {
        case id
        case name = "nameCab"
        case nurse = "enfermera"
        case advisorName = "nameAse"
    }

    init(id: String, name: String, nurse: String = "", advisorName: String = "") {
        self.id = id
        self.name = name
        self.nurse = nurse
        self.advisorName = advisorName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.flexibleString(.id) ?? ""
        name = container.flexibleString(.name) ?? ""
        nurse = container.flexibleString(.nurse) ?? ""
        advisorName = container.flexibleString(.advisorName) ?? ""
    }
}

// MARK: - Peticiones con muchos parámetros

/// Parámetros de `serviciosFechasDisponible.php`. Las listas viajan separadas por comas.
nonisolated struct AvailableDatesRequest: Equatable, Sendable {
    let contractIDs: [String]
    let contractTypeCodes: [String]
    let clientWeight: String
    let cabinID: String
    let clientID: String
    let branchID: String
    let durationMinutes: Int
    /// En el servidor `tipcita == "1"` significa cita de valoración.
    let isValuation: Bool
    let serviceIDs: [String]
}

/// Parámetros de `serviciosguardarcita.php`.
nonisolated struct SaveQuoteRequest: Equatable, Sendable {
    let clientID: String
    let contractIDs: [String]
    /// `dd-MM-yyyy`
    let date: String
    let time: String
    let notes: String
    let branchID: String
    let contractTypeCodes: [String]
    let isValuation: Bool
    let durationMinutes: Int
    let cabinID: String
    let serviceIDs: [String]
}
