# FinTrack

FinTrack is a native iOS personal finance app. It records transactions locally, synchronizes account data with a REST API, and presents budgets and spending reports.

## Project layout

- `ios/` - SwiftUI app, Core Data store, and iOS integrations.
- `server/` - REST API and database-backed account data.

The app is designed to keep manual entry available without a network connection. SMS import uses a user-configured Shortcut that passes message text to the app; it does not read the SMS inbox directly.

Setup and test commands will be documented as each component is added.
