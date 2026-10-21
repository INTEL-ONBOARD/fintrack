# Architecture

FinTrack has a native SwiftUI client and an account-scoped REST API. Core Data holds the working copy of finance data on the device. The API stores a synchronized copy for the signed-in account.

## Transaction path

1. Manual entry, a Shortcut, receipt OCR, or voice input produces a transaction draft.
2. The draft is validated and classified. Imported data that is incomplete or ambiguous is reviewed before saving.
3. The saved transaction appears immediately from local data.
4. A sync worker uploads pending changes and retrieves remote changes when connectivity returns.
5. Dashboard, budgets, reports, and widgets derive their values from persisted transactions.

Each transaction has a client-generated identifier. Repeated uploads must update the same record rather than create duplicates. Deletions remain visible to synchronization as tombstones until the server acknowledges them. Financial amounts use exact minor currency units or decimal values throughout the client and API.

## Financial rules

- Expenses and bank fees increase spending.
- Income and interest increase income.
- Refunds reduce spending.
- Transfers between the user's own accounts do not increase income or spending.
- Cash withdrawals are tracked without counting them as a purchase.

Reports apply explicit date boundaries and the user's calendar and time zone. A monthly budget is evaluated against expense totals after refunds and edits.

## Security and privacy

The API authorizes every account-scoped operation. Credentials are stored in Keychain, and biometric authentication is an optional local access control. Receipt recognition and text classification run on-device. SMS content enters through a user-configured Shortcut; the app has no direct inbox access.

## Verification

Automated checks cover parser rejection and extraction, transaction classification, money and budget calculations, date boundaries, duplicate prevention, and offline sync behavior. The iOS app is built and exercised in Simulator; camera, biometrics, speech, widgets, and notifications also need device-level checks before release.
