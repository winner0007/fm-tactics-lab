import Foundation

public enum NativeProfile {
    public static let defaults:[String:UInt32] = ["0":180,"1":25,"9":0,"10":0,"11":100,"12":5000,"13":5000,"14":5000,"19":75]
    public static func range(_ id:Int)->ClosedRange<UInt32>? {
        switch id {
        case 0:return 140...220
        case 1:return 14...60
        case 2...8,22:return 1...20
        case 9,10:return 0...UInt32.max
        case 11:return 0...200
        case 12...17:return 0...10000
        case 18:return 0...65535
        case 19:return 40...140
        case 20:return 25...82
        case 21:return 0...100
        default:return nil
        }
    }
    public static func validate(_ values:[String:UInt32])throws {
        for (key,v) in values {guard let id=Int(key),String(id)==key,let range=range(id),range.contains(v) else {throw LabError("球员资料字段 \(key) 的值超出原版输入范围。")}}
    }
}
extension Player {
    public mutating func setFoot(_ foot:String?) {
        preferredFoot=foot
        if nativeAttributes != nil {
            nativeAttributes?[39]=foot=="左脚" || foot=="双脚" ? 100:50
            nativeAttributes?[40]=foot=="左脚" ? 50:foot==nil ? 50:100
        }
    }
    public mutating func setPositionDescription(_ value:String) {
        position=value
        if nativeAttributes != nil {
            for i in 0..<15 {nativeAttributes?[i]=1}
            for key in positionKeys {if let i=NativeTeamInput.positionAttribute[key]{nativeAttributes?[i]=20}}
        }
    }
    public mutating func setAttribute(_ key:String,_ value:Int?) {
        attributes[key]=value;abilityPreset=nil
        if let index=NativeTeamInput.attributes[key],nativeAttributes != nil {nativeAttributes?[index]=(value ?? 10)*5}
    }
}
