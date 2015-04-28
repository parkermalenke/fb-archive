# Provides functions for querying and parsing target profile's main
# timeline/wall feed.

FB = require './fb-promisified.coffee'
fs = require 'fs'
Q = require 'q'
U = require './util.coffee'
assert = require 'assert'


# TODO: Download all the likes of each comment
#
# Download any additional comments for a given post and return the post with
# all comments present
#
# @method downloadRemainingComments
# @private
# @param {object} post The post to complete
# @param {string} token The token to use
# @return {Promise object} The post with all comments present
downloadRemainingComments = (post, token) ->
  d = Q.defer()

  if post.comments?.paging?.next?
    FB.downloadStream post.comments.paging.next, token
      .then (restComments) ->
        post.comments.data = post.comments.data.concat restComments
        delete post.comments.paging
        d.resolve post
      .done()
  else
    if post.comments?.paging? then delete post.comments.paging
    d.resolve post

  return d.promise


# Download any additional likes for a given post, return the post with all likes
# present
#
# @method downloadRemainingLikes
# @private
# @param {object} post The post to complete
# @param {string} token The token to use
# @return {Promise object} The post with all likes present
downloadRemainingLikes = (post, token) ->
  d = Q.defer()
  if post.likes?.paging?.next?
    FB.downloadStream post.likes.paging.next, token
      .then (restLikes) ->
        post.likes.data = post.likes.data.concat restLikes
        delete post.likes.paging
        d.resolve post
      .done()
  else
    if post.likes?.paging? then delete post.likes.paging
    d.resolve post

  return d.promise


# Downloads all additional data associated with a chunk, returning the completed
# data structure
#
# @method completeChunk
# @private
# @param {object} chunk The chunk to complete
# @param {string} token The token to use
# @return {Promise object} The completed chunk
completeChunk = (token, chunk) ->
  d = Q.defer()

  proms = chunk.data.map (post) ->
    downloadRemainingComments post, token
      .then (post) ->
        downloadRemainingLikes post, token

  (Q.all proms)
    .then (posts) ->
      chunk.data = posts
      d.resolve chunk
    .done()

  return d.promise


# Recursively download a profile feed given a "next" URL to start at. Write the
# results to the specified output location.
#
# @method reduceMyFeed
# @private
# @param {string} token An access_token to use
# @param {string} nextURL The next url to start downloading at
# @param {string} output The location to write results to
# @param {object} memo Any already downloaded results, in the chronoTree format
# @return {null} Side "Effects" Burns
reduceMyFeed = (token, nextURL, output, memo) ->
  FB.getWithToken nextURL, token
    .then U.curry completeChunk, token
    .then (completeChunk) ->
      if completeChunk.paging?.next?
        nextURL = completeChunk.paging.next
        delete completeChunk.paging
        chronoCarry = U.chronologizeChunk memo, completeChunk
        [toFlush, remainingCarry] = U.removeFlushable chronoCarry
        U.flushToDisk output, toFlush
        reduceMyFeed token, nextURL, output, remainingCarry
      else
        delete completeChunk.paging
        chronoCarry = U.chronologizeChunk memo, completeChunk
        U.flushToDisk output, chronoCarry
    .done()
  return null


# Download the complete feed for the logged in user of the provided token. Write
# the data to the specified output location.
#
# @method consumeMyFeed
# @param {string} token The access_token to use; this user's feed will be
#                       downloaded.
# @param {string} output The location to write the data
# @return {null} Tasteful Side Effect
exports.consumeMyFeed = (token, output) ->
  FB.api '/me/feed', 'get', {access_token: token}
    .then U.curry completeChunk, token
    .then (completeChunk) ->
      if completeChunk.paging?.next?
        nextURL = completeChunk.paging.next
        delete completeChunk.paging
        chronoCarry = U.chronologizeChunk {}, completeChunk
        reduceMyFeed token, nextURL, output, chronoCarry
    .done()
  return null
