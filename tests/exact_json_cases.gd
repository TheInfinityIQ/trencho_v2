extends RefCounted
const Reader = preload("res://kernel/authoritative_json.gd")
const Exporter = preload("res://kernel/run_exporter.gd")

static func run() -> Array:
	var checks: Array = []
	for integer in [0, 1, -1, 17, 1000000, 9007199254740990, 9007199254740991, -9007199254740991]:
		var parsed := Reader.parse(str(integer))
		checks.append({"name": "exact import integer " + str(integer), "passed": parsed.success and parsed.details.value is int and parsed.details.value == integer})
	for token in ["9007199254740992", "-9007199254740992", "999999999999999999999999999"]:
		var parsed := Reader.parse(token)
		checks.append({"name": "reject unsupported integer " + token, "passed": not parsed.success and parsed.error_code == "INTEGER_OUT_OF_EXACT_JSON_RANGE"})
	for token in ["0.1", "33.333", "1.25", "1e3", "1.5e2", "1.0e-4"]:
		var parsed := Reader.parse(token)
		checks.append({"name": "preserve fractional/exponent interpretation " + token, "passed": parsed.success and parsed.details.value is float and parsed.details.value == JSON.parse_string(token)})
	var nested := Reader.parse('{"value":"9007199254740991","a":[9007199254740991,{"b":-9007199254740991}],"flags":[true,false,null]}')
	checks.append({"name": "nested integer arrays objects and numeric string", "passed": nested.success and nested.details.value.value is String and nested.details.value.a[0] == 9007199254740991 and nested.details.value.a[1].b == -9007199254740991 and nested.details.value.flags == [true, false, null]})
	var escapes := Reader.parse('{"quote\\"9007199254740991":"backslash\\\\ digits 9007199254740991 \\u0031","unicode":"\\uD83D\\uDE00"}')
	checks.append({"name": "escaped quotes backslashes unicode and digits remain strings", "passed": escapes.success and escapes.details.value['quote"9007199254740991'] == "backslash\\ digits 9007199254740991 1" and escapes.details.value.unicode == "😀"})
	for malformed in ["", "01", "-", "1.", "1e", "1e+", "true false", "[1,]", '{"a":1,}', '{"a" 1}', "[1 2]", '"unterminated', '"bad\\q"', '"bad\\u12"', '"bad\\uD800"', '"bad\\uDC00"', "\"raw\nline\"", "{" ]:
		checks.append({"name": "malformed JSON rejected " + malformed, "passed": not Reader.parse(malformed).success})
	checks.append({"name": "excessive JSON nesting fails cleanly", "passed": not Reader.parse("[".repeat(130) + "0" + "]".repeat(130)).success})
	var payload := {"front": {"ammo_demand_accumulator_micro": 200000}, "coverage": {"milliseconds": 9007199254740991, "status": "FINITE"}}
	var written := Exporter.write_json("res://artifacts/exact_boundary.json", payload)
	var loaded := Exporter.read_json("res://artifacts/exact_boundary.json")
	checks.append({"name": "max finite coverage and front roundtrip through authoritative JSON file", "passed": written and loaded.success and Exporter.equivalent(payload, loaded.details.value)})
	written = Exporter.write_json("res://artifacts/exact_events.jsonl", [{"payload": payload}, {"value": -9007199254740991}], true)
	loaded = Exporter.read_lines("res://artifacts/exact_events.jsonl")
	checks.append({"name": "nested JSONL event payload exact signed integers", "passed": written and loaded.success and loaded.details.value[0].payload.coverage.milliseconds == 9007199254740991 and loaded.details.value[1].value == -9007199254740991})
	return checks
