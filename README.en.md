# FM Tactics Lab · Mac Edition

[简体中文](README.md) | **English**

Test tactics on a Mac using your installed FM27 engine. Set up both squads, repeat matches and review team/player results, or import clubs from a career save and run a league season.

This is a fork of [lqf0624/fm-tactics-lab](https://github.com/lqf0624/fm-tactics-lab). The original project provides the Windows editor and simulation workflow; this fork adds a native Mac interface and engine adapter. Current Mac version: **0.8.2**, based on upstream **v1109.3 / `6cb32bf`**, under the [MIT license](LICENSE).

## What works

- Dual-phase tactics, drag-to-swap, 12 formation templates, 24 positions and 79 role entries, plus team/player instructions and set pieces based on the upstream editor.
- Manual, CSV, `.fm` and raw 2700 DAT squad input. Seven random ability tiers can target a whole squad, position or player. Attributes reflect positions; hidden attributes and personality vary independently.
- Three tactical plans per team, switched during the same original-engine match by time and score rules. These are tester rules using original FM commands, not an AI manager implementation.
- Batches of 1–2000 original-engine matches, with 1–256 configurable parallel workers and cancellation/resume. Each match still starts a fresh host; warm-host reuse is pending.
- Reports by tactic: possession, passes, crosses, shots, goals, conversion rates, goal distributions/timing, assists and xG timelines. In-match plans have separate segment statistics.
- Leagues of 2–40 custom, random or imported teams, with round-robin schedules, ranking rules, season results and repeated-season comparisons.

Ordinary matches and leagues keep separate squads. Adding a workbench team to a league makes a copy. Opening that league team's squad or tactics edits the same saved team. Each experiment stores its starting configuration, so later edits do not change old results.

Version 0.8.2 starts league matches after each preparation batch instead of waiting for every AI fixture. Imported player attributes stay fixed unless explicitly edited; random ability presets are optional. The new history/storage page can recycle test records and migrate verified history to a chosen directory while keeping team presets and editor settings separate.

## Run on Mac

Save import is verified on **27.0.1+2503222** (clubs, registered first-team players and a complete calendar). **0.6.1 restores original-engine simulation and tactic FMF operations for this game update.** Start a new experiment after changing engine versions; previous reports remain readable, but runs cannot mix versions.

Game tactic FMF files can be imported and exported through the original Mac serializer and parser. Named team presets retain the full squad, attributes, tactics and set pieces. Use “导入真实球队” at the top of the editor to select real teams.

Requires Apple Silicon, macOS 14+ and a complete FM27 installation. The adapter currently supports the specific **27.0.0.2493426** and **27.0.1.2503222** builds; game updates may need a new adapter.

Find the game on the engine page, configure both sides in the workbench, set the match count and click **运行比赛**. Use **联赛实验** for league seasons. See the [Mac guide](macos/README.md).

Discovery uses the current Mac's home directory, Steam library records and mounted volumes. **指定游戏位置** remains available after discovery and accepts a Steam library, `steamapps`, `common`, the game folder or `fm.app`. Paths are not tied to the development machine. Arbitrary installation locations and other game patches are not automatically supported; reading a save does not prove engine compatibility. Other-Mac hardware testing is still pending.

Original AI pre-match generation, live switching, final goal events and crosses are verified on **27.0.1.2503222**. The older supported build retains fixed-tactic matches and FMF import/export. Building requires Apple Command Line Tools and Python 3.11+. Packaged-app users do not need Python, extra runtimes or an administrator installer. This build is ad hoc signed, without Developer ID or notarization; downloaded copies may be blocked by Gatekeeper. See [distribution details](macos/docs/DISTRIBUTION.md).

```sh
git clone https://github.com/winner0007/fm-tactics-lab.git
cd fm-tactics-lab
bash macos/scripts/check.sh
bash macos/scripts/build.sh
open 'macos/dist/FM Tactics Lab 0.8.2.app'
```

## Still to do

Raw 2700 DAT imports now include clubs, players and league membership. Unrated fields use a disclosed deterministic initializer; career initialization, database patches and full competition rules are not loaded. Fixed/random/original-AI tactics can be configured per team or together. Original AI prepares a frozen pre-match plan; missing or ambiguous manager data uses the original benchmark coach with an explicit source label. Saved matchday tactics, set-piece FMF exchange and custom substitution rules remain pending. League runs reset conditions each match; injuries, suspensions and fatigue do not carry over. Training, growth, decline, retirement and transfers are not simulated. Coach locks protect editor settings, not a career hiring/firing system. Special competition stages and playoffs are not implemented. Unverified statistics such as ratings and minutes remain blank.

The updated engine completed **all 552 matches with 24 imported clubs**, plus app batch runs, cancellation/resume, data recovery and save import. See the [test record](macos/docs/MAC_ENGINE_STATUS.md) for scope.

## Documentation

- [Mac guide](macos/README.md) · [Data files and storage](macos/docs/DATA_FORMATS.md)
- [Tactics, coaches and metric definitions](macos/docs/TACTICS_AND_AI.md) · [Packaging and signing](macos/docs/DISTRIBUTION.md)
- [Developer handoff](macos/docs/PORTING.md) · [Changelog](macos/CHANGELOG.md)
- [Original Windows guide](docs/WINDOWS_GUIDE.en.md) · [Third-party notices](THIRD_PARTY_NOTICES.md)

Game binaries, resources and user saves are excluded from this repository and the Mac app.
