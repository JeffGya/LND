extends Node

func _ready() -> void:
    var harness := DemoSimHarness.new()
    var baseline_runs: Array[String] = []
    for i in range(3):
        baseline_runs.append(harness.run_once(DemoSimHarness.DEFAULT_CAMPAIGN_SEED, i + 1))
    var reference := baseline_runs[0]
    for idx in range(baseline_runs.size()):
        assert(baseline_runs[idx] == reference, "Deterministic run mismatch at index %d" % idx)
    print("Determinism: PASS (3/3 identical)")

    var alternate_log := harness.run_once("0xCAFEBABE", 1)
    assert(alternate_log != reference, "Alternate campaign seed should diverge")
    print("Cross-seed divergence: PASS")
