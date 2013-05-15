fs = require 'fs'
async = require 'async'
_ = require 'underscore'
mkdir = require('mkdirp').sync
path = require 'path'
temp = require 'temp'
cp = require('wrench').copyDirSyncRecursive
rm = require('rimraf').sync
config = require './config'
Command = require './command'

module.exports =
class Installer extends Command
  atomDirectory: null
  atomPackagesDirectory: null
  atomNodeDirectory: null
  atomNpmPath: null
  atomNodeGypPath: null

  constructor: ->
    @atomDirectory = config.getAtomDirectory()
    @atomPackagesDirectory = path.join(@atomDirectory, 'packages')
    @atomNodeDirectory = path.join(@atomDirectory, '.node-gyp')
    @atomNpmPath = require.resolve('.bin/npm')
    @atomNodeGypPath = require.resolve('.bin/node-gyp')

  installNode: (callback) =>
    console.log '\nInstalling node...'

    installNodeArgs = ['install']
    installNodeArgs.push("--target=#{config.getNodeVersion()}")
    installNodeArgs.push("--dist-url=#{config.getNodeUrl()}")
    installNodeArgs.push('--arch=ia32')
    env = _.extend({}, process.env, HOME: @atomNodeDirectory)

    mkdir(@atomDirectory)
    @spawn @atomNodeGypPath, installNodeArgs, {env, cwd: @atomDirectory}, (code) ->
      if code is 0
        callback()
      else
        callback("Installing node failed with code: #{code}")

  installModule: (modulePath, callback) ->
    console.log '\nInstalling module...'

    installArgs = ['--userconfig', config.getUserConfigPath(), 'install']
    installArgs.push(modulePath)
    installArgs.push("--target=#{config.getNodeVersion()}")
    installArgs.push('--arch=ia32')
    installArgs.push('--silent')
    env = _.extend({}, process.env, HOME: @atomNodeDirectory)

    installDirectory = temp.mkdirSync('apm-install-dir-')
    nodeModulesDirectory = path.join(installDirectory, 'node_modules')
    mkdir(nodeModulesDirectory)
    @spawn @atomNpmPath, installArgs, {env, cwd: installDirectory}, (code) =>
      if code is 0
        for child in fs.readdirSync(nodeModulesDirectory)
          cp(path.join(nodeModulesDirectory, child), path.join(@atomPackagesDirectory, child), forceDelete: true)
        rm(installDirectory)
        callback()
      else
        rm(installDirectory)
        callback("Installing module failed with code: #{code}")

  installModules: (callback) =>
    console.log '\nInstalling modules...'

    installArgs = ['--userconfig', config.getUserConfigPath(), 'install']
    installArgs.push("--target=#{config.getNodeVersion()}")
    installArgs.push('--arch=ia32')
    installArgs.push('--silent')
    env = _.extend({}, process.env, HOME: @atomNodeDirectory)

    @spawn @atomNpmPath, installArgs, {env}, (code) ->
      if code is 0
        callback()
      else
        callback("Installing modules failed with code: #{code}")

  installPackage: (options, modulePath) ->
    commands = []
    commands.push(@installNode)
    commands.push (callback) => @installModule(modulePath, callback)

    async.waterfall(commands, options.callback)

  installDependencies: (options) ->
    commands = []
    commands.push(@installNode)
    commands.push(@installModules)

    async.waterfall commands, options.callback

  installTextMateBundle: (options, bundlePath) ->
    gitArguments = ['clone']
    gitArguments.push(bundlePath)
    gitArguments.push(path.join(@atomPackagesDirectory, path.basename(bundlePath, '.git')))
    @spawn 'git', gitArguments, (code) ->
      if code is 0
        options.callback()
      else
        options.callback("Installing bundle failed with code: #{code}")

  isTextMateBundlePath: (bundlePath) ->
    path.extname(path.basename(bundlePath, '.git')) is '.tmbundle'

  run: (options) ->
    modulePath = options.commandArgs.shift() ? '.'
    if modulePath is '.'
      @installDependencies(options)
    else if @isTextMateBundlePath(modulePath)
      @installTextMateBundle(options, modulePath)
    else
      @installPackage(options, modulePath)
