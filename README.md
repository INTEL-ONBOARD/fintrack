# FinTrack

FinTrack is a native iOS personal finance app. It records transactions locally and presents budgets and spending reports. An existing external API will be connected after its contract is available.

## Project layout

- `ios/` - SwiftUI app, Core Data store, and iOS integrations.

Manual entry works without a network connection. SMS import uses a user-configured Shortcut that passes message text to the app; it does not read the SMS inbox directly.

Setup and test commands will be documented as each component is added.
