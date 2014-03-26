_             = require('lodash')
_.str         = require('underscore.string')
es5shim       = require('es5-shim')
pkg           = require('../package.json')
EventEmitter2 = require('eventemitter2').EventEmitter2
ScribeEditor  = require('./editor')
ScribeRange   = require('./range')
Tandem        = require('tandem-core')

Modules =
  Authorship    : require('./modules/authorship')
  Keyboard      : require('./modules/keyboard')
  LinkTooltip   : require('./modules/link-tooltip')
  MultiCursor   : require('./modules/multi-cursor')
  PasteManager  : require('./modules/paste-manager')
  Toolbar       : require('./modules/toolbar')
  UndoManager   : require('./modules/undo-manager')

Themes =
  Default : require('./themes/default')
  Snow    : require('./themes/snow')


DEFAULT_API_OPTIONS = { silent: false, source: 'api' }

# fn(Number index, Number length, String name, String value, Object options = {})
# fn(Number index, Number length, Object formats, Object options = {})
# fn(Object range, String name, String value, Object options = {})
# fn(Object range, Object formats, Object options = {})
buildParams = (params...) ->
  if _.isObject(params[0])
    index = params[0].start.getIndex()
    length = params[0].end.getIndex() - index
    params.splice(0, 1, index, length)
  if _.isString(params[2])
    formats = {}
    formats[params[2]] = params[3]
    params.splice(2, 2, formats)
  params[3] = _.defaults(params[3] or {}, DEFAULT_API_OPTIONS)
  return params


class Scribe extends EventEmitter2
  @version: pkg.version
  @editors: []

  @Module: Modules
  @Theme: Themes

  @DEFAULTS:
    formats: ['bold', 'italic', 'strike', 'underline', 'link', 'back-color', 'font-name', 'fore-color', 'font-size']
    iframe: true
    logLevel: false
    modules:
      'keyboard': true
      'paste-manager': true
      'undo-manager': true
    pollInterval: 100
    readOnly: false
    theme: 'default'

  @events:
    FOCUS_CHANGE     : 'focus-change'
    MODULE_INIT      : 'module-init'
    POST_EVENT       : 'post-event'
    PRE_EVENT        : 'pre-event'
    RENDER_UPDATE    : 'renderer-update'
    SELECTION_CHANGE : 'selection-change'
    TEXT_CHANGE      : 'text-change'

  constructor: (container, options = {}) ->
    moduleOptions = _.defaults(options.modules or {}, Scribe.DEFAULTS.modules)
    @options = _.defaults(options, Scribe.DEFAULTS)
    @options.modules = moduleOptions
    @options.id = @id = "scribe-#{Scribe.editors.length + 1}"
    @options.emitter = this
    @modules = {}
    @editor = new ScribeEditor(container, this, @options)
    Scribe.editors.push(@editor)
    themeClass = _.str.capitalize(_.str.camelize(@options.theme))
    @theme = new Scribe.Theme[themeClass](this, @options)
    _.each(@options.modules, (option, name) =>
      this.addModule(name, option)
    )

  addContainer: (className, before = false) ->
    @editor.renderer.addContainer(className, before)

  addModule: (name, options) ->
    className = _.str.capitalize(_.str.camelize(name))
    moduleClass = Scribe.Module[className]
    unless moduleClass?
      throw new Error("Cannot load #{name} module. Are you sure you included it?")
    options = {} unless _.isObject(options)  # Allow for addModule('module', true)
    options = _.defaults(options, @theme.constructor.OPTIONS[name] or {}, moduleClass.DEFAULTS or {})
    @modules[name] = new moduleClass(this, @editor.root, options)
    this.emit(Scribe.events.MODULE_INIT, name, @modules[name])
    return @modules[name]

  addStyles: (styles) ->
    @editor.renderer.addStyles(styles)

  deleteText: (index, length, options = {}) ->
    options = _.defaults(options, DEFAULT_API_OPTIONS)
    delta = Tandem.Delta.makeDeleteDelta(this.getLength(), index, length)
    @editor.applyDelta(delta, options)

  emit: (eventName, args...) ->
    super(Scribe.events.PRE_EVENT, eventName, args...)
    super(eventName, args...)
    super(Scribe.events.POST_EVENT, eventName, args...)

  focus: ->
    @editor.root.focus()

  formatText: (index, length, name, value, options) ->
    [index, length, formats, options] = buildParams(index, length, name, value, options)
    delta = Tandem.Delta.makeRetainDelta(this.getLength(), index, length, formats)
    @editor.applyDelta(delta, options)

  getContents: (index, length, options = {}) ->
    index = 0 unless index?
    length = this.getLength() - index unless length?
    ops = @editor.getDelta().getOpsAt(index, length)
    return new Tandem.Delta(0, ops)

  getHTML: ->
    return @editor.root.innerHTML

  getLength: ->
    return @editor.getDelta().endLength

  getModule: (name) ->
    return @modules[name]

  getSelection: ->
    return @editor.selection.getRange()

  getText: (index, length) ->
    return _.pluck(this.getContents(index, length).ops, 'value').join('')

  insertText: (index, text, name, value, options = {}) ->
    [index, length, formats, options] = buildParams(index, 0, name, value, options)
    delta = Tandem.Delta.makeInsertDelta(this.getLength(), index, text, formats)
    @editor.applyDelta(delta, options)

  onModuleLoad: (name, callback) ->
    if (@modules[name]) then return callback(@modules[name])
    this.on(Scribe.events.MODULE_INIT, (moduleName, module) ->
      callback(module) if moduleName == name
    )

  setContents: (delta, options = {}) ->
    options = _.defaults(options, DEFAULT_API_OPTIONS)
    delta = if _.isArray(delta) then new Tandem.Delta(0, delta) else Tandem.Delta.makeDelta(delta)
    delta.startLength = this.getLength()
    @editor.applyDelta(delta, options)

  setFormat: (name, value) ->
    format = @editor.doc.formatManager.formats[name]
    throw new Error("Unsupported format #{name} #{value}") unless format?
    format.preformat(value)

  setHTML: (html) ->
    @editor.root.innerHTML = html

  setSelection: (start, end, options = {}) ->
    if _.isNumber(start) and _.isNumber(end)
      range = new ScribeRange(@editor, start, end)
    else
      range = start
      options = end or {}
    options = _.defaults(options, DEFAULT_API_OPTIONS)
    @editor.selection.setRange(range, options.silent)

  updateContents: (delta, options = {}) ->
    options = _.defaults(options, DEFAULT_API_OPTIONS)
    @editor.applyDelta(delta, options)

  updateSelection: (options = {}) ->
    options = _.defaults(options, DEFAULT_API_OPTIONS)
    @editor.selection.update(options.silent)


module.exports = Scribe