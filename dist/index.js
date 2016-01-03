var _, app, queue, request;

request = require('xhr');

queue = require('./lib/queue');

_ = require('underscore');

app = require('ampersand-app');

module.exports = function(spec) {
  var couchServerUrl, couchdbUrl, create, get, head, isUserLoggedIn, login, logout, queryByUrl, saveAttachment, upsert;
  couchdbUrl = spec.couchdbUrl, couchServerUrl = spec.couchServerUrl;
  get = function(args, cb) {
    var chunkSize, getDocs, getSearchUrl, ids, q, queries;
    ids = args.ids;
    getSearchUrl = function(ids) {
      return couchdbUrl + "/_all_docs?keys=" + (JSON.stringify(ids)) + "&include_docs=true&reduce=false";
    };
    getDocs = function(url, next) {
      var xhr;
      xhr = request({
        url: url,
        headers: {
          'Content-Type': 'application/json'
        }
      }, function(err, resp, body) {
        var docs;
        if (body) {
          docs = JSON.parse(body).rows.map(function(item) {
            return item.doc;
          });
          next(null, docs);
        }
        return app.trigger('xhr:removeFinished');
      });
      return app.trigger('xhr:add', xhr);
    };
    console.time("startget");
    if (_.isArray(ids)) {
      chunkSize = 100;
      queries = _.chain(ids).groupBy(function(element, index) {
        return Math.floor(index / chunkSize);
      }).toArray().value().map(function(ids) {
        return getSearchUrl(ids);
      });
      q = queue(5);
      app.on('xhr:abortAll', (function(_this) {
        return function() {
          console.log("aborting queue");
          return q.abort();
        };
      })(this));
      queries.forEach(function(url) {
        return q.defer(getDocs, url);
      });
      return q.awaitAll(function(err, res) {
        if (res) {
          return cb(null, _.compact(_.flatten(res)));
        }
      });
    } else {
      return cb({
        error: 'need array of ids and callback'
      });
    }
  };
  queryByUrl = function(url, next) {
    var xhr;
    console.log(couchdbUrl + "/" + url);
    xhr = request(couchdbUrl + "/" + url, function(err, res, body) {
      var json;
      if (body) {
        json = JSON.parse(body);
        next(null, json);
      } else {
        next({
          error: "nothing found"
        });
      }
      return app.trigger('xhr:removeFinished');
    });
    return app.trigger('xhr:add', xhr);
  };
  saveAttachment = function(args, cb) {
    var file, fileReader, id, name, type;
    if (args.id) {
      id = args.id;
      file = args.file;
      name = encodeURIComponent(args.name);
      type = file.type;
      fileReader = new FileReader();
      return head(id, function(err, _rev) {
        var putRequest;
        if (_rev) {
          putRequest = new XMLHttpRequest();
          putRequest.open("PUT", (couchdbUrl + "/" + (encodeURIComponent(id)) + "/") + name + "?rev=" + _rev, true);
          putRequest.setRequestHeader("Content-Type", type);
          fileReader.readAsArrayBuffer(file);
          fileReader.onload = function(readerEvent) {
            return putRequest.send(readerEvent.target.result);
          };
          return putRequest.onreadystatechange = function(response) {
            if (putRequest.readyState === 4) {
              return cb(null, JSON.parse(putRequest.responseText));
            }
          };
        } else {
          console.log(err);
          return cb(err);
        }
      });
    }
  };
  upsert = function(id, body, cb) {
    delete body._rev;
    return this.head(id, function(err, rev) {
      if (rev) {
        body._rev = rev;
      }
      return request({
        url: couchdbUrl + "/" + id,
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(body),
        method: 'PUT'
      }, function(err, res) {
        var val;
        if (err) {
          return cb(err);
        } else {
          try {
            val = JSON.parse(res.body);
          } catch (undefined) {}
          if (val) {
            return cb(null, val);
          } else {
            return cb({
              error: 'status code'
            });
          }
        }
      });
    });
  };
  create = function(body, cb) {
    return request({
      url: couchdbUrl,
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(body),
      method: 'POST'
    }, function(err, res) {
      var val;
      if (err) {
        return cb(err);
      } else {
        try {
          val = JSON.parse(res.body);
        } catch (undefined) {}
        if (val) {
          return cb(null, val);
        } else {
          return cb({
            error: 'status code'
          });
        }
      }
    });
  };
  head = function(id, cb) {
    return request({
      url: couchdbUrl + "/" + id,
      headers: {
        'Content-Type': 'application/json'
      },
      method: 'HEAD'
    }, function(err, res) {
      console.log(err, res);
      if (res.statusCode === 200) {
        return cb(null, JSON.parse(res.headers.etag));
      } else {
        return cb({
          error: res.statusCode
        });
      }
    });
  };
  isUserLoggedIn = function(args, mainCallback) {
    var opts;
    opts = {
      url: couchdbUrl + "/_security",
      headers: {
        "content-type": "application/json"
      },
      withCredentials: true
    };
    return request(opts, function(err, res, body) {
      if (res.statusCode !== 200) {
        return mainCallback(JSON.parse(body));
      } else {
        return mainCallback(null, JSON.parse(body));
      }
    });
  };
  login = function(args, cb) {
    var opts;
    if (!(args.username && args.password)) {
      return cb({
        error: "Please supply username, password and couchdbUrl"
      });
    } else {
      opts = {
        url: couchServerUrl + "/_session",
        data: JSON.stringify({
          name: args.username,
          password: args.password
        }),
        method: 'POST',
        withCredentials: true,
        headers: {
          "content-type": "application/json"
        }
      };
      return request(opts, function(err, res, body) {
        var authResult;
        if (err) {
          cb({
            error: err
          });
        }
        if (body) {
          authResult = JSON.parse(body);
          if (authResult.error) {
            return cb(authResult);
          } else {
            console.log("authResult", authResult);
            return cb(null, authResult);
          }
        }
      });
    }
  };
  logout = function(cb) {
    return request({
      url: "/_session",
      method: 'DELETE'
    }, function(err, res) {
      if ((res != null ? res.statusCode : void 0) === 200) {
        return cb(null, {
          status: 'success'
        });
      } else {
        return cb({
          status: 'fail'
        });
      }
    });
  };
  return Object.freeze({
    head: head,
    get: get,
    queryByUrl: queryByUrl,
    saveAttachment: saveAttachment,
    login: login,
    isUserLoggedIn: isUserLoggedIn,
    logout: logout,
    create: create,
    upsert: upsert
  });
};

/*
//@ sourceMappingURL=index.map
*/
