//
//  NCAssistantCreateNewTask.swift
//  Nextcloud
//
//  Created by Milen on 09.04.24.
//  Copyright © 2024 Marino Faggiana. All rights reserved.
//

import SwiftUI

struct NCAssistantCreateNewTask: View {
    @EnvironmentObject var model: NCAssistantModel
    @State var text = ""
    @FocusState private var inFocus: Bool
    @Environment(\.presentationMode) var presentationMode
    var editMode = false

    var body: some View {
        VStack {
            Text(model.selectedType?.description ?? "")
                .frame(maxWidth: .infinity, alignment: .topLeading)

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(NSLocalizedString("_input_", comment: ""))
                        .padding(24)
                        .foregroundStyle(.secondary)
                }

                TextEditor(text: $text)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding()
                    .transparentScrolling()
                    .background(Color(NCBrandColor.shared.textColor2).opacity(0.1))
                    .focused($inFocus)
                    .accessibilityIdentifier("InputTextEditor")
            }
            .background(Color(NCBrandColor.shared.textColor2).opacity(0.1))
            .clipShape(.rect(cornerRadius: 8))
        }
        .toolbar {
            Button(action: {
                model.scheduleTask(input: text)
                presentationMode.wrappedValue.dismiss()
            }, label: {
                Text(NSLocalizedString(editMode ? "_edit_" : "_create_", comment: ""))
            })
            .disabled(text.isEmpty)
        }
        .navigationTitle(String(format: NSLocalizedString(editMode ? "_edit_task_" : "_new_task_", comment: ""), model.selectedType?.name ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .padding()
        .onAppear {
            inFocus = true
        }
    }
}

#Preview {
    let model = NCAssistantModel(controller: nil)

    NCAssistantCreateNewTask()
        .environmentObject(model)
        .onAppear {
            model.loadDummyData()
        }
}

private extension View {
    func transparentScrolling() -> some View {
        return scrollContentBackground(.hidden)
    }
}
