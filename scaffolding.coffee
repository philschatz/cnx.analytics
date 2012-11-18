module.exports = exports = (argv) ->
  path = require 'path'
  fs = require 'fs'
  jsdom = require 'jsdom'

  # `defaultargs.coffee` exports a function that takes
  # the argv object that is passed in and then does its
  # best to supply sane defaults for any arguments that are missing.
  #argv = require('./defaultargs')(argv)

  # Array shuffler
  shuffle = (arr) ->
    i = arr.length
    return if 0 == i
    while --i
      j = Math.floor( Math.random() * ( i + 1 ) )
      [arr[j], arr[i]] = [arr[i], arr[j]]

  tailCall = (cb) ->
    setTimeout(->
      cb()
    , 1)

  findFiles = (href, regex, callback, state={}) ->
    state.count = state.count or 0
    state.files = state.files or []

    state.count++
    fs.stat href, (err, stat) ->
      state.count--
      throw err if err
      if stat.isDirectory()
        state.count++
        fs.readdir href, (err, files) ->
          state.count--
          throw err if err
          files.forEach (file) ->
            findFiles path.join(href, file), regex, callback, state
      else
        state.files.push href if regex.test href
        if state.count <= 0
          tailCall ->
            callback null, state.files

  safeishEval = (jsString) ->
    # FIXME: I'm sure there are injection problems here. make sure the curly braces and parentheses match before running eval()
    evalStr = """(function(state, config,
      evalStr, jsString, ret,
      argv, findFiles, fs, jsdom, path, safeRunner, shuffle, tailCall,
      exports, __dirName, __fileName, module, require,
      global, process, setInterval, setTimeout,
      undefined) {
         #{jsString}
      }).bind(null)"""
    eval evalStr

  # Parse the javascript function to run
  process.stdin.resume()
  process.stdin.setEncoding 'utf8'

  jsdom.env '<root></root>',
    features:
      FetchExternalResources: false # ['img']
      ProcessExternalResources: false
  , (err, window) ->
    if err
      throw 'jsdom failed to load for some reason'

    jQuery = require('jQuery').create(window)

    process.stdin.on 'data', (jsBuf) ->
      func = safeishEval(jsBuf.toString())
      state = {}

      batcher = (err, files, pending) ->
        batchTick = () ->
          tailCall ->
            pending.splice 0, 1
            batcher(null, files, pending)

        if files.length == 0 and pending.length == 0
          console.log "DONE: state:"
          console.log state
          return

        if pending.length == 0 and files[0]
          if files.length % 400 <= 20

            console.log "Files to go: #{files.length}"
            console.log state if argv.i

          (pending.push files.pop() if files[0]) for num in [1..20]

          pending.forEach (href) ->
            fs.readFile href, 'utf-8', (err, xml) ->
              if err
                return batchTick()

              # Clear up the DOM and then load in the new one
              jQuery('root')[0].innerHTML = xml

              config = {jQuery: jQuery, root: jQuery('root').children()}
              state = func state, config

              batchTick()

      findFiles argv.c, /index\.cnxml/, (err, files) ->
        if argv.r
          shuffle(files)
        if argv.s != 10
          # splice out 90% of the files
          files.splice 0, (10 - argv.s) * files.length / 10
        console.log "Files to parse: #{files.length}"
        tailCall -> batcher(err, files, [])
