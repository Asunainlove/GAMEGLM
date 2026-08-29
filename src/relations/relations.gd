class_name Relations
extends RefCounted

## WP09 关系与立场纯逻辑（契约 docs/plans/contracts/module-contracts.md §0/§5/§7）。
## get_dim/trust/policy_unlocked 为纯函数，只读快照字典，任何缺失返回 0/false。
## change 构造并提交**单个** set_relationship patch：数值钳制 0..100，
## 非法角色/维度在构造 patch 之前干净失败（零修改、不触碰 store）。
## source_id = relations_<reason>_<revision>（稳定 snake_case），同 reason+revision
## 重放经 GameState 的 applied_patch_sources 幂等返回 already_applied。
## store 注入模式按契约 §0：store 为 null 时使用 GameState autoload；
## 注入替身与真实 StatePatch 共用未类型化（Variant）鸭子调用路径。

const MIN_SCORE: int = 0
const MAX_SCORE: int = 100
const VALID_CHARACTERS: Array[String] = ["luoxian", "misa"]
const VALID_DIMENSIONS: Array[String] = ["affection", "trust", "ideology"]
const POLICY_SANCTUARY: String = "policy_sanctuary"
const SANCTUARY_TRUST_THRESHOLD: int = 40


static func get_dim(state: Dictionary, char_id: String, dim: String) -> int:
	var relationships: Dictionary = state.get("relationships", {})
	var record: Dictionary = relationships.get(char_id, {})
	return int(record.get(dim, 0))


static func change(
		state: Dictionary,
		char_id: String,
		dim: String,
		delta: int,
		reason: String,
		store: Object = null
) -> AppResult:
	if not VALID_CHARACTERS.has(char_id):
		return AppResult.failure(
			"invalid_character",
			"Relationship changes are limited to luoxian and misa, got %s." % char_id
		)
	if not VALID_DIMENSIONS.has(dim):
		return AppResult.failure(
			"invalid_dim",
			"Relationship dimension must be affection, trust, or ideology, got %s." % dim
		)

	var revision: int = int(state.get("revision", 0))
	var target: int = clampi(get_dim(state, char_id, dim) + delta, MIN_SCORE, MAX_SCORE)
	var patch: Variant = _begin_patch(
		store, "relations_%s_%d" % [reason, revision], revision)
	patch.set_relationship(char_id, dim, target)
	return _commit(store, patch)


static func policy_unlocked(state: Dictionary, policy_id: String) -> bool:
	if policy_id != POLICY_SANCTUARY:
		return false
	return get_dim(state, "luoxian", "trust") >= SANCTUARY_TRUST_THRESHOLD


static func trust(state: Dictionary, char_id: String) -> int:
	return get_dim(state, char_id, "trust")


## 契约 §0 注入模式：patch 经未类型化变量（Variant）走鸭子调用，
## 以便 DuckPatch 测试替身与真实 StatePatch 共用同一提交路径。
static func _begin_patch(store: Object, source_id: String, expected_revision: int) -> Variant:
	if store == null:
		return GameState.begin_patch(source_id, expected_revision)
	return store.begin_patch(source_id, expected_revision)


static func _commit(store: Object, patch: Variant) -> AppResult:
	if store == null:
		return GameState.commit(patch)
	return store.commit(patch)
