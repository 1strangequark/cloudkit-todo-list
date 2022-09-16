//
//  ContentView.swift
//  (cloudkit-samples) Sharing
//

import SwiftUI
import CloudKit

struct ContentView: View {

    @EnvironmentObject private var vm: ViewModel

    @State private var isAddingToDo = false
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
                        Button(action: { isAddingToDo = true }) { Image(systemName: "plus") }
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
        .sheet(isPresented: $isAddingToDo, content: {
            AddToDoView(onAdd: addToDo, onCancel: { isAddingToDo = false })
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
            case let .loaded(privateToDos, sharedToDos):
                List {
                    ForEach(privateToDos) { toDoRowView(for: $0, isChecked: checkedItems.contains($0.recordID)) }
                    ForEach(sharedToDos) { toDoRowView(for: $0, isChecked: checkedItems.contains($0.recordID), shareable: false) }
                }
            case .error(let error):
//                List {
//
//                }
//                 This is helpful for debugging purposes
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


    /// Builds a ToDo row view for display toDo information in a List.
    private func toDoRowView(for toDo: ToDo, isChecked: Bool, shareable: Bool = true) -> some View {
        HStack {
            Button(action: {
                Task {
                    try await checkOff(toDo:toDo)
                }
            }) {
                Image(systemName: isChecked ? "checkmark.square" : "square")
            }
            Text(toDo.name)
            if shareable {
                Spacer()
                Button(action: { Task { try? await shareToDo(toDo) } }, label: { Image(systemName: "square.and.arrow.up") }).buttonStyle(BorderlessButtonStyle())
                    .sheet(isPresented: $isSharing, content: { shareView() })
            }
        }
    }

    // MARK: - Actions

    private func addToDo(name: String) async throws {
        try await vm.addToDo(name: name)
        try await vm.refresh()
        isAddingToDo = false
    }
    
    private func checkOff(toDo: ToDo) async throws {
        checkedItems.insert(toDo.recordID)
        await Task.sleep(1 * 1_000_000_000)
        await vm.markAsChecked(toDo)
//        try await vm.initialize()
        try await vm.refresh()
        
    }

    private func shareToDo(_ toDo: ToDo) async throws {
        isProcessingShare = true

        do {
            let (share, container) = try await vm.fetchOrCreateShare(toDo: toDo)
            isProcessingShare = false
            activeShare = share
            activeContainer = container
            isSharing = true
        } catch {
            debugPrint("Error sharing toDo record: \(error)")
        }
    }
}

//struct ContentView_Previews: PreviewProvider {
//    private static let previewToDos: [ToDo] = [
//        ToDo(
//            id: UUID().uuidString,
//            recordID: CKRecord().recordID,
//            name: "John Appleseed",
//            associatedRecord: CKRecord(recordType: "ToDo")
//        )
//    ]
//
//    static var previews: some View {
//        ContentView()
//            .environmentObject(ViewModel(state: .loaded(private: previewToDos, shared: previewToDos)))
//    }
//}
