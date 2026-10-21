# FinTrack

FinTrack is a SwiftUI personal finance app for iPhone. It saves data on the device with Core Data and uses LKR for amounts. The existing API can be connected when its contract is available.

## Run the app

1. Open `ios/FinTrack.xcodeproj` in Xcode.
2. Select the **FinTrack** scheme and an iPhone simulator, then press Run.
3. Tap **Get Started** on the first launch.

The app targets iOS 17 or later. No server or package installation is needed for local use.

## What works now

- Add, edit, delete, search, and filter transactions.
- Manage categories and monthly overall or category budgets.
- View an overview and spending reports for preset or custom dates.
- Paste a financial message or choose a receipt image, then review the extracted details before saving.
- Use the app's Shortcuts actions to prepare a message import or quick expense/income entry for review.
- Optionally require the device passcode or biometrics to open the app.

Message import needs a Shortcut configured by the user. FinTrack does not read the SMS inbox. Receipt text recognition runs on the device. Shortcut automation and biometric behavior should also be checked on an iPhone before release.

## Tests

Run the **FinTrackTests** target in Xcode, or use a simulator ID from `xcrun simctl list devices available`:

```sh
xcodebuild -project ios/FinTrack.xcodeproj -scheme FinTrack \
  -destination 'platform=iOS Simulator,id=<simulator-id>' \
  CODE_SIGNING_ALLOWED=NO test
```

## Next development steps

Connect the existing API after its base URL, authentication method, endpoint schemas, and sync rules are provided. Account sign-in, online backup, notifications, widgets, and location views are not part of this local milestone.
