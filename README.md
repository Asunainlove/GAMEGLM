# 星壤：余辉纪元

Windows PC、离线单人、简体中文的 Godot 4 垂直切片。

探索采集 → 引导式建造锚居 → 世界与剧情变化 → 三场回合战斗 → 关系门控政策 → Boss 与三结局 → 保存重载。

产品范围见 [`docs/PROJECT_CHARTER.md`](docs/PROJECT_CHARTER.md)。引擎与验证命令见 [`docs/TOOLCHAIN.md`](docs/TOOLCHAIN.md)。

## 当前状态

代码、内容数据和自动门禁已完成锁定范围。仍开放：

- **G6** 美术/音频：方案 A 按合同生产并人工审批，或方案 B 授权灰盒交付
- **G7** 真人试玩、外部试玩与原创性终审

## 本地运行

需要 Godot `4.7.2-stable` Standard Win64（GL Compatibility）。未放入 PATH 时设置：

```powershell
$env:STARSOIL_GODOT_EXE = 'C:\path\to\Godot_v4.7.2-stable_win64_console.exe'
```

```powershell
pwsh -NoProfile -File .\scripts\Run-Gut.ps1
pwsh -NoProfile -File .\scripts\Verify-Toolchain.ps1
pwsh -NoProfile -File .\scripts\Verify-Slice.ps1
python scripts\validate_content.py
```

`Run-Gut.ps1` 只跑 `tests/unit/`。导出产物在 `build/`（不入库）。

## 仓库约定

- 仅 `ContentDB`、`GameState`、`SaveService` 三个 Autoload
- 玩法内容数据驱动，稳定 `snake_case` ID
- 第三方仅 GUT 9.7.1，见 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)

本仓库角色、文案、UI 与资产均为原创成年设定，不模仿既有商业作品。
