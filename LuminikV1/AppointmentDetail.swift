import UIKit

/// Detalle de una cita de "Mis citas" con las acciones de cancelar y reagendar
/// (`QuoteInfoScreen` en Android).
final class AppointmentDetailViewController: LuminikScreenViewController {
    private let quote: Quote
    private let session: UserSession
    private let service: LuminikServicing
    private let servicesStack = UIStackView()
    private let actionsStack = UIStackView()

    private var quoteServices: [QuoteService] = []
    private var isBusy = false

    init(quote: Quote, session: UserSession, service: LuminikServicing) {
        self.quote = quote
        self.session = session
        self.service = service
        super.init(title: "CITA")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Android: una cita confirmada ya no se puede cancelar ni reagendar.
    private var isConfirmed: Bool {
        quote.confirmed == "1" || quoteServices.contains { $0.confirmada == "1" }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let item = AppointmentItem(quote: quote)

        servicesStack.axis = .vertical
        servicesStack.spacing = 14
        actionsStack.axis = .vertical
        actionsStack.spacing = 14

        var rows: [UIView] = [
            makeInfoRow(title: "Fecha", value: item.date),
            makeInfoRow(title: "Hora", value: item.time),
            makeInfoRow(title: "Sucursal", value: session.branchName),
            makeInfoRow(title: "Observaciones", value: quote.title),
            makeInfoRow(title: "Tiempo de cita", value: quote.totalMinutes.isEmpty ? "" : "\(quote.totalMinutes) min."),
            makeInfoRow(title: "Cabina", value: quote.cabinName),
            makeInfoRow(title: "Asesor", value: quote.advisorName)
        ]
        if quote.isCancelled {
            rows.append(makeInfoRow(title: "Status", value: "Cancelada"))
        }
        rows.append(makeSectionTitle("SERVICIOS"))
        rows.append(servicesStack)
        rows.append(actionsStack)
        setContent(rows)

        loadServices()
    }

    // MARK: Servicios de la cita

    private func loadServices() {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.startAnimating()
        spinner.accessibilityLabel = "Cargando servicios"
        replaceServices(with: [spinner])
        actionsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        Task { [weak self] in
            guard let self else { return }
            do {
                quoteServices = try await service.fetchQuoteServices(quoteID: quote.id)
                if quoteServices.isEmpty {
                    replaceServices(with: [makeLabel("Esta cita no tiene servicios.", style: .body, color: .secondaryLabel, alignment: .center)])
                } else {
                    replaceServices(with: quoteServices.map { makeLabel("• \($0.descri)", style: .title3) })
                }
                showActions()
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

    private func showActions() {
        actionsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        // Las citas ya canceladas no tienen acciones.
        guard !quote.isCancelled else { return }

        actionsStack.addArrangedSubview(
            makeBlockButton(title: "REAGENDAR CITA", background: LuminikStyle.blue, identifier: "appointment.reschedule") { [weak self] in
                self?.askReschedule()
            }
        )
        actionsStack.addArrangedSubview(
            makeBlockButton(title: "CANCELAR CITA", background: .black, identifier: "appointment.cancel") { [weak self] in
                self?.askCancel()
            }
        )
    }

    // MARK: Cancelar

    private func askCancel() {
        guard !isBusy else { return }
        if isConfirmed {
            showConfirmedNotice()
            return
        }
        let alert = UIAlertController(
            title: "Cancelar Cita",
            message: "¿Estás seguro que deseas cancelar la cita?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        alert.addAction(UIAlertAction(title: "Aceptar", style: .destructive) { [weak self] _ in self?.cancelQuote() })
        present(alert, animated: true)
    }

    private func cancelQuote() {
        setBusy(true)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await service.cancelQuote(
                    quoteID: quote.id,
                    clientID: session.userID,
                    branchID: session.branchID,
                    contractID: quote.contractID
                )
                setBusy(false)
                NotificationCenter.default.post(name: .luminikAppointmentsDidChange, object: nil)
                showAlert(title: "CITA CANCELADA", message: "Tu cita se ha cancelado con éxito") { [weak self] in
                    self?.dismiss(animated: true)
                }
            } catch is CancellationError {
                setBusy(false)
            } catch {
                setBusy(false)
                showAlert(title: "No se pudo cancelar", message: error.localizedDescription)
            }
        }
    }

    // MARK: Reagendar

    private func askReschedule() {
        guard !isBusy else { return }
        if isConfirmed {
            showConfirmedNotice()
            return
        }
        // Distinto a Android: la cita actual se cancela hasta que la nueva queda guardada,
        // así no se pierde si el usuario abandona el flujo.
        let alert = UIAlertController(
            title: "Reagendar Cita",
            message: "¿Estás seguro que deseas reagendar la cita? Tu cita actual se cancelará cuando confirmes la nueva.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        alert.addAction(UIAlertAction(title: "Aceptar", style: .default) { [weak self] _ in self?.startReschedule() })
        present(alert, animated: true)
    }

    private func startReschedule() {
        let draft = AppointmentDraft(session: session, service: service)
        draft.prepareReschedule(quote: quote, services: quoteServices)

        let calendar = ScheduleCalendarViewController(draft: draft)
        calendar.modalPresentationStyle = .fullScreen
        present(calendar, animated: true)
    }

    private func showConfirmedNotice() {
        showAlert(
            title: "Cita Confirmada",
            message: "Tu cita ya está confirmada, por lo cual no es posible reagendar o cancelar."
        )
    }

    private func setBusy(_ busy: Bool) {
        isBusy = busy
        actionsStack.isUserInteractionEnabled = !busy
        actionsStack.alpha = busy ? 0.5 : 1
    }
}
