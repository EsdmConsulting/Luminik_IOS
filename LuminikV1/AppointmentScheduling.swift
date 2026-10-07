import UIKit

// MARK: - Modelo del flujo de agendar

/// Tipo de cita. En Android es `tipoCita`: 10 = sin servicios, 0 = valoración, 1 = normal.
enum AppointmentKind: Equatable {
    case none
    case valuation
    case normal
}

enum ServiceToggleResult: Equatable {
    case added
    case removed
    /// No se pueden mezclar servicios de valoración y normales en la misma cita.
    case conflict
}

enum ScheduleError: LocalizedError, Equatable {
    case incomplete
    /// La cita nueva se guardó, pero no se pudo cancelar la anterior (reagendar).
    case previousQuoteNotCancelled

    var errorDescription: String? {
        switch self {
        case .incomplete:
            return "Faltan datos para agendar la cita."
        case .previousQuoteNotCancelled:
            return "Tu cita nueva quedó agendada, pero no pudimos cancelar la anterior. Cancélala desde Mis citas."
        }
    }
}

/// Estado de la cita que se está armando. Aquí vive la lógica que en Android está en
/// `MyQuotesViewModel` (`updateService`, `updateCabinObs`, `getDatesQuotesList`, `getSaveQuote`).
@MainActor
final class AppointmentDraft {
    let session: UserSession
    let service: LuminikServicing

    private(set) var contracts: [Contract] = []
    private(set) var selectedContracts: [Contract] = []
    private(set) var selectedServices: [ContractService] = []
    private(set) var kind: AppointmentKind = .none

    var cabin: Cabin?
    var notes = ""
    /// `dd-MM-yyyy`, igual que lo manda y lo espera el servidor.
    var date = ""
    var time = ""

    /// Citas vigentes del cliente: sirven para no ofrecer servicios que ya están agendados.
    private var upcomingQuotes: [Quote] = []
    private var servicesByContract: [String: [ContractService]] = [:]

    // Reagendar: se guardan los datos de la cita original (Android: `dataRescheduleQuotes`).
    private(set) var replacing: Quote?
    private var replacingTypeCode = ""
    private var replacingMinutes = 0

    init(session: UserSession, service: LuminikServicing = LuminikAPI()) {
        self.session = session
        self.service = service
    }

    // MARK: Contratos y servicios

    func loadContracts() async throws {
        let service = self.service
        let branchID = session.branchID
        let clientID = session.userID
        async let contractsRequest = service.fetchContracts(branchID: branchID, clientID: clientID)
        async let quotesRequest = service.fetchQuotes(branchID: branchID, clientID: clientID)
        contracts = try await contractsRequest
        upcomingQuotes = (try? await quotesRequest) ?? []
    }

    /// Servicios de un contrato que todavía se pueden agendar.
    func loadServices(for contract: Contract) async throws -> [ContractService] {
        let all = try await service.fetchContractServices(
            branchID: session.branchID,
            contractTypeCode: contract.kind.serviceTypeCode,
            contractID: contract.id,
            clientID: session.userID
        )
        let scheduled = await scheduledServiceIDs(forContract: contract.id)
        return all.filter { !scheduled.contains($0.idServiContra) }
    }

    /// Android compara contra los servicios de las citas que ya incluyen el contrato.
    private func scheduledServiceIDs(forContract contractID: String) async -> Set<String> {
        let quotes = upcomingQuotes.filter { quote in
            !quote.isCancelled && quote.contractID.split(separator: ",").contains { $0 == Substring(contractID) }
        }
        var ids = Set<String>()
        for quote in quotes {
            if let services = try? await service.fetchQuoteServices(quoteID: quote.id) {
                ids.formUnion(services.map(\.idServi))
            }
        }
        return ids
    }

    func isSelected(_ contract: Contract) -> Bool {
        selectedContracts.contains { $0.id == contract.id }
    }

    func isSelected(_ service: ContractService) -> Bool {
        selectedServices.contains(service)
    }

    func select(_ contract: Contract, services: [ContractService]) {
        guard !isSelected(contract) else { return }
        selectedContracts.append(contract)
        servicesByContract[contract.id] = services.map { $0.with(contractID: contract.id) }
    }

    func deselect(_ contract: Contract) {
        selectedContracts.removeAll { $0.id == contract.id }
        servicesByContract[contract.id] = nil
        selectedServices.removeAll { $0.contractID == contract.id }
        if selectedServices.isEmpty { kind = .none }
    }

    var availableServices: [ContractService] {
        selectedContracts.flatMap { servicesByContract[$0.id] ?? [] }
    }

    /// Reglas de `MyQuotesViewModel.updateService` de Android.
    func toggle(_ service: ContractService) -> ServiceToggleResult {
        if let index = selectedServices.firstIndex(of: service) {
            selectedServices.remove(at: index)
            if selectedServices.isEmpty { kind = .none }
            return .removed
        }

        if ["2", "3", "4"].contains(service.tipCont) || service.sevaloro == "1" {
            // Facial, Linfonik y BodySculpts (tipCont 2, 3 y 4) y los servicios marcados con
            // `sevaloro` solo pueden ir en citas normales.
            if kind == .valuation { return .conflict }
            kind = .normal
        } else if service.tipCont == "1" {
            // Depilación: con 7 citas o más y sin cita de valoración previa, toca valoración.
            let needsValuation = service.completedAppointments >= 7 && service.valuationBlocked
            if kind == .valuation && !needsValuation { return .conflict }
            if kind == .normal && needsValuation { return .conflict }
            kind = needsValuation ? .valuation : .normal
        } else {
            // Tipo desconocido: Android no hace nada; aquí se trata como cita normal.
            if kind == .valuation { return .conflict }
            kind = .normal
        }
        selectedServices.append(service)
        return .added
    }

    // MARK: Reagendar

    func prepareReschedule(quote: Quote, services: [QuoteService]) {
        replacing = quote
        replacingTypeCode = quote.kind
        replacingMinutes = Int(quote.totalMinutes) ?? 0
        // En el servidor `tipoCita != 0` es valoración.
        kind = (Int(quote.appointmentKind) ?? 0) == 0 ? .normal : .valuation
        cabin = Cabin(id: quote.cabinNumber, name: quote.cabinName)
        notes = quote.title

        var seen = Set<String>()
        selectedServices = services.compactMap { item in
            guard seen.insert(item.idServi).inserted else { return nil }
            return ContractService(idServiContra: item.idServi, descri: item.descri, contractID: item.idContrato)
        }
    }

    // MARK: Datos para el servidor

    var isValuation: Bool { kind == .valuation }

    var totalMinutes: Int {
        if replacing != nil { return replacingMinutes }
        // Android: las valoraciones duran 5 minutos.
        if kind == .valuation { return 5 }
        return selectedServices.reduce(0) { $0 + $1.normalMinutes }
    }

    var contractIDs: [String] {
        if replacing != nil { return Self.distinct(selectedServices.map(\.contractID)) }
        return selectedContracts.map(\.id)
    }

    var contractTypeCodes: [String] {
        if replacing != nil { return [replacingTypeCode] }
        return selectedContracts.map { $0.kind.serviceTypeCode }
    }

    var serviceIDs: [String] {
        Self.distinct(selectedServices.map(\.idServiContra))
    }

    var kindTitle: String {
        kind == .valuation ? "VALORACIÓN" : "NORMAL"
    }

    private static func distinct(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    func makeDatesRequest() -> AvailableDatesRequest? {
        guard let cabin, !cabin.id.isEmpty else { return nil }
        return AvailableDatesRequest(
            contractIDs: contractIDs,
            contractTypeCodes: contractTypeCodes,
            clientWeight: session.weight,
            cabinID: cabin.id,
            clientID: session.userID,
            branchID: session.branchID,
            durationMinutes: totalMinutes,
            isValuation: isValuation,
            serviceIDs: serviceIDs
        )
    }

    func makeSaveRequest() -> SaveQuoteRequest? {
        guard let cabin, !cabin.id.isEmpty, !date.isEmpty, !time.isEmpty, !selectedServices.isEmpty else { return nil }
        return SaveQuoteRequest(
            clientID: session.userID,
            contractIDs: contractIDs,
            date: date,
            time: time,
            notes: notes,
            branchID: session.branchID,
            contractTypeCodes: contractTypeCodes,
            isValuation: isValuation,
            durationMinutes: totalMinutes,
            cabinID: cabin.id,
            serviceIDs: serviceIDs
        )
    }

    /// Guarda la cita. Si se estaba reagendando, cancela después la cita anterior:
    /// así, si el usuario abandona el flujo o falla el guardado, no se pierde la cita original.
    func save() async throws {
        guard let request = makeSaveRequest() else { throw ScheduleError.incomplete }
        try await service.saveQuote(request)

        if let previous = replacing {
            do {
                try await service.cancelQuote(
                    quoteID: previous.id,
                    clientID: session.userID,
                    branchID: session.branchID,
                    contractID: previous.contractID
                )
            } catch {
                NotificationCenter.default.post(name: .luminikAppointmentsDidChange, object: nil)
                throw ScheduleError.previousQuoteNotCancelled
            }
        }
        NotificationCenter.default.post(name: .luminikAppointmentsDidChange, object: nil)
    }
}

// MARK: - Paso 1: contratos y servicios

final class ScheduleSelectionViewController: UIViewController {
    private let draft: AppointmentDraft
    private let contractsStack = UIStackView()
    private let servicesStack = UIStackView()
    private let confirmButton = UIButton(type: .system)
    private var loadingContractIDs = Set<String>()
    private var didLoadContracts = false

    init(draft: AppointmentDraft) {
        self.draft = draft
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        loadContracts()
    }

    private func configureView() {
        view.backgroundColor = LuminikStyle.background

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.spacing = 26
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        let back = UIButton(type: .system)
        back.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        back.tintColor = .white
        back.contentHorizontalAlignment = .leading
        back.accessibilityLabel = "Volver a inicio"
        back.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)

        let title = makeLabel("AGENDAR\nPRÓXIMA CITA", style: .largeTitle, color: .white, alignment: .center)
        let header = UIStackView(arrangedSubviews: [back, title])
        header.axis = .vertical
        header.spacing = 2
        header.layoutMargins = UIEdgeInsets(top: 10, left: 18, bottom: 20, right: 18)
        header.isLayoutMarginsRelativeArrangement = true
        header.backgroundColor = .black
        contentStack.addArrangedSubview(header)

        contentStack.addArrangedSubview(makeLabel("CONTRATOS", style: .largeTitle, alignment: .center))

        let contractsScroll = UIScrollView()
        contractsScroll.showsHorizontalScrollIndicator = false
        contractsScroll.translatesAutoresizingMaskIntoConstraints = false
        contractsScroll.heightAnchor.constraint(equalToConstant: 112).isActive = true
        contractsStack.axis = .horizontal
        contractsStack.spacing = 12
        contractsStack.translatesAutoresizingMaskIntoConstraints = false
        contractsScroll.addSubview(contractsStack)
        NSLayoutConstraint.activate([
            contractsStack.topAnchor.constraint(equalTo: contractsScroll.contentLayoutGuide.topAnchor),
            contractsStack.leadingAnchor.constraint(equalTo: contractsScroll.contentLayoutGuide.leadingAnchor, constant: 8),
            contractsStack.trailingAnchor.constraint(equalTo: contractsScroll.contentLayoutGuide.trailingAnchor, constant: -8),
            contractsStack.bottomAnchor.constraint(equalTo: contractsScroll.contentLayoutGuide.bottomAnchor),
            contractsStack.heightAnchor.constraint(equalTo: contractsScroll.frameLayoutGuide.heightAnchor)
        ])
        contentStack.addArrangedSubview(contractsScroll)

        contentStack.addArrangedSubview(makeLabel("SERVICIOS", style: .largeTitle, alignment: .center))
        servicesStack.axis = .vertical
        servicesStack.spacing = 16
        servicesStack.layoutMargins = UIEdgeInsets(top: 0, left: 22, bottom: 0, right: 22)
        servicesStack.isLayoutMarginsRelativeArrangement = true
        contentStack.addArrangedSubview(servicesStack)

        var configuration = UIButton.Configuration.plain()
        configuration.title = "CONFIRMAR"
        configuration.baseForegroundColor = .white
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 24, leading: 20, bottom: 24, trailing: 20)
        confirmButton.configuration = configuration
        confirmButton.titleLabel?.font = LuminikStyle.serifFont(textStyle: .largeTitle)
        confirmButton.backgroundColor = .black
        confirmButton.accessibilityIdentifier = "schedule.confirmSelection"
        confirmButton.addAction(UIAction { [weak self] _ in self?.confirmSelection() }, for: .touchUpInside)
        contentStack.addArrangedSubview(confirmButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        refreshConfirmButton()
    }

    // MARK: Carga

    private func loadContracts() {
        didLoadContracts = false
        contractsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.startAnimating()
        spinner.accessibilityLabel = "Cargando contratos"
        servicesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        servicesStack.addArrangedSubview(spinner)

        Task { [weak self] in
            guard let self else { return }
            do {
                try await draft.loadContracts()
                didLoadContracts = true
                rebuildContracts()
                rebuildServices()
            } catch is CancellationError {
                return
            } catch {
                showLoadFailure(error.localizedDescription)
            }
        }
    }

    private func showLoadFailure(_ message: String) {
        servicesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        servicesStack.addArrangedSubview(makeLabel(message, style: .body, color: .secondaryLabel, alignment: .center))

        var configuration = UIButton.Configuration.filled()
        configuration.title = "Reintentar"
        configuration.baseBackgroundColor = LuminikStyle.blue
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .fixed
        let retry = UIButton(configuration: configuration)
        retry.accessibilityIdentifier = "schedule.retry"
        retry.addAction(UIAction { [weak self] _ in self?.loadContracts() }, for: .touchUpInside)
        servicesStack.addArrangedSubview(retry)
        UIAccessibility.post(notification: .announcement, argument: message)
        refreshConfirmButton()
    }

    // MARK: Pintado

    private func rebuildContracts() {
        contractsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for contract in draft.contracts {
            let selected = draft.isSelected(contract)
            let loading = loadingContractIDs.contains(contract.id)
            let button = UIButton(type: .system)
            var configuration = UIButton.Configuration.filled()
            configuration.title = "FOLIO: \(contract.displayFolio)\nTIPO: \(contract.kind.rawValue.uppercased())"
            configuration.image = UIImage(systemName: selected ? "checkmark.square.fill" : "list.clipboard")
            configuration.imagePlacement = .leading
            configuration.imagePadding = 12
            configuration.showsActivityIndicator = loading
            configuration.baseBackgroundColor = selected ? LuminikStyle.blue : .secondarySystemBackground
            configuration.baseForegroundColor = selected ? .white : .label
            configuration.cornerStyle = .large
            button.configuration = configuration
            button.titleLabel?.font = LuminikStyle.serifFont(textStyle: .body)
            button.titleLabel?.numberOfLines = 2
            button.isEnabled = !loading
            button.widthAnchor.constraint(equalToConstant: 250).isActive = true
            button.accessibilityIdentifier = "schedule.contract.\(contract.id)"
            button.accessibilityValue = selected ? "Seleccionado" : "No seleccionado"
            button.addAction(UIAction { [weak self] _ in self?.toggleContract(contract) }, for: .touchUpInside)
            contractsStack.addArrangedSubview(button)
        }
    }

    private func rebuildServices() {
        servicesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if draft.contracts.isEmpty && didLoadContracts {
            servicesStack.addArrangedSubview(makeLabel("No tienes contratos para agendar.", style: .body, alignment: .center))
        } else if draft.selectedContracts.isEmpty {
            servicesStack.addArrangedSubview(makeLabel("Selecciona uno o varios contratos para ver sus servicios.", style: .body, alignment: .center))
        } else if draft.availableServices.isEmpty {
            servicesStack.addArrangedSubview(makeLabel("Los servicios de estos contratos ya están agendados.", style: .body, alignment: .center))
        } else {
            for service in draft.availableServices {
                let selected = draft.isSelected(service)
                let button = UIButton(type: .system)
                var configuration = UIButton.Configuration.plain()
                configuration.title = "\(service.displayName)\nTIEMPO ESTIMADO: \(service.normalMinutes) MIN."
                configuration.image = UIImage(systemName: selected ? "checkmark.square.fill" : "square")
                configuration.imagePlacement = .leading
                configuration.imagePadding = 14
                configuration.baseForegroundColor = .label
                configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0)
                button.configuration = configuration
                button.tintColor = LuminikStyle.blue
                button.titleLabel?.font = LuminikStyle.serifFont(textStyle: .body)
                button.titleLabel?.numberOfLines = 3
                button.contentHorizontalAlignment = .leading
                button.accessibilityIdentifier = "schedule.service.\(service.idServiContra)"
                button.accessibilityValue = selected ? "Seleccionado" : "No seleccionado"
                button.addAction(UIAction { [weak self] _ in self?.toggleService(service) }, for: .touchUpInside)
                servicesStack.addArrangedSubview(button)
            }
        }
        refreshConfirmButton()
    }

    private func refreshConfirmButton() {
        confirmButton.isEnabled = !draft.selectedServices.isEmpty
        confirmButton.alpha = confirmButton.isEnabled ? 1 : 0.45
    }

    // MARK: Acciones

    private func toggleContract(_ contract: Contract) {
        if draft.isSelected(contract) {
            draft.deselect(contract)
            rebuildContracts()
            rebuildServices()
            return
        }

        guard !loadingContractIDs.contains(contract.id) else { return }
        loadingContractIDs.insert(contract.id)
        rebuildContracts()

        Task { [weak self] in
            guard let self else { return }
            do {
                let services = try await draft.loadServices(for: contract)
                loadingContractIDs.remove(contract.id)
                draft.select(contract, services: services)
            } catch is CancellationError {
                loadingContractIDs.remove(contract.id)
            } catch {
                loadingContractIDs.remove(contract.id)
                showAlert("No se pudieron cargar los servicios", error.localizedDescription)
            }
            rebuildContracts()
            rebuildServices()
        }
    }

    private func toggleService(_ service: ContractService) {
        if draft.toggle(service) == .conflict {
            showAlert("No se puede agregar", LuminikText.valuationMixError)
        }
        rebuildServices()
    }

    private func confirmSelection() {
        guard !draft.selectedServices.isEmpty else {
            showAlert("Incorrecto", "Debes seleccionar al menos un servicio")
            return
        }
        if draft.kind == .valuation {
            let alert = UIAlertController(title: "¡VALORACIÓN!", message: LuminikText.valuationNotice, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Aceptar", style: .default) { [weak self] _ in self?.showCabinModal() })
            present(alert, animated: true)
        } else {
            showCabinModal()
        }
    }

    private func showCabinModal() {
        let modal = CabinSelectionViewController(draft: draft) { [weak self] in
            guard let self else { return }
            self.dismiss(animated: true) {
                let calendar = ScheduleCalendarViewController(draft: self.draft)
                calendar.modalPresentationStyle = .fullScreen
                self.present(calendar, animated: true)
            }
        }
        modal.modalPresentationStyle = .overFullScreen
        modal.modalTransitionStyle = .crossDissolve
        present(modal, animated: true)
    }

    private func showAlert(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Aceptar", style: .default))
        present(alert, animated: true)
    }

    private func makeLabel(_ text: String, style: UIFont.TextStyle, color: UIColor = .label, alignment: NSTextAlignment = .natural) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = LuminikStyle.serifFont(textStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.textAlignment = alignment
        label.numberOfLines = 0
        return label
    }
}

// MARK: - Paso 2: cabina y observaciones

private final class CabinSelectionViewController: UIViewController {
    private let draft: AppointmentDraft
    private let onAccept: () -> Void
    private let cabinButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let notesField = UITextField()
    private let acceptButton = UIButton(type: .system)
    private var cabins: [Cabin] = []

    init(draft: AppointmentDraft, onAccept: @escaping () -> Void) {
        self.draft = draft
        self.onAccept = onAccept
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        loadCabins()
    }

    private func configureView() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        let card = UIStackView()
        card.axis = .vertical
        card.spacing = 20
        card.layoutMargins = UIEdgeInsets(top: 34, left: 28, bottom: 24, right: 28)
        card.isLayoutMarginsRelativeArrangement = true
        card.backgroundColor = .systemBackground
        card.layer.cornerRadius = 16
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        let title = UILabel()
        title.text = "CABINA"
        title.font = LuminikStyle.serifFont(textStyle: .largeTitle)
        title.textAlignment = .center
        card.addArrangedSubview(title)

        var cabinConfiguration = UIButton.Configuration.gray()
        cabinConfiguration.title = "Cargando cabinas…"
        cabinConfiguration.image = UIImage(systemName: "chevron.down")
        cabinConfiguration.imagePlacement = .trailing
        cabinConfiguration.baseForegroundColor = .label
        cabinConfiguration.showsActivityIndicator = true
        cabinConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 14, bottom: 16, trailing: 14)
        cabinButton.configuration = cabinConfiguration
        cabinButton.contentHorizontalAlignment = .fill
        cabinButton.isEnabled = false
        cabinButton.accessibilityIdentifier = "schedule.cabin"
        card.addArrangedSubview(cabinButton)

        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = .systemRed
        statusLabel.numberOfLines = 0
        statusLabel.isHidden = true
        card.addArrangedSubview(statusLabel)

        let notesLabel = UILabel()
        notesLabel.text = "OBSERVACIONES"
        notesLabel.font = LuminikStyle.serifFont(textStyle: .body)
        notesLabel.textColor = .secondaryLabel
        card.addArrangedSubview(notesLabel)

        notesField.placeholder = "Observaciones opcionales"
        notesField.text = draft.notes
        notesField.borderStyle = .roundedRect
        notesField.font = .preferredFont(forTextStyle: .body)
        notesField.accessibilityIdentifier = "schedule.notes"
        notesField.heightAnchor.constraint(equalToConstant: 52).isActive = true
        card.addArrangedSubview(notesField)

        let actions = UIStackView()
        actions.axis = .horizontal
        actions.distribution = .fillEqually
        let cancel = UIButton(type: .system)
        cancel.setTitle("CANCELAR", for: .normal)
        cancel.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        acceptButton.setTitle("ACEPTAR", for: .normal)
        acceptButton.accessibilityIdentifier = "schedule.acceptCabin"
        acceptButton.addAction(UIAction { [weak self] _ in self?.accept() }, for: .touchUpInside)
        actions.addArrangedSubview(cancel)
        actions.addArrangedSubview(acceptButton)
        card.addArrangedSubview(actions)

        NSLayoutConstraint.activate([
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36)
        ])
    }

    private func loadCabins() {
        statusLabel.isHidden = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let cabins = try await draft.service.fetchCabins(branchID: draft.session.branchID)
                self.cabins = cabins.filter { !$0.id.isEmpty }
                showCabins()
            } catch is CancellationError {
                return
            } catch {
                showCabinsFailure(error.localizedDescription)
            }
        }
    }

    private func showCabins() {
        guard !cabins.isEmpty else {
            showCabinsFailure("No hay cabinas disponibles en esta sucursal.")
            return
        }
        cabinButton.configuration?.showsActivityIndicator = false
        cabinButton.configuration?.title = draft.cabin?.name ?? "Seleccionar cabina"
        cabinButton.isEnabled = true
        cabinButton.menu = UIMenu(children: cabins.map { cabin in
            UIAction(title: cabin.name) { [weak self] _ in self?.selectCabin(cabin) }
        })
        cabinButton.showsMenuAsPrimaryAction = true
    }

    private func showCabinsFailure(_ message: String) {
        cabinButton.configuration?.showsActivityIndicator = false
        cabinButton.configuration?.title = "Seleccionar cabina"
        cabinButton.isEnabled = true
        cabinButton.menu = UIMenu(children: [
            UIAction(title: "Reintentar", image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in
                self?.cabinButton.isEnabled = false
                self?.cabinButton.configuration?.showsActivityIndicator = true
                self?.loadCabins()
            }
        ])
        cabinButton.showsMenuAsPrimaryAction = true
        statusLabel.text = message
        statusLabel.isHidden = false
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private func selectCabin(_ cabin: Cabin) {
        draft.cabin = cabin
        cabinButton.configuration?.title = cabin.name
        cabinButton.configuration?.baseForegroundColor = .label
    }

    private func accept() {
        guard draft.cabin != nil else {
            cabinButton.configuration?.baseForegroundColor = .systemRed
            UIAccessibility.post(notification: .announcement, argument: "Selecciona una cabina")
            return
        }
        draft.notes = notesField.text ?? ""
        onAccept()
    }
}

// MARK: - Paso 3: fecha y hora

/// Los formatos de fecha del servidor (`dd-MM-yyyy`).
private enum ScheduleDateFormat {
    static func formatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd-MM-yyyy"
        return formatter
    }
}

final class ScheduleCalendarViewController: UIViewController {
    private let draft: AppointmentDraft
    private let datePicker = UIDatePicker()
    private let slotsStack = UIStackView()
    private let statusStack = UIStackView()
    private var availableDates = Set<String>()
    private var hoursTask: Task<Void, Never>?

    init(draft: AppointmentDraft) {
        self.draft = draft
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        loadDates()
    }

    private func configureView() {
        view.backgroundColor = LuminikStyle.background
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 22
        stack.layoutMargins = UIEdgeInsets(top: 16, left: 26, bottom: 30, right: 26)
        stack.isLayoutMarginsRelativeArrangement = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        let back = UIButton(type: .system)
        back.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        back.contentHorizontalAlignment = .leading
        back.accessibilityLabel = "Volver"
        back.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        stack.addArrangedSubview(back)

        let title = UILabel()
        title.text = "SELECCIONA FECHA Y HORA"
        title.font = LuminikStyle.serifFont(textStyle: .title1)
        title.textAlignment = .center
        title.numberOfLines = 0
        stack.addArrangedSubview(title)

        datePicker.datePickerMode = .date
        datePicker.preferredDatePickerStyle = .inline
        datePicker.minimumDate = Calendar.current.startOfDay(for: Date())
        datePicker.locale = Locale(identifier: "es_MX")
        datePicker.addTarget(self, action: #selector(dateChanged), for: .valueChanged)
        datePicker.accessibilityIdentifier = "schedule.date"
        datePicker.isHidden = true
        stack.addArrangedSubview(datePicker)

        let duration = UILabel()
        duration.text = "TIEMPO CITA: \(draft.totalMinutes) MIN."
        duration.font = LuminikStyle.serifFont(textStyle: .title2, weight: .semibold)
        stack.addArrangedSubview(duration)

        statusStack.axis = .vertical
        statusStack.spacing = 12
        stack.addArrangedSubview(statusStack)

        slotsStack.axis = .vertical
        slotsStack.spacing = 12
        stack.addArrangedSubview(slotsStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    // MARK: Fechas disponibles

    private func loadDates() {
        guard let request = draft.makeDatesRequest() else {
            showStatus("Faltan datos para buscar fechas. Regresa y elige la cabina.", retry: nil)
            return
        }
        slotsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        datePicker.isHidden = true
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.startAnimating()
        spinner.accessibilityLabel = "Cargando fechas disponibles"
        setStatusViews([spinner])

        Task { [weak self] in
            guard let self else { return }
            do {
                let dates = try await draft.service.fetchAvailableDates(request)
                applyDates(dates)
            } catch is CancellationError {
                return
            } catch {
                showStatus(error.localizedDescription) { [weak self] in self?.loadDates() }
            }
        }
    }

    private func applyDates(_ dates: [String]) {
        let formatter = ScheduleDateFormat.formatter()
        let parsed = dates.compactMap { formatter.date(from: $0) }.sorted()
        availableDates = Set(parsed.map { formatter.string(from: $0) })

        let today = Calendar.current.startOfDay(for: Date())
        guard let first = parsed.first, let last = parsed.last, last >= today else {
            showStatus("No hay fechas disponibles para esta cita. Intenta con otra cabina o más tarde.", retry: nil)
            return
        }

        datePicker.minimumDate = max(first, today)
        datePicker.maximumDate = last
        datePicker.date = max(first, today)
        datePicker.isHidden = false
        setStatusViews([])
        dateChanged()
    }

    @objc private func dateChanged() {
        let key = ScheduleDateFormat.formatter().string(from: datePicker.date)
        draft.date = key
        draft.time = ""
        hoursTask?.cancel()
        slotsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        guard availableDates.contains(key) else {
            setStatusViews([statusLabel("No hay horarios disponibles para este día.")])
            return
        }
        loadHours(for: key)
    }

    // MARK: Horarios

    private func loadHours(for date: String) {
        guard let cabin = draft.cabin else { return }
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.startAnimating()
        spinner.accessibilityLabel = "Cargando horarios"
        setStatusViews([spinner])

        hoursTask = Task { [weak self] in
            guard let self else { return }
            do {
                let hours = try await draft.service.fetchAvailableHours(
                    cabinID: cabin.id,
                    branchID: draft.session.branchID,
                    totalMinutes: draft.totalMinutes,
                    date: date
                )
                guard !Task.isCancelled, draft.date == date else { return }
                showSlots(hours)
            } catch is CancellationError {
                return
            } catch {
                guard draft.date == date else { return }
                showStatus(error.localizedDescription) { [weak self] in self?.loadHours(for: date) }
            }
        }
    }

    private func showSlots(_ hours: [String]) {
        slotsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard !hours.isEmpty else {
            setStatusViews([statusLabel("No hay horarios disponibles para este día.")])
            return
        }
        setStatusViews([])

        for pairStart in stride(from: 0, to: hours.count, by: 3) {
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .fillEqually
            row.spacing = 12
            let chunk = hours[pairStart..<min(pairStart + 3, hours.count)]
            for time in chunk {
                let button = UIButton(type: .system)
                var configuration = UIButton.Configuration.filled()
                configuration.title = Self.displayTime(time)
                configuration.baseBackgroundColor = LuminikStyle.blue
                configuration.baseForegroundColor = .white
                configuration.cornerStyle = .large
                configuration.contentInsets = NSDirectionalEdgeInsets(top: 18, leading: 8, bottom: 18, trailing: 8)
                button.configuration = configuration
                button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
                button.accessibilityIdentifier = "schedule.time.\(time)"
                button.addAction(UIAction { [weak self] _ in self?.selectTime(time) }, for: .touchUpInside)
                row.addArrangedSubview(button)
            }
            // Rellena la última fila para que los botones conserven el mismo ancho.
            for _ in chunk.count..<3 {
                row.addArrangedSubview(UIView())
            }
            slotsStack.addArrangedSubview(row)
        }
    }

    /// `09:30:00` se muestra como `09:30`; el valor original es el que se envía al guardar.
    static func displayTime(_ raw: String) -> String {
        let parts = raw.split(separator: ":")
        if parts.count == 3, parts[0].count == 2, parts[1].count == 2 {
            return "\(parts[0]):\(parts[1])"
        }
        return raw
    }

    private func selectTime(_ time: String) {
        draft.time = time
        let summary = ScheduleSummaryViewController(draft: draft)
        summary.modalPresentationStyle = .fullScreen
        present(summary, animated: true)
    }

    // MARK: Estados

    private func statusLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = LuminikStyle.serifFont(textStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }

    private func setStatusViews(_ views: [UIView]) {
        statusStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        views.forEach { statusStack.addArrangedSubview($0) }
    }

    private func showStatus(_ message: String, retry: (() -> Void)?) {
        var views: [UIView] = [statusLabel(message)]
        if let retry {
            var configuration = UIButton.Configuration.filled()
            configuration.title = "Reintentar"
            configuration.baseBackgroundColor = LuminikStyle.blue
            configuration.baseForegroundColor = .white
            configuration.cornerStyle = .fixed
            let button = UIButton(configuration: configuration)
            button.accessibilityIdentifier = "schedule.retry"
            button.addAction(UIAction { _ in retry() }, for: .touchUpInside)
            views.append(button)
        }
        setStatusViews(views)
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

// MARK: - Paso 4: resumen y guardado

private final class ScheduleSummaryViewController: UIViewController {
    private let draft: AppointmentDraft
    private let scheduleButton = UIButton(type: .system)
    private var isSaving = false

    init(draft: AppointmentDraft) {
        self.draft = draft
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
    }

    private func configureView() {
        view.backgroundColor = LuminikStyle.background
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.layoutMargins = UIEdgeInsets(top: 24, left: 24, bottom: 30, right: 24)
        stack.isLayoutMarginsRelativeArrangement = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        let back = UIButton(type: .system)
        back.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        back.contentHorizontalAlignment = .leading
        back.accessibilityLabel = "Volver al calendario"
        back.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        stack.addArrangedSubview(back)

        stack.addArrangedSubview(makeLabel("RESUMEN", style: .largeTitle, alignment: .center))
        let notes = draft.notes.isEmpty ? "SIN OBSERVACIONES" : draft.notes.uppercased()
        let details = """
        FECHA: \(draft.date)
        HORA: \(ScheduleCalendarViewController.displayTime(draft.time))
        TIEMPO DE CITA: \(draft.totalMinutes) MIN.
        TIPO DE CITA: \(draft.kindTitle)
        CABINA: \(draft.cabin?.name ?? "")
        OBSERVACIONES: \(notes)
        """
        stack.addArrangedSubview(makeLabel(details, style: .title3))
        stack.addArrangedSubview(makeLabel("SERVICIOS", style: .largeTitle, alignment: .center))

        for service in draft.selectedServices {
            let icon = UIImageView(image: UIImage(systemName: "list.clipboard"))
            icon.tintColor = LuminikStyle.blue
            icon.widthAnchor.constraint(equalToConstant: 36).isActive = true
            let row = UIStackView(arrangedSubviews: [icon, makeLabel(service.displayName, style: .title3)])
            row.axis = .horizontal
            row.alignment = .center
            row.spacing = 10
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
            stack.addArrangedSubview(row)
        }

        var configuration = UIButton.Configuration.filled()
        configuration.title = "AGENDAR"
        configuration.baseBackgroundColor = LuminikStyle.blue
        configuration.baseForegroundColor = .white
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 24, leading: 20, bottom: 24, trailing: 20)
        scheduleButton.configuration = configuration
        scheduleButton.titleLabel?.font = LuminikStyle.serifFont(textStyle: .largeTitle)
        scheduleButton.accessibilityIdentifier = "schedule.finish"
        scheduleButton.addAction(UIAction { [weak self] _ in self?.finish() }, for: .touchUpInside)
        stack.addArrangedSubview(scheduleButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    private func makeLabel(_ text: String, style: UIFont.TextStyle, alignment: NSTextAlignment = .natural) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = LuminikStyle.serifFont(textStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = alignment
        label.numberOfLines = 0
        return label
    }

    private func finish() {
        guard !isSaving else { return }
        isSaving = true
        scheduleButton.isEnabled = false
        scheduleButton.configuration?.showsActivityIndicator = true

        Task { [weak self] in
            guard let self else { return }
            do {
                try await draft.save()
                showResult(
                    title: "CITA REGISTRADA",
                    message: draft.replacing == nil
                        ? "Tu cita se ha registrado con éxito"
                        : "Tu cita se ha reagendado con éxito",
                    closesFlow: true
                )
            } catch let error as ScheduleError where error == .previousQuoteNotCancelled {
                showResult(title: "Revisa tus citas", message: error.localizedDescription, closesFlow: true)
            } catch {
                showResult(title: "Error", message: failureMessage(for: error), closesFlow: false)
            }
        }
    }

    /// Los errores de red se explican; el resto usa el mensaje genérico de Android.
    private func failureMessage(for error: Error) -> String {
        let generic = "Ocurrió un error al generar la cita, intenta de nuevo o intenta más tarde."
        guard let apiError = error as? LuminikAPIError else { return generic }
        switch apiError {
        case .offline, .timeout, .network, .server:
            return apiError.localizedDescription
        case .invalidResponse, .rejected:
            return generic
        }
    }

    private func showResult(title: String, message: String, closesFlow: Bool) {
        isSaving = false
        scheduleButton.isEnabled = true
        scheduleButton.configuration?.showsActivityIndicator = false

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Aceptar", style: .default) { [weak self] _ in
            guard closesFlow else { return }
            self?.view.window?.rootViewController?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }
}
