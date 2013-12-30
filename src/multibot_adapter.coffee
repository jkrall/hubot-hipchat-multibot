IpcConnector = require './ipc_connector'

# Require hubot-hipchat
try
  {HipChat} = require 'hubot-hipchat'
catch
  # workaround when `npm link`'ed for development
  prequire = require 'parent-require'
  {HipChat} = prequire 'hubot-hipchat'

# Override HipChat connectorClass to use IpcConnector
HipChat.connectorClass = IpcConnector

exports.use = (robot) ->
  new HipChat robot

