import SwiftUI

struct TestTeamBadge:View {
    var body:some View {
        Label("我的球队",systemImage:"star.fill").font(.system(size:10,weight:.semibold))
            .foregroundStyle(Theme.green).padding(.horizontal,7).padding(.vertical,3)
            .background(Theme.green.opacity(0.1),in:Capsule()).fixedSize()
            .accessibilityLabel("我的测试球队")
    }
}
struct LeagueTeamLabel:View {
    let name:String
    let highlighted:Bool
    var body:some View {
        HStack(spacing:7) {
            Text(name).fontWeight(highlighted ? .semibold:.regular).lineLimit(1).help(name)
            if highlighted {TestTeamBadge()}
        }
    }
}
extension View {
    func testTeamHighlight(_ active:Bool)->some View {
        self.padding(.horizontal,8).padding(.vertical,6)
            .background(active ? Theme.green.opacity(0.08):Color.clear,in:RoundedRectangle(cornerRadius:6))
            .overlay(alignment:.leading){if active {RoundedRectangle(cornerRadius:2).fill(Theme.green).frame(width:3).padding(.vertical,5)}}
    }
}
