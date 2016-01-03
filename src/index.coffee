request = require('xhr')
queue = require('./lib/queue')
_ = require('underscore')
app = require('ampersand-app')

module.exports = (spec) ->
  {couchdbUrl, couchServerUrl} = spec

  # asks for array of ids, unlimited in length
  # callbacks array of docs
  get = (args, cb) ->
    ids = args.ids

    getSearchUrl = (ids) -> "#{couchdbUrl}/_all_docs?keys=#{JSON.stringify ids}&include_docs=true&reduce=false"

    getDocs = (url, next) ->
      xhr = request {
        url: url
        headers: 'Content-Type': 'application/json'
      }, (err, resp, body) ->
        if body
          docs = JSON.parse(body).rows.map (item) -> item.doc
          next(null, docs)
        app.trigger 'xhr:removeFinished'
      app.trigger 'xhr:add', xhr

    console.time("startget")
    if _.isArray ids
      chunkSize = 100
      queries = _.chain(ids).groupBy((element, index) ->  Math.floor index / chunkSize).toArray().value().map (ids) -> getSearchUrl(ids)
      q = queue(5)
      app.on 'xhr:abortAll', =>
        console.log "aborting queue"
        q.abort()
      queries.forEach (url) ->  q.defer(getDocs, url)
      q.awaitAll (err, res) ->
        if res
          cb null, _.compact _.flatten(res)
    else cb {error: 'need array of ids and callback'}

  queryByUrl = (url, next) ->
    console.log "#{couchdbUrl}/#{url}"
    xhr = request "#{couchdbUrl}/#{url}", (err, res, body) ->
      if body
        json = JSON.parse(body)
        next(null, json)
      else next({error: "nothing found"})
      # clean up finished requests
      app.trigger 'xhr:removeFinished'
    app.trigger 'xhr:add', xhr

  # Rewrite this with xhr lib, and make get in view more general for typeahead and other queries
  # call query maybe and model after dexie.js or https://github.com/cloudant/mango
  saveAttachment = (args, cb) ->
    if args.id
      id = args.id
      file = args.file
      name = encodeURIComponent(args.name)
      type = file.type
      fileReader = new FileReader()

      head id, (err, _rev) ->
        if _rev
          putRequest = new XMLHttpRequest()
          putRequest.open "PUT", "#{couchdbUrl}/#{encodeURIComponent(id)}/" + name + "?rev=" + _rev, true
          putRequest.setRequestHeader "Content-Type", type
          fileReader.readAsArrayBuffer file
          fileReader.onload = (readerEvent) ->
            putRequest.send readerEvent.target.result
          putRequest.onreadystatechange = (response) ->
            cb(null, JSON.parse(putRequest.responseText))  if putRequest.readyState is 4
        else
          console.log err
          cb err

  upsert = (id, body, cb) ->
    # we take care of rev update, so any upsert will ALWAYS the doc even if there is the wrong rev
    delete body._rev
    @head id, (err, rev) ->
      if rev
        body._rev = rev

      request {
        url: "#{couchdbUrl}/#{id}"
        headers: 'Content-Type': 'application/json'
        body: JSON.stringify(body)
        method: 'PUT'
      }, (err, res) ->
        if err
          cb err
        else
          try
            val = JSON.parse(res.body)
          if val
            cb null, val
          else cb {error: 'status code'}

  create = (body, cb) ->
    request {
      url: couchdbUrl
      headers: 'Content-Type': 'application/json'
      body: JSON.stringify(body)
      method: 'POST'
    }, (err, res) ->
      if err
        cb err
      else
        try
          val = JSON.parse(res.body)
        if val
          cb null, val
        else cb {error: 'status code'}

  # gimme an id and i give you the _rev back
  head = (id, cb) ->
    request {
      url: "#{couchdbUrl}/#{id}"
      headers: 'Content-Type': 'application/json'
      method: 'HEAD'
    }, (err, res) ->
      console.log err, res
      if res.statusCode is 200
        cb null, JSON.parse(res.headers.etag)
      else
        cb {error: res.statusCode}


  # account methods
  isUserLoggedIn = (args, mainCallback) ->
    opts = { url: "#{couchdbUrl}/_security", headers: {"content-type": "application/json"}, withCredentials: true}
    request opts, (err, res, body) ->
      if res.statusCode isnt 200
        mainCallback(JSON.parse body)
      else
        mainCallback(null, JSON.parse body)


  login = (args, cb) ->
    unless args.username and args.password
      cb error: "Please supply username, password and couchdbUrl"
    else
      opts =
        url: "#{couchServerUrl}/_session"
        data: JSON.stringify {name: args.username, password: args.password}
        method: 'POST'
        withCredentials: true
        headers: {"content-type": "application/json"}
      request opts, (err, res, body) ->
        if err
          cb {error: err}
        if body
          authResult = JSON.parse body
          if authResult.error
            cb authResult
          else
            console.log "authResult", authResult
            cb null, authResult

  logout = (cb) ->
    request {
      url: "/_session"
      method: 'DELETE'
    }, (err, res) ->
      if res?.statusCode is 200
        cb null, {status: 'success'}
      else cb {status: 'fail'}

  # return all nice cool public methods
  return Object.freeze({
    head: head
    get: get
    queryByUrl: queryByUrl
    saveAttachment: saveAttachment
    login: login
    isUserLoggedIn: isUserLoggedIn
    logout: logout
    create: create
    upsert: upsert
    #remove: "remove"
    #removeAttachment: "remove"
  })
