//
//  ContentView.swift
//  (cloudkit-samples) Sharing
//

import SwiftUI
import CloudKit

struct ContentView: View {

    @EnvironmentObject private var vm: ViewModel

    @State private var isAddingContact = false
    @State private var isSharing = false
    @State private var isProcessingShare = false

    @State private var activeShare: CKShare?
    @State private var activeContainer: CKContainer?
    @State private var checkedItems: Set<CKRecord.ID> = []

    var body: some View {
        NavigationView {
            contentView
                .navigationTitle("To Do List")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button { Task { try await vm.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        progressView
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { isAddingContact = true }) { Image(systemName: "plus") }
                    }
                }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            Task {
                try await vm.initialize()
                try await vm.refresh()
            }
        }
        .sheet(isPresented: $isAddingContact, content: {
            AddContactView(onAdd: addContact, onCancel: { isAddingContact = false })
        })
    }

    var progressView: some View {
        let showProgress: Bool = {
            if case .loading = vm.state {
                return true
            } else if isProcessingShare {
                return true
            }

            return false
        }()

        return Group {
            if showProgress {
                ProgressView()
            }
        }
    }

    private var contentView: some View {
        Group {
            switch vm.state {
            case let .loaded(privateContacts, sharedContacts):
                List {
                    ForEach(privateContacts) { contactRowView(for: $0, isChecked: checkedItems.contains($0.recordID)) }
                    ForEach(sharedContacts) { contactRowView(for: $0, isChecked: checkedItems.contains($0.recordID), shareable: false) }
                }
            case .error(let error):
                VStack {
                    Text("An error occurred: \(error.localizedDescription)").padding()
                    Spacer()
                }

            case .loading:
                VStack { ProgressView().progressViewStyle(CircularProgressViewStyle()) }
            }
        }
    }

    /// Builds a `CloudSharingView` with state after processing a share.
    private func shareView() -> CloudSharingView? {
        guard let share = activeShare, let container = activeContainer else {
            return nil
        }

        return CloudSharingView(container: container, share: share)
    }


    /// Builds a Contact row view for display contact information in a List.
    private func contactRowView(for contact: Contact, isChecked: Bool, shareable: Bool = true) -> some View {
        HStack {
            Button(action: {
                Task {
                    try await checkOff(contact:contact)
                }
            }) {
                Image(systemName: isChecked ? "checkmark.square" : "square")
            }
            Text(contact.name)
            if shareable {
                Spacer()
                Button(action: { Task { try? await shareContact(contact) } }, label: { Image(systemName: "square.and.arrow.up") }).buttonStyle(BorderlessButtonStyle())
                    .sheet(isPresented: $isSharing, content: { shareView() })
            }
        }
    }

    // MARK: - Actions

    private func addContact(name: String) async throws {
        try await vm.addContact(name: name)
        try await vm.refresh()
        isAddingContact = false
    }
    
    private func checkOff(contact: Contact) async throws {
        checkedItems.insert(contact.recordID)
        await Task.sleep(1 * 1_000_000_000)
        await vm.markAsChecked(contact)
        try await vm.refresh()
    }

    private func shareContact(_ contact: Contact) async throws {
        isProcessingShare = true

        do {
            let (share, container) = try await vm.fetchOrCreateShare(contact: contact)
            isProcessingShare = false
            activeShare = share
            activeContainer = container
            isSharing = true
        } catch {
            debugPrint("Error sharing contact record: \(error)")
        }
    }
}

//struct ContentView_Previews: PreviewProvider {
//    private static let previewContacts: [Contact] = [
//        Contact(
//            id: UUID().uuidString,
//            recordID: CKRecord().recordID,
//            name: "John Appleseed",
//            associatedRecord: CKRecord(recordType: "Contact")
//        )
//    ]
//
//    static var previews: some View {
//        ContentView()
//            .environmentObject(ViewModel(state: .loaded(private: previewContacts, shared: previewContacts)))
//    }
//}
