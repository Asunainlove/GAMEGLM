extends GutTest


func test_intentional_failure_proves_nonzero_exit() -> void:
	fail_test("Intentional fixture: this suite must return a non-zero exit code.")
