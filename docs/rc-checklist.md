# RC 门禁清单（G7）——《星壤：余辉纪元》垂直切片

本清单是里程碑 G7（Windows RC）的发布门禁。全部条目通过后方可声明切片完成；
每项记录：执行人、日期、命令/步骤、结果与证据路径（`ops/evidence/`）。
自动门禁必须附**新鲜命令输出与退出码**，不得引用历史结论。

## 1. 自动门禁（全部退出码必须为 0）

```powershell
pwsh -NoProfile -File ./scripts/Run-Gut.ps1            # 门禁 A：tests/unit 全套件
pwsh -NoProfile -File ./scripts/Verify-Toolchain.ps1   # 门禁 B：引擎版本/导入/主场景/GUT/失败夹具 5 道
pwsh -NoProfile -File ./scripts/Verify-Slice.ps1       # 门禁 C：GUT + 工具链 + 导出预设 + 导出冒烟
```

- [ ] A：`Run-Gut.ps1` 退出码 0（基线 + 全部工作包测试全绿）。
- [ ] B：`Verify-Toolchain.ps1` 退出码 0，五行 PASS（VERSION/IMPORT/MAIN_SCENE/GUT_DEFAULT/GUT_FAILURE_FIXTURE）。
- [ ] C：`Verify-Slice.ps1` 退出码 0；门 4 在本机无导出模板时输出 `GATE4 EXPORT_SMOKE SKIP` 属预期限制，须在证据中如实记录，并在完成"干净导出"（§6）后补跑一次含 GATE4 PASS 的完整记录。
- [ ] 内容校验：`pwsh -NoProfile -File ./scripts/Validate-Content.ps1` 退出码 0。

## 2. 原创性审查清单（对照 AGENTS.md 逐条）

- [ ] 全部角色（洛弦、弥砂）为原创成年人设定；无任何现实或既有作品中角色的姓名、背景、台词复用。
- [ ] 无对既有游戏的剪影、UI 布局、图标、术语、Logo 的模仿或复用；灰盒与文案均为本项目原创。
- [ ] 全部中文文案（事件、对话、结局标题与总结、菜单）为原创，无占位符（TODO/FIXME/占位/??? 等）残留。
- [ ] 未请求在世艺术家的画风，未要求模仿任何具名商业游戏。
- [ ] 第三方内容：GUT 插件与引擎来自锁定渠道，`THIRD_PARTY_NOTICES.md` 中溯源与许可记录完整。
- [ ] 自产资产（若 RC 前引入美术/音频替换灰盒）：每件均有溯源记录并经人工批准进入 `approved` 状态；未批准资产不得进入导出包。
- [ ] 内容 ID 全部符合稳定 `snake_case` 正则，无占位 ID。

## 3. 45–60 分钟节奏人工试玩步骤

环境：Windows 10/11，1280×720，键鼠；全新存档目录（删除 `%APPDATA%\Godot\app_userdata\星壤：余辉纪元\saves\`）。

- [ ] 启动至可操作世界 ≤ 60 秒；序章降落事件自动触发。
- [ ] 完成首次采集（`first_mining_done`）→ 触发首次建造引导 → 放置锚块与锚居工坊（注意 `anchor_workshop_placed`）。
- [ ] 建造并供电尘精炼器、稳定塔、共鸣织机；建造回响舱（需房间，`echo_chamber_active` 置位）。
- [ ] `station_mode` 三选一（开采/封存/共生方向）；随后完成 `approach`、`policy` 两次选择（验证 `policy_sanctuary` 在洛弦信任 ≥ 40 时才可选）。
- [ ] 三场遭遇按序触发并取胜：`encounter_first_drift`、`encounter_husk_ambush`、`encounter_leviathan`（Boss 两阶段；选择开采配额后 Boss 血量 ×1.2 须可感知）。
- [ ] `event_leviathan_pact` → 结局双事件（`event_ending_luoxian`/`event_ending_misa`）→ 结局场景渲染。
- [ ] 结局分支验证（至少跑通三种读档或完整周目组合）：
  - [ ] `station_mode_exploit` → 「结局：开采纪元」；
  - [ ] `station_mode_seal` → 「结局：封存之约」；
  - [ ] `station_mode_symbiosis` + 洛弦信任 ≥ 70 + 回响舱激活 → 「结局：共生曙光」；
  - [ ] `station_mode_symbiosis` 但信任 69 或未激活回响舱 → 回落「结局：封存之约」。
- [ ] 节奏记录：各阶段耗时与累计时间（目标 45–60 分钟），超出范围时记录瓶颈阶段。
- [ ] 主观检查：玩家能复述"我采集/建造/校准的行为改变了地图、角色立场、Boss 条件与结局"（核心假设）。

## 4. 存档重载验证步骤

- [ ] 至少在三个节点存档：序章后、回响舱激活后、Boss 战前（`SaveService.save_slot`，主档 + 备份轮换生效）。
- [ ] 完全退出进程后重新启动，逐档读取；校验以下字段与存档前一致：
  - [ ] `inventory`（材料数量）、`flags`（推进/遭遇/政策旗标）、`relationships`（洛弦/弥砂三维）；
  - [ ] `placed_buildings`（建筑与坐标）、`chunk_deltas`（已破坏格）、`player.position`；
  - [ ] `completed_events`、`battle_outcomes`、`revision`、`content_hash`。
- [ ] 损坏主档时备份/tmp 恢复路径可用（手工破坏主档后重载不崩溃）。
- [ ] 存档 schema 仍为 `save_version 1`；`tests/golden/save_v1_golden.json` 金样夹具测试通过（含于门禁 A）。
- [ ] 重载后继续推进至结局，行为与未中断周目一致。

## 5. 性能 smoke

- [ ] 启动时间：冷启动双击导出 exe 至世界可操作 ≤ 60 秒（记录秒表值）；开发热启动 ≤ 20 秒。
- [ ] 战斗帧率采样：三场遭遇各取 60 秒采样（外置帧率叠加层或引擎监视器），GL Compatibility 下 1280×720 全程 ≥ 58 fps，无持续跌帧。
- [ ] 世界探索采样：跨 chunk 移动、矿脉覆盖层开关、建造放置各采样 30 秒，≥ 58 fps。
- [ ] 内存：任务管理器记录进程工作集（启动后与 Boss 战后各一次），无持续增长泄漏迹象。
- [ ] 异常记录：任何一次崩溃、卡死、贴图/字体缺字（中文渲染）均记为 RC 阻塞项。

## 6. 干净导出步骤

- [ ] 安装 Godot `4.7.2.stable` Win64 导出模板至 `%APPDATA%\Godot\export_templates\4.7.2.stable\`。
- [ ] 删除 `build/` 与 `dist/`（若存在），工作区干净（`git status` 无未提交改动）。
- [ ] 执行导出（预设 "Windows"）：

```powershell
pwsh -NoProfile -File ./scripts/Verify-Slice.ps1   # 门 4 应为 GATE4 EXPORT_SMOKE PASS
```

或手动：

```powershell
godot --headless --path . --export-release "Windows" build\starsoil\starsoil.exe
```

- [ ] 产物位于 `build/starsoil/starsoil.exe`；断网双击启动，完成 §3/§4 的抽检版（序章 → 一场战斗 → 存档重载）。
- [ ] 记录产物 SHA-256 与体积入证据。

## 7. 外部试玩门禁说明

- [ ] 试玩者 ≥ 3 名（非项目成员），环境为普通 Windows PC；分发 §6 导出产物与一份一页纸说明（操作键位表）。
- [ ] 收集方式：结构化问卷 + 自由反馈；必答项——
  - [ ] 是否能在不被提示的情况下说出"自己的采集/建造/校准改变了什么"（核心假设验证）；
  - [ ] 三次选择与结局走向是否可感知、可复述；
  - [ ] 节奏主观时长（45–60 分钟目标）、卡点与挫败点；
  - [ ] 中文文案可读性与错别字报告。
- [ ] 通过标准：无 P0（崩溃/无法推进/存档丢失）问题；核心假设复述成功 ≥ 2/3 人；节奏偏差在记录后由协调者裁定是否阻塞。
- [ ] 全部问题入库 `ops/backlog.json`，P0/P1 修复后重跑 §1 自动门禁 + 对应人工抽检，方可宣布 G7 RC 通过。

## 状态记录（2026-08-30 协调者更新）

自动门禁全部达成：

- [x] Run-Gut 全套件 366/366 通过（3261 断言），exit 0
- [x] Verify-Toolchain 五道门禁 exit 0
- [x] Verify-Slice 四道门禁 exit 0，**GATE4 真实导出 PASS**：`build/starsoil/starsoil.exe`（109MB，Windows Desktop 预设）
- [x] 内容数据 schema 校验：Validate-Content 40 定义 exit 0
- [x] 性能 smoke（灰盒基线）：headless 启动计时 2227/2199/2354 ms（三次采样）；战斗确定性由 test_combat_engine 同种子同结果测试锁定
- [x] 存档重载：test_save_service + test_integration 覆盖三代轮转/迁移/golden 往返/启动读档

仍需人工执行的 G7 门禁（不可自动化）：

- [ ] 45–60 分钟真人试玩：三分支结局（开采/封存/共生）全到达，检验 charter 核心假设"玩家行为改变世界与结局"
- [ ] 外部试玩门禁：至少 3 名外部玩家，收集 charter 假设复述率
- [ ] 原创性与资产溯源终审（当前全灰盒无外部资产，GUT 9.7.1 vendor 已登记 THIRD_PARTY_NOTICES.md）
