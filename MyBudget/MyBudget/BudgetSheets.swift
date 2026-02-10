//
//  BudgetSheets.swift
//  MyBudget
//
//  Created by David Wojcik on 1/25/26.
//

import SwiftUI

struct AddTransactionView: View {
    @ObservedObject var store: BudgetStore
    @Environment(\.presentationMode) var presentationMode
    
    @State private var payee: String = ""
    @State private var amountString: String = ""
    @State private var category: String = ""
    @State private var date: Date = Date()
    @State private var notes: String = ""
    @State private var isExpense: Bool = true // NEW: Track transaction type

    private var availableCategories: [String] {
        let filtered = store.categoryNames.filter { $0 != "Uncategorized" }
        return filtered.isEmpty ? ["Uncategorized"] : filtered
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Details")) {
                    // NEW: Transaction Type Picker
                    Picker("Type", selection: $isExpense) {
                        Text("Expense").tag(true)
                        Text("Income").tag(false)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.vertical, 4)
                    
                    TextField("Payee Name", text: $payee)
                    
                    // CHANGED: Removed negative overlay hint, kept decimalPad
                    TextField("Amount", text: $amountString)
                        .keyboardType(.decimalPad)
                    
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
                
                Section(header: Text("Category")) {
                    Picker("Category", selection: $category) {
                        ForEach(availableCategories, id: \.self) { name in
                            Text(name.displayWithoutEmoji).tag(name)
                        }
                    }
                }
                
                Section(header: Text("Notes")) {
                    TextField("Memo / Description", text: $notes)
                }
                
                Button("Add Transaction") {
                    if let decimal = Decimal(string: amountString), !payee.isEmpty {
                        // NEW: Calculate positive/negative based on picker
                        let finalAmount = isExpense ? -abs(decimal) : abs(decimal)
                        
                        store.addManualTransaction(payee: payee, amount: finalAmount, category: category, date: date, memo: notes)
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                .disabled(payee.isEmpty || amountString.isEmpty)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .navigationTitle("Add Transaction")
            .navigationBarItems(trailing: Button("Cancel") { presentationMode.wrappedValue.dismiss() })
            .onAppear {
                if !availableCategories.contains(category) {
                    category = availableCategories.first ?? "Uncategorized"
                }
            }
        }
    }
}

struct AddCategoryView: View {
    @ObservedObject var store: BudgetStore; @Environment(\.presentationMode) var presentationMode; @State private var name: String = ""; @State private var amountString: String = ""
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("New Category Details")) { TextField("Category Name", text: $name); TextField("Monthly Budget", text: $amountString).keyboardType(.decimalPad) }
                Button("Create Category") { if let decimal = Decimal(string: amountString), !name.isEmpty { store.addCategory(name: name, amount: decimal); presentationMode.wrappedValue.dismiss() } }
                .disabled(name.isEmpty || amountString.isEmpty).frame(maxWidth: .infinity, alignment: .center)
            }
            .navigationTitle("Add Category").navigationBarItems(trailing: Button("Cancel") { presentationMode.wrappedValue.dismiss() })
        }
    }
}

struct EditBalanceView: View {
    @ObservedObject var store: BudgetStore; @Environment(\.presentationMode) var presentationMode; @State private var amountString: String = ""
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Global Starting Balance"), footer: Text("This balances affects all periods historically.")) { TextField("Amount", text: $amountString).keyboardType(.decimalPad) }
                Button("Save") { if let decimal = Decimal(string: amountString) { store.setStartingBalance(decimal); presentationMode.wrappedValue.dismiss() } }.frame(maxWidth: .infinity, alignment: .center)
            }
            .navigationTitle("Set Balance").navigationBarItems(trailing: Button("Cancel") { presentationMode.wrappedValue.dismiss() }).onAppear { amountString = "\(store.startingBalance)" }
        }
    }
}

struct EditTransactionView: View {
    @ObservedObject var store: BudgetStore
    let transaction: SimpleFinTransaction
    @Environment(\.presentationMode) var presentationMode
    @State private var selectedCategory: String = ""
    @State private var editedPayee: String = ""
    @State private var isSaving = false
    @State private var showPayeeErrorAlert = false
    @State private var payeeErrorMessage = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Transaction Details")) {
                    Text(transaction.uiName).font(.headline)
                    Text(formatCurrency(transaction.decimalAmount))
                }

                Section(header: Text("Payee")) {
                    TextField("Payee", text: $editedPayee)
                        .textInputAutocapitalization(.words)
                }

                Section(header: Text("Change Category")) {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(store.categoryNames, id: \.self) { name in
                            Text(name.displayWithoutEmoji).tag(name)
                        }
                    }
                    .pickerStyle(.wheel)
                }

                Button(isSaving ? "Saving..." : "Save Changes") {
                    isSaving = true
                    let newCategory = selectedCategory
                    let newPayee = editedPayee
                    Task {
                        store.updateCategory(for: transaction.id, to: newCategory)
                        let (success, errorMessage) = await store.updateTransactionPayee(for: transaction.id, to: newPayee)
                        isSaving = false
                        if success {
                            presentationMode.wrappedValue.dismiss()
                        } else {
                            payeeErrorMessage = errorMessage ?? "Unable to update payee."
                            showPayeeErrorAlert = true
                        }
                    }
                }
                .disabled(isSaving)
                .frame(maxWidth: .infinity, alignment: .center)
                .foregroundColor(.blue)
            }
            .navigationTitle("Edit Transaction")
            .navigationBarItems(trailing: Button("Cancel") { presentationMode.wrappedValue.dismiss() })
            .onAppear {
                selectedCategory = store.getCategory(for: transaction)
                editedPayee = transaction.payee ?? transaction.uiName
            }
            .alert("Update Failed", isPresented: $showPayeeErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(payeeErrorMessage)
            }
        }
    }
}
