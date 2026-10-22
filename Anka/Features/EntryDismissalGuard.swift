import SwiftUI
import UIKit

/// SwiftUI exposes dismissal disabling but not the attempted-swipe callback.
/// Use the public presentation delegate to ask before abandoning an edited form.
struct EntryDismissalGuard: UIViewControllerRepresentable {
    let needsConfirmation: Bool
    let attemptedDismiss: () -> Void

    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.needsConfirmation = needsConfirmation
        controller.attemptedDismiss = attemptedDismiss
        controller.connect()
        // A newly presented sheet may attach its hosting parent after this update.
        DispatchQueue.main.async { controller.connect() }
    }

    final class Controller: UIViewController, UIAdaptivePresentationControllerDelegate {
        var needsConfirmation = false
        var attemptedDismiss: (() -> Void)?
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            connect()
        }
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            connect()
        }
        func connect() {
            var controller: UIViewController? = parent
            while let current = controller {
                // NavigationStack adds intermediate controllers. Guard the full hosting
                // chain rather than stopping at a child's unused presentation controller.
                current.isModalInPresentation = needsConfirmation
                current.presentationController?.delegate = self
                controller = current.parent
            }
        }
        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
            !needsConfirmation
        }
        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            if needsConfirmation { attemptedDismiss?() }
        }
    }
}
