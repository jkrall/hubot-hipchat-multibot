{EventEmitter} = require "events"
fs = require "fs"
{bind, isString, isRegExp} = require "underscore"

# ##Public Connector API
module.exports = class IpcConnector extends EventEmitter

  # This is the `Connector` constructor.
  #
  # `options` object:
  #
  #   - `jid`: Connector's Jabber ID
  #   - `password`: Connector's HipChat password
  #   - `host`: Force host to make XMPP connection to. Will look up DNS SRV
  #        record on JID's host otherwise.
  #   - `caps_ver`: Name and version of connector. Override if Connector is being used
  #        to power another connector framework (e.g. Hubot).
  #   - `logger`: A logger instance.
  constructor: (options={}) ->
    @once "connect", (->) # listener bug in Node 0.4.2
    @setMaxListeners 0

    @rooms = options.rooms
    @name = null
    @plugins = {}
    @iq_count = 1 # current IQ id to use
    @logger = options.logger

    # add a JID resource if none was provided
    jid = new xmpp.JID options.jid
    jid.resource = "hubot-hipchat" if not jid.resource

    @jid = jid.toString()
    @password = options.password
    @host = options.host
    @caps_ver = options.caps_ver or "hubot-hipchat:#{pkg.version}"

    # Multi-User-Conference (rooms) service host. Use when directing stanzas
    # to the MUC service.
    @mucHost = "conf.#{if @host then @host else 'hipchat.com'}"

    @onError @disconnect

  # Connects the connector to HipChat and sets the XMPP event listeners.
  connect: ->
    # debug network traffic
    do =>
      process.on "message", (buffer) =>
        @logger.debug "  IN > %s", buffer.toString()

      _send = process.send
      process.send = (stanza) =>
        @logger.debug " OUT > %s", stanza
        _send.call process, stanza

  # Disconnect the connector from HipChat, remove the anti-idle and emit the
  # `disconnect` event.
  disconnect: =>
    @emit "disconnect"

  # Fetches our profile info
  #
  # - `callback`: Function to be triggered: `function (err, data, stanza)`
  #   - `err`: Error condition (string) if any
  #   - `data`: Object containing fields returned (fn, title, photo, etc)
  #   - `stanza`: Full response stanza, an `xmpp.Element`
  getProfile: (callback) ->
    process.once 'message', (response) ->
      response = JSON.parse response
      data = {}
      for k, v of response.vCard
        data[k.toLowerCase()] = v
      callback null, data, response

    process.send JSON.stringify
      command: 'getProfile'
      
  # Fetches the rooms available to the connector user. This is equivalent to what
  # would show up in the HipChat lobby.
  #
  # - `callback`: Function to be triggered: `function (err, items, stanza)`
  #   - `err`: Error condition (string) if any
  #   - `rooms`: Array of objects containing room data
  #   - `stanza`: Full response stanza, an `xmpp.Element`
  getRooms: (callback) ->
    callback null, @rooms, 'noop, you do not get to ask this'

  # Fetches the roster (buddy list)
  #
  # - `callback`: Function to be triggered: `function (err, items, stanza)`
  #   - `err`: Error condition (string) if any
  #   - `items`: Array of objects containing user data
  #   - `stanza`: Full response stanza, an `xmpp.Element`
  getRoster: (callback) ->
    process.once 'message', (response) ->
      items = usersFromStanza response
      callback null, items, response

    process.send JSON.stringify
      command: 'getRoster'

  # Updates the connector's availability and status.
  #
  #  - `availability`: Jabber availability codes
  #     - `away`
  #     - `chat` (Free for chat)
  #     - `dnd` (Do not disturb)
  #  - `status`: Status message to display
  setAvailability: (availability, status) ->
    console.log 'Noop -- IpcConnector does not support availability updates'

  # Join the specified room.
  #
  # - `roomJid`: Target room, in the form of `????_????@conf.hipchat.com`
  # - `historyStanzas`: Max number of history entries to request
  join: (roomJid, historyStanzas) ->
    process.send JSON.stringify
      command: 'join'
      arguments:
        roomJid: roomJid
        historyStanzas: historyStanzas

  # Part the specified room.
  #
  # - `roomJid`: Target room, in the form of `????_????@conf.hipchat.com`
  part: (roomJid) ->
    process.send JSON.stringify
      command: 'part'
      arguments:
        roomJid: roomJid

  # Send a message to a room or a user.
  #
  # - `targetJid`: Target
  #    - Message to a room: `????_????@conf.hipchat.com`
  #    - Private message to a user: `????_????@chat.hipchat.com`
  # - `message`: Message to be sent to the room
  message: (targetJid, message) ->
    process.send JSON.stringify
      command: 'message'
      arguments:
        targetJid: targetJid
        message: message

  # Send a topic change message to a room
  #
  # - `targetJid`: Target
  #    - Message to a room: `????_????@conf.hipchat.com`
  # - `message`: Text string that the topic should be set to
  topic: (targetJid, message) ->
    process.send JSON.stringify
      command: 'topic'
      arguments:
        targetJid: targetJid
        message: message

  # ##Events API

  # Emitted whenever the connector connects to the server.
  #
  # - `callback`: Function to be triggered: `function ()`
  onConnect: (callback) -> @on "connect", callback

  # Emitted whenever the connector disconnects from the server.
  #
  # - `callback`: Function to be triggered: `function ()`
  onDisconnect: (callback) -> @on "disconnect", callback

  # Emitted whenever the connector is invited to a room.
  #
  # `onInvite(callback)`
  #
  # - `callback`: Function to be triggered:
  #               `function (roomJid, fromJid, reason, matches)`
  #   - `roomJid`: JID of the room being invited to.
  #   - `fromJid`: JID of the person who sent the invite.
  #   - `reason`: Reason for invite (text)
  onInvite: (callback) -> @on "invite", callback

  # Makes an onMessage impl for the named message event
  onMessageFor = (name) ->
    (condition, callback) ->
      if not callback
        callback = condition
        condition = null
      @on name, ->
        message = arguments[arguments.length - 1]
        if not condition or message is condition
          callback.apply @, arguments
        else if isRegExp condition
          match = message.match condition
          return if not match
          args = [].slice.call arguments
          args.push match
          callback.apply @, args

  # Emitted whenever a message is sent to a channel the connector is in.
  #
  # `onMessage(condition, callback)`
  #
  # `onMessage(callback)`
  #
  # - `condition`: String or RegExp the message must match.
  # - `callback`: Function to be triggered: `function (roomJid, from, message, matches)`
  #   - `roomJid`: Jabber Id of the room in which the message occured.
  #   - `from`: The name of the person who said the message.
  #   - `message`: The message
  #   - `matches`: The matches returned by the condition when it is a RegExp
  onMessage: onMessageFor "message"

  # Emitted whenever a message is sent privately to the connector.
  #
  # `onPrivateMessage(condition, callback)`
  #
  # `onPrivateMessage(callback)`
  #
  # - `condition`: String or RegExp the message must match.
  # - `callback`: Function to be triggered: `function (fromJid, message)`
  onPrivateMessage: onMessageFor "privateMessage"

  onEnter: (callback) -> @on "enter", callback

  onLeave: (callback) -> @on "leave", callback

  onRosterChange: (callback) -> @on "rosterChange", callback

  # Emitted whenever the connector pings the server (roughly every 30 seconds).
  #
  # - `callback`: Function to be triggered: `function ()`
  onPing: (callback) -> @on "ping", callback

  # Emitted whenever an XMPP stream error occurs. The `disconnect` event will
  # always be emitted afterwards.
  #
  # Conditions are defined in the XMPP spec:
  #   http://xmpp.org/rfcs/rfc6120.html#streams-error-conditions
  #
  # - `callback`: Function to be triggered: `function(condition, text, stanza)`
  #   - `condition`: XMPP stream error condition (string)
  #   - `text`: Human-readable error message (string)
  #   - `stanza`: The raw `xmpp.Element` error stanza
  onError: (callback) -> @on "error", callback


process.on 'message', (data) ->
 packet = JSON.parse data

 if packet.command == 'stanza'
    stanza = packet.arguments
    
    if stanza.type == 'message'
      message = stanza.content

      switch message.type

        # {
        #   command: 'stanza',
        #   arguments: {
        #     type: 'message',
        #     content: {
        #       type: 'groupchat',
        #       body: '...', fromChannel: '...', fromNick: '...'
        #     }
        #   }
        # }
        when 'groupchat'
          return if not message.body
          return if message.delay
          fromChannel = message.fromChannel
          fromNick = message.fromNick
          # Ignore our own messages
          return if fromNick is @name
          @emit "message", fromChannel, fromNick, stanza.body

        # {
        #   command: 'stanza',
        #   arguments: {
        #     type: 'message',
        #     content: {
        #       type: 'chat',
        #       body: '...', fromJid: '...'
        #     }
        #   }
        # }
        when 'chat'
          return if not message.body
          @emit "privateMessage", message.fromJid, message.body

        # {
        #   command: 'stanza',
        #   arguments: {
        #     type: 'message',
        #     content: {
        #       invite: {
        #         reason: '...',
        #         from: '...'
        #       }, 
        #       from: '...'
        #     }
        #   }
        # }
        else
          return if not message.invite
          @emit "invite", message.from, message.invite.from, message.invite.reason
    
    if stanza.type == 'iq'
      iq = stanza.content
      eventId = "iq:#{iq.id}"
      
      switch iq.type

        # {
        #   command: 'stanza',
        #   arguments: {
        #     type: 'iq',
        #     content: {
        #       id: '...',
        #       ...
        #     }
        #   }
        # }
        when "result"
          @emit eventId, null, stanza

        when "set"
          if iq.query.xmlns is "jabber:iq:roster"
            users = usersFromStanza stanza
            @emit "rosterChange", users, stanza

        else
          condition = "unknown"
          error_elem = iq.error
          condition error_elem[0].name if error_elem
          @emit eventId, condition, stanza


    # {
    #   command: 'stanza',
    #   arguments: {
    #     type: 'presence',
    #     content: {
    #       room: '...',
    #       from: '.../...',
    #     }
    #   }
    # }
    if stanza.type == 'presence'
      presence = stanza.content
      return if not presence.room
      name = presence.from.split("/")[1] || ''
      type = presence.type
      entity = presence.item
      return if not entity
      from = entity.jid
      return if not from
      if type is "unavailable"
        @emit "leave", from, room, name
      else if type is "available" and entity.role is "participant"
        @emit "enter", from, room, name


usersFromStanza = (stanza) ->
  # Parse response into objects
  stanza.items.map (el) ->
    jid: el.jid
    name: el.name
    mention_name: el.mention_name



