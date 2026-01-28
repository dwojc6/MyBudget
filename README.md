# MyBudget

A privacy-focused iOS budget tracker built with SwiftUI. Seamlessly syncs with the LunchMoney API to import transactions and trigger Plaid updates. Features emoji-based categorization, monthly budget tracking, and a clean, native interface. No external servers—your data connects directly from your device to LunchMoney.

# MyBudget - LunchMoney Companion App

A native iOS budget tracker built with SwiftUI that integrates directly with the [LunchMoney](https://lunchmoney.app/) API. 

This app is designed to be a privacy-first, lightweight mobile interface for your finances. It pulls your latest transactions, automatically categorizes them based on keywords, and helps you track your monthly spending goals with a clean, emoji-friendly dashboard.

## 🚀 Features

* **Direct API Integration:** Connects directly to LunchMoney's v2 API. No intermediate servers or data collection.
* **Plaid Sync Trigger:** The "Sync Now" button triggers a fresh fetch from Plaid via LunchMoney, ensuring your data is always up to date.
* **Smart Categorization:** Automatically sorts common transactions into categories (Groceries, Utilities, Dining, etc.) using keyword matching.
* **Transaction Cleaning:** Automatically strips clutter from bank descriptions (e.g., removes "CHECKCARD", "POS PURCHASE", and random ID numbers) for a cleaner view.
* **Budget Progress:** Visual progress bars for every category to track spending vs. budget in real-time.
* **Manual Entry:** Quickly add cash transactions or pending items manually.
* **Privacy Focused:** Your API token is stored securely on your device and used only for direct network calls to LunchMoney.

## 📱 Screenshots

| Dashboard | Setup Screen | Transaction List |
|:---:|:---:|:---:|
| <img src="Screenshots/Dashboard.png" width="250"> | <img src="Screenshots/Setup.png" width="250"> | <img src="Screenshots/Transactions.png" width="250"> |

## ⚙️ Setup & Installation

1.  **Prerequisites:**
    * A [LunchMoney](https://lunchmoney.app/) account.
    * Xcode 16.0+ installed on your Mac.
    * iOS 18.0+ device or simulator.

2.  **Get your API Token:**
    * Log in to LunchMoney.
    * Go to **Settings** > **Developers**.
    * Create or copy your **Access Token**.

3.  **Run the App:**
    ```bash
    git clone [https://github.com/yourusername/mybudget-ios.git](https://github.com/yourusername/mybudget-ios.git)
    cd mybudget-ios
    open MyBudget.xcodeproj
    ```
    * Select your target simulator or device in Xcode.
    * Press **Cmd + R** to build and run.

4.  **Initial Configuration:**
    * On the first launch, you will be prompted to enter your **Current Bank Balance** (to establish a baseline) and your **LunchMoney Access Token**.
    * Select a "Start Date" to pull transactions from.

## 🧩 Customization

### Categories & Budgets
The app comes with a standard set of emoji-coded categories (e.g., 💰 Paycheck, 🛒 Groceries, 🏠 Household). 
* **To change budgets:** Tap on any category row in the dashboard to set a new monthly limit.
* **To modify logic:** Check `BudgetModels.swift` to customize the keyword matching rules for your specific spending habits.

### Transaction Cleaning
The app uses Regex in `BudgetModels.swift` to clean up messy bank descriptions. You can modify the `uiName` property logic to filter out specific patterns relevant to your bank.

## 🤝 Contributing

Contributions are welcome! If you'd like to add features like charts, tag management, or Recurring Expenses support:

1.  Fork the repository.
2.  Create your feature branch (`git checkout -b feature/AmazingFeature`).
3.  Commit your changes (`git commit -m 'Add some AmazingFeature'`).
4.  Push to the branch (`git push origin feature/AmazingFeature`).
5.  Open a Pull Request.

## 📄 License

Distributed under the MIT License. See [License](LICENSE) for more information.

## 🙏 Acknowledgments

* Thanks to [LunchMoney](https://lunchmoney.app/) for providing an excellent API for personal finance.
* Built with ❤️ using SwiftUI.
