import std/parseopt

type
  Args* = tuple
    accessory, service, value: string
  Flags* = object
    list*, layout*, panel*, tray*, verbose*, usage*: bool
    args*: Args

converter toArgs*(args: seq[string]): Args =
  if args.len > 0: result.accessory = args[0]
  if args.len > 1: result.service = args[1]
  if args.len > 2: result.value = args[2]

proc newFlags*: Flags =
  var args: seq[string]
  var p = initOptParser()
  for kind, key, value in p.getOpt():
    case kind
    of cmdArgument:
      args.add key
    of cmdShortOption, cmdLongOption:
      case key
      of "h", "help":
        result.usage = true
      of "l", "list":
        result.list = true
      of "L", "layout":
        result.layout = true
      of "p", "panel":
        result.panel = true
      of "t", "tray":
        result.tray = true
      of "v", "verbose":
        result.verbose = true
    of cmdEnd:
      assert(false)
  result.args = args
