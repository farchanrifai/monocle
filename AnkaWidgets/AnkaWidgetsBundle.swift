import SwiftUI
import WidgetKit

@main
struct AnkaWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BudgetWidget()
        StackWidget()
        TodaySpendingWidget()
        QuickCaptureWidget()
        SpendingActivityWidget()
        if #available(iOS 18.0, *) {
            QuickEntryControl()
        }
    }
}
