var _, app, equal, fs, param, queue, request,
  slice = [].slice,
  indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

request = require('xhr');

queue = require('./lib/queue');

_ = require('underscore');

app = require('ampersand-app');

param = require('jquery-param');

equal = require('deep-equal');

fs = require("fs");

module.exports = function(spec) {
  var couchdbServerUrl, couchdbUrl, createView, find, get, head, isUserLoggedIn, login, logout, queryByUrl, remove, saveAttachment, upsert;
  if (!(spec.dbName && spec.couchdbServerUrl)) {
    throw new Error("Please supply {couchdbServerUrl:\"http://localhost:5984\", dbName: \"databaseName\"} ");
    return;
  }
  couchdbServerUrl = spec.couchdbServerUrl;
  couchdbUrl = couchdbServerUrl + "/" + spec.dbName;
  get = function() {
    var cb, chunkSize, getDocs, getSearchUrl, i, ids, opts, q, queries;
    ids = arguments[0], opts = 3 <= arguments.length ? slice.call(arguments, 1, i = arguments.length - 1) : (i = 1, []), cb = arguments[i++];
    ids = _.isArray(ids) ? ids : [ids];
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
        var docs, error, retDocs;
        if (body) {
          try {
            docs = JSON.parse(body);
          } catch (error) {
            err = error;
          }
          if (docs.rows.length > 0 && indexOf.call(opts, "revs") >= 0) {
            retDocs = docs.rows.map(function(item) {
              if (item != null ? item.doc : void 0) {
                return {
                  _id: item.doc._id,
                  _rev: item.doc._rev
                };
              } else {
                return void 0;
              }
            });
            next(null, retDocs);
          } else if (docs.rows.length > 0) {
            retDocs = docs.rows.map(function(item) {
              return item.doc;
            });
            next(null, retDocs);
          } else {
            next(err);
          }
        }
        return app.trigger('xhr:removeFinished');
      });
      return app.trigger('xhr:add', xhr);
    };
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
    xhr = request(couchdbUrl + "/" + url, function(err, res, body) {
      var docs, json;
      if (body) {
        json = JSON.parse(body);
        docs = (json.rows.map(function(item) {
          return item.doc;
        })).filter(function(item) {
          return !item._id.match("^_design");
        });
        next(null, docs);
      } else {
        next({
          error: "nothing found"
        });
      }
      return app.trigger('xhr:removeFinished');
    });
    return app.trigger('xhr:add', xhr);
  };
  find = function(query, cb) {
    var url;
    if (_.isEmpty(query)) {
      url = "_all_docs?reduce=false&include_docs=true";
      return queryByUrl(url, function(err, res) {
        return cb(err, res);
      });
    } else {
      return cb("query not implemented");
    }
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
  upsert = function(docs, cb) {
    var ids;
    docs = _.isArray(docs) ? docs : [docs];
    ids = _.compact(_.pluck(docs, "_id"));
    return get(ids, function(err, docsInCouchdb) {
      var opts, uploadData;
      uploadData = (docsInCouchdb != null ? docsInCouchdb.length : void 0) > 0 ? _.compact(docs.map(function(newDoc) {
        var differentKeys, docInCouchdb, rev;
        docInCouchdb = _.findWhere(docsInCouchdb, {
          _id: newDoc._id
        });
        if (docInCouchdb && (rev = docInCouchdb._rev)) {
          delete docInCouchdb._rev;
          differentKeys = _.difference(Object.keys(newDoc), Object.keys(docInCouchdb));
          if (differentKeys.length > 0) {
            console.log("keys", Object.keys(newDoc).length, Object.keys(docInCouchdb).length, "different keys:", differentKeys);
          }
          if (equal(newDoc, docInCouchdb)) {
            return void 0;
          } else {
            console.log(newDoc._id, "is different", rev);
            newDoc._rev = rev;
            return newDoc;
          }
        } else {
          return newDoc;
        }
      })) : docs;
      opts = {
        url: couchdbUrl + "/_bulk_docs",
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          docs: uploadData
        }),
        method: 'POST'
      };
      return request(opts, function(err, res) {
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
  head = function(id, cb) {
    return request({
      url: couchdbUrl + "/" + id,
      headers: {
        'Content-Type': 'application/json'
      },
      method: 'HEAD'
    }, function(err, res) {
      if (res.statusCode === 200) {
        return cb(null, JSON.parse(res.headers.etag));
      } else {
        return cb({
          error: res.statusCode
        });
      }
    });
  };
  remove = function(id, cb) {
    return head(id, function(err, rev) {
      if (rev) {
        return request({
          url: couchdbUrl + "/" + id + "?rev=" + rev,
          headers: {
            'Content-Type': 'application/json'
          },
          method: 'DELETE'
        }, function(err, res) {
          if (res.statusCode === 200) {
            return cb(null, JSON.parse(res.headers.etag));
          } else {
            return cb({
              error: res.statusCode
            });
          }
        });
      } else {
        return cb(err);
      }
    });
  };
  isUserLoggedIn = function(cb) {
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
        return cb(JSON.parse(body));
      } else {
        return cb(null, JSON.parse(body));
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
        url: couchdbServerUrl + "/_session",
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
  createView = function(opts, cb) {
    var designViews, viewObj;
    if (opts != null ? opts.keys : void 0) {
      designViews = opts.keys.map(function(item) {
        var func, viewObj;
        viewObj = {
          "language": "coffeescript",
          views: {}
        };
        func = {
          map: "(doc) -> emit doc." + item + " if doc." + item,
          reduce: "_count"
        };
        viewObj.views[item] = func;
        viewObj._id = "_design/" + item;
        return viewObj;
      });
      return upsert(designViews, function(err, res) {
        return console.log(err, res);
      });
    } else if ((opts != null ? opts.map : void 0) && (opts != null ? opts.reduce : void 0)) {
      viewObj = {
        language: "coffeescript",
        views: {
          erster: {
            map: opts.map,
            reduce: opts.reduce,
            _id: "_design/" + zweoter
          }
        }
      };
      return upsert(viewObj, function(err, res) {
        return console.log(err, res);
      });
    }
  };
  return Object.freeze({
    get: get,
    upsert: upsert,
    find: find,
    queryByUrl: queryByUrl,
    saveAttachment: saveAttachment,
    login: login,
    logout: logout,
    isUserLoggedIn: isUserLoggedIn,
    createView: createView,
    head: head,
    remove: remove
  });
};

/*
//@ sourceMappingURL=index.map
*/
