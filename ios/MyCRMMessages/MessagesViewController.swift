import Messages
import MyCRMShared
import UIKit

/// Stub iMessage app extension — expand later for CRM cards / log-to-thread actions.
final class MessagesViewController: MSMessagesAppViewController {
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .title3)
        label.text = AppConfig.isConfigured
            ? "My CRM\niMessage integration stub\n(Shared config loaded)"
            : "My CRM\nOpen the app to configure your Mac CRM."
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}
