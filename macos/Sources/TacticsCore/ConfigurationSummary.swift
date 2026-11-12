import Foundation

extension NativeTeamInput {
    /// Keep stored notes unchanged for old experiment fingerprints.
    public var executionNotes:[String] {
        notes.map {text in
            if preparationSource != nil,text.hasPrefix("双方由手动战术控制") {
                return "本场使用已保存的赛前方案；首发 11 人及最多 9 名候补，不运行生涯 AI 临场执教。"
            }
            return text
        }
    }
}

extension NativeTeamInput {
    public var playerInstructionLines:[String] {
        phases.enumerated().flatMap {phase,cells in cells.enumerated().compactMap {i,c in
            let choices=c.instructions.compactMap {id in NativeCatalog.playerInstructions.first{$0.options.contains{$0.id==id}}.flatMap{g in g.options.first{$0.id==id}.map{g.label+"："+$0.label}}}
            guard !choices.isEmpty else{return nil}
            var suffix=""
            if c.targetPlayer != 255 {suffix=" · 对方名单第 \(c.targetPlayer+1) 人"}
            if c.targetPosition != 0 {suffix=" · "+(NativeCatalog.positions.first{$0.mask==c.targetPosition}?.label ?? "未知位置")}
            return players[i].name+" · "+(phase==0 ? "有球":"无球")+" · "+choices.joined(separator:"；")+suffix
        }}
    }
    public var setPieceLines:[String] {
        var lines=GameSetPieceKind.allCases.flatMap {kind in setPieces.routines[kind.id].map {r in
            var line=kind.label+" · "+r.name+" · "+["较少","正常","更多"][r.frequency]
            if kind.strategyLabels.indices.contains(r.strategy){line+=" · "+kind.strategyLabels[r.strategy]}
            if kind.hasSwing{line+=" · "+["内旋","外旋"][r.swing]}
            let taskNames=kind.attacking ? GameSetPieces.attackTasks:GameSetPieces.defendTasks
            line+=" · "+r.priority.map {g in GameSetPieces.categories[g]+"："+r.groups[g].enumerated().map {i,task in taskNames[task]+(r.backups[g][i]==0 ? "":"（备选："+taskNames[r.backups[g][i]]+"）")}.joined(separator:"、")}.joined(separator:"；")
            return line
        }}
        lines += setPieces.priorities.keys.sorted{Int($0)!<Int($1)!}.map {key in GameSetPieces.listNames[Int(key)!]+"："+setPieces.priorities[key]!.map{players[$0].name}.joined(separator:" → ")}
        lines += ["界外球（后场／中场／前场）："+setPieces.throwStyles.enumerated().map{i,v in i==2 ? (v==0 ? "短距离界外球":"长距离界外球"):(v==0 ? "保持球权":"沿边线推进")}.joined(separator:" / ")]
        return lines
    }
    public var conditionLines:[String] {
        players.map {p in
            let v=p.profile
            return p.name+" · 体能 \((v["15"] ?? 0)/100)% · 比赛状态 \((v["16"] ?? 0)/100)% · 疲劳原值 \(v["18"] ?? 0) · 士气 \(v["22"] ?? 0) · 凝聚力 \(v["20"] ?? 0) · CA \(v["11"] ?? 0)"
        }
    }
}
