# GAMEGLM 项目组交接单（产品协调）

- 日期：2026-09-03（Asia/Shanghai）
- 仓库：Asunainlove/GAMEGLM
- 基线提交：`3d6cd1c`（feat(audio): inject P0 SFX/BGM hooks — PR #18；含 PR #17 AudioCatalog）
- 状态源：`ops/state.json`（`project_team_status: active`，`active_packet: G7-HUMAN`，`last_verified_commit: 3d6cd1c`）
- 完成门：`G7 Windows RC`（见 `ops/GOAL.md`）

## 1. 当前状态（一句话）

G6 方案 A P0（batch1–4）**全部 done**（资产 approved + drop-in；音频 resolver/§6 P0 钩子已合入 main）；`active_packet=G7-HUMAN`。自动门禁绿（近端 tip：`validate_content` PASS、默认 GUT 712+/715 PASS）。**G7 真人试玩/外部试玩/原创性终审仍待主人填写**（不得捏造结果）。

## 2. 角色与责任人

| 角色 | 职责范围 | 当前 Owner | 关键产出 |
|---|---|---|---|
| 产品 | 范围/优先级/门禁裁定、节奏与核心假设验收 | 产品（Asunainlove / 协调代理） | `ops/state.json`、本交接单、G7 通过裁定 |
| 美术 | 方案 A 资产生产、溯源登记、落位与目检 | 美术 + 幕僚长（生成/整理） | `ops/art-staging/**`、`ops/art-approval.md`、`assets/art/**`（仅 approved） |
| 工程 | 适配层/接线包、导出、自动门禁绿、集成修复 | 工程 | `src/**`、`scripts/**`、`build/starsoil/`、证据包 |
| 测试 | 自动门禁复跑、RC 清单抽检、试玩记录质检 | 测试 | `docs/rc-checklist.md` 勾选、证据新鲜输出 |
| 幕僚长 | 并行调度、提示词/批次整理、交接与 PR 协调 | 幕僚长 | `ops/handoffs/**`、批次提示词、审批表草稿 |

> 审批硬规则（AGENTS.md）：资产状态仅所有者可改为 `approved`；未批准资产不得进入 `assets/` 导出包。

## 3. G6 方案 A 批次看板

| 批次 | 包 ID | 内容 | 状态 | Owner | 落位 / 合同 |
|---|---|---|---|---|---|
| 1 环境 | `G6A-P0-BATCH1-ENV` | 地表/矿脉/岩壁/Boss 刻印 | **done** | 美术 / 已审批 | `assets/art/world/tiles|decals/` · environment-assets.md |
| 2 单位 | `G6A-P0-BATCH2-UNITS` | 6 单位 × 8 帧（Boss 双相位） | **done** | 美术 / 已审批 | `assets/art/battle/units/<id>/` · battle-assets.md |
| 3 UI | `G6A-P0-BATCH3-UI` | 面板/按钮/物品图标（+字体） | **done** | 美术 / 已审批 | `assets/art/ui/**` · ui-assets.md |
| 4 音频 | `G6A-P0-BATCH4-AUDIO` | 5 BGM + 17 SFX + 接线 | **done** | 美术 / 工程（PR #17/#18） | `assets/audio/**` · audio-assets.md |

提示词包：`docs/art/prompts/plan-a-p0-batch-prompts.md`  
Drop-in 对照：`ops/evidence/G6P-1.md` §3  
审批表：`ops/art-approval.md`（**全批 P0 行已 `approved`**）

每批完成标准（已满足）：

1. 按合同尺寸/命名产出 → 登记 `ops/art-approval.md`
2. 所有者人工审批 → `approved`
3. Drop-in 到合同路径 → 复跑 `Run-Gut.ps1` +（按需）`Verify-Slice.ps1`
4. 启动游戏目检三挂点（世界 / 战斗单位 / HUD 图标）与音频

## 4. G7 真人门禁状态

| 门禁 | 状态 | 填写位置 |
|---|---|---|
| 45–60 分钟三分支试玩 | **未执行 / 待主人填写** | `docs/rc-playthrough-record.md` §A |
| 存读档人工抽检 | **未执行 / 待主人填写** | 同文件 §A 存读档 + §A.4 |
| 外部试玩 ≥3 人 | **未执行 / 待主人填写** | 同文件 §B |
| 原创性终审 C.1/C.2 | **待主人复核签署** | 同文件 §C |
| 性能 smoke / 干净导出抽检 | **自动侧有历史证据；RC 仍建议新鲜补记** | `docs/rc-checklist.md` §5–§6 |

操作指引：`docs/g7-playtest-facilitator.md`（辅：`docs/g6-g7-human-gates-guide.md`）  
RC 总清单：`docs/rc-checklist.md`

**禁止**：在试玩记录中填写未实际发生的用时、复述、签署或“通过”。

## 5. 剩余工作清单（可勾选）

### 5.1 G6 生产（已关闭）

- [x] Batch2：产出 6 单位帧（含 `lumen_leviathan` phase1/phase2）并 staging
- [x] Batch2：`ops/art-approval.md` 登记 → 所有者 `approved` → drop-in → 门禁 + 目检
- [x] Batch3：面板/按钮/6 物品图标 staging → 审批 → drop-in → 目检
- [x] Batch4：5 BGM + 17 SFX 产出与路径对齐 `docs/art/audio-assets.md`
- [x] Batch4：审批后落位；AudioCatalog + §6 P0 钩子合入（PR #17 / #18）

**非真人可清残留（不阻塞 G7 裁定；产品确认后不另开产项）：**

- [ ] SFX / BGM **全表调用点**收尾接线（resolver 与 P0 钩子已在；余：`bgm_build` 焦点、结局 BGM-only fade、标题点击 SFX 等，见 `docs/art/audio-assets.md` §6）
- [ ] 新鲜 `Verify-Slice` / 导出冒烟输出记入 `ops/evidence/`（不得只引用历史结论）
- [ ] 合同剩余非 P0 / R1–R9 接线包可登记 backlog，**不阻塞 G7**

### 5.2 G7 人工门禁（**硬门：仅主人可关闭**）

- [ ] 按 `docs/g7-playtest-facilitator.md` 本机跑通开采 / 封存 / 共生三路线
- [ ] 填写 `docs/rc-playthrough-record.md` 元信息、用时、检查点、复述检验（留空项保持空）
- [ ] 完成存读档三点抽检与字段核对
- [ ] 外部 ≥3 名非开发者试玩 + 问卷汇入 §B
- [ ] 原创性终审勾选并签署 §C / §D（含 G6 资产溯源 C.2）
- [ ] （建议）按需补跑并粘贴新鲜自动门禁输出到 `ops/evidence/`

### 5.3 协调收尾

- [ ] 全部 G7 人工项通过后：更新 `ops/state.json`（milestone/window_status/`G7` accepted）
- [ ] 宣布垂直切片 RC 完成；未通过项入库 `ops/backlog.json`（P0/P1 阻塞）

## 6. 统一验证命令（改动后复跑）

```powershell
pwsh -NoProfile -File ./scripts/Run-Gut.ps1
pwsh -NoProfile -File ./scripts/Verify-Toolchain.ps1
pwsh -NoProfile -File ./scripts/Verify-Slice.ps1
python scripts/validate_content.py
```

## 7. 确切下一步

1. **主人（硬门）**：按 `docs/g7-playtest-facilitator.md` 填 `docs/rc-playthrough-record.md`；代理不得代填。
2. **工程/测试（非阻塞）**：SFX 全表调用点收尾；新鲜 Verify-Slice/导出冒烟入 evidence；顺手盯 `test_craft_button_in_inventory_panel_closes_the_loop` 顺序污染（不挡 G7）。
3. **产品**：本交接单与 `ops/state.json` 已对齐 G7-HUMAN；确认后不另开 G6 产项。

## 8. 恢复协议

1. 读 `AGENTS.md`、`ops/GOAL.md`、`ops/state.json`、本文件。
2. 确认 `last_verified_commit` 为当前工作祖先或已记录的验证点（现基线 `3d6cd1c`）。
3. 仅从 `resume_from` / `next_packet_ids` 恢复；G7 结果不得由代理代填。
