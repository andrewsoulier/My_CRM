import MyCRMShared
import UIKit

/// Stub custom keyboard — expand later for CRM snippets / contact insert.
final class KeyboardViewController: UIInputViewController {
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground

        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .label
        label.font = .preferredFont(forTextStyle: .body)
        label.text = AppConfig.isConfigured
            ? "My CRM Keyboard\n(Ready to extend — shared config loaded)"
            : "My CRM Keyboard\nOpen the My CRM app to set the server URL."
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}
