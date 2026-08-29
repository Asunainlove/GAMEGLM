class_name Endings
extends RefCounted

## WP15 三结局判定与文案纯逻辑（契约 docs/plans/contracts/module-contracts.md
## §5/§7）。evaluate 为纯函数：只读快照字典，任何缺失键按空值处理，不写入持久
## 状态。门控逐字取自 §7：station_mode_exploit → ending_mining；
## station_mode_seal → ending_seal；station_mode_symbiosis 且
## relationships.luoxian.trust ≥ 70 且 flags.echo_chamber_active == true →
## ending_symbiosis，否则回落 ending_seal；无任何 station_mode_* → ""（未定）。
## 多个 station_mode_* 同时置位时按 §7 罗列顺序取第一个（exploit 优先）。
## 结局总结为原创中文成稿，呼应产品契约核心假设：玩家的采集、建造与校准
## 改变了地图、Boss 条件与角色立场。

const ENDING_MINING: String = "ending_mining"
const ENDING_SEAL: String = "ending_seal"
const ENDING_SYMBIOSIS: String = "ending_symbiosis"

const STATION_MODE_EXPLOIT_FLAG: String = "station_mode_exploit"
const STATION_MODE_SEAL_FLAG: String = "station_mode_seal"
const STATION_MODE_SYMBIOSIS_FLAG: String = "station_mode_symbiosis"
const ECHO_CHAMBER_FLAG: String = "echo_chamber_active"

const SYMBIOSIS_CHAR_ID: String = "luoxian"
const SYMBIOSIS_DIM: String = "trust"
const SYMBIOSIS_TRUST_THRESHOLD: int = 70

const TITLE_MINING: String = "结局：开采纪元"
const TITLE_SEAL: String = "结局：封存之约"
const TITLE_SYMBIOSIS: String = "结局：共生曙光"

const SUMMARY_MINING: String = "你把锚居的节拍改成了开采的序曲：精炼器与织机彻夜运转，星壤尘沿着新修的输送道流进仓库，矿脉的低语被量具一格一格地翻译成产量。洛弦学会了用图纸倾听大地，弥砂把织机改成了输出定神雾的工位——她们都以自己的方式接受了这个决定。余辉没有被熄灭，只是从回应者变成了资源。"
const SUMMARY_SEAL: String = "你按下了封存的界线：开采停在图纸的第一页，锚块与稳定塔围出的不是矿区，而是一片留给矿脉的安静领地。洛弦重新听见了深处久违的回响，弥砂把织机留在星空之下——你们留在这里不是为了取走，而是为了等待下一个懂得轻声的人。余辉仍在，且只属于这片土地。"
const SUMMARY_SYMBIOSIS: String = "回响舱的灯光在最后一夜亮起，矿脉的低语第一次有了可以被听懂的形状。你的采集、建造与校准没有征服这片土地，而是替它和洛弦、弥砂搭起了一张彼此回应的网——足够的信任把封存的界线变成了共生的门槛。余辉纪元的黎明，由你们与琉砂海一起写下。"


## 按契约 §7 判定结局 id；结局未定返回 ""。
static func evaluate(state: Dictionary) -> String:
	if _flag_enabled(state, STATION_MODE_EXPLOIT_FLAG):
		return ENDING_MINING
	if _flag_enabled(state, STATION_MODE_SEAL_FLAG):
		return ENDING_SEAL
	if _flag_enabled(state, STATION_MODE_SYMBIOSIS_FLAG):
		if _symbiosis_conditions_met(state):
			return ENDING_SYMBIOSIS
		return ENDING_SEAL
	return ""


## 结局标题：三个已知结局逐字映射，其余（含空 id）返回 ""。
static func ending_title(id: String) -> String:
	match id:
		ENDING_MINING:
			return TITLE_MINING
		ENDING_SEAL:
			return TITLE_SEAL
		ENDING_SYMBIOSIS:
			return TITLE_SYMBIOSIS
		_:
			return ""


## 结局总结：三个已知结局返回原创中文成稿，其余（含空 id）返回 ""。
static func ending_summary(id: String) -> String:
	match id:
		ENDING_MINING:
			return SUMMARY_MINING
		ENDING_SEAL:
			return SUMMARY_SEAL
		ENDING_SYMBIOSIS:
			return SUMMARY_SYMBIOSIS
		_:
			return ""


# ---------------------------------------------------------------- 内部工具


static func _symbiosis_conditions_met(state: Dictionary) -> bool:
	if not _flag_enabled(state, ECHO_CHAMBER_FLAG):
		return false
	var relationships: Dictionary = state.get("relationships", {}) as Dictionary
	var record: Dictionary = relationships.get(SYMBIOSIS_CHAR_ID, {}) as Dictionary
	return int(record.get(SYMBIOSIS_DIM, 0)) >= SYMBIOSIS_TRUST_THRESHOLD


static func _flag_enabled(state: Dictionary, flag_id: String) -> bool:
	var flags: Dictionary = state.get("flags", {}) as Dictionary
	return bool(flags.get(flag_id, false))
