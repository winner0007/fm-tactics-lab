# FM 战术实验室 · Mac 原生版 v0.4

基于 [lqf0624/fm-tactics-lab](https://github.com/lqf0624/fm-tactics-lab) 的产品流程和公开源码调研，在同一仓库新增的 SwiftUI 客户端。上游检出版本：`6cb32bf`（v1109.3），调研日期 2026-11-10。上游 Windows 代码保持原样；本目录提供独立 Mac 草图模型，并直接兼容上游逐场 CSV。

**本版已能用本机 FM 原版引擎完成内置测试比赛，支持单场／多种子运行和真实统计图表。工作台自定义战术、球员、定位球还未写入引擎；不支持 `.fm` / `.fmf` 导入导出。**

## 启动

双击 `dist/FM Tactics Lab 0.4.app`。当前交付为 Apple Silicon 版本，要求 macOS 14 或以上，无需 Python、Node 或联网。使用本机临时签名，尚未做面向公开分发的 Developer ID 公证。

## 0.4 原版引擎更新

在「引擎与接入」自动找到游戏后，设置起始种子和 1 / 5 / 10 / 20 场，点击「开始原版模拟」。运行的是安装包自带的测试阵容与战术，不是工作台草图。每场递增种子、使用独立子进程，完成后可直接查看本批次球队与球员统计。

- 已实测原版 ICU、资源包、xG 模型、线程上下文、PKM 反序列化、比赛准备和自然终场。没有替代引擎，没有修改安装包、存档或原版机器指令。
- 固定支持本机 `27.0.0.2493426` arm64 二进制指纹；每次检查 SHA-256，不匹配就停止。Intel Mac 与其他补丁版本尚未适配。
- 球队：比分、xG、控球率、射门、射正、传球、成功传球、黄牌、红牌。球员：进球、xG、射门、射正、传球、成功传球、红黄牌；按原版 ID 显示，未映射姓名。未知的评分、助攻、出场分钟等保持缺失。
- 引擎页显示最近一场累计 xG 曲线；完整场次自动进入实验页，支持现有图表、明细和 CSV / JSON 导出。原始逐分钟记录和运行日志保留在本机。
- 仅接受自然完赛、退出码为 0、输入种子一致、统计合计通过的结果。取消、崩溃、45 秒超时、看门狗边界均不计入结果；中途停止保留已完成场次。
- 9 场命令行回归通过；同种子逐步进度及统计一致，不同种子结果变化。完整证据与 Mac ABI 差异见 [原版引擎实测记录](docs/MAC_ENGINE_STATUS.md)。
- 应用内 5 场连续运行通过，生成 200 条球员记录；重读数据一致，工作台未被改动。界面实测截图位于 `.build/evidence-v04/ui/`。

## 0.3 编辑与分析能力（继续保留）

- 能力档次改成每人、每项独立随机：随机 1–20、业余 3–7、半职业 5–10、职业 8–13、享誉国内 11–16、洲际 13–18、国际 15–20。支持全队、位置、个人；再次应用重新抽取，可撤销。这些区间是本工具的实验预设，不是 FM 的 CA／声望换算。
- 球员属性扩展到技术、精神、身体、门将、定位球；旧方案只有六项基础属性时，其余保持未知。名单支持首发／候补筛选、替换首发、添加候补、惯用脚和分组属性编辑。
- 定位球新增主罚排序、内旋／外旋、左右复制、四类职责优先级、各类球员排序、依首发递补；支持三段场地区域的界外球偏好和罚失后更换点球手。排序建议按界面说明中的相关属性等权计算，缺失属性不参与推荐，不冒充 FM 的内部评分。原来的按位置手工分工继续保留，启用人员排序后切换为按球员分工。
- 结果页新增球队指标对比图、胜平负分布、球员累计指标／平均评分图、分页比赛明细与球员赛后表。缺失指标保持为空，均值使用有记录场次的分母。
- 每次导入自动保存历史批次；球队 CSV、球员 CSV、完整批次 JSON 可导入／导出。可分析导入文件，也可分析 0.4 原版内置基线的实际输出。
- 保留独立的动态加载诊断入口。加载检查和完整原版模拟是两个独立操作。

继续保留：拖动重叠自动换位、双阶段战术板、球队／个人指令、状态／磨合／性格／关系记录、方案对照、撤销与自动安装路径查找。

**请退出旧版后再打开 0.4**，两版共用本地工作区。读取旧方案时保存迁移前备份；新文件使用 `tactics-lab-mac/3`，兼容读入版本 1 和 2，旧应用不能读取新版方案。

## 先这样用

1. 在「球员与阵容」导出 CSV 模板，填入自己的球员属性，再导入。内置名单是演示球员，不来自你的游戏存档。
2. 在「战术工作台」分别选择有球、无球阵型；拖拽调整站位，点击球员更换首发或任务。选中另一名已上场球员时，自动交换首发，避免重复上场。
3. 点击「设为对照」，保存战术与完整球员属性快照。每次只调整一项指令，在下方查看差异与结构提醒。「恢复对照」也恢复球员属性。
4. 通过「导出方案」保存 Mac JSON；之后可重新导入。更改自动保存在本机，支持 `⌘Z` 撤销、`⇧⌘Z` 重做、`⌘O` 打开和 `⇧⌘S` 导出。
5. 若已有 Windows 版实验结果，在「实验对比」导入逐场 CSV，选择对照和改动方案，查看配对净胜球变化和探索性区间。

战术体检与对照卡片在球场下方，可向下滚动查看。任务「保护、串联、拉开、前插」是草图概念，未映射成游戏原生角色。滑杆采用本工具 1–5 档，不等同于 FM 序列化字段。

## 数据格式与统计范围

球员 CSV 保留必需列 `name,position,pace,stamina,passing,decisions,tackling,finishing`，也支持对应中文表头。模板包含全部扩展属性列，可留空；已填写的属性必须为 1–20。`preferred_foot` 可填左脚、右脚、双脚或留空。名单 11–100 人，前 11 人成为初始首发；导入替换名单、保留站位并清除旧对照及定位球人员绑定，可撤销。

实验 CSV 支持上游原始列：`模式,方案,种子,主队进球,客队进球,耗时秒,尝试次数,日志`。此格式按主队视角计算，缺少对手和主客场，因此只能将**同一个固定条件批次**作为一个文件导入，不能混入不同阵容或比赛背景。

也支持扩展列：`variant,seed,goals_for,goals_against,opponent,venue,status,xg_for,xg_against`。前四列必需；`venue` 为 `home` 或 `away`；`goals_for` 始终指被测试球队进球，与其主客场无关。`status` 默认为 `complete`；失败、错误、取消和未完成行排除。重复的「方案 + 种子 + 对手 + 场地」拒绝导入。单文件最大 10 MB、20,000 行。

统计展示完整场次、胜率、场均进失球、场均积分；两方案按种子、对手、场地配对，比较净胜球差。不匹配的比赛只参与各方案描述汇总，不进入配对区间。至少 20 对样本才展示 1,000 次固定随机种子 bootstrap 的百分位 95% 区间；该阈值只是显示门槛，不保证样本足够。结果仅用于探索；多方案反复筛选后应在独立种子和对手上验证。xG 与其他可选统计只使用实际提供的值，未提供的数据不会生成。

样例 `samples/players.csv` 为虚构名单；`samples/demo-results.csv` 为人工测试数据，可验证导入界面，不可用于战术结论。

扩展球队指标：`possession`、`shots`、`shots_on_target`、`passes`、`completed_passes`、`corners`、`fouls`、`offsides`、`tackles`、`interceptions`、`saves`、`yellow_cards`、`red_cards`，均以 `_for` / `_against` 区分本队和对手。控球率使用 0–100 百分数；成功传球不能多于传球、射正不能多于射门。`goals_for` 与 `goals_against` 必需，其余可留空。

球员赛后 CSV：先导入球队比赛，再导入球员文件。通过 `variant,seed,opponent,venue` 关联比赛；必填 `player_id,player_name,team`（`for` / `against`）。支持出场分钟、评分、进球、助攻、xG、xA、射门、射正、传球、成功传球、关键传球、创造机会、抢断、拦截、争顶、盘带、跑动公里、扑救、失球与红黄牌。程序可导出完整表头；没有对应比赛或同场球员重复时拒绝导入。不是 FM 原生导出格式，需要按模板整理。

## 保存位置

`~/Library/Application Support/FM Tactics Lab Mac/`：

- `workspace.json`：当前战术与阵容；旧版迁移前保留 `workspace-before-v03-*.json`。
- `experiment.json`：当前完整实验批次，包含球员记录；`experiment.csv` 为兼容旧版的最近文件。
- `experiments/*.json`：历史导入快照，每次导入使用新文件。
- `engine-location.json`：记住的手动安装位置；`engine-load-check.json`：最近一次动态加载验证。
- `original-matches.json`：最近一组原版比赛报告，含趋势采样，重开应用可恢复。
- `engine-runs/<批次>/seed-*.jsonl` 和 `.stderr.txt`：原版比赛原始日志，包括未完成／取消的尝试。

损坏的工作区不会被示例覆盖；姓名为空等未完成编辑暂缓自动保存。方案保存采用原子写入。加载验证只从已安装的游戏读取动态库，不修改游戏包与存档。

## 构建与验证

安装 Apple Command Line Tools / Swift 5.9 或以上，在本目录运行：

```sh
bash scripts/check.sh
bash scripts/build.sh
```

`check.sh` 在仅有 Command Line Tools 的环境运行与 XCTest 相同的核心测试用例；完整 Xcode 环境可用 `swift test`。当前机器没有 XCTest 模块，采用前者验证。构建和模块缓存留在 `.build/`。

GUI 快照检查（启动原生窗口，不写入正式工作区）：

```sh
mkdir -p .build/evidence
open -n './dist/FM Tactics Lab 0.4.app' --args --snapshot "$PWD/.build/evidence/workbench.png"
```

当前核心检查 34 项。原版宿主回归（需要本机完整游戏）：

```sh
python3 scripts/check-engine.py '/你的游戏路径/fm.app'
swiftc -O -parse-as-library -module-name EngineReportChecks -module-cache-path .build/ModuleCache Sources/TacticsCore/*.swift scripts/CheckEngineReports.swift -o .build/checks/engine-report-check
.build/checks/engine-report-check .build/evidence-v04
```

`--engine-smoke <目录> --data-dir <目录>/data` 可运行应用内 5 场真实比赛、校验 200 条球员记录、持久化恢复并截图三个结果视图；必须使用隔离数据目录。

该检查验证撤销/重做、拖拽换位、按位置设置能力与拖拽坐标边界，并渲染工作台、球员表、球队指令、球员指令、定位球、状态与磨合、空结果、引擎页和明确标注的人工实验数据页（总览、球队明细、球员数据），共 11 个视图。不等同于真实鼠标端到端测试。

## 源码结构

- `Sources/TacticsCore/`：数据模型、规则分析、CSV、配对统计、球队／球员数据和引擎文件识别。
- `Sources/TacticsLabMac/`：SwiftUI 窗口、AppKit 文件面板、本地保存和撤销。
- `Tests/TacticsCoreTests/`：核心测试以及 Command Line Tools 兼容运行器。
- `scripts/`：构建、图标生成和检查脚本。
- `native/EngineLoadProbe.m`：独立动态库加载诊断。
- `native/EngineRuntimeProbe.mm` / `EngineABI_arm64.S`：限定版本的 Mac 原版比赛宿主与 ABI 桥接。
- `Sources/TacticsCore/OriginalMatchReport.swift`：自然完赛校验、原版统计与现有结果模型连接。
- `scripts/check-engine.py` / `CheckEngineReports.swift`：真实引擎回归与无效结果门禁校验。
- [Mac 引擎接入与优化路线](docs/PORTING.md)：已确认障碍、架构取舍和各阶段验收要求。

工具源码沿用仓库 MIT 许可。原项目的游戏资源、PKM 初始输入、私有目录和原版二进制不包含在 Mac 应用内；参见根目录 `THIRD_PARTY_NOTICES.md`。
