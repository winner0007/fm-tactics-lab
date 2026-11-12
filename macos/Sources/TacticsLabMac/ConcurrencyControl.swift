import SwiftUI
import TacticsCore

struct ConcurrencyControl:View {
    @EnvironmentObject var store:LabStore
    var body:some View {
        HStack(spacing:5) {
            Text("并行").font(.system(size:11))
            TextField("1–256",value:$store.simulationWorkers,format:.number.grouping(.never))
                .frame(width:48).textFieldStyle(.roundedBorder).accessibilityLabel("并行通道数")
            Menu {
                Button("使用本机建议：\(SimulationConcurrency.recommended) 路"){store.simulationWorkers=SimulationConcurrency.recommended}
                ForEach([1,2,4,8,16,32],id:\.self){n in Button("\(n) 路"){store.simulationWorkers=n}}
            } label:{Image(systemName:"slider.horizontal.3")}.menuStyle(.borderlessButton).fixedSize()
        }.disabled(store.runningOriginal || store.leagueRunning)
            .help("同时计算的比赛数，支持 1–256，自动记住。建议 \(SimulationConcurrency.recommended) 路；可按内存与运行速度调整。续跑可更改通道数。")
    }
}
