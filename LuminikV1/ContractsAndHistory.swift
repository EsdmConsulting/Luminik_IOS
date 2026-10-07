import UIKit

// MARK: - Mis contratos

final class ContractsViewController: LuminikScreenViewController {
    private let session: UserSession
    private let service: LuminikServicing

    init(session: UserSession, service: LuminikServicing) {
        self.session = session
        self.service = service
        super.init(title: "MIS CONTRATOS")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        load()
    }

    private func load() {
        showSpinner("Cargando contratos")
        Task { [weak self] in
            guard let self else { return }
            do {
                let contracts = try await service.fetchContracts(branchID: session.branchID, clientID: session.userID)
                render(contracts)
            } catch is CancellationError {
                return
            } catch {
                showMessage(error.localizedDescription) { [weak self] in self?.load() }
            }
        }
    }

    private func render(_ contracts: [Contract]) {
        guard !contracts.isEmpty else {
            showMessage("No tienes contratos")
            return
        }
        setContent(contracts.map { contract in
            makeCard(
                icon: "list.clipboard",
                text: "FOLIO: \(contract.displayFolio)\nTIPO: \(contract.kind.rawValue.uppercased())",
                identifier: "contract.\(contract.id)"
            ) { [weak self] in
                self?.open(contract)
            }
        })
    }

    private func open(_ contract: Contract) {
        let detail = ContractDetailViewController(contract: contract, session: session, service: service)
        detail.modalPresentationStyle = .fullScreen
        present(detail, animated: true)
    }
}

final class ContractDetailViewController: LuminikScreenViewController {
    private let contract: Contract
    private let session: UserSession
    private let service: LuminikServicing
    private let servicesStack = UIStackView()

    init(contract: Contract, session: UserSession, service: LuminikServicing) {
        self.contract = contract
        self.session = session
        self.service = service
        super.init(title: "INFORMACIÓN DEL CONTRATO")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setContent([
            makeInfoRow(title: "Folio", value: contract.displayFolio),
            makeInfoRow(title: "Tipo", value: contract.kind.rawValue),
            makeInfoRow(title: "Fecha", value: AppointmentItem.displayDate(contract.date)),
            makeInfoRow(title: "Total", value: contract.total.isEmpty ? "" : "$ \(contract.total)"),
            makeSectionTitle("SERVICIOS"),
            servicesStack
        ])
        servicesStack.axis = .vertical
        servicesStack.spacing = 14
        loadServices()
    }

    private func loadServices() {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.startAnimating()
        spinner.accessibilityLabel = "Cargando servicios"
        replaceServices(with: [spinner])

        Task { [weak self] in
            guard let self else { return }
            do {
                let services = try await service.fetchContractServices(
                    branchID: session.branchID,
                    contractTypeCode: contract.kind.serviceTypeCode,
                    contractID: contract.id,
                    clientID: session.userID
                )
                if services.isEmpty {
                    replaceServices(with: [makeLabel("Este contrato no tiene servicios.", style: .body, color: .secondaryLabel, alignment: .center)])
                } else {
                    replaceServices(with: services.map { makeLabel("• \($0.displayName)", style: .title3) })
                }
            } catch is CancellationError {
                return
            } catch {
                var configuration = UIButton.Configuration.filled()
                configuration.title = "Reintentar"
                configuration.baseBackgroundColor = LuminikStyle.blue
                configuration.baseForegroundColor = .white
                configuration.cornerStyle = .fixed
                let retry = UIButton(configuration: configuration)
                retry.addAction(UIAction { [weak self] _ in self?.loadServices() }, for: .touchUpInside)
                replaceServices(with: [
                    makeLabel(error.localizedDescription, style: .body, color: .secondaryLabel, alignment: .center),
                    retry
                ])
            }
        }
    }

    private func replaceServices(with views: [UIView]) {
        servicesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        views.forEach { servicesStack.addArrangedSubview($0) }
    }
}

// MARK: - Historial

final class HistoryViewController: LuminikScreenViewController {
    private let session: UserSession
    private let service: LuminikServicing

    init(session: UserSession, service: LuminikServicing) {
        self.session = session
        self.service = service
        super.init(title: "HISTORIAL")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        load()
    }

    private func load() {
        showSpinner("Cargando historial")
        Task { [weak self] in
            guard let self else { return }
            do {
                let history = try await service.fetchHistory(branchID: session.branchID, clientID: session.userID)
                render(history)
            } catch is CancellationError {
                return
            } catch {
                showMessage(error.localizedDescription) { [weak self] in self?.load() }
            }
        }
    }

    private func render(_ history: [Quote]) {
        guard !history.isEmpty else {
            showMessage("Historial vacío")
            return
        }
        setContent(history.map { entry in
            let item = AppointmentItem(quote: entry)
            return makeCard(
                icon: "checklist",
                text: "FECHA: \(item.date)\nHORA: \(item.time)\nCONTRATO: \(item.contract)",
                identifier: "history.\(entry.id)"
            ) { [weak self] in
                self?.open(entry)
            }
        })
    }

    private func open(_ entry: Quote) {
        let detail = HistoryDetailViewController(entry: entry, session: session, service: service)
        detail.modalPresentationStyle = .fullScreen
        present(detail, animated: true)
    }
}

final class HistoryDetailViewController: LuminikScreenViewController {
    private let entry: Quote
    private let session: UserSession
    private let service: LuminikServicing
    private let servicesStack = UIStackView()

    init(entry: Quote, session: UserSession, service: LuminikServicing) {
        self.entry = entry
        self.session = session
        self.service = service
        super.init(title: "INFORMACIÓN")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let item = AppointmentItem(quote: entry)
        setContent([
            makeInfoRow(title: "Fecha", value: item.date),
            makeInfoRow(title: "Hora", value: item.time),
            makeInfoRow(title: "Sucursal", value: session.branchName),
            makeInfoRow(title: "Status", value: entry.isCancelled ? "Cancelada" : "Confirmada"),
            makeInfoRow(title: "Cabina", value: entry.cabinName),
            makeInfoRow(title: "Asesor", value: entry.advisorName),
            makeSectionTitle("SERVICIOS"),
            servicesStack
        ])
        servicesStack.axis = .vertical
        servicesStack.spacing = 14
        loadServices()
    }

    private func loadServices() {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.startAnimating()
        spinner.accessibilityLabel = "Cargando servicios"
        replaceServices(with: [spinner])

        Task { [weak self] in
            guard let self else { return }
            do {
                let services = try await service.fetchQuoteServices(quoteID: entry.id)
                if services.isEmpty {
                    replaceServices(with: [makeLabel("Esta cita no tiene servicios.", style: .body, color: .secondaryLabel, alignment: .center)])
                } else {
                    replaceServices(with: services.map { makeLabel("• \($0.descri)", style: .title3) })
                }
            } catch is CancellationError {
                return
            } catch {
                var configuration = UIButton.Configuration.filled()
                configuration.title = "Reintentar"
                configuration.baseBackgroundColor = LuminikStyle.blue
                configuration.baseForegroundColor = .white
                configuration.cornerStyle = .fixed
                let retry = UIButton(configuration: configuration)
                retry.addAction(UIAction { [weak self] _ in self?.loadServices() }, for: .touchUpInside)
                replaceServices(with: [
                    makeLabel(error.localizedDescription, style: .body, color: .secondaryLabel, alignment: .center),
                    retry
                ])
            }
        }
    }

    private func replaceServices(with views: [UIView]) {
        servicesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        views.forEach { servicesStack.addArrangedSubview($0) }
    }
}
