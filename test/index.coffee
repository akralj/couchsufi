# works in browser but not on console, does phantom not like cookies
# delete cookies after seesion in browser
prova = require('prova')
_ = require("underscore")
couchdbUtils = require('../dist/index')

couchdbServerUrl = "http://devi:5984"
dbName = "couchsufi-test"
couchdb = couchdbUtils({couchdbServerUrl: couchdbServerUrl, dbName: dbName})

###
prova 'query', (test) ->
  test.plan 2
  couchdb.head '100016', (err, rev) ->
    test.equals  rev, '1-967a00dff5e02add41819138abb3284d'
  couchdb.get ['100016', '100096'], (err, res) ->
    test.equals res.length, 2

prova 'upsert', (test) ->
  test.plan 1
  sameDoc = require("./fixtures/upsertSameDocTest")
  newDoc = (JSON.parse(JSON.stringify(sameDoc)))
  newDoc._id = "newDoc09"
  couchdb.upsert newDoc, (err,res) ->
    console.log err,res
    test.equals (_.isArray(res) and res?.length is 1), true
###

prova 'design docs', (test) ->
  test.plan 1
  console.log views = require("./fixtures/views")
  couchdb.createView {keys: ["name", "country"]}, (err, res) ->
    console.log err, res
  test.equals 1,1
###
  couchdb.upsert sameDoc, (err,res) ->
    test.equals (_.isArray(res) and res.length is 0), true
  notSameDoc = (JSON.parse(JSON.stringify(sameDoc)))
  notSameDoc.datePublished = 1999
  couchdb.upsert notSameDoc, (err,res) ->
    test.equals (_.isArray(res) and res.length is 1), true


prova 'login failures', (test) ->
  test.plan 3
  couchdb.isUserLoggedIn {couchdbUrl: couchdbUrl}, (err, res) ->
    test.notOk res?.name, "get user name"
  couchdb.login {username: "a"}, (err, res) ->
    test.ok err?.error, "not sufficient login data"
  couchdb.login {username: 'a', password:'wrongPassword', couchdbUrl: couchdbServerUrl}, (err, res) ->
    console.log res, err
    test.ok err?.error,  "wrong login data"

# XXX test has to run last because httpOnly cookie will be set
prova 'login success', (test) ->
  test.plan 2
  couchdb.login {username: 'a', password:'a', couchdbUrl: couchdbServerUrl}, (err, res) ->
    test.ok res?.ok, "correct login data"
    # needs extra time before cookie is set
    setTimeout (=>
      couchdb.isUserLoggedIn {couchdbUrl: couchdbUrl}, (err ) =>
        test.equal res.roles.length, 3, "correct roles"
    ), 333

###