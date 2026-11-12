import Foundation
import CryptoKit

public struct EngineDiagnostic:Codable,Identifiable {
    public let title:String
    public let passed:Bool
    public var id:String {title}
}

public struct EngineSearchEnvironment {
    public var home: URL
    public var applicationFolders: [URL]
    public var volumes: [URL]
    public init(home: URL, applicationFolders: [URL], volumes: [URL]) {
        self.home=home; self.applicationFolders=applicationFolders; self.volumes=volumes
    }
    public static var current: EngineSearchEnvironment {
        let fm=FileManager.default
        return EngineSearchEnvironment(home:fm.homeDirectoryForCurrentUser,
            applicationFolders:[URL(fileURLWithPath:"/Applications"),fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),URL(fileURLWithPath:"/Users/Shared/Epic Games")],
            volumes:(try? fm.contentsOfDirectory(at:URL(fileURLWithPath:"/Volumes"),includingPropertiesForKeys:nil,options:.skipsHiddenFiles)) ?? [])
    }
}

public struct EngineReport: Codable {
    public let appPath: String?
    public let version: String
    public let architectures: [String]
    public let pluginFound: Bool
    public let canSimulate: Bool
    public let reason: String
    public var discoverySource: String = ""
    public var searchedLocations: [String] = []
    public var diagnostics: [EngineDiagnostic] = []
    public var binarySHA256: String? = nil
    public var installationFound: Bool { appPath != nil && pluginFound && !architectures.isEmpty }
    public var filesReady: Bool { installationFound && !diagnostics.isEmpty && diagnostics.allSatisfy(\.passed) }
    public var adapterSupported:Bool {filesReady && architectures.contains("arm64") && binarySHA256==OriginalMatchReport.engineHash}
    public var compatibilityMessage:String {adapterSupported ? "此引擎指纹在已验证范围内，比赛结果仍需通过逐场回读校验。":"当前游戏版本 \(version) 的比赛引擎尚未适配。可继续编辑、读取已支持存档及查看历史报告；模拟和游戏战术 FMF 读写暂不可用。"}
    public static var searching: EngineReport { EngineReport(appPath:nil,version:"正在查找",architectures:[],pluginFound:false,canSimulate:false,reason:"正在检查 Steam 游戏库、应用程序目录与已挂载磁盘。") }

    public static func inspect(app: URL? = nil, preferredApp: URL? = nil, environment: EngineSearchEnvironment = .current) -> EngineReport {
        let fm=FileManager.default
        var candidates:[(URL,String)]=[], checked=[String](), seen=Set<String>()
        func add(_ url: URL, _ source: String) {
            let normalized=url.standardizedFileURL.resolvingSymlinksInPath()
            if seen.insert(normalized.path).inserted { candidates.append((normalized,source)) }
        }
        func directory(_ root: URL, _ source: String) {
            checked.append(root.path)
            if root.pathExtension.lowercased()=="app" { add(root,source); return }
            for name in ["fm.app","Football Manager 27.app","Football Manager 27/fm.app","Football Manager 27/Football Manager 27.app","FootballManager27/fm.app","FM27/fm.app"] { add(root.appendingPathComponent(name),source) }
            // Scan only immediate FM27-named children, never an entire disk.
            for item in (try? fm.contentsOfDirectory(at:root,includingPropertiesForKeys:nil,options:.skipsHiddenFiles)) ?? [] {
                let name=item.lastPathComponent.lowercased().replacingOccurrences(of:" ",with:"")
                if name.contains("footballmanager27") || name=="fm27" { add(item.pathExtension=="app" ? item : item.appendingPathComponent("fm.app"),source) }
            }
        }
        func steam(_ root: URL, _ source: String) {
            directory(root.appendingPathComponent("steamapps/common"),source)
            directory(root.appendingPathComponent("SteamApps/common"),source)
        }
        if let app {
            directory(app,"手动指定")
        } else {
            if let preferredApp { directory(preferredApp,"上次指定的位置") }
            var roots=[environment.home.appendingPathComponent("Library/Application Support/Steam")]
            for volume in environment.volumes {
                for name in ["SteamLibrary","Steam","Games/SteamLibrary","Games/Steam","Games","Application Support/Steam","Library/Application Support/Steam"] { roots.append(volume.appendingPathComponent(name)) }
            }
            let initialRoots=roots
            for root in initialRoots {
                for relative in ["steamapps/libraryfolders.vdf","config/libraryfolders.vdf"] {
                    let vdf=root.appendingPathComponent(relative)
                    if let text=try? String(contentsOf:vdf,encoding:.utf8) {
                        roots.append(contentsOf:steamLibraries(text).map { URL(fileURLWithPath:$0) })
                    }
                }
            }
            for root in roots { steam(root,"Steam 游戏库") }
            for root in environment.applicationFolders {
                directory(root,"应用程序目录")
                directory(root.appendingPathComponent("Steam"),"应用程序目录")
                directory(root.appendingPathComponent("Epic Games"),"Epic 游戏目录")
            }
            for volume in environment.volumes {
                for name in ["Applications","Games","Epic Games"] { directory(volume.appendingPathComponent(name),"外置磁盘常见目录") }
            }
        }
        var manualFailure:EngineReport?
        var partialInstallation:EngineReport?
        for (candidate,source) in candidates {
            guard fm.fileExists(atPath:candidate.appendingPathComponent("Contents/Info.plist").path) else { continue }
            var report=readApplication(candidate)
            report.discoverySource=source; report.searchedLocations=Array(Set(checked)).sorted()
            if report.filesReady { return report }
            if report.installationFound { partialInstallation=partialInstallation ?? report }
            // A manual choice must get an actionable validation result. Automatic
            // discovery skips broken/stale apps and continues to the next library.
            if app != nil { manualFailure=manualFailure ?? report }
            if app?.pathExtension.lowercased()=="app" { return report }
        }
        if let partialInstallation { return partialInstallation }
        if let manualFailure { return manualFailure }
        return EngineReport(appPath:nil,version:"未发现安装",architectures:[],pluginFound:false,canSimulate:false,
            reason:"常见路径中未找到完整的 FM27。请指定 fm.app 或包含它的游戏文件夹。",discoverySource:"自动查找未找到",searchedLocations:Array(Set(checked)).sorted())
    }

    public static func steamLibraries(_ text: String) -> [String] {
        guard let regex=try? NSRegularExpression(pattern:#""(?:path|[0-9]+)"\s+"(/[^"]+)""#) else { return [] }
        return regex.matches(in:text,range:NSRange(text.startIndex...,in:text)).compactMap { match in
            Range(match.range(at:1),in:text).map { String(text[$0]).replacingOccurrences(of:"\\\\",with:"\\") }
        }
    }

    private static func readApplication(_ location: URL) -> EngineReport {
        let info=(try? Data(contentsOf:location.appendingPathComponent("Contents/Info.plist"))).flatMap { try? PropertyListSerialization.propertyList(from:$0,format:nil) as? [String:Any] }
        let version=info?["CFBundleShortVersionString"] as? String ?? "未知版本"
        let isFM27=version.hasPrefix("27.") && ((info?["CFBundleIdentifier"] as? String).map { $0.lowercased().contains("footballmanager27") } ?? true)
        let plugin=location.appendingPathComponent("Contents/PlugIns/game_plugin.bundle/Contents/MacOS/game_plugin")
        var architectures:[String]=[]
        if isFM27, let handle=try? FileHandle(forReadingFrom:plugin) {
            defer { try? handle.close() }
            if let bytes=try? handle.read(upToCount:512) { architectures=machArchitectures(bytes).filter { ["arm64","x86_64"].contains($0) } }
        }
        let found=isFM27 && FileManager.default.fileExists(atPath:plugin.path)
        var reason = !isFM27 ? "所选应用不是可识别的 FM27，请重新选择。" : (!found || architectures.isEmpty ? "所选安装的引擎文件缺失或无法识别，请选择完整的 FM27。" : "已识别 FM27 安装与 Mac 引擎文件，游戏位置设置成功。")
        let bundle=location.appendingPathComponent("Contents/PlugIns/game_plugin.bundle/Contents")
        let resources=[("游戏共享资源","Resources/shared"),("国际化资源","Resources/icudt65l.dat"),("Steam 动态库","Frameworks/libsteam_api.dylib"),("EOS 动态库","Frameworks/libEOSSDK-Mac-Shipping.dylib"),("PlayFab 通信框架","Frameworks/PlayFabPartyMac.framework"),("PlayFab 多人框架","Frameworks/PlayFabMultiplayerFramework_macOS.framework")]
        let checks=[EngineDiagnostic(title:"FM27 应用版本",passed:isFM27),EngineDiagnostic(title:"Mach-O 引擎与架构",passed:found && !architectures.isEmpty)] + resources.map { EngineDiagnostic(title:$0.0,passed:FileManager.default.fileExists(atPath:bundle.appendingPathComponent($0.1).path)) }
        if isFM27 && found && !architectures.isEmpty && !checks.allSatisfy(\.passed) { reason="已识别 FM27，但部分配套文件缺失。请检查游戏安装，或指定另一处完整安装。" }
        var result=EngineReport(appPath:location.path,version:version,architectures:architectures,pluginFound:found,canSimulate:false,reason:reason,diagnostics:checks)
        if found,let handle=try? FileHandle(forReadingFrom:plugin) {
            defer{try? handle.close()}
            do {var hash=SHA256();while let bytes=try handle.read(upToCount:1_048_576),!bytes.isEmpty {hash.update(data:bytes)};result.binarySHA256=hash.finalize().map{String(format:"%02x",$0)}.joined()}catch{}
        }
        return result
    }

    public static func machArchitectures(_ data: Data) -> [String] {
        let b = Array(data)
        func number(_ offset: Int, little: Bool = false) -> UInt32 {
            guard offset+4 <= b.count else { return 0 }
            let a = Array(b[offset..<offset+4])
            return (little ? a.reversed().map { $0 } : a).reduce(0) { ($0 << 8) | UInt32($1) }
        }
        func label(_ n: UInt32) -> String { n == 0x0100000c ? "arm64" : (n == 0x01000007 ? "x86_64" : "CPU \(n)") }
        let magic = number(0)
        if magic == 0xcafebabe || magic == 0xcafebabf {
            let count = min(Int(number(4)), 10), stride = magic == 0xcafebabe ? 20 : 32
            guard 8+count*stride <= b.count else { return [] }
            return (0..<count).map { label(number(8+$0*stride)) }
        }
        if magic == 0xcffaedfe { return [label(number(4,little:true))] }
        if magic == 0xfeedfacf { return [label(number(4))] }
        return []
    }
}
