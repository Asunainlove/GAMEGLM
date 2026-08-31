# 音频资产规范（W003-A9 · G6 前置）

状态：`DRAFT — 生产未启动`（当前全游戏零音频为审核基线；本文档是"发什么声"的单一来源）。
框架：`src/audio/audio_director.gd`（W003-A9）已就绪——资产就绪前框架空转不崩溃（resolver 未注入 / 返回 null 时告警并忽略）。
接线执行包：W003-A10+（本包不改 `scenes/app.tscn`、`src/integration/**`、`src/ui/**`、`project.godot`）。

## 1. 总线布局（Master → BGM / SFX）

建议的 `default_bus_layout.tres`（由协调者后续提交；本包禁改 `project.godot`）：

```
Master（音量 0 dB，线性 1.0）
├── BGM（音量 0 dB）   ← AudioDirector 的 BgmPlayer
└── SFX（音量 0 dB）   ← AudioDirector 的 8 槽 SfxPool
```

- `AudioDirector.set_master_muted(muted)` 操作 **Master** 总线静音（一次静音全局生效）。
- **降级行为（已实现并测试）**：仓库当前没有 `default_bus_layout.tres` 时，`AudioDirector._ready`
  检测 BGM/SFX 总线不存在即回退 Master 总线运行（功能无损，仅失去分总线混音能力）；
  协调者提交总线布局后，运行时创建的 AudioDirector 自动绑定 BGM/SFX，无需改代码。
- 本切片仅需要 Master/BGM/SFX 三条总线；UI/Ambience 等细分总线超出锁定范围，不预建。

## 2. 通用格式与交付约定（全部资产适用）

| 项 | 约定 |
|---|---|
| 运行时格式 | OGG Vorbis，44.1 kHz；BGM 立体声，SFX 单声道优先（省体积，Godot 会按需混音） |
| 母带存档 | WAV（PCM 16/24-bit，44.1 kHz）随源归档；`*.wav` / `*.ogg` 均已走 Git LFS（`.gitattributes`） |
| 循环标记 | BGM 一律无缝循环：OGV 导入后在 Godot 导入面板勾选 **loop**（`AudioStreamOggVorbis.loop = true`），循环点须无爆音、无节拍断口（建议按小节边界裁剪并在 DAW 内试听回环）；SFX 一律 `loop = false` |
| 命名 | 文件名 = 资产 ID（`snake_case`），BGM 放 `assets/audio/bgm/`，SFX 放 `assets/audio/sfx/`（目录由 A10 资产包建立并登记 LFS） |
| 响度 | BGM 整合响度 **-16 LUFS**（integrated，true peak ≤ -1.5 dBTP）；SFX **-12 LUFS**（单条校准，true peak ≤ -1.0 dBTP）；UI 类音效相对战斗类再降 2–3 dB 防听觉疲劳 |
| 原创性 | 全部原创合成。**禁止采样他人作品、禁止模仿在世作曲家/艺术家风格**（AGENTS.md 原创性条款同样约束音频） |

## 3. AudioDirector 框架约定（W003-A9 → A10+ 接口）

- **实例化**：app 层负责（A10 标题包在 app.tscn 中 `AudioDirector.new()` 并 `add_child`）。
- **resolver 注入**（资产就绪后由 app 层提供）：
  - `track_resolver: Callable(track_id: String) -> AudioStream`——BGM 曲目解析；
  - `sfx_resolver: Callable(sfx_id: String) -> AudioStream`——音效解析；
  - 典型实现是 `load("res://assets/audio/bgm/%s.ogg" % track_id)` 的 id→流映射；
  - resolver 未注入 / 返回 null / 返回非 AudioStream → `push_warning` 并忽略该次播放（零崩溃）。
- **播放行为**：
  - `play_bgm(track_id, fade_seconds = 1.0)`：同曲重入忽略；换曲先淡出旧流再淡入新流
    （Tween 控制 `volume_db`，谷底 -60 dB）；`fade_seconds <= 0` 立即硬切；
  - `play_sfx(sfx_id, volume_offset_db = 0.0)`：8 槽轮转（第 9 次覆盖第 1 槽，旧音自然截断）；
  - `stop_all()`：停 BGM 与全部 SFX 槽并重置当前曲目选择（重播同曲不算重入）；
  - `bgm_history`：最近 8 条 track_id（测试/调试观察用）。
- **状态边界**：音频是纯表现状态——不进 `GameState` / `SaveService` / `StatePatch`，存档不含音频信息，
  读档后由 A10 按游戏进度重放对应 BGM。

## 4. BGM 资产（5 首）

风格总语言（余辉氛围）：**环境合成垫底（低温、宽混响、缓慢演化）+ 东方拨弦点缀（古筝/柳琴质感的合成音色，五声音阶骨架）**；全原创，禁止在世艺术家类比。

### 4.1 bgm_title —— 希望·余绪（标题）

| 项 | 内容 |
|---|---|
| 资产 ID | `bgm_title` |
| 用途与触发点 | 启动进入标题画面（A10：标题场景 `_ready` → `play_bgm("bgm_title", 1.0)`）；从游戏回到标题时恢复 |
| 格式 | OGG Vorbis 44.1 kHz 立体声，`loop = true` |
| 时长 | 90–120 s 循环 |
| 风格语言 | 希望与余绪并存：明亮五声音阶拨弦动机悬于低温余辉氛围垫之上；慢起，中段微光渐强，尾段回落留白 |
| 混音参考 | -16 LUFS，true peak ≤ -1.5 dBTP；主旋律层高于垫底层 4–6 dB |
| 验收标准 | 循环点无缝（无爆音/断口）；连续播放 5 分钟无疲劳；响度达标；provenance 齐全 |
| 优先级 | P0（A10 标题包必需） |
| 预估工时 | 6–8 h |

### 4.2 bgm_explore —— 琉砂海旷野（探索）

| 项 | 内容 |
|---|---|
| 资产 ID | `bgm_explore` |
| 用途与触发点 | 沙盒主循环默认 BGM：序章落地事件完成后切入；战斗/结局结束回到探索时切回 |
| 格式 | OGG Vorbis 44.1 kHz 立体声，`loop = true` |
| 时长 | 120–180 s 循环 |
| 风格语言 | 低密度旷野：风感噪声垫 + 稀疏拨弦点缀 + 缓慢低音行进；刻意留白，给采集/放置音效让位 |
| 混音参考 | -16 LUFS；垫底层占比大，避免中频拥挤（HUD 提示音在其上清晰可辨） |
| 验收标准 | 循环无缝；与 `bgm_build`/`bgm_battle` 互切（fade 1–2 s）不突兀；响度达标 |
| 优先级 | P0 |
| 预估工时 | 8–10 h |

### 4.3 bgm_build —— 锚居暖意（建造）

| 项 | 内容 |
|---|---|
| 资产 ID | `bgm_build` |
| 用途与触发点 | 建造锚居段落：建造热键栏（BuildBar）交互焦点时段切入；退出建造/确认后切回探索曲（切点细节由 A10 定，建议 2 s fade） |
| 格式 | OGG Vorbis 44.1 kHz 立体声，`loop = true` |
| 时长 | 90–150 s 循环 |
| 风格语言 | 暖色调：规整温和的节奏层 + 拨弦分解和弦，比探索曲多一分"家"的稳定感；仍保持环境垫，不抢放置音效 |
| 混音参考 | -16 LUFS；与探索曲响度一致（切换不跳 Feel） |
| 验收标准 | 循环无缝；与放置/拒绝音效同时播放层次清晰；响度达标 |
| 优先级 | P1 |
| 预估工时 | 6–8 h |

### 4.4 bgm_battle —— 轨道交锋（普通战斗）

| 项 | 内容 |
|---|---|
| 资产 ID | `bgm_battle` |
| 用途与触发点 | 普通遭遇战（`encounter_first_drift` / `encounter_husk_ambush`）：`battle.tscn` 实例化即切入（fade 0.5 s）；战斗结束 2 s 内切回探索曲 |
| 格式 | OGG Vorbis 44.1 kHz 立体声，`loop = true`（防超时战斗无限静音） |
| 时长 | 60–120 s 循环 |
| 风格语言 | 节奏层驱动：急促拨弦音型 + 脉冲低音 + 金属质感打击；"轨道交锋"的对峙感靠切分音型而非管弦齐奏 |
| 混音参考 | -16 LUFS；节奏层与行动/受击音效（-12 LUFS）并列时不互掩（BGM 中频段避让 2–4 kHz） |
| 验收标准 | 循环无缝；与战斗 SFX 并行可辨；响度达标 |
| 优先级 | P0 |
| 预估工时 | 6–8 h |

### 4.5 bgm_boss —— 辉砂巨兽（Boss 战 · 两阶段变奏）

| 项 | 内容 |
|---|---|
| 资产 ID | `bgm_boss`（一段）/ `bgm_boss_final`（二段变奏）；逻辑上算一首曲目的两个段落，交付两个 OGG |
| 用途与触发点 | Boss 战 `encounter_leviathan`：开战切 `bgm_boss`（fade 0.5 s）；Boss HP ≤ 50% 触发引擎 `phase_change`（`lumen_leviathan` → `leviathan_p1`，见 `combat_engine.gd::_refresh_phases`）同帧播 `sfx_boss_phase` 并切 `bgm_boss_final`（fade 0.5 s） |
| 格式 | OGG Vorbis 44.1 kHz 立体声，两段各自 `loop = true`；**两段必须同 BPM/同调**，变奏靠加厚低频、提速感（加倍拨弦密度）、动机半音化实现，衔接点可 seamless 对齐 |
| 时长 | 90–150 s（两段合计） |
| 风格语言 | 一段：压迫感的脉冲低音 + 拨弦主题陈述；二段：同动机变奏加压——低频加厚、拨弦半音化、打击密度翻倍；"辉砂巨兽苏醒"的体量感 |
| 混音参考 | -16 LUFS；二段可比一段高 1 LU 以外的密度（响度不变，靠频谱密度造势） |
| 验收标准 | 两段切换（0.5 s fade）听感连贯；循环无缝；与 `sfx_boss_phase` 同帧触发不抢拍 |
| 优先级 | P0 |
| 预估工时 | 10–12 h |

## 5. SFX 资产（17 条）

SFX 通用条款：OGG Vorbis 44.1 kHz 单声道；`loop = false`；-12 LUFS（true peak ≤ -1.0 dBTP）；
风格沿用"环境合成 + 东方拨弦点缀"的音色家族（同一套合成器/效果链保证一致性）；全部原创，禁止采样。

| # | 资产 ID | 用途与触发点 | 时长 | 风格语言 | 验收标准 | 优先级 | 工时 |
|---|---|---|---|---|---|---|---|
| 1 | `sfx_mine_hit` | 采集命中：`GameSession.request_mine` 每次有效敲击（未耗尽） | 0.15–0.3 s | 短促岩层敲击 + 星壤结晶微光泛音；起音 < 5 ms | 无爆音；连击不刺耳 | P0 | 1–2 h |
| 2 | `sfx_mine_depleted` | 矿破采集成功：`request_mine` 耗尽（`depleted` → `Progression.react(mined)`） | 0.6–1.0 s | 碎裂下行 + 结晶收获的明亮琶音点缀 | 与命中音区分明确；有"收获感" | P0 | 1–2 h |
| 3 | `sfx_build_place` | 放置建筑：`request_place` 成功（`attempt_build` ok） | 0.4–0.8 s | 沉稳落位声 + 拨弦确认点缀（暖色） | 低频不发闷；与 BGM 不互掩 | P0 | 1–2 h |
| 4 | `sfx_build_denied` | 建造拒绝：`request_place` 失败分支（材料不足/地形/岩壁等 AppResult 失败） | 0.3–0.5 s | 低哑双击 + 轻微失谐，明确"不行"但不惩罚感过重 | 音量可比其他 SFX 低 3 dB（`volume_offset_db = -3`） | P0 | 1–2 h |
| 5 | `sfx_craft_success` | 合成成功：`GameSession._on_craft_requested` 成功 | 0.8–1.5 s | 结晶共鸣上行琶音（五声音阶），"精炼完成"的仪式感 | 与 UI 点击区分；-12 LUFS | P1 | 1–2 h |
| 6 | `sfx_ui_click` | UI 点击：HUD 菜单按钮 / BuildBar 槽位 / 合成按钮等 `pressed` | 0.08–0.15 s | 极短玻璃质点击；音量 -3 dB（`volume_offset_db`）防同帧叠爆 | 连点不刺耳；与开关音区分 | P0 | 0.5–1 h |
| 7 | `sfx_ui_toggle` | UI 开关：菜单/背包/帮助面板开合（`menu` / `toggle_inventory`） | 0.15–0.3 s | 轻推风铃/滑动质感；开与关可同素材不同 pitch（±50 音分） | 与点击音层次分明 | P1 | 0.5–1 h |
| 8 | `sfx_dialogue_page` | 对话翻页：DialogueBox 逐行推进 | 0.1–0.2 s | 纸页/风页轻响；音量 -6 dB，逐行连发不烦 | 快速连按不刺耳 | P1 | 0.5–1 h |
| 9 | `sfx_dialogue_choice` | 选项选择：`DialogueBox.option_chosen` | 0.3–0.6 s | 拨弦确认音 + 轻微空间感尾音 | 明确"选择已生效" | P1 | 0.5–1 h |
| 10 | `sfx_battle_action` | 战斗行动：`battle_scene.play_ally_action` 提交（敌方行动可复用并降 3 dB） | 0.2–0.5 s | 中性"指令生效"脉冲；不带伤害感（伤害归受击音） | 行动密集时不与受击音混淆 | P0 | 1–2 h |
| 11 | `sfx_battle_hit` | 受击：战斗结算单位 HP 下降 | 0.2–0.4 s | 打击感冲击 + 短促失谐；己方受击低沉、敌方受击清脆（同一素材 pitch 区分或两条变体） | 高频不过载；连击可叠 | P0 | 1–2 h |
| 12 | `sfx_power_unstable` | 失稳：断电 effect_flag 建筑出现（`unpowered_effect_flags` 非空 / 供电评估新增断电实例） | 0.8–1.5 s | 低频颤动 + 电流不稳质感；警告但不惊吓 | 与战斗音区分；低频不轰头 | P1 | 1–2 h |
| 13 | `sfx_boss_phase` | 相位切换：CombatEngine `phase_change`（`lumen_leviathan` HP ≤ 50% → `leviathan_p1`） | 1.0–2.0 s | 巨兽咆哮质感的合成低吼 + 拨弦动机骤变提示；与 `bgm_boss_final` 切换同帧 | 体量感足够；不爆音（true peak 限值内） | P1 | 2–3 h |
| 14 | `sfx_victory` | 胜利：`encounter_finished` 且 `outcome.result == "victory"` | 1.5–2.5 s | 明亮五声上行短乐句 + 结晶泛音收尾 | 有"胜利感"但不拖沓；之后 2 s 内切回探索曲 | P0 | 1–2 h |
| 15 | `sfx_defeat` | 败北：`outcome.result == "defeat"` | 1.5–2.5 s | 下行半音 + 余烬熄灭质感；克制、不惩罚 | 与胜利音情绪对比明确 | P1 | 1–2 h |
| 16 | `sfx_save_notice` | 保存提示：存档成功，与 HUD `flash_notice("已保存")` 同帧 | 0.3–0.6 s | 轻柔双音确认；音量 -3 dB | 不打断注意力；与 UI 点击区分 | P0 | 0.5–1 h |
| 17 | `sfx_ending_bell` | 结局钟声：`GameSession._show_ending`（ending.tscn 挂载） | 3.0–4.0 s | 余辉编钟质感：大钟泛音缓慢衰减，可叠极简拨弦回响；结局段以钟声 + 现有 BGM 淡出收束 | 衰减自然无截断感；`loop = false` 尾音完整 | P1 | 2–3 h |

## 6. 触发点接线表（W003-A10+ 执行清单）

> 约定：A10 在 app 层实例化 AudioDirector 并注入 resolver；下表"调用点"是接线位置建议——
> 由**调用方**（app/集成层包装，或 A10 增补的轻量转发）调用 AudioDirector，
> W003-A9 未改动 `src/integration/**`、`src/ui/**`、`scenes/app.tscn` 任何一行。

| 触发点（代码位置） | 建议调用 | 资产 ID | 备注 |
|---|---|---|---|
| 标题场景（A10 新建）`_ready` | `play_bgm("bgm_title", 1.0)` | bgm_title | 回标题同此 |
| 序章事件 `event_prologue_landing` 完成（`GameSession._finish_active_event` 后的进度切换点） | `play_bgm("bgm_explore", 2.0)` | bgm_explore | 或按 `Hud.objective_for` 链里程碑切 |
| 建造热键栏焦点时段（BuildBar 交互） | `play_bgm("bgm_build", 2.0)` | bgm_build | 切点由 A10 定 |
| `GameSession.request_mine` 敲击未耗尽 | `play_sfx("sfx_mine_hit")` | sfx_mine_hit | 可加 ±20 音分 pitch 抖动 |
| `request_mine` 耗尽分支 | `play_sfx("sfx_mine_depleted")` | sfx_mine_depleted | 与 `Progression.react(mined)` 同帧 |
| `request_place` 成功 | `play_sfx("sfx_build_place")` | sfx_build_place | |
| `request_place` 失败分支（含 rock_wall_cell） | `play_sfx("sfx_build_denied", -3.0)` | sfx_build_denied | AppResult 非 ok 即拒 |
| `GameSession._on_craft_requested` 成功 | `play_sfx("sfx_craft_success")` | sfx_craft_success | |
| HUD 面板开合（menu / toggle_inventory / 帮助） | `play_sfx("sfx_ui_toggle")` | sfx_ui_toggle | |
| 各 Button `pressed`（菜单/BuildBar/合成按钮） | `play_sfx("sfx_ui_click", -3.0)` | sfx_ui_click | |
| DialogueBox 逐行推进 | `play_sfx("sfx_dialogue_page", -6.0)` | sfx_dialogue_page | 批量行时逐行触发 |
| `DialogueBox.option_chosen` | `play_sfx("sfx_dialogue_choice")` | sfx_dialogue_choice | |
| `GameSession._start_encounter`（普通） | `play_bgm("bgm_battle", 0.5)` | bgm_battle | |
| `_start_encounter`（`encounter_leviathan`） | `play_bgm("bgm_boss", 0.5)` | bgm_boss | |
| CombatEngine `phase_change` 事件（Boss） | `play_sfx("sfx_boss_phase")` + `play_bgm("bgm_boss_final", 0.5)` | sfx_boss_phase / bgm_boss_final | 同帧 |
| `battle_scene.play_ally_action` / 敌方行动 | `play_sfx("sfx_battle_action")` | sfx_battle_action | 敌方行动 -3 dB |
| 战斗结算单位 HP 下降 | `play_sfx("sfx_battle_hit")` | sfx_battle_hit | 己/敌 pitch 变体可选 |
| `encounter_finished` victory | `play_sfx("sfx_victory")`；2 s 后 `play_bgm("bgm_explore", 2.0)` | sfx_victory / bgm_explore | |
| `encounter_finished` defeat | `play_sfx("sfx_defeat")` | sfx_defeat | 保留 due flag，BGM 维持 |
| 供电评估新增断电实例 / `unpowered_effect_flags` 出现 | `play_sfx("sfx_power_unstable")` | sfx_power_unstable | 幂等：同建筑只报一次 |
| 存档成功（`save_now` / `_on_save_requested` ok，与 `flash_notice` 同帧） | `play_sfx("sfx_save_notice", -3.0)` | sfx_save_notice | |
| `GameSession._show_ending` | `play_sfx("sfx_ending_bell")`；现有 BGM 4 s 淡出 | sfx_ending_bell | 结局曲不在本切片范围 |
| 主菜单"重新开始"生效后 | `stop_all()` → 按新进度重放 | — | `GameSession._on_restart_requested` 链 |

## 7. 溯源与审批（原创性合规）

- **工具登记（provenance）**：每个资产交付时在 `ops/`（A10 资产包建立清单）登记：
  工具 + 版本、工程文件/参数（合成器 patch、效果链、随机种子）、制作者、日期、文件哈希、
  母带路径。无 provenance 的资产不得进入 `assets/audio/` 交付目录。
- **原创合成工具建议**（无在世画师类比条款同样适用于音频：禁止模仿在世作曲家/艺术家风格；
  **禁止采样他人作品**，包括"只采样几个音符"）：
  - DAW：Reaper / Bitwig（任一即可，工程文件随 provenance 归档）；
  - 合成器：Vital、Surge XT、Dexed（开源免费），拨弦质感建议物理建模（Karplus-Strong）或自建 patch；
  - SFX 快速原型：Bfxr / jsfxr 变体 + Audacity 后期（裁剪/降噪/响度归一）；
  - 响度校准：ffmpeg `loudnorm`（-16/-12 LUFS 双目标）或 Youlean Loudness Meter 校验。
- **审批流**：generated assets 需 provenance 完整 + 人工试听审批后方可置 `approved` 状态
  （AGENTS.md：Generated assets require provenance and human approval before approved status）。
- **验收测试挂钩**：A10 接线时为每个资产 id 加载即得 `AudioStream`；`AudioDirector` 侧已覆盖
  resolver 缺失/坏返回的降级路径（`tests/unit/test_audio_director.gd`）。

## 8. 工时与优先级汇总

| 类别 | 数量 | P0 | P1 | 工时合计 |
|---|---|---|---|---|
| BGM | 5（bgm_boss 含两段交付） | 4 | 1 | 36–46 h |
| SFX | 17 | 8 | 9 | 17–28 h |
| 合计 | 22 | 12 | 10 | 53–74 h |

G6 前置门禁：22 项资产全部满足 §2 格式/响度/循环标记 + provenance 齐全 + 人工审批通过；
Windows 实机试听无爆音、循环无缝、BGM 不压 SFX。
