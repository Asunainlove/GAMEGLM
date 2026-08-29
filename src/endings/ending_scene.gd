class_name EndingScene
extends Node2D

## WP15 结局场景（契约 docs/plans/contracts/module-contracts.md §4）。表现层
## 节点只读快照、绝不写持久状态：快照经 snapshot_provider 注入，缺省（Callable()
## 无效时）取 GameState autoload 的 snapshot()。结局 id 由 Endings.evaluate
## 判定："" 显示 UNFINISHED_TITLE 并清空总结；否则显示对应标题与总结。
## show_ending 可重复调用以刷新显示。

const UNFINISHED_TITLE: String = "旅程尚未完结…"

var snapshot_provider: Callable = Callable()

@onready var _title_label: Label = $TitleLabel
@onready var _summary_label: Label = $SummaryLabel


func _ready() -> void:
	show_ending()


## 依据当前快照渲染结局标题与总结；结局未定（evaluate 返回 ""）时显示
## UNFINISHED_TITLE 且总结置空。
func show_ending() -> void:
	var ending_id: String = Endings.evaluate(_snapshot())
	if ending_id.is_empty():
		_title_label.text = UNFINISHED_TITLE
		_summary_label.text = ""
		return
	_title_label.text = Endings.ending_title(ending_id)
	_summary_label.text = Endings.ending_summary(ending_id)


## 优先使用注入的 snapshot_provider；provider 无效或返回值不是 Dictionary 时
## 回落 GameState.snapshot()，保证场景在无注入时也能工作。
func _snapshot() -> Dictionary:
	if snapshot_provider.is_valid():
		var provided: Variant = snapshot_provider.call()
		if provided is Dictionary:
			return provided
	return GameState.snapshot()
