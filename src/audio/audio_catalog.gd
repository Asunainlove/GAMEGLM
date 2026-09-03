class_name AudioCatalog
extends RefCounted

## G6 batch4 接线：把 track_id / sfx_id 解析到 `res://assets/audio/**/*.ogg`。
## AudioDirector 经 Callable 注入；缺文件返回 null（Director 告警并忽略）。

const BGM_DIR: String = "res://assets/audio/bgm"
const SFX_DIR: String = "res://assets/audio/sfx"


static func resolve_track(track_id: String) -> AudioStream:
	if track_id.is_empty():
		return null
	return _load_stream(BGM_DIR.path_join("%s.ogg" % track_id))


static func resolve_sfx(sfx_id: String) -> AudioStream:
	if sfx_id.is_empty():
		return null
	return _load_stream(SFX_DIR.path_join("%s.ogg" % sfx_id))


static func _load_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var loaded: Variant = load(path)
	if loaded is AudioStream:
		return loaded as AudioStream
	return null
