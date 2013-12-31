#!/usr/bin/env coffee

Log = require 'log'
{_} = require "underscore"
{spawn} = require('child_process')
{format_child_data} = require('./utils')

# Require hubot-hipchat connector
connector_path = 'hubot-hipchat/src/connector'
try
  Connector = require '../../'+connector_path
catch
  # in dev w/ npm link, we might need to source the connector from the hubot repo
  Connector = require '../../hubot/node_modules/'+connector_path

class HipChatProxy
  DEFAULT_HUBOT_COMMAND = 'node_modules/.bin/hubot'
  DEFAULT_HUBOT_ARGS = ['-a', 'hipchat-multibot']

  children: {}

  constructor: (options={}) ->
    @logger = options.logger || new Log(process.env.HUBOT_LOG_LEVEL or 'debug')
    @rooms = options.rooms?.split(/[\s,]/) || []

  spawn_room: (room) ->
    @logger.info "Spawning Room: #{room} ..."
    child_cmd = process.env.HUBOT_COMMAND || DEFAULT_HUBOT_COMMAND
    child_args = process.env.HUBOT_ARGS?.split(' ') || DEFAULT_HUBOT_ARGS

    child_env = _.clone process.env
    child_env.HUBOT_HIPCHAT_ROOMS = room
    child_env.HUBOT_PARENT_PID = process.pid

    @children[room] = spawn child_cmd, child_args,
      cwd: process.cwd()
      env: child_env
      stdio: ['pipe', 'pipe', 'pipe', 'ipc']

    @children[room].stdout.on 'data', (data) => @logger.debug format_child_data(room, 'stdout', data)
    @children[room].stderr.on 'data', (data) => @logger.debug format_child_data(room, 'stderr', data)

    @children[room].on 'message', (data) =>
      packet = JSON.parse data
      payload = packet.arguments
      @logger.debug 'PARENT got message:', packet

      if packet.command == 'getProfile'
        @connector.getProfile (err, data, res) =>
          @children[room].send JSON.stringify data

      if packet.command == 'getRoster'
        @connector.getRoster (err, items, stanza) =>
          @children[room].send JSON.stringify
            items: items

      if packet.command == 'setAvailability'
        @connector.setAvailability payload.availability, payload.status

      if packet.command == 'join'
        @connector.join payload.roomJid, payload.historyStanzas

      if packet.command == 'part'
        @connector.part payload.roomJid

      if packet.command == 'message'
        @connector.message payload.targetJid, payload.message

      if packet.command == 'topic'
        @connector.topic payload.targetJid, payload.message

  spawnRooms: ->
    @spawn_room(room) for room in @rooms

  connect: ->
    @logger.info "Connecting to HipChat..."
    options =
      jid:        process.env.HUBOT_HIPCHAT_JID
      password:   process.env.HUBOT_HIPCHAT_PASSWORD
      token:      process.env.HUBOT_HIPCHAT_TOKEN or null
      rooms:      process.env.HUBOT_HIPCHAT_ROOMS or "All"
      host:       process.env.HUBOT_HIPCHAT_HOST or null
      autojoin:   process.env.HUBOT_HIPCHAT_JOIN_ROOMS_ON_INVITE isnt "false"
    @logger.debug "HipChat adapter options: #{JSON.stringify options}"

    # create Connector object
    @connector = new Connector
      jid: options.jid
      password: options.password
      host: options.host
      logger: @logger

    @connector.onConnect =>
      @logger.info "Connected as @#{@connector.mention_name}"

      @connector.onMessage (channel, from, message) =>
        @children[channel].send JSON.stringify
          command: 'stanza'
          arguments:
            type: 'message'
            content:
              type: 'groupchat'
              body: message
              fromChannel: channel
              fromNick: from

      @connector.onPrivateMessage (from, message) =>
        # TODO: how do we handle dispatching of private messages?
        #  @children[channel].send JSON.stringify
        #    command: 'stanza'
        #    arguments:
        #      type: 'message'
        #      content:
        #        type: 'chat'
        #        body: message
        #        fromJid: from

      @connector.onEnter (user_jid, room_jid, currentName) =>
        @children[room_jid].send JSON.stringify
          command: 'stanza'
          arguments:
            type: 'presence'
            content:
              type: 'available'
              from: user_jid
              room: room_jid
              name: currentName

      @connector.onLeave (user_jid, room_jid) =>
        @children[room_jid].send JSON.stringify
          command: 'stanza'
          arguments:
            type: 'presence'
            content:
              type: 'unavailable'
              from: user_jid
              room: room_jid
              name: currentName

      @connector.onDisconnect =>
        @logger.info "Disconnected from #{host}"
        for room, child of @children
          child.send JSON.stringify
            command: 'disconnect'

      @connector.onError =>
        @logger.error [].slice.call(arguments).map(inspect).join(", ")

      @connector.onInvite (room_jid, from_jid, message) =>
        # TODO: how do we handle invites?
        #  action = if @options.autojoin then "joining" else "ignoring"
        #  @logger.info "Got invite to #{room_jid} from #{from_jid} - #{action}"
        #  connector.join room_jid if @options.autojoin

      for room, child of @children
        child.send JSON.stringify
          command: 'connect'
          arguments:
            name: @connector.mention_name

    @connector.connect()

  setupExitHandlers: ->
    process.on 'exit', ->
      child.kill() for _, child of @children

    process.on 'uncaughtException', (err) ->
      console.log err
      child.kill() for _, child of @children

  start: ->
    @connect()
    @spawnRooms()
    @setupExitHandlers()


proxy = new HipChatProxy
  rooms: process.env.HUBOT_HIPCHAT_ROOMS

proxy.start()

