# This is the worker process.
# It opens all the files in a directory tree and executes **arbitrary**
# user-provided Javascript on each.
#
# The Javascript is read in via stdin
# and the worker outputs progress information and intermediate state to stdio.
module.exports = exports = (argv) ->
  path = require 'path'
  fs = require 'fs'
  jsdom = require 'jsdom'

  class State
    state = {}
    toString: () -> JSON.stringify state
    increment: (key, x=1) ->
      state[key] ?= 0
      state[key] += x

  # Array shuffler (so we randomly walk over the content)
  shuffle = (arr) ->
    i = arr.length
    return if 0 == i
    while --i
      j = Math.floor( Math.random() * ( i + 1 ) )
      [arr[j], arr[i]] = [arr[i], arr[j]]

  # Helper function to reduce the stack size
  tailCall = (cb) ->
    setTimeout(->
      cb()
    , 1)

  # Recursively finds files that match a certain regex and then
  # calls `callback` with the array of file paths
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

  # Executes arbitrary javascript
  # This is **VERY** unsafe.
  # I think there are 3 ways to prevent misuse:
  #
  # 1. unassign all variables in this scope
  # 2. parse the string to make sure curly braces and parens match
  #    (and the nesting depth never equals 0)
  # 3. Kill this process after inactivity (no infinite loops)
  #
  # The webserver can tell it's inactive because:
  #
  # 1. This function can't spawn work to occur later (`setTimeout` and `setInterval`)
  # 2. By being in this loop the worker cannot report progress to stdout (yay event loops!)
  safeishEval = (jsString) ->
    # FIXME: I'm sure there are injection problems here. make sure the curly braces and parentheses match before running eval()
    evalStr = """(function(define,
      evalStr, jsString, ret,
      argv, findFiles, fs, jsdom, path, safeRunner, shuffle, tailCall,
      exports, __dirName, __fileName, module, require,
      global, process, setInterval, setTimeout,
      undefined) {
        #{jsString}
      }).bind(null)"""
    f = eval evalStr
    return f

  # Prepare to read in the **unsafe** arbitrary javascript
  process.stdin.resume()
  process.stdin.setEncoding 'utf8'

  # Start up a DOM and jQuery.
  # It is very time consuming to start one up for each piece of content
  # So we start one up and then reuse it for every piece of content
  jsdom.env '<root></root>',
    features:
      FetchExternalResources: false # ['img']
      ProcessExternalResources: false
  , (err, window) ->
    if err
      throw 'jsdom failed to load for some reason'

    jQuery = require('jQuery').create(window)

    # Once we have a DOM started up read in the **unsafe** javascript
    process.stdin.on 'data', (jsBuf) ->
      func = safeishEval(jsBuf.toString())
      state = new State()
      progress = {total: 0, finished: 0}

      # Because there are many files to open we batch proceesing them
      # (otherwise we'd run out of file descriptors)
      batcher = (err, files, pending) ->

        # A tick is called when done with a piece of content
        # This decreases the pending queue and runs batch
        # (if patch is called with a non-empty pending queue then nothing happens)
        batchTick = () ->
          tailCall ->
            progress.finished++
            pending.splice 0, 1
            batcher(null, files, pending)

        # If the pending queue is empty and there are no more files
        # to process then we're done!
        if files.length == 0 and pending.length == 0
          console.log "FINISHED: #{state.toString()}"
          return

        # If the pending queue is empty again, refill it
        if pending.length == 0 and files[0]
          console.log "PROGRESS: #{JSON.stringify progress}"
          console.log "STATE: #{state.toString()}" if argv.i

          # Pop 40 pieces of content at time into the pending queue
          # (we'll be waiting for disk io)
          (pending.push files.pop() if files[0]) for num in [1..40]

          pending.forEach (href) ->
            fs.readFile href, 'utf-8', (err, xml) ->
              return batchTick() if err

              # Clear up the DOM and then load in the new one
              jQuery('root')[0].innerHTML = xml

              $root = jQuery('root').children() # The <document> element for modules

              # Emulate requirejs syntax by providing a `define` function
              # that provides access to objects.
              # This way we (backend) can see/limit which features are being
              # used and optimize (Don't reset/load jQuery
              #   or parse the DOM of it isn't going to be used.
              valids =
                state: state
                jQuery: jQuery
                $root: $root
              define2 = (dependencies, callback) ->
                args = (valids[d] for d in dependencies)
                callback.apply null, args

              try
                func define2
              catch e
                console.log "ERROR: #{JSON.stringify e}"

              batchTick()

      # Here is where all the work starts
      #
      # * Find all the files that match a pattern
      # * Shuffle them
      # * Drop some of them if we are only running on a subset
      # * Start the batch analysis process
      findFiles argv.c, /index\.cnxml/, (err, files) ->
        if argv.r
          shuffle(files)
        # If this worker is running on a subset of content then
        # splice the rest out.
        if argv.s != 100
          files.splice 0, (100 - argv.s) * files.length / 100
        progress.total = files.length
        console.log "PROGRESS: #{JSON.stringify progress}"
        tailCall -> batcher(err, files, [])
