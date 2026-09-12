import SwiftUI
import WidgetKit

@main
struct MonocleWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BudgetWidget()
        TodaySpendingWidget()
        QuickCaptureWidget()
        SpendingActivityWidget()
    }
}
