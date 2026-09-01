# DLX-4 信任可见 + 死内容消费 + 世界回应感知

## 目标
PM 计划 DLX-4：修复三个产品缺陷——trust 数值不可见（P0）、echo_seed 死内容、世界回应无地图载体。

## 初始现状
接手中断半成品：三个任务分别已提交（f9df0af 关系面板 / 47dc6d3 种子消费者 / cf4ac67 世界富集），缺 evidence 与 .uid 收尾。

## 实现摘要
1. **HUD 关系面板**（f9df0af）：RelationsPanel 显示洛弦/弥砂 trust/affection 数值条；政策门（<40）与共生门（<70）提示文案从事件数据 requires_trust 与 endings.json 读取（数据驱动，不再写死数值）。
2. **echo_seed 消费者**（47dc6d3）：echo_chamber inputs 增加种子（放置即消耗，BuildingRules 零代码生效）；时序裁决——种子经 event_leviathan_pact grant_items 战前授予（解死锁：Boss 在 station_mode 之后）+ Boss 掉落双渠道。
3. **世界回应感知**（cf4ac67）：chunk_data.generate 增 enriched 参数（矿脉种子 10→14，同 seed 同参数确定性）；world 按 snapshot 的 world_response_exploited flag 翻变触发重生成+delta 重放——"选择改变地图"最小可感载体。

## 测试证据（新鲜输出）
```
pwsh -NoProfile -File ./scripts/Run-Gut.ps1
Tests 604 / Passing 604（578 基线 + 26 新增）
```
新增：test_ui_relations.gd（12）、test_world_dlx4.gd、test_world_chunk_data.gd +4（enriched 确定性/超集/格界）、test_integration_dlx4.gd。

## 决策与限制
- 种子双渠道：pact 事件授予（时序解死锁）+ Boss 掉落（冗余）。
- enriched 重生成保留已破坏格 delta 重放；已破坏格不因富集复活。
- trust 门提示文案为数据驱动读取，新增门控自动出现（需数据侧补条目时才改）。

## 确切下一步
合并 main → DLX-5 世界布局外置 → DLX-6 存档内容政策 → 复审六场景走查。
