request = require('xhr')
d3 = require('d3-queue')
_ = require('underscore')
app = require('ampersand-app')
param = require('jquery-param')
equal = require('deep-equal') # deep object equal
# debugging
fs = require("fs")

module.exports = (spec) ->
  unless spec.dbName and spec.couchdbServerUrl
    throw new Error("""Please supply {couchdbServerUrl:"http://localhost:5984", dbName: "databaseName"} """)
    return
  couchdbServerUrl = spec.couchdbServerUrl
  couchdbUrl       = "#{couchdbServerUrl}/#{spec.dbName}"

  # asks for array of ids, unlimited in length
  # opts: "revs" -> return only _id and _rev
  # callbacks array of docs
  get = (ids, opts..., cb) ->
    ids = if _.isArray(ids) then ids else [ids]

    getSearchUrl = (ids) -> "#{couchdbUrl}/_all_docs?keys=#{JSON.stringify ids}&include_docs=true&reduce=false"

    getDocs = (url, next) ->
      xhr = request {
        url: url
        headers: 'Content-Type': 'application/json'
      }, (err, resp, body) ->
        if body
          try docs = JSON.parse(body)
          catch err
          if docs.rows.length > 0 and "revs" in opts
            retDocs = docs.rows.map (item) ->
              if item?.doc
                {_id: item.doc._id, _rev: item.doc._rev}
              else undefined
            next(null, retDocs)
          else if docs.rows.length > 0
            retDocs = docs.rows.map (item) -> item.doc
            next(null, retDocs)
          else next err
        app.trigger 'xhr:removeFinished'
      app.trigger 'xhr:add', xhr

    #console.time("startget")
    if _.isArray ids
      chunkSize = 100
      queries = _.chain(ids).groupBy((element, index) ->  Math.floor index / chunkSize).toArray().value().map (ids) -> getSearchUrl(ids)
      q = d3.queue(5)
      app.on 'xhr:abortAll', =>
        console.log "aborting queue"
        q.abort()
      queries.forEach (url) ->  q.defer(getDocs, url)
      q.awaitAll (err, res) ->
        if res
          #console.timeEnd("startget")
          cb null, _.compact(_.flatten(res))
    else cb {error: 'need array of ids and callback'}

  queryByUrl = (url, next) ->
    #console.log "#{couchdbUrl}/#{url}"
    xhr = request "#{couchdbUrl}/#{url}", (err, res, body) ->
      if body
        json = JSON.parse(body)
        # parse and return everthing apart of _design docs
        docs = (json.rows.map (item) -> item.doc).filter (item) -> not item._id.match("^_design")
        next(null, docs)
      else next({error: "nothing found"})
      # clean up finished requests
      app.trigger 'xhr:removeFinished'
    app.trigger 'xhr:add', xhr

  find = (query, cb) ->
    #console.log "query", query, param(query)
    if _.isEmpty(query)
      url = "_all_docs?reduce=false&include_docs=true"
      queryByUrl url, (err, res) -> cb err, res
    else cb "query not implemented"


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

  upsert = (docs, cb) ->
    # we take care of rev update, so any upsert will ALWAYS the doc even if there is the wrong rev
    docs = if _.isArray(docs) then docs else [docs]
    # get revs of already available docs
    ids = _.compact(_.pluck(docs, "_id"))
    get ids, (err, docsInCouchdb) ->
      uploadData =
        if docsInCouchdb?.length > 0
          _.compact docs.map (newDoc) ->
            docInCouchdb = _.findWhere(docsInCouchdb, _id: newDoc._id)
            # 1. update case
            if docInCouchdb and rev = docInCouchdb._rev
              delete docInCouchdb._rev
              #fs.writeFileSync "./debug.json", JSON.stringify({newDoc: newDoc, docInCouchdb: docInCouchdb}, "utf8")
              differentKeys = _.difference(Object.keys(newDoc), Object.keys(docInCouchdb))
              if differentKeys.length > 0
                console.log "keys", Object.keys(newDoc).length, Object.keys(docInCouchdb).length , "different keys:", differentKeys
              if equal(newDoc, docInCouchdb)
                #console.log "same doc", newDoc._id
                undefined
              else
                #console.log newDoc._id, "is different", rev
                newDoc._rev = rev
                newDoc
            else
              newDoc
        else docs

      opts =
        url: "#{couchdbUrl}/_bulk_docs"
        headers: 'Content-Type': 'application/json'
        body: JSON.stringify({docs: uploadData})
        method: 'POST'

      request opts, (err, res) ->
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
      if res.statusCode is 200
        cb null, JSON.parse(res.headers.etag)
      else
        cb {error: res.statusCode}

  # TODO: decide if it makes sense to keep the whole doc by GETing doc and PUTing _deleted into the doc
  remove = (id, cb) ->
    head id, (err, rev) ->
      if rev
        request {
          url: "#{couchdbUrl}/#{id}?rev=#{rev}"
          headers: 'Content-Type': 'application/json'
          method: 'DELETE'
        }, (err, res) ->
          if res.statusCode is 200
            cb null, JSON.parse(res.headers.etag)
          else
            cb {error: res.statusCode}
      else cb err

  # account methods
  isUserLoggedIn = (cb) ->
    opts = { url: "#{couchdbUrl}/_security", headers: {"content-type": "application/json"}, withCredentials: true}
    request opts, (err, res, body) ->
      if res.statusCode isnt 200
        cb(JSON.parse body)
      else
        cb(null, JSON.parse body)


  login = (args, cb) ->
    unless args.username and args.password
      cb error: "Please supply username, password and couchdbUrl"
    else
      opts =
        url: "#{couchdbServerUrl}/_session"
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

  # gimme keys, i give you a standdard view
  createView = (opts, cb) ->
    if opts?.keys
      designViews = opts.keys.map (item) ->
        viewObj = "language": "coffeescript", views: {}
        func = map: "(doc) -> emit doc.#{item} if doc.#{item}", reduce: "_count"
        viewObj.views[item] = func
        viewObj._id = "_design/#{item}"
        viewObj
      upsert designViews, (err, res) -> console.log err, res
    else if opts?.map and opts?.reduce
      viewObj =
        language: "coffeescript"
        views:
          erster:
            map: opts.map
            reduce: opts.reduce
            _id: "_design/#{zweoter}"
      upsert viewObj, (err, res) -> console.log err, res



  # return all nice cool public methods
  return Object.freeze({
    get: get
    upsert: upsert
    # remove: remove
    find: find
    queryByUrl: queryByUrl
    saveAttachment: saveAttachment
    login: login
    logout: logout
    isUserLoggedIn: isUserLoggedIn
    createView: createView
    head: head
    remove: remove
    #removeAttachment: "remove"
  })
