import UIKit

/// Antes era `private`, pero también lo usan `DashboardViewController.swift` y
/// `AppointmentScheduling.swift`; con `private` esos archivos no compilaban.
enum LuminikStyle {
    static let blue = UIColor(red: 12 / 255, green: 70 / 255, blue: 151 / 255, alpha: 1)
    static let background = UIColor(red: 1, green: 248 / 255, blue: 1, alpha: 1)
    static let cardBackground = UIColor(red: 241 / 255, green: 238 / 255, blue: 242 / 255, alpha: 1)

    static func serifFont(textStyle: UIFont.TextStyle, weight: UIFont.Weight = .regular) -> UIFont {
        let base = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: textStyle).pointSize, weight: weight)
        let descriptor = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: UIFont(descriptor: descriptor, size: 0))
    }
}

struct Branch: Equatable, Sendable {
    /// `id` de la sucursal en el servidor; es el `idSucursal` que pide el login.
    let id: String
    let name: String
    let mark: String
    let subtitle: String?
}

final class ViewController: UIViewController {
    private let service: LuminikServicing = LuminikAPI()
    private var loadTask: Task<Void, Never>?

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    /// Vistas que dependen de la carga (tarjetas, spinner o error). Se reemplazan en cada carga.
    private var dynamicViews: [UIView] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        loadBranches()
    }

    private func loadBranches() {
        loadTask?.cancel()
        showLoading()
        loadTask = Task { [weak self, service] in
            do {
                let dtos = try await service.fetchBranches()
                guard !Task.isCancelled else { return }
                let branches = dtos
                    .filter { !$0.id.isEmpty && !$0.name.isEmpty }
                    .map(Branch.init(dto:))
                self?.showBranches(branches)
            } catch is CancellationError {
                return
            } catch {
                self?.showFailure(error.localizedDescription)
            }
        }
    }

    private func replaceDynamicViews(with views: [UIView]) {
        dynamicViews.forEach { $0.removeFromSuperview() }
        dynamicViews = views
        views.forEach { stackView.addArrangedSubview($0) }
    }

    private func showLoading() {
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.startAnimating()
        spinner.accessibilityLabel = "Cargando sucursales"
        spinner.accessibilityIdentifier = "branches.loading"
        replaceDynamicViews(with: [spinner])
    }

    private func showBranches(_ branches: [Branch]) {
        guard !branches.isEmpty else {
            showFailure("No hay sucursales disponibles por el momento.")
            return
        }
        let cards: [UIView] = branches.map { branch in
            let card = BranchCardControl(branch: branch)
            card.addAction(UIAction { [weak self] _ in
                self?.showLogin(for: branch)
            }, for: .touchUpInside)
            return card
        }
        replaceDynamicViews(with: cards)
    }

    private func showFailure(_ message: String) {
        let label = UILabel()
        label.text = message
        label.font = LuminikStyle.serifFont(textStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.accessibilityIdentifier = "branches.error"

        var configuration = UIButton.Configuration.filled()
        configuration.title = "Reintentar"
        configuration.baseBackgroundColor = LuminikStyle.blue
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .fixed
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 24, bottom: 14, trailing: 24)
        let retry = UIButton(configuration: configuration)
        retry.accessibilityIdentifier = "branches.retry"
        retry.addAction(UIAction { [weak self] _ in
            self?.loadBranches()
        }, for: .touchUpInside)

        replaceDynamicViews(with: [label, retry])
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private func configureView() {
        view.backgroundColor = LuminikStyle.background

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        stackView.axis = .vertical
        stackView.spacing = 18
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        let titleContainer = UIView()
        titleContainer.backgroundColor = .black
        titleContainer.layer.cornerRadius = 2
        titleContainer.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = "SUCURSALES"
        titleLabel.textColor = .white
        titleLabel.font = LuminikStyle.serifFont(textStyle: .largeTitle)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleContainer.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: titleContainer.topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: titleContainer.leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(equalTo: titleContainer.trailingAnchor, constant: -28),
            titleLabel.bottomAnchor.constraint(equalTo: titleContainer.bottomAnchor, constant: -14)
        ])

        let titleWrapper = UIView()
        titleWrapper.addSubview(titleContainer)
        NSLayoutConstraint.activate([
            titleContainer.topAnchor.constraint(equalTo: titleWrapper.topAnchor),
            titleContainer.centerXAnchor.constraint(equalTo: titleWrapper.centerXAnchor),
            titleContainer.bottomAnchor.constraint(equalTo: titleWrapper.bottomAnchor)
        ])
        stackView.addArrangedSubview(titleWrapper)
        stackView.setCustomSpacing(38, after: titleWrapper)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 36),
            stackView.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28)
        ])
    }

    private func showLogin(for branch: Branch) {
        let loginViewController = LoginViewController(branch: branch, viewModel: LoginViewModel(branch: branch))
        loginViewController.modalPresentationStyle = .fullScreen
        present(loginViewController, animated: true)
    }
}

private final class BranchCardControl: UIControl {
    init(branch: Branch) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = LuminikStyle.cardBackground
        layer.cornerRadius = 14
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.14
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 2)
        clipsToBounds = false
        accessibilityLabel = "Sucursal \(branch.name)"
        accessibilityTraits = .button
        accessibilityIdentifier = "branch.\(branch.name.lowercased().replacingOccurrences(of: " ", with: "-"))"

        let brandArea = UIView()
        brandArea.backgroundColor = LuminikStyle.blue
        brandArea.isUserInteractionEnabled = false
        brandArea.translatesAutoresizingMaskIntoConstraints = false
        addSubview(brandArea)

        let markLabel = UILabel()
        markLabel.text = branch.mark
        markLabel.textColor = .white
        markLabel.font = LuminikStyle.serifFont(textStyle: .largeTitle, weight: .semibold)
        markLabel.adjustsFontForContentSizeCategory = true
        markLabel.adjustsFontSizeToFitWidth = true
        markLabel.minimumScaleFactor = 0.45
        markLabel.numberOfLines = 2
        markLabel.textAlignment = .center
        markLabel.translatesAutoresizingMaskIntoConstraints = false
        brandArea.addSubview(markLabel)

        let subtitleLabel = UILabel()
        subtitleLabel.text = branch.subtitle
        subtitleLabel.textColor = .white
        subtitleLabel.font = .preferredFont(forTextStyle: .caption1)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textAlignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        brandArea.addSubview(subtitleLabel)

        let nameLabel = UILabel()
        nameLabel.text = branch.name
        nameLabel.font = LuminikStyle.serifFont(textStyle: .title1)
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.numberOfLines = 0
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 250),
            brandArea.topAnchor.constraint(equalTo: topAnchor),
            brandArea.leadingAnchor.constraint(equalTo: leadingAnchor),
            brandArea.trailingAnchor.constraint(equalTo: trailingAnchor),
            brandArea.heightAnchor.constraint(equalToConstant: 180),
            markLabel.centerXAnchor.constraint(equalTo: brandArea.centerXAnchor),
            markLabel.centerYAnchor.constraint(equalTo: brandArea.centerYAnchor, constant: branch.subtitle == nil ? 0 : -12),
            markLabel.leadingAnchor.constraint(greaterThanOrEqualTo: brandArea.leadingAnchor, constant: 24),
            markLabel.trailingAnchor.constraint(lessThanOrEqualTo: brandArea.trailingAnchor, constant: -24),
            subtitleLabel.topAnchor.constraint(equalTo: markLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: brandArea.leadingAnchor, constant: 16),
            subtitleLabel.trailingAnchor.constraint(equalTo: brandArea.trailingAnchor, constant: -16),
            nameLabel.topAnchor.constraint(equalTo: brandArea.bottomAnchor, constant: 18),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            nameLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.12) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.98, y: 0.98) : .identity
                self.alpha = self.isHighlighted ? 0.88 : 1
            }
        }
    }
}

private final class LoginViewController: UIViewController {
    private let branch: Branch
    private let viewModel: LoginViewModel
    private let phoneField = UITextField()
    private let passwordField = UITextField()
    private let phoneErrorLabel = UILabel()
    private let passwordErrorLabel = UILabel()
    private let messageLabel = UILabel()
    private let signInButton = UIButton(type: .system)

    init(branch: Branch, viewModel: LoginViewModel) {
        self.branch = branch
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        configureBindings()
    }

    private func configureView() {
        view.backgroundColor = LuminikStyle.blue

        let scrollView = UIScrollView()
        scrollView.backgroundColor = LuminikStyle.background
        scrollView.keyboardDismissMode = .interactive
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        let header = LoginHeaderView(branchName: branch.name)
        header.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(header)

        let form = UIStackView()
        form.axis = .vertical
        form.spacing = 10
        form.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(form)

        configure(field: phoneField, label: "TELÉFONO", placeholder: "3859304510")
        phoneField.keyboardType = .phonePad
        phoneField.textContentType = .telephoneNumber
        phoneField.accessibilityIdentifier = "login.phone"
        configureErrorLabel(phoneErrorLabel, text: "Ingresa un número de teléfono válido.")

        configure(field: passwordField, label: "PASSWORD", placeholder: "Contraseña")
        passwordField.isSecureTextEntry = true
        passwordField.textContentType = .password
        passwordField.returnKeyType = .go
        passwordField.accessibilityIdentifier = "login.password"
        configureErrorLabel(passwordErrorLabel, text: "Ingresa tu contraseña.")

        let phoneGroup = FieldGroupView(title: "TELÉFONO", field: phoneField, errorLabel: phoneErrorLabel)
        let passwordGroup = FieldGroupView(title: "PASSWORD", field: passwordField, errorLabel: passwordErrorLabel)
        form.addArrangedSubview(phoneGroup)
        form.setCustomSpacing(16, after: phoneGroup)
        form.addArrangedSubview(passwordGroup)

        let separator = UIView()
        separator.backgroundColor = .separator
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        form.setCustomSpacing(34, after: passwordGroup)
        form.addArrangedSubview(separator)

        messageLabel.font = .preferredFont(forTextStyle: .footnote)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.isHidden = true
        messageLabel.accessibilityIdentifier = "login.message"
        form.addArrangedSubview(messageLabel)

        let rightsLabel = UILabel()
        rightsLabel.text = "Derechos reservados por\nESDM"
        rightsLabel.font = .preferredFont(forTextStyle: .body)
        rightsLabel.adjustsFontForContentSizeCategory = true
        rightsLabel.textColor = .secondaryLabel
        rightsLabel.textAlignment = .center
        rightsLabel.numberOfLines = 2
        form.setCustomSpacing(48, after: messageLabel)
        form.addArrangedSubview(rightsLabel)

        var buttonConfiguration = UIButton.Configuration.plain()
        buttonConfiguration.title = "INICIAR SESIÓN"
        buttonConfiguration.baseForegroundColor = .white
        buttonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 22, leading: 20, bottom: 22, trailing: 20)
        signInButton.configuration = buttonConfiguration
        signInButton.titleLabel?.font = LuminikStyle.serifFont(textStyle: .title1)
        signInButton.backgroundColor = LuminikStyle.blue
        signInButton.accessibilityIdentifier = "login.submit"
        signInButton.translatesAutoresizingMaskIntoConstraints = false
        signInButton.addTarget(self, action: #selector(signInTapped), for: .touchUpInside)
        view.addSubview(signInButton)

        NSLayoutConstraint.activate([
            signInButton.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            signInButton.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            signInButton.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            signInButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 88),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: signInButton.topAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            header.topAnchor.constraint(equalTo: contentView.topAnchor),
            header.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            form.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 32),
            form.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
            form.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
            form.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -34)
        ])

        phoneField.addTarget(self, action: #selector(fieldDidChange), for: .editingChanged)
        passwordField.addTarget(self, action: #selector(fieldDidChange), for: .editingChanged)
        passwordField.addTarget(self, action: #selector(signInTapped), for: .editingDidEndOnExit)
    }

    private func configure(field: UITextField, label: String, placeholder: String) {
        field.placeholder = placeholder
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.borderStyle = .none
        field.layer.borderColor = UIColor.secondaryLabel.cgColor
        field.layer.borderWidth = 1
        field.backgroundColor = LuminikStyle.background
        field.clearButtonMode = .whileEditing
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        field.leftViewMode = .always
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true
        field.accessibilityLabel = label
    }

    private func configureErrorLabel(_ label: UILabel, text: String) {
        label.text = text
        label.textColor = .systemRed
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.isHidden = true
    }

    private func configureBindings() {
        viewModel.onStateChange = { [weak self] state in
            self?.render(state)
        }
    }

    private func render(_ state: LoginViewModel.State) {
        let isLoading = state == .loading
        phoneField.isEnabled = !isLoading
        passwordField.isEnabled = !isLoading
        signInButton.isEnabled = !isLoading
        signInButton.configuration?.showsActivityIndicator = isLoading

        switch state {
        case .idle, .loading:
            messageLabel.isHidden = true
        case .authenticated:
            messageLabel.isHidden = true
            showDashboard()
        case let .failed(message):
            messageLabel.text = message
            messageLabel.textColor = .systemRed
            messageLabel.isHidden = false
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }

    private func showDashboard() {
        guard let session = viewModel.session, let window = view.window else { return }
        let dashboard = DashboardTabBarController(session: session, branch: branch)
        UIView.transition(with: window, duration: 0.35, options: .transitionCrossDissolve) {
            window.rootViewController = dashboard
        }
    }

    @objc private func fieldDidChange() {
        messageLabel.isHidden = true
        if !phoneErrorLabel.isHidden || !passwordErrorLabel.isHidden {
            _ = validateFields()
        }
    }

    @objc private func signInTapped() {
        guard validateFields() else { return }
        view.endEditing(true)
        Task {
            await viewModel.signIn(phone: phoneField.text ?? "", password: passwordField.text ?? "")
        }
    }

    private func validateFields() -> Bool {
        let invalidFields = viewModel.validate(phone: phoneField.text ?? "", password: passwordField.text ?? "")
        phoneErrorLabel.isHidden = !invalidFields.contains(.phone)
        passwordErrorLabel.isHidden = !invalidFields.contains(.password)

        if invalidFields.contains(.phone) {
            phoneField.becomeFirstResponder()
        } else if invalidFields.contains(.password) {
            passwordField.becomeFirstResponder()
        }
        return invalidFields.isEmpty
    }
}

private final class LoginHeaderView: UIView {
    init(branchName: String) {
        super.init(frame: .zero)
        backgroundColor = LuminikStyle.blue

        let backButton = UIButton(type: .system)
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.tintColor = .white
        backButton.accessibilityLabel = "Volver a sucursales"
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.addAction(UIAction { [weak backButton] _ in
            backButton?.window?.rootViewController?.presentedViewController?.dismiss(animated: true)
        }, for: .touchUpInside)
        addSubview(backButton)

        let logo = UILabel()
        logo.text = "◌  LUMINIK"
        logo.textColor = .white
        logo.font = LuminikStyle.serifFont(textStyle: .largeTitle)
        logo.adjustsFontForContentSizeCategory = true
        logo.textAlignment = .center
        logo.adjustsFontSizeToFitWidth = true
        logo.minimumScaleFactor = 0.7

        let clinic = UILabel()
        clinic.text = "CLINICAL LASER CENTER"
        clinic.textColor = .white
        clinic.font = .preferredFont(forTextStyle: .caption1)
        clinic.adjustsFontForContentSizeCategory = true
        clinic.textAlignment = .center

        let slogan = UILabel()
        slogan.text = "ilumina tu piel"
        slogan.textColor = .white
        slogan.font = .italicSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .headline).pointSize)
        slogan.adjustsFontForContentSizeCategory = true
        slogan.textAlignment = .center

        let welcome = UILabel()
        welcome.text = "BIENVENIDO"
        welcome.textColor = .white
        welcome.font = LuminikStyle.serifFont(textStyle: .largeTitle)
        welcome.adjustsFontForContentSizeCategory = true
        welcome.textAlignment = .center

        let subtitle = UILabel()
        subtitle.text = "INGRESA TUS DATOS PARA CONTINUAR"
        subtitle.textColor = .white
        subtitle.font = LuminikStyle.serifFont(textStyle: .body)
        subtitle.adjustsFontForContentSizeCategory = true
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [logo, clinic, slogan, welcome, subtitle])
        stack.axis = .vertical
        stack.spacing = 3
        stack.setCustomSpacing(52, after: slogan)
        stack.setCustomSpacing(12, after: welcome)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        accessibilityLabel = "Luminik Clinical Laser Center. Sucursal \(branchName)"

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 350),
            backButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),
            stack.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 62),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -22)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class FieldGroupView: UIStackView {
    init(title: String, field: UITextField, errorLabel: UILabel) {
        super.init(frame: .zero)
        axis = .vertical
        spacing = 8

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = LuminikStyle.serifFont(textStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .secondaryLabel

        addArrangedSubview(titleLabel)
        addArrangedSubview(field)
        addArrangedSubview(errorLabel)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
