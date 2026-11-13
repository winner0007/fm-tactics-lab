import Foundation
import CryptoKit

/// Only these entries belong to test history. Editor setups, presets and imports
/// deliberately stay in the application's configuration directory.
public enum ExperimentStorage {
    public static let markerName=".fm-tactics-lab-experiments"
    public static let marker=Data("fm-tactics-lab/experiments/1".utf8)
    public static let directories=["engine-runs","league-runs","experiments"]
    public static let snapshots=["experiment.csv","experiment.json","latest-batch.json","original-matches.json","latest-league.json"]
    public static let names=directories+snapshots
    public static func entries(at root:URL)throws->[URL] {
        let fm=FileManager.default
        return try names.compactMap {name in
            let url=root.appendingPathComponent(name)
            guard fm.fileExists(atPath:url.path) else{return nil}
            try check(url,under:root)
            return url
        }
    }
    public static func check(_ url:URL,under root:URL)throws {
        let base=root.standardizedFileURL.resolvingSymlinksInPath().path+"/"
        let actual=url.standardizedFileURL.resolvingSymlinksInPath().path
        guard actual.hasPrefix(base),let first=actual.dropFirst(base.count).split(separator:"/").first,names.contains(String(first)),
              !(try url.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink ?? false) else {throw LabError("测试数据路径不在当前保存目录内，未执行操作。")}
    }
    public static func inventory(_ root:URL)throws->[String:String] {
        let root=root.standardizedFileURL.resolvingSymlinksInPath()
        var result:[String:String]=[:]
        func visit(_ url:URL)throws {
            try check(url,under:root)
            let info=try url.resourceValues(forKeys:[.isDirectoryKey,.isRegularFileKey])
            let relative=String(url.standardizedFileURL.resolvingSymlinksInPath().path.dropFirst(root.path.count+1))
            if info.isDirectory==true {
                result[relative]="directory"
                for child in try FileManager.default.contentsOfDirectory(at:url,includingPropertiesForKeys:nil) {try visit(child)}
            } else {
                guard info.isRegularFile==true else{throw LabError("测试目录包含不支持的文件类型。")}
                let handle=try FileHandle(forReadingFrom:url);defer{try? handle.close()}
                var hash=SHA256()
                while let data=try handle.read(upToCount:1_048_576),!data.isEmpty {hash.update(data:data)}
                result[relative]=hash.finalize().map{String(format:"%02x",$0)}.joined()
            }
        }
        for url in try entries(at:root) {try visit(url)}
        return result
    }
    public static func copyHistory(from source:URL,to destination:URL)throws {
        let fm=FileManager.default,source=source.standardizedFileURL.resolvingSymlinksInPath(),destination=destination.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().appendingPathComponent(destination.lastPathComponent)
        guard source != destination,!destination.path.hasPrefix(source.path+"/"),!source.path.hasPrefix(destination.path+"/") else {throw LabError("新位置不能是当前数据目录或它的上下级目录。")}
        guard fm.fileExists(atPath:source.path) else{throw LabError("原测试目录不可用，请先连接磁盘。")}
        guard !fm.fileExists(atPath:destination.path) else{throw LabError("目标文件夹已存在，未覆盖任何数据。")}
        let before=try inventory(source)
        try fm.createDirectory(at:destination,withIntermediateDirectories:true)
        do {
            for url in try entries(at:source) {try fm.copyItem(at:url,to:destination.appendingPathComponent(url.lastPathComponent))}
            guard try inventory(destination)==before,try inventory(source)==before else{throw LabError("复制校验未通过或原目录发生变化，仍使用原位置。")}
            try marker.write(to:destination.appendingPathComponent(markerName),options:.atomic)
        } catch {try? fm.removeItem(at:destination);throw error}
    }
}
