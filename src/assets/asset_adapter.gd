class_name AssetAdapter
extends RefCounted

## G6P-1 统一资产解析器（加载侧适配层）：G6 正式美术零代码 drop-in 的唯一入口。
##
## 职责边界（AGENTS.md / docs/art 合同）：
## - 资产落位 = docs/art 合同（environment-assets.md / battle-assets.md /
##   ui-assets.md / character-assets.md）；**未 approved 的资产不得提交到
##   assets/**——本层只负责“文件存在即加载、缺失即返回 null”，绝不生产、
##   不创建占位资产文件，也绝不改动资产内容。
## - 缺失资产一律返回 null（调用方回退现有灰盒）；本层不 push_error/warning，
##   汇总告警由调用方一次性自行发出。
##
## 探测顺序（先合同落位、后任务书平铺，两者都支持即“按合同放置即生效”）：
## - texture()：按资产 id 前缀分类（env_→world / ui_→ui / battle_→battle /
##   char_→characters），依次探测各分类的合同子目录，再退回分类平铺目录；
##   ui_item_<item_id>（HUD 物品图标，G6P-1 任务 4）额外优先探测 A7 §9 合同
##   命名 uia_ico_<item_id>[.png|_32.png]；
## - sprite_frames()：帧命名按 A8 §7.1 `<asset_id>_<state>_<NN>.png`（NN 两位
##   零填充、从 00 起）；battle_<unit_id> 优先探测 A8 §7.2 落位
##   battle/units/<unit_id>/（Boss 备选 phase1/），再退回分类平铺目录；
## - texture_at()：接受完整路径（res:// 走导入系统，导出包行为一致；非
##   res://（如 user:// 测试注入）走原生 PNG 读取）。

const DEFAULT_BASE_DIR: String = "res://assets/art"

## 资产 id 前缀 → 分类目录（G6P-1 任务书约定的映射表）。
const PREFIX_CATEGORIES: Dictionary = {
	"env_": "world",
	"ui_": "ui",
	"battle_": "battle",
	"char_": "characters",
}

## 各分类的合同子目录探测序（docs/art 三份合同的 §目录结构；命中即用）。
## 探测终项为分类平铺目录（任务书落位兜底）。
const CATEGORY_SUBDIRS: Dictionary = {
	"world": [
		"world/tiles",
		"world/buildings",
		"world/fx",
		"world/background",
		"world/decals",
		"world",
	],
	"ui": [
		"ui/icons",
		"ui/hud",
		"ui/inventory",
		"ui/buildbar",
		"ui/dialogue",
		"ui/panels",
		"ui/buttons",
		"ui/battle",
		"ui/title",
		"ui",
	],
	"battle": [
		"battle/units",
		"battle/banners",
		"battle/backgrounds",
		"battle/icons",
		"battle/fx",
		"battle",
	],
	"characters": [
		"characters",
		"units",
	],
}

## A8 §7.1 帧号格式：两位零填充、从 00 起。
const FRAME_NUMBER_FORMAT: String = "%02d"

## A8 §7.3 帧节奏契约（动画名 → {fps, loop}）；未列出的状态按 2 fps 循环兜底。
const STATE_ANIMATION_SPECS: Dictionary = {
	"idle": {"fps": 2.0, "loop": true},
	"attack": {"fps": 8.0, "loop": false},
	"hit": {"fps": 6.0, "loop": false},
	"death": {"fps": 6.0, "loop": false},
}

## 状态兜底节奏（STATE_ANIMATION_SPECS 未收录的状态名共用）。
const FALLBACK_FPS: float = 2.0
const FALLBACK_LOOP: bool = true


## 单图纹理解析：按 id 前缀分类逐候选探测；任一候选命中即返回；全缺失 → null。
## res:// 形态的 id 直接按完整路径处理（委托 texture_at）。
static func texture(asset_id: String, base_dir: String = DEFAULT_BASE_DIR) -> Texture2D:
	if asset_id.begins_with("res://"):
		return texture_at(asset_id)
	for path: String in _texture_candidates(asset_id, base_dir):
		var loaded := texture_at(path)
		if loaded != null:
			return loaded
	return null


## 完整路径纹理解析：res:// 走导入系统（编辑器与导出包一致；导入缓存缺失时
## 兜底从磁盘直读，导出包内原文件不在包里时自然失败 → null）；非 res:// 走
## 原生 PNG 读取（user:// 测试注入路径）。
static func texture_at(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if path.begins_with("res://"):
		if ResourceLoader.exists(path):
			var loaded := ResourceLoader.load(path) as Texture2D
			if loaded != null:
				return loaded
		if FileAccess.file_exists(path):
			var image := Image.load_from_file(path)
			if image != null:
				return ImageTexture.create_from_image(image)
		return null
	if not FileAccess.file_exists(path):
		return null
	var raw_image := Image.load_from_file(path)
	if raw_image == null:
		return null
	return ImageTexture.create_from_image(raw_image)


## 动画帧组解析：按 A8 §7.1 命名 `<stem>_<state>_<NN>.png` 组装 SpriteFrames；
## 任一帧缺失 → 整体返回 null（不产出半成品帧组，调用方回退灰盒）。
## states 与 frame_counts 必须一一对应且帧数 ≥ 1，否则返回 null。
static func sprite_frames(
		asset_id: String, states: Array, frame_counts: Dictionary,
		base_dir: String = DEFAULT_BASE_DIR) -> SpriteFrames:
	if asset_id.is_empty() or states.is_empty():
		return null
	for state_value: Variant in states:
		if typeof(state_value) != TYPE_STRING:
			return null
		var state := str(state_value)
		if not frame_counts.has(state):
			return null
		if int(frame_counts[state]) < 1:
			return null
	for candidate: Dictionary in _sprite_frame_candidates(asset_id, base_dir):
		var frames := _try_build_sprite_frames(
			str(candidate["dir"]), str(candidate["stem"]), states, frame_counts)
		if frames != null:
			return frames
	return null


## 目录存在性探测（res:// 与 user:// 通用），供调用方做批量降级判断。
static func probe(dir: String) -> bool:
	return DirAccess.dir_exists_absolute(dir)


# ---------------------------------------------------------------- 内部解析


## 单图候选路径序：合同子目录（命中即用）→ 分类平铺目录 → base_dir 平铺。
## ui_item_<item_id> 额外在最前追加 A7 §9 合同命名候选（uia_ico_<item_id> 及
## 其 _32 尺寸变体）。
static func _texture_candidates(asset_id: String, base_dir: String) -> PackedStringArray:
	var candidates := PackedStringArray()
	if asset_id.begins_with("ui_item_"):
		var item_id := asset_id.substr("ui_item_".length())
		candidates.append("%s/ui/icons/uia_ico_%s.png" % [base_dir, item_id])
		candidates.append("%s/ui/icons/uia_ico_%s_32.png" % [base_dir, item_id])
	var category := _category_of(asset_id)
	if category != "":
		for sub_dir: String in CATEGORY_SUBDIRS[category]:
			candidates.append("%s/%s/%s.png" % [base_dir, sub_dir, asset_id])
	candidates.append("%s/%s.png" % [base_dir, asset_id])
	return candidates


## 帧组候选（dir + 帧名 stem）：battle_<unit_id> 优先 A8 §7.2 落位
## units/<unit_id>/（Boss phase1/ 备选），其余分类退回平铺目录与 base_dir。
static func _sprite_frame_candidates(asset_id: String, base_dir: String) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	if asset_id.begins_with("battle_"):
		var unit_id := asset_id.substr("battle_".length())
		if unit_id != "":
			candidates.append({
				"dir": "%s/battle/units/%s" % [base_dir, unit_id],
				"stem": unit_id,
			})
			candidates.append({
				"dir": "%s/battle/units/%s/phase1" % [base_dir, unit_id],
				"stem": unit_id,
			})
	var category := _category_of(asset_id)
	if category != "":
		candidates.append({"dir": "%s/%s" % [base_dir, category], "stem": asset_id})
	candidates.append({"dir": base_dir, "stem": asset_id})
	return candidates


## 单一落位尝试：目录存在且该落位全部帧齐备 → 装配 SpriteFrames；否则 null。
static func _try_build_sprite_frames(
		dir_path: String, stem: String, states: Array, frame_counts: Dictionary) -> SpriteFrames:
	if not probe(dir_path):
		return null
	var textures_by_state: Dictionary = {}
	for state_value: Variant in states:
		var state := str(state_value)
		var count := int(frame_counts[state])
		var state_frames: Array[Texture2D] = []
		for frame_index: int in count:
			var frame_path := "%s/%s_%s_%s.png" % [
				dir_path, stem, state, FRAME_NUMBER_FORMAT % frame_index,
			]
			var frame_texture := texture_at(frame_path)
			if frame_texture == null:
				return null
			state_frames.append(frame_texture)
		textures_by_state[state] = state_frames
	var frames := SpriteFrames.new()
	if frames.has_animation("default"):
		frames.remove_animation("default")
	for state_value: Variant in states:
		var state := str(state_value)
		var spec: Dictionary = STATE_ANIMATION_SPECS.get(
			state, {"fps": FALLBACK_FPS, "loop": FALLBACK_LOOP})
		frames.add_animation(state)
		frames.set_animation_speed(state, float(spec["fps"]))
		frames.set_animation_loop(state, bool(spec["loop"]))
		for frame_texture: Texture2D in textures_by_state[state]:
			frames.add_frame(state, frame_texture)
	return frames


## 资产 id 前缀 → 分类目录名；未知前缀返回 ""（按 base_dir 平铺探测）。
static func _category_of(asset_id: String) -> String:
	for prefix: String in PREFIX_CATEGORIES:
		if asset_id.begins_with(prefix):
			return str(PREFIX_CATEGORIES[prefix])
	return ""
