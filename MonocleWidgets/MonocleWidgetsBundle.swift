import SwiftUI
import WidgetKit

@main
struct MonocleWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BudgetWidget()
        StackWidget()
        TodaySpendingWidget()
        QuickCaptureWidget()
        SpendingActivityWidget()
    }
}
