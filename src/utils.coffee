module.exports =
  format_child_data: (child_name, type, output) ->
    output = output.toString().replace /(\n|\r)+$/, ''
    "#{child_name} (#{type}): #{output}"
