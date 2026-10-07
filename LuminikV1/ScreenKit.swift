import UIKit

extension Notification.Name {
    /// Se publica cuando se agenda, reagenda o cancela una cita para que "Mis citas" se actualice.
    static let luminikAppointmentsDidChange = Notification.Name("luminik.appointmentsDidChange")
}

/// Base de las pantallas que se abren encima del dashboard (contratos, historial, detalle de cita):
/// encabezado negro con botón de regreso, scroll vertical y utilidades para los estados
/// de carga, error y vacío que comparten todas.
class LuminikScreenViewController: UIViewController {
    let scrollView = UIScrollView()
    let contentStack = UIStackView()

    private let screenTitle: String
    /// Vistas que dependen de la carga actual; `setContent` las reemplaza.
    private var dynamicViews: [UIView] = []

    init(title: String) {
        self.screenTitle = title
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = LuminikStyle.background

        let header = makeHeader()
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)

        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 18
        contentStack.layoutMargins = UIEdgeInsets(top: 24, left: 22, bottom: 32, right: 22)
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
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

    private func makeHeader() -> UIView {
        let container = UIView()
        container.backgroundColor = .black

        let back = UIButton(type: .system)
        back.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        back.tintColor = .white
        back.accessibilityLabel = "Volver"
        back.accessibilityIdentifier = "screen.back"
        back.translatesAutoresizingMaskIntoConstraints = false
        back.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        container.addSubview(back)

        let title = makeLabel(screenTitle, style: .title1, color: .white, alignment: .center)
        title.accessibilityTraits = .header
        title.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(title)

        NSLayoutConstraint.activate([
            back.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 6),
            back.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            back.widthAnchor.constraint(equalToConstant: 44),
            back.heightAnchor.constraint(equalToConstant: 44),
            title.topAnchor.constraint(equalTo: back.bottomAnchor, constant: 2),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 22),
            title.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -22),
            title.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20)
        ])
        return container
    }

    // MARK: - Contenido dinámico

    func setContent(_ views: [UIView]) {
        dynamicViews.forEach { $0.removeFromSuperview() }
        dynamicViews = views
        views.forEach { contentStack.addArrangedSubview($0) }
    }

    func showSpinner(_ accessibilityText: String) {
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.startAnimating()
        spinner.accessibilityLabel = accessibilityText
        setContent([spinner])
    }

    /// Mensaje centrado (vacío o error) con botón opcional de reintento.
    func showMessage(_ text: String, retry: (() -> Void)? = nil) {
        var views: [UIView] = [makeLabel(text, style: .body, color: .secondaryLabel, alignment: .center)]
        if let retry {
            var configuration = UIButton.Configuration.filled()
            configuration.title = "Reintentar"
            configuration.baseBackgroundColor = LuminikStyle.blue
            configuration.baseForegroundColor = .white
            configuration.cornerStyle = .fixed
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 24, bottom: 14, trailing: 24)
            let button = UIButton(configuration: configuration)
            button.accessibilityIdentifier = "screen.retry"
            button.addAction(UIAction { _ in retry() }, for: .touchUpInside)
            views.append(button)
        }
        setContent(views)
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    // MARK: - Fábrica de vistas

    func makeLabel(
        _ text: String,
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

    func makeSectionTitle(_ text: String) -> UILabel {
        let label = makeLabel(text, style: .title2, alignment: .center)
        label.accessibilityTraits = .header
        return label
    }

    /// Fila "Título / valor" de las pantallas de información.
    func makeInfoRow(title: String, value: String) -> UIView {
        let titleLabel = makeLabel(title.uppercased(), style: .footnote, color: .secondaryLabel)
        let valueLabel = makeLabel(value.isEmpty ? "—" : value, style: .title3)
        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.isAccessibilityElement = true
        stack.accessibilityLabel = "\(title): \(value.isEmpty ? "sin dato" : value)"
        return stack
    }

    func makeBlockButton(
        title: String,
        background: UIColor = .black,
        identifier: String? = nil,
        action: @escaping () -> Void
    ) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.baseBackgroundColor = background
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .fixed
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 22, leading: 16, bottom: 22, trailing: 16)
        let button = UIButton(configuration: configuration)
        button.titleLabel?.font = LuminikStyle.serifFont(textStyle: .title2)
        button.accessibilityIdentifier = identifier
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    /// Tarjeta azul de las listas (contratos, historial, citas).
    func makeCard(icon: String, text: String, identifier: String? = nil, onTap: (() -> Void)? = nil) -> UIView {
        let card = LuminikCardControl()
        card.accessibilityIdentifier = identifier
        card.accessibilityLabel = text.replacingOccurrences(of: "\n", with: ". ")
        card.accessibilityTraits = onTap == nil ? .staticText : .button
        card.isUserInteractionEnabled = onTap != nil
        if let onTap {
            card.addAction(UIAction { _ in onTap() }, for: .touchUpInside)
        }

        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        iconView.isUserInteractionEnabled = false
        iconView.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(iconView)

        let label = makeLabel(text, style: .title3, color: .white)
        label.isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(label)

        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 110),
            iconView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 26),
            iconView.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),
            label.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            label.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18)
        ])
        return card
    }

    func showAlert(title: String, message: String, buttonTitle: String = "Aceptar", onDismiss: (() -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: buttonTitle, style: .default) { _ in onDismiss?() })
        present(alert, animated: true)
    }
}

/// Tarjeta azul tocable con retroalimentación al presionar.
final class LuminikCardControl: UIControl {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = LuminikStyle.blue
        layer.cornerRadius = 14
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.12) {
                self.alpha = self.isHighlighted ? 0.85 : 1
            }
        }
    }
}

/// Textos de fecha que comparten las pantallas.
enum LuminikText {
    /// Mensaje que muestra Android cuando se mezclan servicios de valoración y normales.
    static let valuationMixError = "No puedes agendar contratos de valoración y normales en una misma cita"
    static let valuationNotice = "Su cita es una cita de valoración, por favor presentarse a cita con el vello crecido como se lo indico su enfermera. si tiene alguna duda comunicarse a sucursal"
}
