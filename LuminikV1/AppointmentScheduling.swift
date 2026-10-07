import UIKit

struct ScheduleService: Hashable, Sendable {
    let id: String
    let name: String
    let durationMinutes: Int
}

struct ScheduleContract: Hashable, Sendable {
    let folio: String
    let type: String
    let services: [ScheduleService]
}

@MainActor
final class AppointmentDraft {
    let contracts = [
        ScheduleContract(
            folio: "L362",
            type: "LINFONIK",
            services: [
                ScheduleService(id: "l362-back", name: "LINFONIK ESPALDA 6 4-SARAH SANTOS", durationMinutes: 15),
                ScheduleService(id: "l362-waist", name: "LINFONIK ABDOMEN-CINTURA 6 4-SARAH SANTOS", durationMinutes: 20)
            ]
        ),
        ScheduleContract(
            folio: "HP336",
            type: "FACIAL",
            services: [ScheduleService(id: "hp336-face", name: "FACIAL - SARAH SANTOS", durationMinutes: 30)]
        ),
        ScheduleContract(
            folio: "B14",
            type: "BODYSCULPTS",
            services: [
                ScheduleService(id: "b14-glute", name: "GLÚTEO - SARAH SANTOS", durationMinutes: 15),
                ScheduleService(id: "b14-legs", name: "PIERNAS - SARAH SANTOS", durationMinutes: 20)
            ]
        )
    ]

    var selectedContractFolios: Set<String> = []
    var selectedServiceIDs: Set<String> = []
    var cabin = ""
    var notes = ""
    var date: Date?
    var time = ""

    var availableServices: [ScheduleService] {
        contracts
            .filter { selectedContractFolios.contains($0.folio) }
            .flatMap(\.services)
    }

    var selectedServices: [ScheduleService] {
        availableServices.filter { selectedServiceIDs.contains($0.id) }
    }

    var totalDuration: Int {
        selectedServices.reduce(0) { $0 + $1.durationMinutes }
    }
}

final class ScheduleSelectionViewController: UIViewController {
    private let draft: AppointmentDraft
    private let contractsStack = UIStackView()
    private let servicesStack = UIStackView()
    private let confirmButton = UIButton(type: .system)

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
        rebuildContracts()
        rebuildServices()
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
        confirmButton.addAction(UIAction { [weak self] _ in self?.showCabinModal() }, for: .touchUpInside)
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
    }

    private func rebuildContracts() {
        contractsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for contract in draft.contracts {
            let selected = draft.selectedContractFolios.contains(contract.folio)
            let button = UIButton(type: .system)
            var configuration = UIButton.Configuration.filled()
            configuration.title = "FOLIO: \(contract.folio)\nTIPO: \(contract.type)"
            configuration.image = UIImage(systemName: selected ? "checkmark.square.fill" : "list.clipboard")
            configuration.imagePlacement = .leading
            configuration.imagePadding = 12
            configuration.baseBackgroundColor = selected ? LuminikStyle.blue : .secondarySystemBackground
            configuration.baseForegroundColor = selected ? .white : .label
            configuration.cornerStyle = .large
            button.configuration = configuration
            button.titleLabel?.font = LuminikStyle.serifFont(textStyle: .body)
            button.titleLabel?.numberOfLines = 2
            button.widthAnchor.constraint(equalToConstant: 250).isActive = true
            button.accessibilityIdentifier = "schedule.contract.\(contract.folio)"
            button.addAction(UIAction { [weak self] _ in self?.toggleContract(contract.folio) }, for: .touchUpInside)
            contractsStack.addArrangedSubview(button)
        }
    }

    private func rebuildServices() {
        servicesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if draft.availableServices.isEmpty {
            servicesStack.addArrangedSubview(makeLabel("Selecciona uno o varios contratos para ver sus servicios.", style: .body, alignment: .center))
        } else {
            for service in draft.availableServices {
                let selected = draft.selectedServiceIDs.contains(service.id)
                let button = UIButton(type: .system)
                var configuration = UIButton.Configuration.plain()
                configuration.title = "\(service.name)\nTIEMPO ESTIMADO: \(service.durationMinutes) MIN."
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
                button.accessibilityIdentifier = "schedule.service.\(service.id)"
                button.addAction(UIAction { [weak self] _ in self?.toggleService(service.id) }, for: .touchUpInside)
                servicesStack.addArrangedSubview(button)
            }
        }
        confirmButton.isEnabled = !draft.selectedServices.isEmpty
        confirmButton.alpha = confirmButton.isEnabled ? 1 : 0.45
    }

    private func toggleContract(_ folio: String) {
        if draft.selectedContractFolios.contains(folio) {
            draft.selectedContractFolios.remove(folio)
        } else {
            draft.selectedContractFolios.insert(folio)
        }
        let availableIDs = Set(draft.availableServices.map(\.id))
        draft.selectedServiceIDs.formIntersection(availableIDs)
        rebuildContracts()
        rebuildServices()
    }

    private func toggleService(_ id: String) {
        if draft.selectedServiceIDs.contains(id) {
            draft.selectedServiceIDs.remove(id)
        } else {
            draft.selectedServiceIDs.insert(id)
        }
        rebuildServices()
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

private final class CabinSelectionViewController: UIViewController {
    private let draft: AppointmentDraft
    private let onAccept: () -> Void
    private let cabinButton = UIButton(type: .system)
    private let notesField = UITextField()
    private let cabins = ["CABINA PASEO LA FE", "CABINA 1", "CABINA 2", "CABINA 3"]

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
        cabinConfiguration.title = draft.cabin.isEmpty ? "Seleccionar cabina" : draft.cabin
        cabinConfiguration.image = UIImage(systemName: "chevron.down")
        cabinConfiguration.imagePlacement = .trailing
        cabinConfiguration.baseForegroundColor = .label
        cabinConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 14, bottom: 16, trailing: 14)
        cabinButton.configuration = cabinConfiguration
        cabinButton.contentHorizontalAlignment = .fill
        cabinButton.accessibilityIdentifier = "schedule.cabin"
        cabinButton.menu = UIMenu(children: cabins.map { cabin in
            UIAction(title: cabin) { [weak self] _ in self?.selectCabin(cabin) }
        })
        cabinButton.showsMenuAsPrimaryAction = true
        card.addArrangedSubview(cabinButton)

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
        let accept = UIButton(type: .system)
        accept.setTitle("ACEPTAR", for: .normal)
        accept.accessibilityIdentifier = "schedule.acceptCabin"
        accept.addAction(UIAction { [weak self] _ in self?.accept() }, for: .touchUpInside)
        actions.addArrangedSubview(cancel)
        actions.addArrangedSubview(accept)
        card.addArrangedSubview(actions)

        NSLayoutConstraint.activate([
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36)
        ])
    }

    private func selectCabin(_ cabin: String) {
        draft.cabin = cabin
        cabinButton.configuration?.title = cabin
    }

    private func accept() {
        guard !draft.cabin.isEmpty else {
            cabinButton.configuration?.baseForegroundColor = .systemRed
            UIAccessibility.post(notification: .announcement, argument: "Selecciona una cabina")
            return
        }
        draft.notes = notesField.text ?? ""
        onAccept()
    }
}

private final class ScheduleCalendarViewController: UIViewController {
    private let draft: AppointmentDraft
    private let datePicker = UIDatePicker()
    private let slotsStack = UIStackView()

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
        dateChanged()
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
        back.accessibilityLabel = "Volver a servicios"
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
        stack.addArrangedSubview(datePicker)

        let duration = UILabel()
        duration.text = "TIEMPO CITA: \(draft.totalDuration) MIN."
        duration.font = LuminikStyle.serifFont(textStyle: .title2, weight: .semibold)
        stack.addArrangedSubview(duration)

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

    @objc private func dateChanged() {
        draft.date = datePicker.date
        rebuildSlots()
    }

    private func rebuildSlots() {
        slotsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let day = Calendar.current.component(.day, from: datePicker.date)
        let allSlots = day.isMultiple(of: 2)
            ? ["09:30", "11:00", "14:30", "17:15", "19:45", "20:30"]
            : ["09:41", "09:56", "14:46", "16:20", "20:10", "20:40"]
        for pairStart in stride(from: 0, to: allSlots.count, by: 3) {
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .fillEqually
            row.spacing = 12
            for time in allSlots[pairStart..<min(pairStart + 3, allSlots.count)] {
                let button = UIButton(type: .system)
                var configuration = UIButton.Configuration.filled()
                configuration.title = time
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
            slotsStack.addArrangedSubview(row)
        }
    }

    private func selectTime(_ time: String) {
        draft.time = time
        let summary = ScheduleSummaryViewController(draft: draft)
        summary.modalPresentationStyle = .fullScreen
        present(summary, animated: true)
    }
}

private final class ScheduleSummaryViewController: UIViewController {
    private let draft: AppointmentDraft

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
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.dateFormat = "dd-MM-yyyy"
        let dateText = draft.date.map(formatter.string) ?? "Sin fecha"
        let notes = draft.notes.isEmpty ? "SIN OBSERVACIONES" : draft.notes.uppercased()
        let details = "FECHA: \(dateText)\nHORA: \(draft.time)\nTIEMPO DE CITA: \(draft.totalDuration) MIN.\nTIPO DE CITA: NORMAL\nCABINA: \(draft.cabin)\nOBSERVACIONES: \(notes)"
        stack.addArrangedSubview(makeLabel(details, style: .title3))
        stack.addArrangedSubview(makeLabel("SERVICIOS", style: .largeTitle, alignment: .center))

        for service in draft.selectedServices {
            let icon = UIImageView(image: UIImage(systemName: "list.clipboard"))
            icon.tintColor = LuminikStyle.blue
            icon.widthAnchor.constraint(equalToConstant: 36).isActive = true
            let row = UIStackView(arrangedSubviews: [icon, makeLabel(service.name, style: .title3)])
            row.axis = .horizontal
            row.alignment = .center
            row.spacing = 10
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
            stack.addArrangedSubview(row)
        }

        let schedule = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.title = "AGENDAR"
        configuration.baseBackgroundColor = LuminikStyle.blue
        configuration.baseForegroundColor = .white
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 24, leading: 20, bottom: 24, trailing: 20)
        schedule.configuration = configuration
        schedule.titleLabel?.font = LuminikStyle.serifFont(textStyle: .largeTitle)
        schedule.accessibilityIdentifier = "schedule.finish"
        schedule.addAction(UIAction { [weak self] _ in self?.finish() }, for: .touchUpInside)
        stack.addArrangedSubview(schedule)

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
        let alert = UIAlertController(title: "Cita agendada", message: "La cita mock fue registrada correctamente.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Aceptar", style: .default) { [weak self] _ in
            self?.view.window?.rootViewController?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }
}
