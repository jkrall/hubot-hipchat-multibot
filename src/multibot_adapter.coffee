IpcConnector = require './ipc_connector'

# Require hubot-hipchat
{HipChat} = require 'hubot-hipchat'

# Override HipChat connectorClass to use IpcConnector
HipChat.connectorClass = IpcConnector

exports.use = (robot) ->
  new HipChat robot

