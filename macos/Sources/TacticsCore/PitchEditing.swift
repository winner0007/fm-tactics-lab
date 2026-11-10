import Foundation

extension Tactic {
    public func overlapTarget(slotID: Int, phase: Phase, point: Point, width: Double, height: Double) -> Int? {
        guard slots.contains(where: { $0.id == slotID }), point.x.isFinite, point.y.isFinite, width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        var target:Int?, nearest=Double.infinity
        for slot in slots where slot.id != slotID {
            let p=slot.point(phase)
            let distance=hypot((p.x-point.x)*width,(p.y-point.y)*height)
            if distance <= 32 && (distance < nearest || (distance == nearest && slot.id < (target ?? Int.max))) { target=slot.id; nearest=distance }
        }
        return target
    }

    // Player identities swap between fixed tactical slots. Coordinates and tasks
    // remain attached to the slots, and the shared lineup updates both phases.
    @discardableResult public mutating func dropPlayer(slotID: Int, phase: Phase, point: Point, width: Double, height: Double) -> Int? {
        guard let source = slots.firstIndex(where: { $0.id == slotID }), point.x.isFinite, point.y.isFinite else { return nil }
        let p = Point(min(0.95,max(0.05,point.x)),min(0.95,max(0.05,point.y)))
        if let targetID = overlapTarget(slotID:slotID,phase:phase,point:p,width:width,height:height), let target = slots.firstIndex(where: { $0.id == targetID }) {
            let player = slots[source].playerID
            slots[source].playerID = slots[target].playerID; slots[target].playerID = player
            return targetID
        }
        if phase == .possession { if slots[source].possession != p { slots[source].possession=p; formation="自定义" } }
        else if slots[source].defending != p { slots[source].defending=p; defensiveFormation="自定义" }
        return nil
    }
}
