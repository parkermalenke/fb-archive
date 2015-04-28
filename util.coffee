Q = require 'q'
assert = require 'assert'
fs = require 'fs'


exports.curry = (f, curriedArgs...) ->
  return (newArgs...) -> f(curriedArgs..., newArgs...)

# Organizes the posts from a chunk into an object by year then by month. Prefers
# the `created_time` key but will use `updated_time` as a fallback.
#
# @method chronologizeChunk
# @param {object} chronoTree The structure to organize posts into
# @param {object} chunk The chunk to organize
# @param {boolean} [rev] Whether the chunk is in reverse order, default = false
# @return {object} The object of chronologically organized posts
exports.chronologizeChunk = (chronoTree, chunk, rev = false) ->
  reducer = (memo, post) ->
    date = new Date(post.created_time or post.updated_time)
    year = date.getUTCFullYear()
    month = date.getUTCMonth()

    if not memo[year] then memo[year] = {}
    if not memo[year][month] then memo[year][month] = []

    memo[year][month].push post
    return memo

  if rev
    return chunk.data.reverse().reduce reducer, chronoTree
  else
    return chunk.data.reduce reducer, chronoTree

# Splits a chronological organization of posts into a group of months that is
# completely downloaded and can be written to disk and a group that needs to
# wait it to be completely downloaded.
#
# @method removeFlushable
# @param {object} chronoTree The chronological structure of posts to split
# @return {Array chronoTree, chronoTree} The split up analysis
exports.removeFlushable = (chronoTree) ->
  years = Object.keys chronoTree

  if years.length < 1 then return [{}, {}]

  comp = (a, b) -> return if parseInt(a, 10) > parseInt(b, 10) then -1 else 1
  reducer = (memo, year) ->
    [toFlush, toCarry] = memo
    toFlush[year] = toCarry[year]
    delete toCarry[year]
    return [toFlush, toCarry]

  furthestYear = (years.sort comp).pop()
  [toFlush, toCarry] = years.reduce reducer, [{}, chronoTree]


  months = Object.keys chronoTree[furthestYear]

  assert months.length > 0
  furthestMonth = (months.sort comp).pop()
  toFlush[furthestYear] = {}
  reducer2 = (memo, month) ->
    [toFlush, toCarry] = memo
    toFlush[furthestYear][month] = toCarry[furthestYear][month]
    delete toCarry[furthestYear][month]
    return [toFlush, toCarry]

  return months.reduce reducer2, [toFlush, chronoTree]

# TODO: warn and then overwrite existing files
# Write a chronoTree structure to disk at the specified location
#
# @method flushToDisk
# @private
# @param {string} location Where to write the results
# @param {object} chronoTree The posts to write
# @return {null} Side Effects, son.
exports.flushToDisk = (location, chronoTree) ->
  for own year, months of chronoTree
    try
      fs.mkdirSync "#{location}/#{year}"
    catch error
      if error.code isnt 'EEXIST' then throw error

    for own month, posts of months
      filename = "#{location}/#{year}/#{month}.json"
      fs.writeFileSync filename, JSON.stringify(posts, null, 2)

  return null