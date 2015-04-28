FB = require 'fb'
Q = require 'q'
request = require 'request'
assert = require 'assert'
url = require 'url'
U = require('./util.coffee')

# Formats an API endpoint into a complete url with protocol and version
#
# @method formatURL
# @param {string} endpoint The api endpoint to format
# @return {string} The formatted endpoint with protocol and version
formatURL = (endpoint) ->
  assert typeof endpoint is 'string' or endpoint instanceof String

  if !endpoint.match(/^http/)           # test protocol
    if !endpoint.match(/^\/?v\d+\.\d+/) # test version
      if !endpoint.match(/^\//)         # test initial '/'
        endpoint = '/'+endpoint
      endpoint = '/v2.2'+endpoint
    endpoint = url.format
      protocol: 'https'
      hostname: 'graph.facebook.com'
      pathname: endpoint
  return endpoint

# Theoretically rate limits a promise returning function such that is never
# invoked more than once per `limit` milliseconds
#
# @method rateLimit
# @param {function} fn The promise returning function to throttle
# @param {number} limit Limit in milliseconds, default is 2500
# @return {function} A rate limited version of fn
rateLimit = (fn, limit = 2500) ->
  last = Date.now()
  servicingQueue = false
  queue = []
  coolingDown = false
  needsCoolDown = false
  cooldown = 2 * 60 * 1000

  serviceQueue = () ->
    if needsCoolDown and not coolingDown
      console.log 'Cooling down for', cooldown / 1000 / 60, 'minutes'
      afterCooldown = ->
        coolingDown = false
        needsCoolDown = false
        serviceQueue()
      setTimeout afterCooldown, cooldown
      coolingDown = true
      return null
    else if coolingDown
      return null

    if Date.now() - last > limit
      [d, args] = queue.shift()
      (fn args...).then (results...) ->
        if results[0].error and results[0].error.code is 613
          queue.unshift([d, args])
          needsCoolDown = true
          if servicingQueue isnt true then serviceQueue()
        else
          d.resolve results...
      last = Date.now()

    if queue.length > 0
      servicingQueue = true
      setTimeout serviceQueue, limit
    else
      servicingQueue = false

  return (args...) ->
    d = Q.defer()
    queue.push([d, args])
    if servicingQueue isnt true then serviceQueue()
    return d.promise

# Core function for hitting the FB API, wrapped with promises.
#
# @method api
# @param {string} path The endpoint to hit. Gets formatted with `formatURL`
# @param {string} method 'GET' or 'POST'
# @param {object} params Object of params that are set in the body for POST or
#                        appended to the query string for GET
# @param {function} callback Not used, listed for compatibility with FBs
#                            official JS client
# @return {Promise Array} The chunk of data
api = (path, method, params, callback) ->
  if !start then start = Date.now()
  d = Q.defer()
  options = { url: formatURL path, method: method, json: true }

  console.log (url.parse path).pathname

  if method.toLowerCase() is 'get' then options.qs = params
  if method.toLowerCase() is 'post' then options.body = params

  options.qs = {} unless options.qs?
  options.qs.limit = 30
  options.qs.since = '01/01/2008'

  request options, (error, _, res) ->
    if error
      throw JSON.stringify error, null, 2
      d.reject res

    res = JSON.parse(res)
    if res.error and res.error.code isnt 613
      throw JSON.stringify res.error, null, 2
      d.reject res
    else
      d.resolve res
  return d.promise

exports.api = rateLimit api, 2000

exports.getWithToken = (path, token) ->
  return exports.api path, 'get', {access_token: token}

# Recursively downloads paginated content at the given URL. It just keeps
# following the 'next' endpoint that is returned until there isn't one.
#
# @method downloadStream
# @param {String} nextURL The url to start streaming from
# @param {String} [token] The token to use for downloading. Optional becuase the
#                         'next' endpoint typically includes the token already.
# @return {Promise Array} The whole stream of data
exports.downloadStream = (nextURL, token) ->
  d = Q.defer()
  exports.api nextURL, 'get', {access_token: token}
    .then (chunk) ->
      if chunk.paging?.next?
        exports.downloadStream chunk.paging.next, token
          .then (rest) ->
            d.resolve chunk.data.concat rest
          .done()
      else
        d.resolve chunk.data
    .done()

  return d.promise

# Extract a next path if there is one from a chunk. Returns NULL if one doesn't
# exist.
#
# @method extractNextPath
# @param {Object} chunk The chunk to extract from
# @return {String|null} The next url or NULL if one doesn't make sense.
exports.extractNextPath = (chunk) ->
  # there is nothing next
  if chunk.data.length < 1 then return null

  # trust the precomputed next path if cursor-based pagination
  if chunk.paging.cursors? then return chunk.paging.next

  # tweak the until value if time-based pagination
  urlData = url.parse chunk.paging.next, true
  delete urlData.search
  urlData.query.until--
  return url.format urlData

# Reduce an API endpoint until there are no more items in it. Starts with memo,
# then calls cb with memo and the current chunk until it runs out.
#
# @method paginateStream
# @param {String} token The token to use
# @param {String} path The endpoint to reduce
# @param {Any} memo The item to use as initial memory
# @param {Function} cb The callback to invoke with memo and the current chunk
# @return {null} S s s side effects
exports.paginateStream = (token, path, memo, cb) ->
  exports.api path, 'get', {access_token: token, since: "01/01/2008"}
    .then (chunk) ->
      carry = cb memo, chunk
      if chunk.data.length > 0
        exports.paginateStream token, (exports.extractNextPath chunk), carry, cb
    .done()

  return null