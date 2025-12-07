//
//  LifelogWidgetsBundle.swift
//  LifelogWidgets
//
//  Created for Widget Implementation
//

import WidgetKit
import SwiftUI

@main
struct LifelogWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ScheduleWidget()
        HabitWidget()
        AnniversaryWidget()
        MemoWidget()
    }
}
