require('coffee-script/register')

var FB = require('./fb-promisified.coffee')
  , fs = require('fs')
  , readline = require('readline')
  , consumeMyFeed = require('./feed.coffee').consumeMyFeed
  , consumeMyMessages = require('./messages.coffee').consumeMyMessages

// extract configuration from command line
var token = process.argv[2]
  , outFolderName = process.argv[3]



// consumeMyFeed(token, outFolderName)
consumeMyMessages(token, outFolderName)