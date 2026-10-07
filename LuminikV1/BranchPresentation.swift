import Foundation

extension Branch {
    /// Convierte una sucursal del servidor en el modelo que dibuja la tarjeta.
    ///
    /// El servidor solo manda `id` y `nombre`; el logotipo de texto (`mark`) y el
    /// subtítulo se derivan del nombre para conservar el diseño actual de las
    /// tres sucursales conocidas. Cualquier sucursal nueva se muestra con su nombre.
    init(dto: BranchDTO) {
        let name = dto.name.uppercased()
        let normalized = name.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_MX"))

        if normalized.contains("VALLE ORIENTE") {
            self.init(id: dto.id, name: name, mark: "VO", subtitle: "GALERÍAS VALLE ORIENTE")
        } else if normalized.contains("LA FE") {
            self.init(id: dto.id, name: name, mark: "PASEO | LA FE", subtitle: nil)
        } else if normalized.hasPrefix("PLAZA FIESTA") {
            // "PLAZA FIESTA SAN AGUSTIN" y "PLAZA FIESTA ANAHUAC" comparten logotipo;
            // lo que sobra del nombre distingue una de otra.
            let rest = name.dropFirst("PLAZA FIESTA".count).trimmingCharacters(in: .whitespaces)
            self.init(id: dto.id, name: name, mark: "PLAZA\nFIESTA", subtitle: rest.isEmpty ? nil : rest)
        } else {
            self.init(id: dto.id, name: name, mark: name, subtitle: nil)
        }
    }
}
