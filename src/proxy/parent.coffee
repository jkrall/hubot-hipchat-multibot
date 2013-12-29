#!/usr/bin/env coffee

spawn = require('child_process').spawn

format = (type, output) ->
  console.log 'child says (' + type + '): ' + output

child = spawn 'node_modules/.bin/hubot', ['-r', 'custom'],
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
