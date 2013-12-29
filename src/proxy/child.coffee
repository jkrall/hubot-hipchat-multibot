console.log 'child was created with PID: ' + process.pid

process.on 'exit', (code,signal) ->
  console.warn 'child is exiting with code: '+ code +' and signal: '+signal

process.on 'message', (data) ->
  console.log 'child: got message from parent: ' + data
  process.send 'hi, thanks for the message!'

