# 2026-08-31 PM 深度审核裁决与 DLC 就绪计划

审核方法：对照章程 + 六场景"新增内容步骤数"实测走查 + 架构纪律核查（只读）。完整证据见审核原始报告（对话留档）；本文是裁决与执行计划。

## PM 三问裁决

| 问题 | 裁决 | 评分 | 依据摘要 |
|---|---|---|---|
| 作为游戏成立吗 | **成立**（垂直切片意义） | 3.5/5 | 核心循环 4/5（tick 链互斥推进无死结，闭环真实存在）；可感知反馈 3/5（信任数值不可见、世界差分几乎纯台词）；节奏 3/5（完整周目约 30-45 分钟，速通可 <25） |
| 内容开发完成了吗 | **锁定范围代码侧完成** | 4/5 | 章程 Locked scope 逐项 ✅（55 定义被测试锁定）；G6 美术音频（合同已备）、G7 真人门禁为章程既定阶段 |
| 可复用部件完成了吗 | **服务层完成、内容管线半程** | 3/5 | 物品/配方/战斗/事件文本维度已是纯数据（★★★★★）；事件链顺序、结局门控、世界布局、目标链、引导触发、建造反应六条管线仍代码硬编码（★-★★）——"数据包即 DLC"尚未成立 |

## 架构纪律核查（全部通过）

Autoload 恰 3 个；无全局事件总线；无表达式求值；表现层零直改状态；存档 v1+迁移链+golden fixture+content_hash 记录。**已知缺口**：content_hash 有记录无消费（读档无 mismatch 政策）→ DLX-6 处理。

## 已确认最有价值的可复用部件（零/低耦合，DLC 直接复用）

Gathering、InventoryModel、PowerGrid、CraftingService（完全通用）；CombatEngine、EncounterDirector、BuildingRules、SaveService/Codec/StatePatch、ContentDB、AudioDirector（高通用，各有 1-2 个声明式化即可消除的边缘耦合点）。

## 执行计划（六包，串行派发，每包 TDD+全量门禁）

| 包 | 目标（含审核发现的 P0） | 关键交付 | 工作量 |
|---|---|---|---|
| DLX-1 | 结局/门控数据化（DL4）+ 信任经济均等（P0） | `data/content/endings.json`（all_of_flags/trust 对象/fallback/文案）驱动 Endings；`requires_trust` 对象化 {char,dim,value}（兼容标量=luoxian.trust）；外交路线补 +5 信任来源使双路线 70 可达（或等效裁决）；移除 relations.policy_unlocked 死 API；golden 兼容 | M |
| DLX-2 | 事件链外置（DL1）+ 测试去硬编码（DL7） | `data/progression/event_chain.json`（id/requires_all/requires_any_prefix/requires_ending_ready 声明式有序链）驱动 due_event；EXPECTED_DEFINITION_COUNT→派生断言 | M |
| DLX-3 | 建造反应通用化（DL2）+ 目标链/提示外置（DL5） | 供电 effect_flag 通用规则 + `place_flag` 声明式字段，删 `_react_built` match；`objectives.json`/`hints.json` 触发表驱动 HUD | S-M |
| DLX-4 | PM-P0a 信任可见 + 死内容与世界回应感知 | HUD 关系面板（affection/trust/ideology 数值显示 + 政策门提示"信任不足 x/40"）；echo_seed 消费者（数据侧：结局门控/回响舱输入/终章事件三选一，裁决记录）；`world_response_exploited` → 矿脉富集的世界变化（flag 消费者落地） | M |
| DLX-5 | 世界布局外置（DL3） | `data/world/world_config.json`（网格尺寸/seed）+ `data/world/chunks/chunk_3_1.json`（wall_rects/ore_rects/boss_room）+ 地区声明式触发（entry_event/entered_flag/checkpoint_rect）；删 GDScript 布局常量与特判 | M-L |
| DLX-6 | 存档内容政策（DL6） | 读档比对 content_hash：mismatch 时声明式孤儿清理（引用不存在定义/事件的 flag 降级）+ golden fixture 扩展 + 政策文档化 | S |

## 明确不做（范围裁决）

- **不做 mods/插件框架、事件总线、表达式求值**（AGENTS.md 禁区；DLC = 内容数据包，加载路径就是 ContentDB.bootstrap 的 data/ 目录约定）。
- **不做 7 个程序 chunk 的 POI 全量填充**（L 级，属 G6 后内容扩展；本波以 DLX-4 的矿脉富集世界变化回应章程"行为改变地图"假设的最小可感版本）。
- **45-60 分钟最终校准**归 G7 真人试玩（不可自动化），本计划把速通路径从 25 分钟抬到 35+ 分钟维度（新增事件+信任可见+世界变化）后交由试玩裁决。

## 完成定义（本计划级）

六包全部 VERIFIED 合并 + 复审走查"六场景新增内容步骤数"全部 ≤ 1 个 JSON 文件（无 GDScript diff）+ 全量门禁绿 + PM 三问复评（目标：可复用性 3/5 → 4.5/5）。随后项目状态回到 G6 资产生产（人工审批门）与 G7 真人门禁。
