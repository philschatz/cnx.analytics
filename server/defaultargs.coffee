# **defaultargs.coffee** when called with on the argv object this
# module will create reasonable defaults for options not supplied.
path = require 'path'

module.exports = (argv) ->
  argv or= {}
  argv.o or= ''
  argv.p or= 3000
  argv.u or= 'http://localhost' + (':' + argv.p) unless argv.p is 80
  argv
