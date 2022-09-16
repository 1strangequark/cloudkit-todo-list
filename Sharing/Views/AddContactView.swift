//
//  AddToDoView.swift
//  (cloudkit-samples) Sharing
//

import Foundation
import SwiftUI

/// View for adding new toDos.
struct AddToDoView: View {
    @State private var nameInput: String = ""

    let onAdd: ((String) async throws -> Void)?
    let onCancel: (() -> Void)?

    var body: some View {
        NavigationView {
            VStack {
                TextField("What do you need to do?", text: $nameInput)
                    .textContentType(.name)
                Spacer()
            }
            .padding()
            .navigationTitle("New To Do Item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: { onCancel?() })
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: { Task { try? await onAdd?(nameInput) } })
                        .disabled(nameInput.isEmpty)
                }
            }
        }
    }
}
