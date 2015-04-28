# Download all the threads in the user's inbox. The root nodes of each thread is
# stored as the array that comes from the /me/inbox endpoint, paginated by
# month. If a thread has more messages they are downloaded and stored separately
# in a threads/{thread_id} folder, also paginated by month.

FB = require './fb-promisified.coffee'
fs = require 'fs'
U = require './util.coffee'

# If any of the threads have additional data, download it and save to disk.
#
# @method downloadThreads
# @param {string} token The access token to use
# @param {string} output The location to write the data to
# @param {object} chunk The inbox chunk to download for
# @return {null} Side Effect City
downloadThreads = (token, output, chunk) ->
  chunk.data.forEach (thread) -> downloadThread token, output, thread
  return null



downloadThread = (token, output, thread) ->
  if !thread.comments then return null

  nextPath = FB.extractNextPath thread.comments
  if !nextPath then return null

  output = "#{output}/threads/#{thread.id}"
  FB.paginateStream token, nextPath, {}, (memo, page) ->
    [toFlush, carry] = U.removeFlushable (U.chronologizeChunk memo, page, true)
    if (Object.keys toFlush).length isnt 0
      try
        fs.mkdirSync output
      catch error
        if error.code isnt 'EEXIST' then throw error

    U.flushToDisk output, toFlush
    U.flushToDisk output, carry unless page.data.length > 0

    return carry




# Downloads the inbox and all threads in it. Saves the inbox chronologically
# and any threads which need extra data in a separate folder also by date. Gets
# a chunk of threads, which it tries to download. Then the inbox chunk is
# chronologized and flushed to disk. Any remainder is returned to become the new
# memo in paginateStream.
#
# @method consumeMyMessages
# @param {String} token The access token to use
# @param {String} output The output path to write to
# @return {Null} ssssside effectssssss
exports.consumeMyMessages = (token, output) ->
  inboxOutput = "#{output}/inbox"
  try
    fs.mkdirSync inboxOutput
  catch e
    if e.code isnt 'EEXIST' then throw e

  try
    fs.mkdirSync "#{output}/threads"
  catch error
    if error.code isnt 'EEXIST' then throw error

  FB.paginateStream token, 'me/inbox', {}, (memo, chunk) ->
    downloadThreads token, output, chunk
    [toFlush, carry] = U.removeFlushable (U.chronologizeChunk memo, chunk)
    U.flushToDisk inboxOutput, toFlush
    return carry

  return null
