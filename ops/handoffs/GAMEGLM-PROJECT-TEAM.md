# GAMEGLM 项目组交接单（产品协调）

- 日期：2026-09-03（Asia/Shanghai）
- 仓库：Asunainlove/GAMEGLM
- 基线提交：`b597a2e`（feat(art): G6 Plan A batch1 env approved and drop-in）
- 状态源：`ops/state.json`（`project_team_status: active`）
- 完成门：`G7 Windows RC`（见 `ops/GOAL.md`）

## 1. 当前状态（一句话）

代码侧垂直切片与自动门禁已就绪；G6 方案 A 资产生产中——**batch1 环境已批准并 drop-in**，**batch2/3/4 进行中**；**G7 真人试玩/外部试玩/原创性终审仍待人工填写**（不得捏造结果）。

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
| 1 环境 | `G6A-P0-BATCH1-ENV` | 地表/矿脉/岩壁/Boss 刻印 | **done**（approved + drop-in） | 美术 / 已审批 Asunainlove | `assets/art/world/tiles|decals/` · environment-assets.md |
| 2 单位 | `G6A-P0-BATCH2-UNITS` | 6 单位 × 8 帧（Boss 双相位） | **in_progress** | 美术 | `assets/art/battle/units/<id>/` · battle-assets.md |
| 3 UI | `G6A-P0-BATCH3-UI` | 面板/按钮/物品图标（+字体建议） | **in_progress** | 美术 | `assets/art/ui/**` · ui-assets.md |
| 4 音频 | `G6A-P0-BATCH4-AUDIO` | 5 BGM + 17 SFX | **in_progress** | 美术 / 工程接线 | `assets/audio/**` · audio-assets.md |

提示词包：`docs/art/prompts/plan-a-p0-batch-prompts.md`  
Drop-in 对照：`ops/evidence/G6P-1.md` §3  
审批表：`ops/art-approval.md`（batch1 七行已 `approved`）

每批完成标准：

1. 按合同尺寸/命名产出 → 登记 `ops/art-approval.md`（pending）
2. 所有者人工审批 → `approved`
3. Drop-in 到合同路径 → 复跑 `Run-Gut.ps1` + `Verify-Slice.ps1`
4. 启动游戏目检三挂点（世界 / 战斗单位 / HUD 图标）与音频（batch4）

## 4. G7 真人门禁状态

| 门禁 | 状态 | 填写位置 |
|---|---|---|
| 45–60 分钟三分支试玩 | **未执行 / 待填写** | `docs/rc-playthrough-record.md` §A |
| 存读档人工抽检 | **未执行 / 待填写** | 同文件 §A 存读档 + §A.4 |
| 外部试玩 ≥3 人 | **未执行 / 待填写** | 同文件 §B |
| 原创性终审 C.1/C.2 | **待人工复核签署**（C.1 可复核；C.2 随 G6 批次推进） | 同文件 §C |
| 性能 smoke / 干净导出抽检 | **待人工补记**（自动侧有历史证据，RC 仍需新鲜记录） | `docs/rc-checklist.md` §5–§6 |

操作指引：`docs/g6-g7-human-gates-guide.md`  
RC 总清单：`docs/rc-checklist.md`

**禁止**：在试玩记录中填写未实际发生的用时、复述、签署或“通过”。

## 5. 剩余工作清单（可勾选）

### 5.1 G6 生产（美术主导，工程/幕僚长配合）

- [ ] Batch2：产出 6 单位帧（含 `lumen_leviathan` phase1/phase2）并 staging
- [ ] Batch2：`ops/art-approval.md` 登记 → 所有者 `approved` → drop-in → 门禁 + 目检
- [ ] Batch3：面板/按钮/6 物品图标（双尺寸按合同）staging → 审批 → drop-in → 目检
- [ ] Batch4：5 BGM + 17 SFX 产出与路径对齐 `docs/art/audio-assets.md`
- [ ] Batch4：审批后落位；工程确认 AudioDirector 接线/冒烟
- [ ] （可选后续）合同剩余非 P0 / R1–R9 接线包登记进 backlog，不阻塞 G7 裁定路径

### 5.2 G7 人工门禁（产品/测试主导，**仅人类可关闭**）

- [ ] 本机用 `build/starsoil/starsoil.exe`（或编辑器 F5）跑通开采 / 封存 / 共生三路线
- [ ] 填写 `docs/rc-playthrough-record.md` 元信息、用时、检查点、复述检验（留空项保持空）
- [ ] 完成存读档三点抽检与字段核对
- [ ] 外部 ≥3 名非开发者试玩 + 问卷汇入 §B
- [ ] 原创性终审勾选并签署 §C / §D（含 G6 资产溯源 C.2）
- [ ] 按需补跑并粘贴新鲜自动门禁输出到 `ops/evidence/`（不得只引用历史结论）

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

1. **美术**：推进 `G6A-P0-BATCH2-UNITS`（当前 `active_packet`），并行准备 batch3/4 素材。
2. **产品/测试**：按 `docs/g6-g7-human-gates-guide.md` §2 启动真人三路线试玩，只写真实结果到 `docs/rc-playthrough-record.md`。
3. **幕僚长**：跟踪批次审批与本交接单勾选进度；准备下一次 state 刷新。

## 8. 恢复协议

1. 读 `AGENTS.md`、`ops/GOAL.md`、`ops/state.json`、本文件。
2. 确认 `last_verified_commit` 为当前工作祖先或已记录的验证点。
3. 仅从 `resume_from` / `next_packet_ids` 恢复；G7 结果不得由代理代填。
