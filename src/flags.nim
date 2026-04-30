import std/parseopt

type
  Args* = tuple
    accessory, service, value: string
  Flags* = object of RootObj
    list*, layout*, panel*, tray*, verbose*, usage*: bool
    args*: Args

converter toArgs*(args: seq[string]): Args =
  if args.len > 0: result.accessory = args[0]
  if args.len > 1: result.service = args[1]
  if args.len > 2: result.value = args[2]

proc setup*(flags: var Flags) =
  var args: seq[string]
  var p = initOptParser()
  for kind, key, value in p.getOpt():
    case kind
    of cmdArgument:
      args.add key
    of cmdShortOption, cmdLongOption:
      case key
      of "h", "help":
        flags.usage = true
      of "l", "list":
        flags.list = true
      of "L", "layout":
        flags.layout = true
      of "p", "panel":
        flags.panel = true
      of "t", "tray":
        flags.tray = true
      of "v", "verbose":
        flags.verbose = true
    of cmdEnd:
      assert(false)
  flags.list = true
  flags.args = args
