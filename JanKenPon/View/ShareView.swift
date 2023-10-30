//
//  ShareView.swift
//  JanKenPon
//
//  Created by Ed Gamble on 11/14/23.
//

import SwiftUI
import UIKit
import CloudKit
import CoreData

/// This struct wraps a `UICloudSharingController` for use in SwiftUI.
struct CloudSharingView: UIViewControllerRepresentable {

    // MARK: - Properties

    @Environment(\.presentationMode) var presentationMode
    let container: CKContainer
    let object: NSManagedObject
    let share: CKShare?
    let handler: (NSManagedObject, @escaping (CKShare?, CKContainer?, Error?) -> Void) -> Void

    // MARK: - UIViewControllerRepresentable

    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {}

    func makeUIViewController(context: Context) -> some UIViewController {
        let sharingController: UICloudSharingController
        if let share = share {
            sharingController = UICloudSharingController (share: share, container: container)
        }
        else {
            sharingController = UICloudSharingController { (_, completion: @escaping (CKShare?, CKContainer?, Error?) -> Void) in
                handler (object, completion)
            }
        }

        sharingController.availablePermissions = [.allowReadWrite, .allowPrivate]
        sharingController.delegate = context.coordinator
        sharingController.modalPresentationStyle = .formSheet
        return sharingController
    }

    func makeCoordinator() -> CloudSharingView.Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            debugPrint("Error saving share: \(error)")
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            "Sharing Example"
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            debugPrint("Did save share")
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            debugPrint("Did stop share")
        }

    }
}

//private func shareView() -> CloudSharingView? {
//    guard let share = activeShare, let container = activeContainer else {
//        return nil
//    }
//
//    return CloudSharingView(container: container, share: share)
//}

///// Builds a Contact row view for display contact information in a List.
//private func contactRowView(for contact: Contact, shareable: Bool = true) -> some View {
//    HStack {
//        VStack(alignment: .leading) {
//            Text(contact.name)
//            Text(contact.phoneNumber)
//                .textContentType(.telephoneNumber)
//                .font(.footnote)
//        }
//        if shareable {
//            Spacer()
//            Button(action: { Task { try? await shareContact(contact) } }, label: { Image(systemName: "square.and.arrow.up") }).buttonStyle(BorderlessButtonStyle())
//                .sheet(isPresented: $isSharing, content: { shareView() })
//        }
//    }
//}
//
