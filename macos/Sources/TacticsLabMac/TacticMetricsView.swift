import SwiftUI
import Charts
import TacticsCore

struct TacticMetricsView:View {
    let reports:[OriginalMatchReport]
    var focusSides:[UInt32:Int]=[:]
    @State private var metric:TacticalMetric = .goals
    var body:some View {
        let groups=TacticMatchGroup.aggregate(reports,focusSides:focusSides)
        VStack(alignment:.leading,spacing:16) {
            Text("按本队完整战术分组；阵型、角色、指令、定位球或临场规则不同会另列。每行的对手数据来自同一组比赛。").font(.system(size:11)).foregroundStyle(Theme.muted)
            Card {
                HStack {Text("战术数据对比").font(.system(size:15,weight:.semibold));Spacer();Picker("指标",selection:$metric){ForEach(TacticalMetric.allCases){Text($0.title).tag($0)}}.frame(width:230)}
                Chart {
                    ForEach(Array(groups.enumerated()),id:\.element.id){index,group in
                        ForEach(0...1,id:\.self){side in
                            if let value=metric.value(group.impact,side:side) {
                                BarMark(x:.value(metric.title,value),y:.value("战术","战术 \(index+1)"),height:.ratio(0.7))
                                    .foregroundStyle(by:.value("球队",side==0 ? "本队":"对手")).position(by:.value("球队",side==0 ? "本队":"对手"))
                                    .annotation(position:.trailing){Text(metric.format(value)).font(.system(size:10)).monospacedDigit()}
                            }
                        }
                    }
                }.chartForegroundStyleScale(["本队":Theme.green,"对手":Theme.amber]).chartLegend(.hidden)
                    .chartYAxis {AxisMarks(preset:.aligned,position:.leading){_ in AxisValueLabel(anchor:.trailing)}}
                    .chartXAxisLabel(metric.title+(metric.percent ? " · %":""))
                    .chartXScale(domain:0...chartMaximum(groups)).frame(height:CGFloat(max(150,groups.count*75)))
                ForEach(Array(groups.enumerated()),id:\.element.id){index,g in
                    Text("战术 \(index+1) · \(g.shape) · \(g.reports.count) 场 · 编号 \(g.id.prefix(8))").font(.system(size:11)).foregroundStyle(Theme.muted)
                }
            }
            ForEach(Array(groups.enumerated()),id:\.element.id){index,group in
                Card {
                    Text("战术 \(index+1) · \(group.reports.count) 场比赛").font(.system(size:15,weight:.semibold))
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:320),spacing:24)],spacing:10) {
                        ForEach(TacticalMetric.allCases){m in
                            HStack {Text(m.title);Spacer();Text(m.format(m.value(group.impact,side:0))).foregroundStyle(Theme.green).frame(width:62,alignment:.trailing);Text(m.format(m.value(group.impact,side:1))).foregroundStyle(Theme.amber).frame(width:62,alignment:.trailing)}.font(.system(size:12)).monospacedDigit()
                        }
                    }
                }
            }
            Text("场均值只计有该项数据的完赛记录。成功率按总量相除；射门转化率＝本队球员进球 ÷ 射门，不含对方乌龙球。控球率按每场等权平均。有进球场次占比＝至少进一球的场次 ÷ 完赛场次。缺失数据或分母为零显示 —。").font(.system(size:11)).foregroundStyle(Theme.muted)
        }
    }
    private func chartMaximum(_ groups:[TacticMatchGroup])->Double {
        let highest=groups.flatMap{g in (0...1).compactMap{metric.value(g.impact,side:$0)}}.max() ?? 0
        return max(1,highest)*1.25
    }
}
