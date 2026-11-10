# FM Tactics Lab · Native Mac Extension

[简体中文](README.md) | **English**

This repository forks [lqf0624/fm-tactics-lab](https://github.com/lqf0624/fm-tactics-lab), preserves its Windows implementation, and adds a SwiftUI client and native macOS match host under `macos/`. Current Mac version: **0.4**. Upstream baseline: **v1109.3 / [6cb32bf](https://github.com/lqf0624/fm-tactics-lab/commit/6cb32bfab936d1ce2a0558a70f489537edfb5442)**.

## About the upstream project

FM Tactics Lab runs tactical experiments with the original detailed FM27 match engine installed on the user's computer. Its Windows version connects dual-phase tactical boards, squads, set pieces, career-save matches and FMF import/export to seeded batch execution, A/B comparisons and native match statistics. It uses a web editor, Python service, C# desktop launcher and Windows C++ host.

Credit for the original design and Windows implementation belongs to the upstream author and contributors. The tool code remains [MIT-licensed](LICENSE). The Mac host separately handles Mach-O loading, the arm64 C++ ABI, resource mounts and macOS thread context.

## Mac 0.4 additions

- Native SwiftUI/AppKit client for macOS 14+ on Apple Silicon, with autosave, undo/redo, JSON workspaces and CSV exchange.
- Dual-phase boards with a shared lineup, drag-to-swap, reference snapshots and configuration differences.
- Team, position and individual ability presets: random, amateur, semi-professional, professional, national, continental and international. Each player attribute is sampled within a range; these are experimental presets, not official CA/reputation conversions.
- Team/player instructions, set-piece taker and responsibility priorities, left/right setups and substitute fallback; condition, familiarity, personality and relationship records.
- Automatic installation discovery across Steam libraries, application folders and external disks, with manual selection as a fallback.
- Original Mac engine initialization and natural completion using the game's bundled test fixture; 1/5/10/20-match seed sequences, isolated processes, cancellation and timeouts.
- Actual xG timelines, team/player statistics, batch history and exports. Missing metrics remain missing; native player IDs are displayed until names are mapped.

**Mac simulations currently use the game's bundled test squads and tactics. Workbench players, tactics, set pieces and condition settings are not yet passed to the engine. Mac `.fm` and `.fmf` import/export are not implemented.** This is an original-engine baseline milestone, not full Windows feature parity.

## Build and run on Mac

Requires macOS 14+, Apple Silicon and Apple Command Line Tools. Simulation additionally requires the user's complete supported FM27 installation.

```sh
git clone https://github.com/winner0007/fm-tactics-lab.git
cd fm-tactics-lab
bash macos/scripts/check.sh
bash macos/scripts/build.sh
open 'macos/dist/FM Tactics Lab 0.4.app'
```

Open the engine page, set the starting seed and match count, then select **开始原版模拟**. The host checks the exact supported `27.0.0.2493426` arm64 binary hash before every run; other builds are rejected. App bundles are built locally into `macos/dist/`, not committed to Git. Game binaries, resource archives, PKM inputs, saves and local logs are excluded.

Validation: 34 core checks; 9 native-engine regression matches including repeated and boundary seeds; 11 invalid/incomplete-result checks; 5 real matches through the app producing 200 player records, with persistence verified. These checks do not establish equivalence to every career-match condition.

See the [Mac guide](macos/README.md), [Mac changelog](macos/CHANGELOG.md), [engine validation and scope](macos/docs/MAC_ENGINE_STATUS.md) and [porting roadmap](macos/docs/PORTING.md). Next: bind and read back custom squads, tactics and set pieces, then extend player identities/statistics and save/FMF support.

## Upstream Windows guide

The remainder preserves the Windows guide from upstream v1109.3. EXE downloads, career-save matches and FMF capabilities below refer to Windows. For current Mac capabilities, use the scope above and the Mac guide.

**Test your tactics locally with the original FM27 match engine.**

Configure both squads in Free Simulation or import an FM27 career save to play opponents from the same league. Compare scores, xG, shots, possession and passing statistics across complete matches.

Use it to explore which formation suits your players, how pressing or role changes affect performance, and whether an advantage holds across repeated matches.

## Interface preview

Edit possession and out-of-possession formations, team instructions and player roles side by side.

![Dual-phase tactical boards and team instructions](docs/screenshots/tactics.png)

The screenshots show Free Simulation with the included example players. The interface is in Chinese.

## How it works

The tool loads the original match engine from your local FM27 installation. It supplies player and tactical inputs, then runs the original code for decisions, movement, passing, challenges, shooting and match rules until the match finishes naturally.

```text
Players and tactics → Original engine runs a complete match → Scores, events and statistics → Batch comparison
```

**Match calculation and visual presentation are separate layers.** The engine advances players, the ball and match events; the match view presents those states. FM Tactics Lab runs detailed matches in the background and collects their results without displaying the pitch.

### Is this a played match, a holiday simulation, or Instant Result?

The tool runs the **original detailed match calculation**, corresponding to the detailed simulation layer used when entering a match. Set your inputs before kickoff, let the engine finish, then inspect the results. Live player interventions such as changing tactics or giving touchline instructions belong to the normal game interface.

A complete background simulation can also use detailed match logic. Holiday and Instant Result additionally involve game-level task scheduling and assistant management. Think of this project as a way to run the original detailed engine repeatedly for tactical experiments.

### Comparing results

Player actions and match rules use the original implementation. Scores, xG, shots and passing statistics are read from native match objects.

Each batch uses a sequence of random seeds. When comparing a saved reference with an edited setup, both variants run with the same seed sequence. Repeated matches help show average changes and variability.

## Download and launch

The current source version is **v1109.3**. Download published desktop builds from [GitHub Releases](https://github.com/lqf0624/fm-tactics-lab/releases). Exit the previous app from its tray menu before launching an update.

Install FM27, open Steam and sign in to the account that owns the game, then launch the EXE. The tool looks for your installation automatically. You can also select the game root containing `fm_Data` and `shared` in the engine settings at the top.

The EXE includes its Python runtime. Players do not need Python or a compiler. The desktop interface in this release is in Chinese; the English documentation below explains the controls. Source setup is described in the [developer guide](docs/DEVELOPMENT.md).

## Career-save matches

1. Switch to **存档对战** (Career-save Matches), import an FM27 .fm save, and select the club you manage.
2. Load its tactic, review first-team attributes, and adjust your starting lineup and bench.
3. Select opponents from the same league. Preview their in-possession and out-of-possession boards, then run home and away matches.

Opponent tactics use a built-in preset selected from the head coach's saved style and formation preferences. A team is selectable when both the coach and preferences can be verified. Opponent squads load in batches as needed. You can track or cancel match preparation.

## Save tactics

On **存档战术** (Save Tactics), read a save to list same-league opponents' coach-preference presets, excluding your club. Export all of them into a local folder or add them to the away tactic pool in one click. Saves store no country or league names, so the page groups teams by the current league. Exported opponent files are preset approximations, not the actual match-day tactics.

## Free Simulation

### 1. Configure both squads

Start with the included player inputs and choose each side's starting lineup. Both sides can be edited independently. In **球员属性** (Player Attributes), adjust abilities and positional familiarity. Export a full JSON setup to keep your experiment.

![Player attributes and whole-squad editing](docs/screenshots/players.png)

### 2. Import or edit a tactic

Open **战术板** (Tactics Board):

- Use **导入主队／客队比赛战术 FMF** to import a home or away tactic.
- Edit **有球阶段** (In Possession) and **无球阶段** (Out of Possession) separately; both phases share the starting lineup.
- Drag shirts to swap players while keeping roles, duties and instructions attached to their positions. Moving to an empty position prompts for confirmation if any settings need to change.
- Adjust mentality, passing, pressing and other team instructions.
- Configure or import set-piece routines separately in **定位球与职责** (Set Pieces and Responsibilities).
- **Away tactic pool**: import local FMF tactics on the pool page, or add same-league opponent presets from **存档战术** in one click. With random mode enabled in the bottom bar, each match draws one away tactic by weight.

Imported tactics remain editable. When the away tactic pool is enabled, every away player's ability attributes can be unified to a configurable interface value (15 by default), while starters receive maximum positional familiarity for the drawn tactic's positions. Draws are derived from the task seed and reproduce within the same experiment.

### 3. Run matches

At the bottom, set the starting seed, matches per variant and worker count, then select **运行比赛** (Run Matches). Start with a small batch to check your setup.

| Setting | Purpose |
| --- | --- |
| 起始种子 — Starting seed | Controls the batch's seed sequence for later comparison |
| 每方案场数 — Matches per variant | Number of matches for each setup |
| 并行数 — Workers | Number of concurrent native workers |
| 快速模式 — Quick mode | Complete detailed matches, scores and team statistics, with reduced player-event collection |
| 完整模式 — Full mode | Also collects and checks scorer, assist and card details |

**Quick mode still runs complete detailed matches.** The difference is the scope of event collection and validation.

### 4. Read the results

Open **实验结果** (Results) for batch summaries, averages and individual matches. Full mode includes player-event details. Export individual results as CSV to keep your own comparisons.

Failed matches are listed separately. Aggregates use completed matches that passed validation.

![Paired tactical comparison and native team statistics](docs/screenshots/results.png)

Example: six completed matches per variant, showing the comparison, xG, shots, possession and passing statistics.

## Example: does stronger pressing help?

1. Load your original tactic, confirm both squads and set pieces, and save it as the reference.
2. Increase pressing while keeping the other inputs unchanged.
3. Enable **与已保存战术对比** (Compare with Saved Tactic), choose the seed and batch size, then run.
4. Compare goals for and against, xG, shots and possession.
5. Try another seed sequence or opponent setup, or swap home and away, to examine stability.

With 100 matches per variant, the tool runs 100 reference matches and 100 edited matches: 200 in total. The saved reference contains the entire setup, so changing one thing at a time makes the comparison easier to interpret.

## Reading the numbers

| Question | Look at |
| --- | --- |
| Is attack improving? | Goals, xG, shots and shots on target |
| Is defence improving? | Opponent goals, xG, shots and shots on target |
| Is the playing style changing? | Possession, passes and completed passes |
| Is the advantage stable? | Multiple seed sequences, opponent setups and home/away comparisons |

For example, after increasing possession, check whether the side also creates more or better shooting opportunities.

### Starting conditions

Both full squads start with condition and match sharpness at 100%, accumulated fatigue at 0, morale at 20/20, team cohesion at 80 and club cohesion at 100. States evolve normally after kickoff. This makes repeated tactical comparisons easier; consider actual fatigue, morale, cohesion and injuries when applying findings in your season.

### Tactical effectiveness experiment

Set tactical understanding, player buy-in and opposition information separately for each team on a 0–100 scale. The native engine calculates player ability contributions from each player's CA and suitability for both phase roles. The experiment is off by default. Career-save effectiveness values are not yet available.

The random away tactic pool can be combined with experimental tactical execution. Each side retains its three manual scores, while the native engine computes ability contribution from the current roster CA and the drawn tactic's two-phase roles. Execution matches use isolated processes and run more slowly than normal reused sessions. The pool changes tactics and retains the current away squad. Native-generated tactics remain incompatible with the pool.

## Save and export

- **Full setup JSON:** save both sides and reopen the setup for later experiments.
- **Tactic FMF:** export the selected side's tactic; set pieces have separate export controls.
- **Match CSV:** save individual results for analysis.
- **Experiment history:** name, find, rename or delete experiments. Confirming deletion removes their local results and logs.
- **Tray menu:** open the local results directory or exit the desktop tool.

## Version and project information

The current source version is **v1109.3**, for Windows x64. The adapter reference build is `27.0.0+2493426`. Tool code is licensed under MIT; the engine and game resources come from your local installation.

Original engine code and a career match's complete conditions are separate considerations. This tool standardizes starting states; inputs, random states and in-match interventions affect results. Evidence and validation scope are described in [Simulation Fidelity](docs/SIMULATION_FIDELITY.md).

For startup, path or version issues, see [Troubleshooting](docs/TROUBLESHOOTING.md). Developers can read the [build guide](docs/DEVELOPMENT.md), [contribution guide](CONTRIBUTING.md) and [third-party notices](THIRD_PARTY_NOTICES.md).

The interface and system tray follow the Windows display language. Simplified Chinese and English are supported, with English as the fallback. Player names, club names, tactic data and raw logs retain their original text.
