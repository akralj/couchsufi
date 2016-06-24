doc = subkey = key = undefined


module.exports =
  "stats.all":
    map: """Object.keys(doc).forEach (key) ->
      if key is "termine" and doc[key]?.length > 0
        emit "termine-#{doc?[key].length}x"
        emit "termineAlsArray", doc[key]
      else if key is "meta"
        Object.keys(doc[key]).forEach (subkey) -> emit "#{key}.#{subkey}", doc[key][subkey]
      else if key is "location"
        Object.keys(doc[key]).forEach (subkey) -> emit "#{key}.#{subkey}", doc[key][subkey]
      else if doc[key] is "0" or doc[key] is "00:00"
        emit "wrong-#{key}", doc[key]
      else if doc[key]
        emit key, doc[key]"""
    reduce: "_count"