import UIKit

struct MockUser: Sendable {
    let name: String
    let phone: String
    let email: String
}

struct MockAppointment: Sendable {
    let date: String
    let time: String
    let contract: String
}

final class DashboardTabBarController: UITabBarController {
    private let branch: Branch
    private let user = MockUser(
        name: "SARAH SANTOS",
        phone: "8181360496",
        email: "SARAHOSANTOS3@GMAIL.COM"
    )

    init(branch: Branch) {
        self.branch = branch
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
        let home = HomeViewController(user: user)
        home.tabBarItem = UITabBarItem(title: "Inicio", image: UIImage(systemName: "house.fill"), tag: 0)

        let appointments = AppointmentsViewController()
        appointments.tabBarItem = UITabBarItem(title: "Mis citas", image: UIImage(systemName: "list.bullet.rectangle"), tag: 1)

        let profile = ProfileViewController(user: user, branch: branch)
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
    private let user: MockUser

    init(user: MockUser) {
        self.user = user
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

        let welcome = makeSerifLabel(text: "BIENVENIDO\n\(user.name)", style: .title2)
        contentStack.addArrangedSubview(welcome)

        let promotion = PromotionView()
        contentStack.addArrangedSubview(promotion)
        contentStack.setCustomSpacing(46, after: promotion)

        let shortcuts = UIStackView()
        shortcuts.axis = .horizontal
        shortcuts.distribution = .fillEqually
        shortcuts.spacing = 14
        shortcuts.addArrangedSubview(makeShortcut(title: "MIS CONTRATOS", symbol: "list.clipboard"))
        shortcuts.addArrangedSubview(makeShortcut(title: "HISTORIAL", symbol: "checklist"))
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
        contentStack.addArrangedSubview(scheduleButton)
    }

    private func makeShortcut(title: String, symbol: String) -> UIButton {
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
    private let appointments = [
        MockAppointment(date: "02/SEPTIEMBRE/2026", time: "11:51:00", contract: "B14"),
        MockAppointment(date: "19/SEPTIEMBRE/2026", time: "15:40:00", contract: "L362"),
        MockAppointment(date: "20/SEPTIEMBRE/2026", time: "17:21:00", contract: "A108")
    ]

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

        for appointment in appointments {
            contentStack.addArrangedSubview(AppointmentCardView(appointment: appointment))
        }
    }
}

private final class AppointmentCardView: UIView {
    init(appointment: MockAppointment) {
        super.init(frame: .zero)
        backgroundColor = LuminikStyle.blue
        layer.cornerRadius = 14

        let icon = UIImageView(image: UIImage(systemName: "note.text"))
        icon.tintColor = .white
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)

        let details = UILabel()
        details.text = "FECHA: \(appointment.date)\nHORA: \(appointment.time)\nCONTRATO: \(appointment.contract)"
        details.textColor = .white
        details.font = LuminikStyle.serifFont(textStyle: .title3)
        details.adjustsFontForContentSizeCategory = true
        details.numberOfLines = 0
        details.translatesAutoresizingMaskIntoConstraints = false
        addSubview(details)

        accessibilityLabel = "Cita. Fecha \(appointment.date). Hora \(appointment.time). Contrato \(appointment.contract)"

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
    private let user: MockUser
    private let branch: Branch

    init(user: MockUser, branch: Branch) {
        self.user = user
        self.branch = branch
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

        let name = makeSerifLabel(text: user.name, style: .largeTitle, alignment: .center)
        name.accessibilityIdentifier = "profile.name"
        contentStack.addArrangedSubview(name)

        let details = makeSerifLabel(
            text: "TELÉFONO: \(user.phone)\n\nCORREO: \(user.email)\n\nSUCURSAL: \(branch.name)",
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
        guard let window = view.window else { return }
        UIView.transition(with: window, duration: 0.35, options: .transitionCrossDissolve) {
            window.rootViewController = ViewController()
        }
    }
}
