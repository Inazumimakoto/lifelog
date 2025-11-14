# GEMINI.md

## Project Overview

This is a comprehensive lifelogging iOS application built with SwiftUI. The app is designed to be a single place for users to manage their daily lives, inspired by the Bullet Journal method. It integrates various aspects of life including schedules, tasks, diary entries, habits, and health data.

The project follows the MVVM (Model-View-ViewModel) architecture. It uses a central `AppDataStore` to manage the application's state, which is passed down to various views as an environment object. The UI is built entirely with SwiftUI, and the app is designed for iOS 17 and above.

The application is structured into four main tabs:
*   **Today:** A dashboard view that provides a summary of the current day's events, tasks, habits, and health data.
*   **Calendar:** A calendar view that displays events from EventKit and allows for adding and editing events.
*   **Habits & Countdown:** A section for tracking habits and counting down to important anniversaries.
*   **Health:** A dashboard for visualizing health data, including steps, sleep, and fitness data from HealthKit.

## Building and Running

To build the project, use the following command:

```sh
xcodebuild -project lifelog.xcodeproj -scheme lifelog -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

**Note:** If you encounter issues with the CoreSimulatorService, you may need to run the build on a machine with a simulator or a connected iOS device.

## Development Conventions

*   **Architecture:** The project uses the MVVM design pattern. Views are responsible for the UI, ViewModels contain the business logic, and Models represent the data structures.
*   **State Management:** The application uses a centralized `AppDataStore` to manage shared state. This object is injected into the view hierarchy as an environment object.
*   **Documentation:** The project is well-documented.
    *   `docs/requirements.md`: Contains the detailed functional and non-functional requirements for the application.
    *   `docs/ui-guidelines.md`: Provides specific UI and UX guidelines for each screen.
    *   `AGENTS.md`: Contains guidelines for contributors.
*   **Code Style:** The code is written in Swift and follows standard Swift conventions. The UI is built using SwiftUI.
*   **Data Persistence:** The application currently uses an in-memory `AppDataStore` for data persistence. The documentation mentions plans to migrate to Core Data and CloudKit in the future.
*   **Dependencies:** The project uses standard iOS frameworks like SwiftUI, EventKit, HealthKit, and PhotosUI. There are no external package dependencies mentioned in the documentation.
