# csv 表格工具
# 暂无 Options 支持
@tool
extends "table_tool.gd"

const CSV_DELIM = ","

var _last_parse_error: Error = ERR_PARSE_ERROR
var _header: _TableHeader
var _data: Array[Dictionary] = []


func _get_support_types() -> PackedByteArray:
	return [
		TYPE_BOOL,
		TYPE_INT,
		TYPE_FLOAT,
		TYPE_STRING,
		TYPE_STRING_NAME,
		TYPE_NODE_PATH,
		TYPE_ARRAY,
		TYPE_DICTIONARY,
		TYPE_PACKED_BYTE_ARRAY,
		TYPE_PACKED_INT32_ARRAY,
		TYPE_PACKED_INT64_ARRAY,
		TYPE_PACKED_FLOAT32_ARRAY,
		TYPE_PACKED_FLOAT64_ARRAY,
		TYPE_PACKED_STRING_ARRAY,
	]


func _get_parse_error() -> Error:
	return _last_parse_error


func _parse_table_file(csv_file: String, _options:PackedStringArray) -> Error:
	var fa = FileAccess.open(csv_file, FileAccess.READ)
	if not is_instance_valid(fa):
		_Log.error([tr("无法读取csv文件: "), csv_file, " - ", error_string(FileAccess.get_open_error())])
		_last_parse_error = FileAccess.get_open_error()
		return _last_parse_error

	_header = _TableHeader.new()
	var metas := fa.get_csv_line(CSV_DELIM)
	var descs := fa.get_csv_line(CSV_DELIM)
	var fields := fa.get_csv_line(CSV_DELIM)
	var types := fa.get_csv_line(CSV_DELIM)

	# 移除尾随空项（由其他软件产生）
	for i in range(metas.size()-1,-1,-1):
		if metas[i].is_empty():
			metas.remove_at(i)
		else:
			break
	
	for i in range(descs.size()-1,-1,-1):
		if descs[i].is_empty():
			descs.remove_at(i)
		else:
			break

	if metas.size() == 1 and metas[0] == "PlaceHolder Metas":
		metas.clear()
	if descs.size() == 1 and descs[0] == "PlaceHolder Descriptions":
		descs.clear()

	_header.metas = metas
	_header.descriptions = descs
	_header.fields = fields
	_header.types = types

	# 检查字段与类型是否匹配
	if fields.size() != types.size():
		_header = null
		_data.clear()
		_Log.error([tr("解析csv文件失败: "), csv_file, " - ", tr("请使用生成工具创建合法的表头。")])
		_last_parse_error = ERR_PARSE_ERROR
		return _last_parse_error

	# 检查字段名
	for f in fields:
		if not f.is_valid_identifier() and not is_meta_filed(f):
			_header = null
			_data.clear()
			_Log.error([tr("解析csv文件失败: "), csv_file, " - ", tr("非法标识符: "), f])
			_last_parse_error = ERR_PARSE_ERROR
			return _last_parse_error
	# 检查类型
	for t in types:
		if get_type_id(t) <= 0:
			_header = null
			_data.clear()
			_Log.error([tr("解析csv文件失败: "), csv_file, " - ", tr("不支持的类型: "), t])
			_last_parse_error = ERR_PARSE_ERROR
			return _last_parse_error

	_data.clear()
	# 读取数据行
	while not fa.eof_reached():
		var row := fa.get_csv_line(CSV_DELIM)
		if _is_empty_csv_row(row, fields.size()):
			# 跳过空行
			continue
		var row_data := {}
		for i in range(min(types.size(), row.size())):
			var type := get_type_id(types[i].strip_edges())
			var field := fields[i].strip_edges()
			if type < 0:
				_header = null
				_data.clear()
				_Log.error([tr("解析csv文件失败: "), csv_file])
				_last_parse_error = ERR_PARSE_ERROR
				return _last_parse_error

			var value := parse_value(row[i], type)

			if typeof(value) == TYPE_NIL:
				_header = null
				_data.clear()
				_Log.error([tr("解析csv文件失败: "), csv_file])
				_last_parse_error = ERR_PARSE_ERROR
				return _last_parse_error

			row_data[field] = value

		_data.push_back(row_data)

	return OK


func _get_table_file_extension() -> String:
	return "csv"


func _generate_table_file(save_path: String, header: _TableHeader, data_rows: Array[PackedStringArray], _options:PackedStringArray) -> Error:
	if not is_instance_valid(header):
		_Log.error([tr("生成表格失败: "), error_string(ERR_INVALID_PARAMETER)])
		return ERR_INVALID_PARAMETER

	# 生成用于跳过导入的.import
	var f = FileAccess.open(save_path + ".import", FileAccess.WRITE)
	if not is_instance_valid(f):
		_Log.error([tr("生成表格失败,无法生成:"), save_path + ".import", " - ", error_string(FileAccess.get_open_error())])
		return FAILED

	var engine_version := Engine.get_version_info()
	if engine_version.major >= 4 and engine_version.minor >= 3:
		# 4.3 之后使用skip
		f.store_string('[remap]\n\nimporter="skip"\n')
	else:
		# 4.3 之前使用keep
		f.store_string('[remap]\n\nimporter="keep"\n')

	f.close()

	var fa := FileAccess.open(save_path, FileAccess.WRITE)
	if not is_instance_valid(fa):
		_Log.error([tr("生成表格失败: "), error_string(FileAccess.get_open_error())])
		return FileAccess.get_open_error()

	# 确保非空行
	var metas = header.metas.duplicate()
	var descs = header.descriptions.duplicate()
	if metas.size() == 0:
		metas.push_back("PlaceHolder Metas")
	if descs.size() <= 0:
		descs.push_back("PlaceHolder Descriptions")
	fa.store_csv_line(metas, CSV_DELIM)
	fa.store_csv_line(descs, CSV_DELIM)
	fa.store_csv_line(header.fields, CSV_DELIM)
	fa.store_csv_line(header.types, CSV_DELIM)
	for row in data_rows:
		fa.store_csv_line(row, CSV_DELIM)
	fa.close()

	return OK


func _to_value_text(value: Variant) -> String:
	if not typeof(value) in get_support_types():
		_Log.error([tr("转换为文本失败,不支持的类型: "), value, " - ", type_string(typeof(value))])
		return ""
	# 不带两侧括号
	if typeof(value) in [TYPE_STRING, TYPE_NODE_PATH, TYPE_STRING_NAME]:
		return str(value)
	return JSON.stringify(value).trim_prefix("[").trim_suffix("]").trim_prefix("{").trim_suffix("}")


func _parse_value(text: String, type_id: int) -> Variant:
	if text.is_empty() and type_id in get_support_types():
		return type_convert(null, type_id)
	match type_id:
		TYPE_BOOL:
			return "t" in text.to_lower()
		TYPE_INT:
			return text.to_int()
		TYPE_FLOAT:
			return text.to_float()
		TYPE_STRING:
			return text
		TYPE_STRING_NAME:
			return StringName(text)
		TYPE_NODE_PATH:
			return NodePath(text)
		TYPE_ARRAY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			var value_text := text
			if not text.begins_with("[") and not text.ends_with("]"):
				value_text = "[%s]" % text
			var arr = JSON.parse_string(value_text)
			if typeof(arr) != TYPE_ARRAY:
				_Log.error([tr("非法值文本: "), text])
				return null
			return convert(arr, type_id)
		TYPE_DICTIONARY:
			var value_text := text
			if not text.begins_with("{") and not text.ends_with("}"):
				value_text = "{%s}" % text
			var arr = JSON.parse_string(value_text)
			if typeof(arr) != TYPE_DICTIONARY:
				_Log.error([tr("非法值文本: "), text])
				return null
			return convert(arr, type_id)

	_Log.error([tr("不支持的类型: "), type_string(type_id)])
	return null


func _get_header() -> _TableHeader:
	return _header


func _get_data() -> Array[Dictionary]:
	return _data


# --------------
func _is_empty_csv_row(row: PackedStringArray, fileds_count: int) -> bool:
	for i in range(min(row.size(), fileds_count)):
		if not row[i].strip_edges().is_empty():
			return false
	return true
