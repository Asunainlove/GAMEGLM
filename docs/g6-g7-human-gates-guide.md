# G6/G7 人工门禁一页操作说明（2026-08-31）

面向项目所有者的一页操作指引。当前代码侧全部完成（main @ 700/700 测试全绿，三道门禁 exit 0，含 `build/starsoil/starsoil.exe` 导出）；本页覆盖仅剩的两类人工门禁。

## 0. 决策点（二选一，即可关闭 G6 门禁）

- **方案 A｜生产正式资产**：按 §1 流程产出 128 项美术 + 22 项音频，逐批人工审批后 drop-in。
- **方案 B｜保持灰盒交付**：明示授权"灰盒即 G6 交付形态"（本切片的全部视觉已由运行时灰盒渲染构成且功能完整），协调者据此把 G6 标记为 `accepted_greybox` 并直接进入 G7。

> 说明：`docs/art/` 四份合同（角色 20 / 环境 29 / UI 49 / 战斗 28 = 126 项）+ 音频合同（5 BGM + 17 SFX = 22 项）已把每项资产的 ID/落位/尺寸/构图/验收/优先级/工时写全，可交给任何人工或 AI 生图工具按合同执行。

## 1. 方案 A：G6 资产生产与审批流程

1. **生产**：按合同逐批（P0 优先）产出资产；生成式工具需在溯源登记表记录（工具/提示词/日期/生成者）。
2. **落位（drop-in 对照表见 `ops/evidence/G6P-1.md` §3）**——放置后零代码生效：
   - 环境：`assets/art/world/tiles/env_world_soil_base.png`、`env_ore_{dust,shard,core}_set.png`、`env_mine_wall_atlas.png`（已接线的 4 个 TileSet 源；其余 ENV 条目为后续接线包 R1-R9，放置可解析不报错）
   - 战斗单位：`assets/art/battle/units/<unit_id>/<unit_id>_<state>_<NN>.png`（idle×2/attack×3/hit×1/death×2，8 帧零起两位编号；Boss 另备 `phase1/` 与 `phase2/` 双套）
   - HUD 物品图标：`assets/art/ui/icons/ui_item_<item_id>.png`（24×24）
3. **审批（AGENTS.md 强制）**：对照合同验收标准逐项审 → 在 `ops/art-approval.md` 登记（资产 ID/来源/批准人/日期）→ 状态 `approved` 后方可提交到 `assets/`。
4. **验证**：`pwsh -NoProfile -File ./scripts/Run-Gut.ps1`（700/700）+ `Verify-Slice.ps1`（GATE4 导出冒烟）；启动游戏目检三挂点替换效果。
5. **音频**：AudioDirector 已就绪（resolver 注入 + `docs/art/audio-assets.md` §6 接线表）；音频文件按合同路径放入后由集成层接线包接上（接线包为 S 级遗留，登记在案）。

## 2. G7 真人门禁执行指引

### 2.1 45–60 分钟三分支试玩（校准核心假设）

启动 `build/starsoil/starsoil.exe`（或 Godot 编辑器 F5）。每条路线走一遍，记录时长与三问复述：

1. **开采线**：新游戏 → 对话推进 → 采尘矿（左键）→ 建锚块+工坊（数字键 1-6 选择、右键放置）→ 采晶片/核矿 → I 打开背包合成定神雾 → 经历两次战斗（回合制按钮）→ 建回响舱 → 三次选择选"最大化开采/直接接近/开采配额" → 决战 Boss → 结局：开采纪元。检查点：矿脉富集是否可感知（exploit 后重生成）、BuildBar 断电红点、信任面板数值。
2. **封存线**：同链路选"封存矿脉/先观察再接触/开采配额"→ 结局：封存之约。
3. **共生线**：选"尝试共生/直接接近/庇护政策（需信任 ≥40）"→ 结局：共生曙光。检查点：信任是否走到 70（HUD 关系面板可见）。
4. **复述检验（章程核心假设）**：问试玩者"你的采集/建造/校准改变了什么？"——应能复述地图变化、角色立场变化、Boss 条件变化与结局差异。
5. **存读档**：菜单键保存 → 重启 → 继续（标题界面）→ 进度一致；重新开始 → 归零。
6. **节奏记录表**：每路线实际用时、卡点、超 60 分钟段落 → 填入 `docs/rc-checklist.md` §3。

### 2.2 外部试玩门禁

- ≥3 名未参与开发的外部玩家，各走 1 条路线；收集复述率与首 5 分钟流失点；汇入 rc-checklist §5。

### 2.3 原创性终审

- 对照 AGENTS.md 内容规则：角色/台词/UI/资产全原创；生成资产逐一核对溯源登记；第三方仅 GUT 9.7.1（已登记 `THIRD_PARTY_NOTICES.md`）；结果写入 rc-checklist §6。

## 3. 统一验证命令（每步操作后复跑）

```powershell
pwsh -NoProfile -File ./scripts/Run-Gut.ps1          # 700/700 全绿
pwsh -NoProfile -File ./scripts/Verify-Toolchain.ps1 # 五道门禁 exit 0
pwsh -NoProfile -File ./scripts/Verify-Slice.ps1     # 四道门禁 + 导出冒烟 exit 0
python scripts/validate_content.py                   # 内容 schema 校验 PASS
```

维护契约：改动 `data/**` 或进度配置后必须重跑 `tests/golden/generate_golden_v1.gd` 更新 golden fixture（DLX-6 政策）。
