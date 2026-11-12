# FM Tactics Lab · Mac Edition

[简体中文](README.md) | **English**

Test tactics on a Mac using your installed FM27 engine. Set up both squads, repeat matches and review team/player results, or import clubs from a career save and run a league season.

This is a fork of [lqf0624/fm-tactics-lab](https://github.com/lqf0624/fm-tactics-lab). The original project provides the Windows editor and simulation workflow; this fork adds a native Mac interface and engine adapter. Current Mac version: **0.6**, based on upstream **v1109.3 / `6cb32bf`**, under the [MIT license](LICENSE).

## What works

- Dual-phase tactics, drag-to-swap, 12 formation templates, 24 positions and 79 role entries, plus team/player instructions and set pieces based on the upstream editor.
- Manual, CSV and `.fm` squad input. Seven random ability tiers can target a whole squad, position or player. Attributes reflect positions; hidden attributes and personality vary independently.
- Batches of 1–2000 original-engine matches using your workbench settings, with reports, charts, both lineups and player statistics.
- Leagues of 2–40 custom, random or imported teams, with round-robin schedules, ranking rules, season results and repeated-season comparisons.

Ordinary matches and leagues keep separate squads. Adding a workbench team to a league makes a copy. Opening that league team's squad or tactics edits the same saved team. Each experiment stores its starting configuration, so later edits do not change old results.

## Run on Mac

Save import is verified on **27.0.1+2503222** (clubs, registered first-team players and a complete calendar). Its updated Mac match-engine binary is **not yet supported**. Editing and historical reports remain available; simulation and game FMF operations stay disabled until that binary is adapted.

Game tactic FMF files can be imported and exported through the original Mac serializer and parser. Named team presets retain the full squad, attributes, tactics and set pieces. Use “Import from FM save” at the top of the editor to select real teams.

Requires Apple Silicon, macOS 14+ and a complete FM27 installation. The adapter currently supports the specific **27.0.0.2493426** build; game updates may need a new adapter.

Find the game on the engine page, configure both sides in the workbench, set the match count and click **运行比赛**. Use **联赛实验** for league seasons. See the [Mac guide](macos/README.md).

Building requires Apple Command Line Tools and Python 3.11+. Packaged-app users do not need Python.

```sh
git clone https://github.com/winner0007/fm-tactics-lab.git
cd fm-tactics-lab
bash macos/scripts/check.sh
bash macos/scripts/build.sh
open 'macos/dist/FM Tactics Lab 0.6.app'
```

## Still to do

Raw `.dat` databases, automatic saved-tactic extraction, set-piece FMF exchange and live coaching are not yet supported. To use initial rosters, save a new career in FM and import that `.fm`. League runs reset conditions each match; injuries, suspensions, fatigue and transfers do not carry over. Special competition stages and playoffs are not implemented. Unverified statistics such as assists and ratings remain blank.

Validation includes **20 imported clubs playing all 380 matches**, plus app batch runs, cancellation/resume, data recovery and save import. See the [test record](macos/docs/MAC_ENGINE_STATUS.md) for scope.

## Documentation

- [Mac guide](macos/README.md) · [Data files and storage](macos/docs/DATA_FORMATS.md)
- [Developer handoff](macos/docs/PORTING.md) · [Changelog](macos/CHANGELOG.md)
- [Original Windows guide](docs/WINDOWS_GUIDE.en.md) · [Third-party notices](THIRD_PARTY_NOTICES.md)

Game binaries, resources and user saves are excluded from this repository and the Mac app.
