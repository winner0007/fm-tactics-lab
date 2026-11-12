# 接手 Mac 版开发

## 当前做到哪里

0.6 增加新开档读取、球队锁定、对手战术分组报告和游戏更新检测。原版比赛仍只验证了旧的 27.0.0.2493426；本机已更新到 27.0.1.2503222，当前可读新存档，不能运行新版引擎。上游 Windows 代码保留在原目录，Mac 实现在 `macos/`。

当前只适配 FM27 `27.0.0.2493426` 的指定 arm64 二进制；引擎指纹、字段和 ABI 依据在 [实测记录](MAC_ENGINE_STATUS.md)。游戏更新后要重新验证，不能只改版本字符串。

## 代码入口

| 要改什么 | 从哪里看 |
| --- | --- |
| 球员、战术和原版功能目录 | `Sources/TacticsCore/Models.swift`、`NativeCatalog.swift`、`GameTactics.swift`、`GameSetPieces.swift` |
| 随机属性与个人资料 | `AbilityPresets.swift`、`NativeProfile.swift` |
| 送入比赛的配置与校验 | `NativeScenario.swift`、`native/EngineScenario.h`、`EngineSetPieces.h` |
| Mac 引擎启动与自然完赛 | `native/EngineRuntimeProbe.mm`、`EngineABI_arm64.S` |
| 编辑哪支球队、自动保存和撤销 | `Sources/TacticsLabMac/Store.swift`、`LeagueStore.swift`、`EditingTeamBar.swift` |
| 存档读取 | `runtime/SaveReader.py` → 上游 `src/desktop_save_*`；Swift 侧 `SaveReaderJob.swift`、`SaveImport.swift` |
| 方案库与 FMF | `TeamPreset.swift`、`TeamPresetStore.swift`、`FMF.swift`、`TacticFileJob.swift`、`native/EngineTactics.h` |
| 联赛排程与排名 | `LeagueSimulation.swift`；界面 `LeagueView.swift` |
| 统计与报告 | `OriginalMatchReport.swift`、`BatchExport.swift`、`LeagueExport.swift` |

阵型、角色、指令锁定和定位球任务参照上游 v1109.3（`6cb32bf`）。修改个人指令策略后运行 `scripts/sync-native-policy.py`，保持 Swift 编辑器与原生宿主的校验一致。

## 球队和实验的数据关系

`Workspace` 保存普通对战双方；`LeagueSetup.teams` 中每个 `LeagueTeam` 保存独立的 `plan`。`LabStore.editing` 和 `change` 统一处理当前球队，战术页和球员页不能再直接改全局 `workspace`。每支联赛球队有自己的撤销记录。

“复制普通对战球队”只复制一次。联赛编辑直接更新选中球队，球队名和战术名分开；随机单队不能影响其他队、首发身份或战术。

`LeagueRun` 保存开赛时的整套配置和固定赛程，运行、续跑和报告都读它，不读正在编辑的 `leagueSetup`。普通批次同样保存 `NativeScenario`。目录、文件格式、导出和恢复过程见 [数据说明](DATA_FORMATS.md)。

## 怎样验证

在仓库根目录运行 `bash macos/scripts/check.sh` 和 `bash macos/scripts/build.sh`。存档读取组件需要 Python 3.11+ 构建，发布应用无需用户安装 Python。

- `check-engine.py`：用安装包内置阵容检查 9 场原版比赛、同种子复现、边界种子和取消。
- `check-workbench.sh`：验证 12 阵型及状态、盯人、队长、定位球变化。依次传绝对路径：输出目录、宿主、`fm.app`；可再传存档阵容和目录 JSON 跑完整联赛。
- `CheckLeagueReport.swift`：复核整赛季配置、身份、种子、排名和汇总，拒绝被改动的报告。
- `check-tactic-files.sh`：12 阵型经原版 FMF 写入／归档读取／战术解析再导入，保留中文名、职责与附加位；畸形归档拒绝。
- `check-fmf-archives.py`：用 SaveReader 构建虚拟环境运行，核对上游 Windows 封装兼容性与原版压缩归档读取；参数同上，为输出目录、宿主和 `fm.app`。
- 应用参数 `--scenario-smoke <目录> --data-dir <目录>/data`：检查普通批次、球队编辑隔离、单队随机、联赛停止续跑、配置快照、恢复和截图。可追加 `--save-smoke <存档路径>` 验证打包后的读取组件。

测试必须用隔离目录。最终本机证据放在 `.build/evidence-v05/`；不提交真实存档、导入阵容、日志或反汇编。游戏文件只读，运行中的比赛使用独立进程。

## 下一步

### 已核对上游 v1112（2026-11-12）

对照提交 `dc10a12`，Mac 主干仍基于 `6cb32bf`，没有整体合入新版 Windows 适配器。优先看这些已实现的路线：

已单独移植 `desktop_save_compat.py` 的正式版布局与辅助指令映射修复，并为本机 `27.0.1+2503222` 增加经过球队／赛程读取验证的精确登记。这不会改变原生比赛适配器。继续适配时必须重新定位 Mac 函数、对象布局和线程状态，不能只替换旧引擎哈希。

| 项目 | Mac 当前状态 | 上游参考与移植要点 |
| --- | --- | --- |
| 原版 AI 生成 | 尚未接通；当前导入真实球员后使用明确的工具模板 | `desktop_real_generation.py`、`desktop_real_generation_prepare.py`、`native_source_generation.h`：绑定真实教练及阵容，0 tick 准备后读取主／客场完整战术；先验证身份、阵容与原版回读，再接 UI。生成结果是固定预览计划，不是生涯实战还原。 |
| 引擎复用与并发 | 每场独立子进程，串行 | `desktop_warm_batch.py` 的协议 2：宿主能力握手、逐场清理执行力与线程状态、释放比赛对象、逐场超时取消。Mac 先证明冷／热运行一致和内存稳定，再开放并发；Windows 1–256 是输入范围，性能只实测到 8 路。 |
| 随机对手战术池 | 尚无独立池；可用多支独立联赛球队测试 | `fm27_tactic_pool.py`：按种子固定抽签、权重、A/B 共用对手抽签。与本版 `TacticPerformance` 分组报告衔接。不要把上游统一属性选项替换成我们的按位置随机。 |
| 正式版与 FMF | 已验证 27.0.0.2493426 及战术 FMF；未验证 27.0.1 | 上游版本为 27.0.1+2494687，`desktop_save_compat.py` 增加布局与辅助指令映射修复。Windows 地址和对象布局不能复制到 arm64；旧版本继续保留独立指纹。 |
| 球队、联赛名称 | 当前显示存档球队名和联赛 ID | `desktop_game_db_names.py` 可借鉴本机 lang_db.dat 名称读取；这不等于已有完整初始数据库导入。 |
| 定位球 FMF | 可编辑并执行，单独文件交换未接通 | 对照上游单独的定位球入口；战术 FMF 不含定位球，不能宣称已覆盖。 |

推荐顺序：原版 AI 生成和版本适配 → 对手池及配对实验 → 宿主复用与并发。职业生涯赛程生成、自动聘任和解雇主教练仍未接入，上游这次更新也未提供这些功能。

本机只读研究已用 Mac 原版 staff reader 验证新存档的 21 位 AI 教练偏好，但还没有接入正式导入链路。证据留在 `.build/evidence-save-20261112/`；不可将“读到教练”写成“已生成 AI 战术”。

### 其他待办

1. 原始 `.dat` 数据库：为快速选择真实球队与联赛解析初始阵容和赛事规则，不能用初始化 JSON 代替。目前支持新开档立即保存的 `.fm`。定位球套路 FMF 交换也待适配。
2. 更多原版统计：先核实字段的产生与读取位置，再加入助攻、分钟、评分等列；缺失项保持缺失。
3. 原生 A/B 队列：固定双方阵容，用相同种子分别运行两套战术，保留各自结果和配对关系。
4. 临场策略与跨场状态：换人、改阵、疲劳、伤停需要独立的原版调用验证。
5. 更完整的联赛规则：附加赛、分组、公平竞赛分和行政扣分不能套用普通积分榜排序。

战术理解、认同、对手情报和球员关系尚未接入。体能、比赛状态、疲劳原值、士气、凝聚力及七项性格已有映射。当前比赛仍是固定条件实验，不能将它描述成完整职业生涯模拟。

FMF 对照上游 `native_tactic_export.h`、`native_tactic_import.h`、`native_fmf_probe.h` 和 `src/fm27_fmf.py`。Mac 写入 `0x4a8d728`、读取 `0x4856b6c`，计划在 manager + `0x1800`，流虚表读写槽为 6（Windows 为 5），返回值遵循 Itanium ABI。FMF 归档由原版驱动读取，支持压缩条目；Swift 只封装原版生成的 TAC。职责与未命名球队位按上游规则保留，未知个人指令及无法表达的冲突拒绝。
