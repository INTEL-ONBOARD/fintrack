# Architecture

FinTrack is a native SwiftUI app. Core Data stores finance data on the device. Integration with the existing external API will follow once its endpoints and authentication contract are available.

## Transaction path

1. Manual entry, a Shortcut, receipt OCR, or voice input produces a transaction draft.
2. The draft is validated and classified. Imported data that is incomplete or ambiguous is reviewed before saving.
3. The saved transaction appears immediately from local data.
4. Dashboard, budgets, and reports derive their values from persisted transactions.

Each transaction has a client-generated identifier. Financial amounts use exact minor currency units. The future API integration will need idempotent uploads, offline retries, and a clear deletion rule.

## Financial rules

- Expenses and bank fees increase spending.
- Income and interest increase income.
- Refunds reduce spending.
- Transfers between the user's own accounts do not increase income or spending.
- Cash withdrawals are tracked without counting them as a purchase.

Reports apply explicit date boundaries and the user's calendar and time zone. A monthly budget is evaluated against expense totals after refunds and edits.

## Security and privacy

Biometric authentication can be used as a local access control. Receipt recognition and text classification run on-device. SMS content enters through a user-configured Shortcut; the app has no direct inbox access. API credentials will be stored in Keychain when integration is added.

## Verification

Automated checks cover parser rejection and extraction, money and budget calculations, and date boundaries. The iOS app is built and exercised in Simulator; camera, biometrics, speech, widgets, and notifications also need device-level checks before release.
