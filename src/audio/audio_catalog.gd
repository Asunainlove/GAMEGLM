class_name AudioCatalog
extends RefCounted

## W003-A10 资产解析：id → res://assets/audio/{bgm|sfx}/<id>.ogg。
## 缺失 / 非 AudioStream 时返回 null（AudioDirector 侧告警并忽略，零崩溃）。

const BGM_PATH_FORMAT: String = "res://assets/audio/bgm/%s.ogg"
const SFX_PATH_FORMAT: String = "res://assets/audio/sfx/%s.ogg"


static func resolve_track(track_id: String) -> AudioStream:
	return _load_stream(BGM_PATH_FORMAT % track_id)


static func resolve_sfx(sfx_id: String) -> AudioStream:
	return _load_stream(SFX_PATH_FORMAT % sfx_id)


static func _load_stream(path: String) -> AudioStream:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var loaded: Variant = load(path)
	if loaded is AudioStream:
		return loaded as AudioStream
	return null
