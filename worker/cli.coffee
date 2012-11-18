# Cli for the mock express server

path = require 'path'
optimist = require 'optimist'
server = require './scaffolding'

# Handle command line options

argv = optimist
  .usage('Usage: $0')
  .options('h',
    alias     : 'help'
    boolean   : true
    describe  : 'Show this help info and exit'
  )
  .options('c',
    alias     : 'content-directory'
    default   : path.join(__dirname)
    describe  : 'Directory to load the corpus of content from'
  )
  .options('i',
    alias     : 'intermediate'
    default   : false
    describe  : 'Periodically show intermediate state (every 40 ticks)'
  )
  .options('r',
    alias     : 'random'
    default   : false
    describe  : 'Shuffle using a random seed'
  )
  .options('s',
    alias     : 'subset'
    default   : 100
    describe  : 'Only run on a subset of the data [1-100] where 1 = 10% and 100 = all the data'
  )
  .argv

# If h/help is set print the generated help message and exit.
if argv.h
  optimist.showHelp()
  process.exit()

server(argv)
