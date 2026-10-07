import UIKit

/// Cita lista para dibujarse en la tarjeta de "Mis citas".
struct AppointmentItem: Equatable, Sendable {
    let date: String
    let time: String
    let contract: String
    let isCancelled: Bool
}

extension AppointmentItem {
    private static let displayLocale = Locale(identifier: "es_MX")

    init(quote: Quote) {
        self.init(
            date: Self.displayDate(quote.appointmentDate.isEmpty ? quote.date : quote.appointmentDate),
            time: quote.appointmentTime.isEmpty ? quote.time : quote.appointmentTime,
            contract: quote.formattedContracts,
            isCancelled: quote.isCancelled
        )
    }

    /// El servidor manda `dd-MM-yyyy` (formato que Android parsea); también se acepta
    /// `yyyy-MM-dd`. Se muestra como `02/SEPTIEMBRE/2026`. Si no se reconoce, se deja tal cual.
    static func displayDate(_ raw: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        for format in ["dd-MM-yyyy", "yyyy-MM-dd"] {
            parser.dateFormat = format
            if let date = parser.date(from: raw) {
                let formatter = DateFormatter()
                formatter.locale = displayLocale
                formatter.dateFormat = "dd/MMMM/yyyy"
                return formatter.string(from: date).uppercased()
            }
        }
        return raw
    }
}

final class DashboardTabBarController: UITabBarController {
    private let session: UserSession
    private let branch: Branch
    private let service: LuminikServicing

    init(session: UserSession, branch: Branch, service: LuminikServicing = LuminikAPI()) {
        self.session = session
        self.branch = branch
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureTabs()
        configureAppearance()
    }

    private func configureTabs() {
        let home = HomeViewController(session: session, service: service)
        home.tabBarItem = UITabBarItem(title: "Inicio", image: UIImage(systemName: "house.fill"), tag: 0)

        let appointments = AppointmentsViewController(session: session, service: service)
        appointments.tabBarItem = UITabBarItem(title: "Mis citas", image: UIImage(systemName: "list.bullet.rectangle"), tag: 1)

        let profile = ProfileViewController(session: session)
        profile.tabBarItem = UITabBarItem(title: "Perfil", image: UIImage(systemName: "person.fill"), tag: 2)

        viewControllers = [home, appointments, profile]
    }

    private func configureAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .black

        let itemAppearances = [
            appearance.stackedLayoutAppearance,
            appearance.inlineLayoutAppearance,
            appearance.compactInlineLayoutAppearance
        ]
        for itemAppearance in itemAppearances {
            itemAppearance.normal.iconColor = .white
            itemAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.white]
            itemAppearance.selected.iconColor = LuminikStyle.blue
            itemAppearance.selected.titleTextAttributes = [.foregroundColor: LuminikStyle.blue]
        }

        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.tintColor = LuminikStyle.blue
        tabBar.unselectedItemTintColor = .white
        tabBar.itemPositioning = .fill
        tabBar.accessibilityIdentifier = "dashboard.tabs"
    }
}

private class DashboardContentViewController: UIViewController {
    let scrollView = UIScrollView()
    let contentStack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = LuminikStyle.background

        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    func makeSerifLabel(
        text: String,
        style: UIFont.TextStyle,
        color: UIColor = .label,
        alignment: NSTextAlignment = .natural
    ) -> UILabel {
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

private final class HomeViewController: DashboardContentViewController {
    private let session: UserSession
    private let service: LuminikServicing

    init(session: UserSession, service: LuminikServicing) {
        self.session = session
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        contentStack.spacing = 28
        contentStack.layoutMargins = UIEdgeInsets(top: 52, left: 18, bottom: 36, right: 18)
        contentStack.isLayoutMarginsRelativeArrangement = true

        let logo = makeSerifLabel(text: "LUMINIK", style: .largeTitle, alignment: .center)
        logo.font = LuminikStyle.serifFont(textStyle: .largeTitle)
        logo.accessibilityIdentifier = "dashboard.logo"
        contentStack.addArrangedSubview(logo)
        contentStack.setCustomSpacing(46, after: logo)

        let welcome = makeSerifLabel(text: "BIENVENIDO\n\(session.fullName.uppercased())", style: .title2)
        contentStack.addArrangedSubview(welcome)

        let promotion = PromotionView()
        contentStack.addArrangedSubview(promotion)
        contentStack.setCustomSpacing(46, after: promotion)

        let shortcuts = UIStackView()
        shortcuts.axis = .horizontal
        shortcuts.distribution = .fillEqually
        shortcuts.spacing = 14
        shortcuts.addArrangedSubview(makeShortcut(title: "MIS CONTRATOS", symbol: "list.clipboard", identifier: "dashboard.contracts") { [weak self] in
            guard let self else { return }
            self.presentFullScreen(ContractsViewController(session: self.session, service: self.service))
        })
        shortcuts.addArrangedSubview(makeShortcut(title: "HISTORIAL", symbol: "checklist", identifier: "dashboard.history") { [weak self] in
            guard let self else { return }
            self.presentFullScreen(HistoryViewController(session: self.session, service: self.service))
        })
        contentStack.addArrangedSubview(shortcuts)

        let scheduleButton = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.title = "AGENDAR PRÓXIMA"
        configuration.baseForegroundColor = .white
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 24, leading: 16, bottom: 24, trailing: 16)
        scheduleButton.configuration = configuration
        scheduleButton.titleLabel?.font = LuminikStyle.serifFont(textStyle: .title1)
        scheduleButton.backgroundColor = .black
        scheduleButton.accessibilityIdentifier = "dashboard.schedule"
        scheduleButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            let draft = AppointmentDraft(session: self.session, service: self.service)
            self.presentFullScreen(ScheduleSelectionViewController(draft: draft))
        }, for: .touchUpInside)
        contentStack.addArrangedSubview(scheduleButton)
    }

    private func presentFullScreen(_ controller: UIViewController) {
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true)
    }

    private func makeShortcut(title: String, symbol: String, identifier: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.image = UIImage(systemName: symbol)
        configuration.imagePlacement = .leading
        configuration.imagePadding = 12
        configuration.baseForegroundColor = .label
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 4, bottom: 12, trailing: 4)
        button.configuration = configuration
        button.tintColor = LuminikStyle.blue
        button.titleLabel?.font = LuminikStyle.serifFont(textStyle: .body)
        button.accessibilityIdentifier = identifier
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }
}

private final class PromotionView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 48 / 255, green: 205 / 255, blue: 196 / 255, alpha: 1)
        layer.cornerRadius = 2
        clipsToBounds = true

        let leftSymbol = UIImageView(image: UIImage(systemName: "figure.strengthtraining.traditional"))
        let rightSymbol = UIImageView(image: UIImage(systemName: "figure.run"))
        for imageView in [leftSymbol, rightSymbol] {
            imageView.tintColor = .white
            imageView.contentMode = .scaleAspectFit
            imageView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(imageView)
        }

        let title = UILabel()
        title.text = "LINFONIK"
        title.font = LuminikStyle.serifFont(textStyle: .title2, weight: .semibold)
        title.textColor = .white
        title.layer.shadowColor = UIColor.black.cgColor
        title.layer.shadowOpacity = 1
        title.layer.shadowRadius = 1
        title.textAlignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)

        accessibilityLabel = "Promoción Linfonik"

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 140),
            leftSymbol.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            leftSymbol.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            leftSymbol.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            leftSymbol.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.28),
            rightSymbol.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            rightSymbol.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            rightSymbol.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            rightSymbol.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.28),
            title.centerXAnchor.constraint(equalTo: centerXAnchor),
            title.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class AppointmentsViewController: DashboardContentViewController {
    private let session: UserSession
    private let service: LuminikServicing
    private var loadTask: Task<Void, Never>?
    /// Vistas que dependen de la carga (tarjetas, spinner, mensaje). Se reemplazan en cada carga.
    private var dynamicViews: [UIView] = []

    init(session: UserSession, service: LuminikServicing) {
        self.session = session
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        contentStack.spacing = 28
        contentStack.layoutMargins = UIEdgeInsets(top: 54, left: 34, bottom: 34, right: 34)
        contentStack.isLayoutMarginsRelativeArrangement = true

        let title = makeSerifLabel(text: "MIS CITAS", style: .largeTitle, color: .white, alignment: .center)
        title.backgroundColor = .black
        title.layer.cornerRadius = 2
        title.clipsToBounds = true
        title.heightAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
        title.accessibilityIdentifier = "appointments.title"
        contentStack.addArrangedSubview(title)
        contentStack.setCustomSpacing(30, after: title)

        let refreshControl = UIRefreshControl()
        refreshControl.addAction(UIAction { [weak self] _ in
            self?.loadAppointments(showsSpinner: false)
        }, for: .valueChanged)
        scrollView.refreshControl = refreshControl

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appointmentsDidChange),
            name: .luminikAppointmentsDidChange,
            object: nil
        )

        loadAppointments(showsSpinner: true)
    }

    @objc private func appointmentsDidChange() {
        loadAppointments(showsSpinner: false)
    }

    private func loadAppointments(showsSpinner: Bool) {
        loadTask?.cancel()
        if showsSpinner {
            let spinner = UIActivityIndicatorView(style: .large)
            spinner.startAnimating()
            spinner.accessibilityLabel = "Cargando citas"
            spinner.accessibilityIdentifier = "appointments.loading"
            replaceDynamicViews(with: [spinner])
        }

        loadTask = Task { [weak self, service, session] in
            do {
                let quotes = try await service.fetchQuotes(
                    branchID: session.branchID,
                    clientID: session.userID
                )
                guard !Task.isCancelled else { return }
                self?.scrollView.refreshControl?.endRefreshing()
                self?.showAppointments(quotes)
            } catch is CancellationError {
                return
            } catch {
                self?.scrollView.refreshControl?.endRefreshing()
                self?.showFailure(error.localizedDescription)
            }
        }
    }

    private func replaceDynamicViews(with views: [UIView]) {
        dynamicViews.forEach { $0.removeFromSuperview() }
        dynamicViews = views
        views.forEach { contentStack.addArrangedSubview($0) }
    }

    private func showAppointments(_ quotes: [Quote]) {
        guard !quotes.isEmpty else {
            let label = makeSerifLabel(text: "Aún no tienes citas.", style: .title3, color: .secondaryLabel, alignment: .center)
            label.accessibilityIdentifier = "appointments.empty"
            replaceDynamicViews(with: [label])
            return
        }
        replaceDynamicViews(with: quotes.map { quote in
            let card = AppointmentCardView(appointment: AppointmentItem(quote: quote))
            card.accessibilityIdentifier = "appointment.\(quote.id)"
            card.addAction(UIAction { [weak self] _ in self?.openDetail(quote) }, for: .touchUpInside)
            return card
        })
    }

    private func openDetail(_ quote: Quote) {
        let detail = AppointmentDetailViewController(quote: quote, session: session, service: service)
        detail.modalPresentationStyle = .fullScreen
        present(detail, animated: true)
    }

    private func showFailure(_ message: String) {
        let label = makeSerifLabel(text: message, style: .body, color: .secondaryLabel, alignment: .center)
        label.accessibilityIdentifier = "appointments.error"

        var configuration = UIButton.Configuration.filled()
        configuration.title = "Reintentar"
        configuration.baseBackgroundColor = LuminikStyle.blue
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .fixed
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 24, bottom: 14, trailing: 24)
        let retry = UIButton(configuration: configuration)
        retry.accessibilityIdentifier = "appointments.retry"
        retry.addAction(UIAction { [weak self] _ in
            self?.loadAppointments(showsSpinner: true)
        }, for: .touchUpInside)

        replaceDynamicViews(with: [label, retry])
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

private final class AppointmentCardView: UIControl {
    init(appointment: AppointmentItem) {
        super.init(frame: .zero)
        backgroundColor = LuminikStyle.blue
        layer.cornerRadius = 14

        let icon = UIImageView(image: UIImage(systemName: "note.text"))
        icon.tintColor = .white
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)

        let details = UILabel()
        var detailsText = "FECHA: \(appointment.date)\nHORA: \(appointment.time)\nCONTRATO: \(appointment.contract)"
        if appointment.isCancelled {
            detailsText += "\nESTATUS: CANCELADA"
        }
        details.text = detailsText
        details.textColor = .white
        details.font = LuminikStyle.serifFont(textStyle: .title3)
        details.adjustsFontForContentSizeCategory = true
        details.numberOfLines = 0
        details.translatesAutoresizingMaskIntoConstraints = false
        addSubview(details)

        accessibilityLabel = "Cita. Fecha \(appointment.date). Hora \(appointment.time). Contrato \(appointment.contract)."
            + (appointment.isCancelled ? " Cancelada." : "")
        accessibilityTraits = .button

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 150),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 34),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 34),
            icon.heightAnchor.constraint(equalToConstant: 34),
            details.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            details.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 30),
            details.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            details.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class ProfileViewController: DashboardContentViewController {
    private let session: UserSession

    init(session: UserSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        contentStack.spacing = 24
        contentStack.alignment = .fill
        contentStack.layoutMargins = UIEdgeInsets(top: 120, left: 16, bottom: 40, right: 16)
        contentStack.isLayoutMarginsRelativeArrangement = true

        let name = makeSerifLabel(text: session.fullName.uppercased(), style: .largeTitle, alignment: .center)
        name.accessibilityIdentifier = "profile.name"
        contentStack.addArrangedSubview(name)

        let details = makeSerifLabel(
            text: "TELÉFONO: \(session.phone)\n\nCORREO: \(session.email)\n\nSUCURSAL: \(session.branchName)",
            style: .title3,
            alignment: .center
        )
        contentStack.addArrangedSubview(details)
        contentStack.setCustomSpacing(38, after: details)

        let logoutButton = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Cerrar Sesión"
        configuration.baseBackgroundColor = LuminikStyle.blue
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .fixed
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20)
        logoutButton.configuration = configuration
        logoutButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        logoutButton.accessibilityIdentifier = "profile.logout"
        logoutButton.addAction(UIAction { [weak self] _ in
            self?.logOut()
        }, for: .touchUpInside)
        contentStack.addArrangedSubview(logoutButton)
    }

    private func logOut() {
        SessionStore.shared.clear()
        guard let window = view.window else { return }
        UIView.transition(with: window, duration: 0.35, options: .transitionCrossDissolve) {
            window.rootViewController = ViewController()
        }
    }
}
