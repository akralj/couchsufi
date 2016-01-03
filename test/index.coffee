# works in browser but not on console, does phantom not like cookies
# delete cookies after seesion in browser
prova = require('prova')
couchdbUtils = require('../dist/index')

couchServerUrl = "http://localhost:5984"
couchdbUrl = "#{couchServerUrl}/kunstgut-dev"
couchdb = couchdbUtils({couchServerUrl: couchServerUrl, couchdbUrl: couchdbUrl})

prova 'query', (test) ->
  test.plan 2
  couchdb.head '100016', (err, rev) ->
    test.equals  rev, '1-040630ff1bbeac138f911876d15c9943'
  couchdb.getByIds ['100016', '100096'], (err, res) ->
    console.log err, res
    test.equals res.length, 2

prova 'login failures', (test) ->
  test.plan 3
  couchdb.isUserLoggedIn {couchdbUrl: couchdbUrl}, (err, res) ->
    test.notOk res?.name, "get user name"
  couchdb.login {username: "a"}, (err, res) ->
    test.ok err?.error, "not sufficient login data"
  couchdb.login {username: 'a', password:'wrongPassword', couchdbUrl: couchServerUrl}, (err, res) ->
    console.log res, err
    test.ok err?.error,  "wrong login data"

# XXX test has to run last because httpOnly cookie will be set
prova 'login success', (test) ->
  test.plan 2
  couchdb.login {username: 'a', password:'a', couchdbUrl: couchServerUrl}, (err, res) ->
    test.ok res?.ok, "correct login data"
    # needs extra time before cookie is set
    setTimeout (=>
      couchdb.isUserLoggedIn {couchdbUrl: couchdbUrl}, (err ) =>
        test.equal res.roles.length, 3, "correct roles"
    ), 333

