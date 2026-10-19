extends RefCounted
# Authoritative artifact loader: integer tokens never pass through float.
# Decimal/exponent conversion and valid string decoding use Godot's existing JSON.
const R = preload("res://kernel/result.gd")
const MAX_INTEGER_TEXT = "9007199254740991"
var _text: String
var _cursor := 0
var _error := ""

static func parse(text: String) -> Dictionary:
	var reader := new()
	reader._text = text
	var value: Variant = reader._value(0)
	reader._space()
	if reader._error.is_empty() and reader._cursor != text.length():
		reader._error = "INVALID_JSON"
	if not reader._error.is_empty():
		return R.fail(reader._error, {"offset": reader._cursor})
	return R.ok(null, {"value": value})

func _space() -> void:
	while _cursor < _text.length() and _text[_cursor] in [" ", "\t", "\r", "\n"]:
		_cursor += 1

func _take(character: String) -> bool:
	if _cursor < _text.length() and _text[_cursor] == character:
		_cursor += 1
		return true
	return false

func _invalid() -> Variant:
	if _error.is_empty():
		_error = "INVALID_JSON"
	return null

func _value(depth: int) -> Variant:
	_space()
	if depth > 128 or _cursor >= _text.length():
		return _invalid()
	match _text[_cursor]:
		"{":
			return _object(depth + 1)
		"[":
			return _array(depth + 1)
		"\"":
			return _string()
	for pair in [["true", true], ["false", false], ["null", null]]:
		if _text.substr(_cursor, pair[0].length()) == pair[0]:
			_cursor += pair[0].length()
			return pair[1]
	return _number()

func _object(depth: int) -> Variant:
	_cursor += 1
	var result: Dictionary = {}
	_space()
	if _take("}"):
		return result
	while _error.is_empty():
		_space()
		if _cursor >= _text.length() or _text[_cursor] != "\"":
			return _invalid()
		var key: Variant = _string()
		_space()
		if not _take(":"):
			return _invalid()
		var value: Variant = _value(depth)
		if not _error.is_empty():
			return null
		result[key] = value
		_space()
		if _take("}"):
			return result
		if not _take(","):
			return _invalid()
	return null

func _array(depth: int) -> Variant:
	_cursor += 1
	var result: Array = []
	_space()
	if _take("]"):
		return result
	while _error.is_empty():
		result.append(_value(depth))
		if not _error.is_empty():
			return null
		_space()
		if _take("]"):
			return result
		if not _take(","):
			return _invalid()
	return null

func _hex4() -> int:
	if _cursor + 4 > _text.length():
		_invalid()
		return -1
	var token := _text.substr(_cursor, 4)
	for character in token:
		if not character in "0123456789abcdefABCDEF":
			_invalid()
			return -1
	_cursor += 4
	return token.hex_to_int()

func _string() -> Variant:
	var start := _cursor
	_cursor += 1
	while _cursor < _text.length():
		var character := _text[_cursor]
		_cursor += 1
		if character == "\"":
			var parser := JSON.new()
			if parser.parse(_text.substr(start, _cursor - start)) != OK:
				return _invalid()
			return parser.data
		if character.unicode_at(0) < 32:
			return _invalid()
		if character == "\\":
			if _cursor >= _text.length():
				return _invalid()
			var escaped := _text[_cursor]
			_cursor += 1
			if escaped == "u":
				var code := _hex4()
				if code < 0:
					return null
				if code >= 0xd800 and code <= 0xdbff:
					if not _take("\\") or not _take("u"):
						return _invalid()
					var low := _hex4()
					if low < 0xdc00 or low > 0xdfff:
						return _invalid()
				elif code >= 0xdc00 and code <= 0xdfff:
					return _invalid()
			elif not escaped in ["\"", "\\", "/", "b", "f", "n", "r", "t"]:
				return _invalid()
	return _invalid()

func _digit() -> bool:
	return _cursor < _text.length() and _text[_cursor] in "0123456789"

func _number() -> Variant:
	var start := _cursor
	_take("-")
	if not _take("0"):
		if not _digit() or _text[_cursor] == "0":
			return _invalid()
		while _digit():
			_cursor += 1
	var integer := true
	if _take("."):
		integer = false
		if not _digit():
			return _invalid()
		while _digit():
			_cursor += 1
	if _take("e") or _take("E"):
		integer = false
		if not _take("+"):
			_take("-")
		if not _digit():
			return _invalid()
		while _digit():
			_cursor += 1
	var token := _text.substr(start, _cursor - start)
	if integer:
		var magnitude := token.trim_prefix("-")
		if magnitude.length() > MAX_INTEGER_TEXT.length() or (magnitude.length() == MAX_INTEGER_TEXT.length() and magnitude > MAX_INTEGER_TEXT):
			_error = "INTEGER_OUT_OF_EXACT_JSON_RANGE"
			return null
		return token.to_int()
	var parser := JSON.new()
	if parser.parse(token) != OK:
		return _invalid()
	return parser.data
