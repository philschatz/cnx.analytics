# Set export objects for node and coffee to a function that generates a sfw server.
module.exports = exports = (argv) ->

  #### Dependencies ####
  # anything not in the standard library is included in the repo, or
  # can be installed with an:
  #     npm install
  spawn       = require('child_process').spawn
  express     = require('express')
  path        = require('path')
  EventEmitter = require('events').EventEmitter
  carrier     = require 'carrier' # Stream parser that returns whole lines


  #### State ####
  # Stores in-memory state
  class Promise extends EventEmitter
    constructor: (prerequisite) ->
      #events.push @
      @status = 'PENDING'
      @created = new Date()
      @history = []
      @isProcessing = true
      @data = null
      if prerequisite?
        that = @
        prerequisite.on 'update', (msg) -> that.update "Prerequisite update: #{msg}"
        prerequisite.on 'fail', () ->
          that.update 'Prerequisite task failed'
          that.fail()
        prerequisite.on 'finish', (_, mimeType) -> that.update "Prerequisite finished generating object with mime-type=#{mimeType}"
    toString: () ->
      JSON.stringify @, (key, value) ->
        # Skip the pid so we can serialize
        return value if 'pid' != key
    # Send either the data (if available), or a HTTP Status with this JSON
    send: (res) ->
      if @isProcessing
        # Use @toString so the pid is removed and reparse so we send the right content type
        res.status(202).send JSON.parse(@toString())
      else if @data
        res.header('Content-Type', @mimeType)
        res.send @data
      else
        # Use @toString so the pid is removed and reparse so we send the right content type
        res.status(404).send JSON.parse(@toString())
    update: (msg=null) ->
      @modified = new Date()
      return if msg is null
      @history.push msg
      if @history.length > 50
        @history.splice(0,1)
      @emit('update', msg)

    work: (message, @status='WORKING') ->
      @update(message)
      @emit('work')
    wait: (message, @status='PAUSED') ->
      @update(message)
      @emit('work')

    fail: (msg) ->
      @update msg
      @isProcessing = false
      @status = 'FAILED'
      @data = null
      @emit('fail')
      @pid.kill() if @pid
    finish: (@data, @mimeType='text/html; charset=utf-8') ->
      @update "Generated file"
      @isProcessing = false
      @status = 'FINISHED'
      @emit('finish', @data, @mimeType)

  TASKS = []

  #### Spawns ####
  env = { cwd: path.join(__dirname, '..') }

  spawnScaffolding = (id, promise, rawJavascript) ->
    child = spawn('node', [ path.join(__dirname, '..', 'worker', 'index.js'), '--content-directory', argv.c, '--intermediate', '--subset', argv.s ], env)

    # Set the pid so we can kill it if requested
    promise.pid = child

    carrier.carry(child.stdout).on 'line', (line) ->
      # See if it matches anything and adjust the promise accordingly
      if /^FINISHED:\ /.test line
        line = line.slice 'FINISHED: '.length # Remove the prefix
        promise.finish JSON.parse(line), 'text/json'
      else if /^PROGRESS:\ /.test line
        line = line.slice 'PROGRESS: '.length # Remove the prefix
        promise.progress = JSON.parse line
        promise.update()
      else if /^STATE:\ /.test line
        line = line.slice 'STATE: '.length # Remove the prefix
        promise.state = JSON.parse line
        promise.update()
      else
        console.log 'Whoops, something slipped through!'
        promise.update line.toString()
    child.stderr.on 'data', (chunk) ->
      promise.update chunk.toString()

    child.stdin.write rawJavascript
    return child


  # Create the main application object, app.
  app = express.createServer()

  # defaultargs.coffee exports a function that takes the argv object that is passed in and then does its
  # best to supply sane defaults for any arguments that are missing.
  argv = require('./defaultargs')(argv)

  #### Express configuration ####
  # Set up all the standard express server options,
  # including hbs to use handlebars/mustache templates
  # saved with a .html extension, and no layout.
  app.configure( ->
    app.set('view options', layout: false)
    app.use(express.cookieParser())
    app.use(express.bodyParser())
    app.use(express.methodOverride())
    app.use(express.session({ secret: 'notsecret'}))
    app.use(app.router)
    app.use(express.static(path.join(__dirname, '..', 'node_modules'))) # for jQuery
    app.use(express.static(path.join(__dirname, '..', 'static')))
  )

  ##### Set up standard environments. #####
  # In dev mode turn on console.log debugging as well as showing the stack on err.
  app.configure('development', ->
    app.use(express.errorHandler({ dumpExceptions: true, showStack: true }))
    argv.debug = console? and true
  )

  # Show all of the options a server is using.
  console.log argv if argv.debug

  # Swallow errors when in production.
  app.configure('production', ->
    app.use(express.errorHandler())
  )

  #### Routes ####
  # Routes currently make up the bulk of the Express
  # server. Most routes use literal names,
  # or regexes to match, and then access req.params directly.

  ##### Redirects #####
  # Common redirects that may get used throughout the routes.
  app.all('/', (req, res) ->
    res.redirect('/new.html')
  )

  ##### Get routes #####
  # Routes have mostly been kept together by http verb

  # Accept GET and POST Submissions
  app.post('/tasks', (req, res, next) ->
    rawJavascript = req.param('src')
    promise = new Promise()
    id = TASKS.length
    TASKS.push promise

    promise.source = rawJavascript
    spawnScaffolding(id, promise, rawJavascript)

    res.send "/tasks/#{id}"
  )

  app.get("/tasks", (req, res) ->
    # Build up a little map of all the promises (TASKS)
    tasks = {}
    for id, promise of TASKS
      tasks[id] = JSON.parse(promise.toString())
    res.send tasks
  )

  app.get("/tasks/:id([0-9]+)", (req, res) ->
    TASKS[req.params.id].send res
  )

  app.all("/tasks/:id([0-9]+)/kill", (req, res) ->
    TASKS[req.params.id].fail('User Killed this task')
  )


  #### Start the server ####

  app.listen(argv.p, argv.o if argv.o)
  # When server is listening emit a ready event.
  app.emit "ready"
  console.log("Server listening in mode: #{app.settings.env}")

  # Return app when called, so that it can be watched for events and shutdown with .close() externally.
  app
