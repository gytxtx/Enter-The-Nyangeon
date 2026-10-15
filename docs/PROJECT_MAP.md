# Project Map / 项目地图

> Bilingual project knowledge base. English headings, Chinese explanations, code symbols verbatim.
> 双语项目知识库。英文标题、中文说明、代码符号原样保留。
> Entry point / 入口: `AGENTS.md` → `docs/`.
> 用户纠正优先于本文推断；来源标记（code/user/test）见 `docs/LEARNINGS.md`。
> Last updated / 最后更新: 2026-10-15

## 1. What this is / 项目是什么

- **Engine**: Godot **4.7**, Forward Plus, 2D.
- **Genre**: top-down arena shooter / roguelite (Blue Archive–flavored fan game).
- **Main scene**: `res://scenes/main/title_screen.tscn` (`project.godot:18`).
- **Scale**: 本体 `script/` / `scenes/` / `ui/` / `resources/` 共 483 个 GDScript（含本轮两个新 helper）；整体场景/SDK/测试规模以审计地图统计为准。
- **Physics**: Rapier2D (`project.godot:234`).
- **Resolution**: design 640×360, window override 1280×720, stretch `canvas_items` (`project.godot:46-50`).
- **Version**: 以 `script/Game.gd:13` 的 `Game.version_number` 为准，当前 **`v0.5.1.4`**；官方联机发布版本 `0.1.10`，尚未提交上游的联机协议变更统一为 v4。SUPERSEDED: 2026-10-14 先回滚本体至 `v0.5.1.3`（原标 `v0.5.1.4`/`0.1.12`/协议 v5），随后用户改定发布版本为 `v0.5.1.4`（导出文件名同步 0.5.1.4）；联机与具备前置伤害接口的本体仍需配套更新。
- **README**: 根目录 `README.md` 面向玩家、Mod 开发者与项目维护者，提供下载、源码启动、SDK 和知识库入口；顶部横幅复用 `ui/ark_of_Shittim/ETN_key_visual.png`。

## 2. Directory layout / 目录职责

| Dir | Purpose / 职责 |
|---|---|
| `scenes/` | 场景 + **与场景同目录同名的脚本**（feature subfolders）。含 `player/`, `enemies/`, `bullet/`, `update_item/`, `manager/`, `main/`, `weapon/`, `summoned/`, `item/`, `debuff/`, `shop/`, `props/`, `player_support/`, `game_camera/`, `crosshair/`, `shadow/`。 |
| `script/` | 跨场景/全局系统脚本：autoload 脚本（`Game.gd`, `GameEvents.gd`, `PlayerData.gd`, `locale_font.gd`, `extension_hooks.gd`…）、基类与路由器（`entity_ENEMY.gd`, `Stats.gd`, `damage_router.gd`, `buff_router.gd`, `projectile_spawner.gd`…）、`props/` 道具脚本。 |
| `resources/` | 数据资源：每类一个 `class_name` 脚本 + 大量 `<snake_case>.tres`。子类：`buff/`(+`components/`,`player_buff/`,`enemy_buff/`,`summoned_buff/`)、`upgrades/`、`player/`(+`PS/`)、`enemy/`、`shop/character/`、`clothes/`、`equip/`、`game_mode/`、`level/`、`raid_formwork/`、`support/`、`talk/`。 |
| `sprites/` | 全部源贴图（`.png` + `.import`），按主题分子目录。 |
| `ui/` | 菜单/HUD/卡片：`ui/*.tscn` + 同名 `.gd` + 图标；含 `ark_of_Shittim/`, `support_ui/`, `health/`, `weapon/`, `res/`, `school/`, `card icon/`。另含主菜单弹窗 `option.tscn`（设置，通用容器；子页 `game_option.tscn`/`controls_option.tscn`/`mod_option.tscn`（设置 / 按键说明 / MOD 管理），基类 `script/option_menu.gd`、页签 `option_button.tscn`、共享开关 `option_toggle.tscn`）、`scoreboard.tscn`（记分板）、`credits.tscn`（鸣谢，可滚动翻译者名单，复用 `shaders/motion_screen.gdshader` 做背景模糊）。 |
| `shaders/` | `shader_type canvas_item;` 着色器 + `funcs.gdshaderinc` + `erotion_shader.tres`。 |
| `sounds/` | `BGM/` 与 `voice/`；根目录为 SFX。 |
| `fonts/` | 位图字体 + `theme.tres`（全局 UI 主题）。 |
| `assets/` | 空（未使用）。 |
| `addons/` | `godot-rapier2d`（物理）、`godot_ai`（编辑器 MCP 插件，非游戏运行时）。 |
| `android/` | Android 导出配置与资源；`icons/` 存放启动器主图标、自适应前景/背景及主题单色 SVG，`build/` 为忽略的生成目录。 |
| `mod_sdk/` | **Mod 开发套件**（含 `.gdignore`，不进本体包）：包契约、示例模组、`build_mod.ps1` / `build_coop_mod.ps1` / `build_local_mod.ps1`（项目根 `mods/` 本地打包）、官方联机源码 `coop_mod/`；通用隔离打包 `pack_mod_source.ps1`。详见 `mod_sdk/README.md`、`CONVENTIONS.md` §10。 |
| `tests/` | MCP 测试套件（`test_*.gd`，`extends McpTestSuite`），由编辑器内 `test_run` 运行（`addons/godot_ai`）；另有独立 UI 回归入口 `run_ui_ux_checks.py` + `test_ui_ux_regressions.gd`，不依赖插件，隔离用户目录运行，`--screenshots` 可输出局部场景渲染。 |
| `docs/` | **本知识库**（本项目新增）。 |

- **存档/安装边界（2026-10-13）**：`script/scene_data_store.gd` 管主档/备份读取与文件替换，`Game.gd` 管元进度赋值；`script/mod_installer.gd` 管 ZIP 暂存/验证/目录交换，`ModManager` 保留公开入口与挂载/注册职责。两者均为 RefCounted helper，不增加 autoload。
- **独立回归（2026-10-13）**：`tests/run_persistence_checks.py`、`run_mod_install_checks.py`、`run_coop_recovery_checks.py` 与既有 UI / 联机拓展入口使用隔离 user://；`test_relay_limits.py` 为回环服务测试；`check_localization.py` 为源格式防护，`godot_check_output.py` 统一原生错误分类。

- **审计修复入口（2026-10-14）**：`tests/run_support_persistence_checks.py` 覆盖支援 Mod 启停与 v2→v3 迁移；`run_mod_lifecycle_checks.py` 覆盖冲突闭包、卸载链接；联机 runner 新增 relay_queue / simultaneous_leave。SDK `net/coop_enet_peer.gd` 适配原生 ENet 的连接事件/发送边界，不增加 autoload；`SceneData` 格式升为 3，运行期资源由 SupportData 恢复。

- **从零全量审查及修复（2026-10-14）**：full 审查新增的五项（Relay 准入、前置伤害、导出镜像、刷新权重、外推）已修复；实现原理见 `ARCHITECTURE.md`、`SYSTEMS.md`，回归入口见 `MOD_TESTING.md`。新永久守卫 `run_damage_contract_checks.py`、`run_upgrade_snapshot_checks.py`、`run_export_boundary_checks.py`；联机恢复扩至 13 组，增加真实双端 damage 场景；中继测试强制并发准入顺序。旧观察型诊断保留并随实际调用链更新。

## 3. Scene ↔ script pairing rule / 场景与脚本配对规则

- 约定：脚本与场景**同目录、同基名**。例：`scenes/main/main.tscn` ↔ `scenes/main/main.gd`；`scenes/item/medical_kit.tscn` ↔ `scenes/item/medical_kit.gd`。
- 例外：玩家角色场景根节点**统一引用 `script/player.gd`**（`class_name Player`），角色目录不再自带 `<char>.gd`（仅 `hina`/`aris_armed` 例外，见 §4）。
- 约定是**习惯而非强制**：并非每个 `.tscn` 都有同名 `.gd`（纯数据/子弹/敌人场景常没有），也并非每个 `.gd` 都有同名 `.tscn`（helper 脚本如 `StateMachine.gd`, `HeatBar.gd`, `MomoiPS.gd`）。
- **命名**：场景/资源文件用 `lower_snake_case`（`title_screen.tscn`, `droid_helmet_smg.tres`）；角色/武器子目录有的用 `lower_snake_case`，武器目录多用 `PascalCase`（`scenes/weapon/Red_Dragon/`）。
- 脚本多数 `lower_snake_case`，少量遗留 `PascalCase`：`script/Game.gd`, `PlayerData.gd`, `SoundManager.gd`, `Stats.gd`, `scenes/manager/PoolManager.gd`, `ui/BuffCard.gd`, `ui/UpgradeScreen.gd`, 部分角色 PS（`MomoiPS.gd`, `HibikiPS.gd`）。

## 4. Key subfolder patterns / 关键子目录模式

- `scenes/player/<char>/`：每角色一个目录，含 `<char>.tscn`（根节点脚本统一引用 `script/player.gd`）+ PS 卡 + 头发/技能辅助脚本（`aris/`, `momoi/`, `ako/`, …, 22 个）。仅 `hina`/`aris_armed` 用各自 `<char>.gd`。
- `scenes/weapon/<WeaponName>/`：每武器一个目录（22 个）+ 共享 `BaseWeapon.gd` 与枪口闪光场景。
- `scenes/enemies/`：敌人场景/脚本 + `boss/`（14）+ `enemies_spawn/`（55，波次生成器）。
- `scenes/update_item/`：**最大子目录（约 396 文件）**，一件道具一个脚本，多为 `EquipItem` 子类。
- `scenes/item/`：地图拾取物（`coin`, `pyroxenes`, `medical_kit`, `coin_box`, `game_tv`, `vending_machine`…）；**长按拾取物通用基类 `hold_pickup_item.gd`**（`class_name HoldPickupItem`，helper 脚本，无同名场景）。
- `scenes/manager/`：单例式管理器场景（`round_manager`, `enemy_manager`, `upgrade_manager`, `pick_item_manager`, `sound_manager`, `*_buff_manager`, `interaction_manager`, `summoned_manager`…）。
- `resources/<type>/`：`<type>.gd` 定义 `class_name`，每个 `.tres` 一条记录，`id` 通常等于文件名（见 `ARCHITECTURE.md` §Resource data model）。

## 5. Main flow scenes / 主流程场景

```
title_screen.tscn  (CanvasLayer, title_screen.gd)
      │  title_anim_end → Game.load_playerdata() → change_scene_to_file(path)
      ▼
menu_screen.tscn   (CanvasLayer, menu_screen.gd)
      │  选角色/社团 → LevelSelect → level_button.gd
      │  GameEvents.change_scene("res://scenes/main/main.tscn", <player_scene>)
      ▼
main.tscn          (Node2D, main.gd)   ← 正式战斗
      │  first_round_add → first_round() → round_manager.first_round_start()
      │  rounds: round_start → enemy spawn → round_end → UpgradeScreen → round_upgrade_end → next round
      │  胜利/失败 → game_over_page.tscn
      ▼
test_room.tscn     (Node2D, test_room.gd)  ← 沙盒/测试房（从 menu 进入）
```

- 进入战斗时 `GameEvents.change_scene()` 会：切换场景 → `await tree_changed` → 播放 transition 收尾 → 把所选玩家场景实例化到组 `"PlayerRoot"` → `call_deferred("emit_first_round_add")`（`GameEvents.gd:163-181`）。
- `main.tscn` 的根下分组容器：`BuffBox`, `BackLayer`, `FloorLayer`, `YSort`（含 `Wall`/`Map`/`SpawnMap`/`SpawnNorth/East/South/West` TileMap）, `PlayerRoot`, `EnemiesRoot`, `CoinRoot`, `PropRoot`, `BulletRoot`, `EquipLayer`, `SELayer`, `ForegroundLayer`。

## 6. Localization files / 本地化文件

5 组 `ETN_*localization.csv`（+ 生成的 `.translation` + `.import`）：

| CSV | Languages / 语言 |
|---|---|
| `ETN_localization.csv` | zh_CN, en, pt, vi_VN |
| `ETN_item_localization.csv` | zh_CN, en, pt, vi_VN |
| `ETN_player_localization.csv` | zh_CN, en, pt, vi_VN |
| `ETN_shop_localization.csv` | zh_CN, en, pt, vi_VN |
| `ETN_support_localization.csv` | zh_CN, en, pt, vi_VN |

规则见 `CONVENTIONS.md` §Localization 与 `AGENTS.md`。

## 7. Where to look first / 从哪里开始读

| 想了解 | 先读 |
|---|---|
| 启动/单例/事件总线 | `docs/ARCHITECTURE.md` → `script/Game.gd`, `script/GameEvents.gd` |
| 伤害/治疗/血量 | `docs/SYSTEMS.md` §Combat → `script/damage_data.gd`, `script/health_component.gd` |
| Buff | `docs/SYSTEMS.md` §Buff → `scenes/manager/buff_manager_base.gd` |
| 敌人/玩家/召唤物 | `docs/SYSTEMS.md` §Entities → `script/entity_ENEMY.gd`, `script/player.gd`, `script/summoned.gd` |
| 数据资源字段 | `docs/SYSTEMS.md` §Resource data model |
| 命名/层/本地化/输入 | `docs/CONVENTIONS.md` |
| 按语言换字体（越南语 Roboto） | `docs/ARCHITECTURE.md` §1.10 → `script/locale_font.gd` |
| Mod 系统（挂载/内容/补丁/entry） | `docs/ARCHITECTURE.md` §1.11、`docs/SYSTEMS.md` §11、`docs/CONVENTIONS.md` §10 → `script/mod_manager.gd`、`mod_sdk/README.md` |
| Mod 导出/真机验证 | `docs/MOD_TESTING.md` |
| Mod 元数据与拒载设计（草案） | [MOD_MANIFEST_V2_DESIGN.md](MOD_MANIFEST_V2_DESIGN.md)；尚未实施，当前包格式仍见 SDK |
| 官方联机通用拓展接口 | `docs/COOP_EXTENSION_API.md` → 官方 `net/coop_extensions.gd`；`tests/run_coop_extension_contract_checks.py` |
| 已知坑与未解问题 | `docs/LEARNINGS.md`, `docs/WORKLOG.md` |

## 8. Layout review / 目录复查（2026-10-15）

当前目录大体可用。`script/` 也存放 20 个共享 `.tscn`，并非纯代码目录；专属设置脚本在 `script/game_option.gd` / `mod_option.gd`，对应场景在 `ui/`。后续可逐功能整理，不能机械全仓搬迁或删除所谓零字面量入引用脚本。SDK 源码是维护真源，本地 `mods/` 是编辑器镜像，包内 `res://mods/` 是运行命名空间。移动资源前核对静态路径、动态拼接、UID 及仓外 Mod 兼容性。`mods/_mod_template/` 是忽略的本地骨架，不随干净克隆提供；跟踪示例源位于 `mod_sdk/example_mod/mods/example/`。


## 9. Repair guards / 架构修复守卫（2026-10-15）

- `tests/architecture_contract_checks.gd` / `run_architecture_checks.py`：首回合、补丁、场景代次、暂停归属、购买事务、标签、身份、候选池和刷怪；测试资源集中在 `tests/fixtures/architecture/`。
- `mod_sdk/build_common.ps1` / `verify_mod_pack.gd`：三个构建入口共用成功判定，复用 `script/mod_pack_validator.gd`；`tests/test_build_contract.py` 验证失败保留与真实导出。
- 系统行为以 `ARCHITECTURE.md`、`SYSTEMS.md` 为准；验证入口见 `MOD_TESTING.md`，不机械移动公开 SDK 路径。
