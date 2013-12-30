#!/usr/bin/env coffee

spawn = require('child_process').spawn

format = (type, output) ->
  console.log 'child says (' + type + '): ' + output


child_cmd = process.env.HUBOT_COMMAND || 'node_modules/.bin/hubot'
child_args = process.env.HUBOT_ARGS?.split(' ') || ['-a', 'hipchat-multibot']


child = spawn child_cmd, child_args,
  cwd: process.cwd()
  env: process.env
  stdio: ['pipe', 'pipe', 'pipe', 'ipc']
child.stdout.on 'data', format.bind(global,'stdout')
child.stderr.on 'data', format.bind(global,'stderr')


child.on 'message', (data) ->
  console.log 'PARENT got message:', data

setTimeout ->
  child.send('hello from your parent')
, 2000

setTimeout ->
  child.send('hello from your parent')
, 4000
