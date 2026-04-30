import
  std/[
    json,
    parseopt,
    strformat,
    sequtils,
    tables
  ],
  ./hbapi

const USAGE_MESSAGE = """
Usage: hb [flags] [accessory] [key] [value]

FLAGS
  -l, --list       List accessories or keys
  -L, --layout     Show the accessories layout
  -p, --panel      Display the panel GUI
  -t, --tray       Launch as a system-tray icon
  -v, --verbose    Print verbose output
  -h, --help       Show this message

ENVIRONMENT VARIABLES
  HB_HOST          Hostname        (default: homebridge.local)
  HB_PORT          TCP port        (default: 8581)
  HB_USER          Login user name (default: $USER)
  HB_PASS          Login password
"""

type
  CLI* = object
    api: API
    args: Args
    list*, layout*, panel*, tray*, verbose*, usage*: bool

  Args = tuple
    accessory, service, value: string

converter toArgs(args: seq[string]): Args =
  if args.len > 0: result.accessory = args[0]
  if args.len > 1: result.service = args[1]
  if args.len > 2: result.value = args[2]

proc find(haystack: Accessories, needle: string): ptr Accessory =
  for accessory in haystack:
    if accessory.serviceName == needle:
      return accessory.addr

proc find(haystack: seq[ServiceChar], needle: string): ptr ServiceChar =
  for service in haystack:
    if service.`type` == needle:
      return service.addr

proc list(cli: CLI, accessories: Accessories) =
  let len_1 = accessories.map(proc(a: Accessory): int = a.serviceName.len).max
  for accessory in accessories:
    stdout.write accessory.serviceName.alignString(len_1)
    if cli.verbose:
      stdout.write "  (", accessory.humanType, ")"
      stdout.write " ", accessory.uniqueId
    stdout.write "\n"

proc list(cli: CLI, services: seq[ServiceChar]) =
  #let len_1 = services.map(proc(s: ServiceChar): int = s.`type`.len).max
  for service in services:
    stdout.write service.`type`
    if cli.verbose:
      stdout.write " = ", $service.value
    stdout.write "\n"

proc do_list(cli: CLI): int =
  let accessories = cli.api.fetch_accessories()
  if accessories.len == 0:
    stderr.write "Unable to load accessories.\n"
    return 1

  if cli.args.accessory.len == 0:
    cli.list accessories
    return

  let accessory = accessories.find(cli.args.accessory)
  if accessory == nil:
    stderr.write fmt"Accessory '{cli.args.accessory}' not found.", "\n"
    return 1

  if cli.args.service.len == 0:
    cli.list accessory.serviceCharacteristics
    return

  let service = accessory.serviceCharacteristics.find(cli.args.service)
  if service == nil:
    stderr.write fmt"Service '{cli.args.service}' not found.", "\n"
    return 1

  if cli.args.value.len == 0:
    stdout.write service.value, "\n"
    return

  let accessory_id = accessory.uniqueId
  discard cli.api.put_accessory(accessory_id, cli.args.service, cli.args.value)

proc do_layout(cli: CLI): int =
  let layout = cli.api.fetch_layout()
  let accessories: Table[string, Accessory] = cli.api.fetch_accessories()
  for room in layout:
    stdout.write room.name, "\n"
    for svc in room.services:
      if accessories.hasKey(svc.uniqueId):
        let accessory = accessories[svc.uniqueId]
        let name = accessory.serviceName
        stdout.write "    ", name, "\n"
      else:
        continue
  return

proc do_usage(cli: CLI): int =
  echo USAGE_MESSAGE
  return 2

proc setup*(cli: var CLI) =
  var args: seq[string]
  var p = initOptParser()
  for kind, key, value in p.getOpt():
    case kind
    of cmdArgument:
      args.add key
    of cmdShortOption, cmdLongOption:
      case key
      of "h", "help":
        cli.usage = true
      of "l", "list":
        cli.list = true
      of "L", "layout":
        cli.layout = true
      of "p", "panel":
        cli.panel = true
      of "t", "tray":
        cli.tray = true
      of "v", "verbose":
        cli.verbose = true
    of cmdEnd:
      assert(false)
  cli.list = true
  cli.args = args

proc main*(cli: var CLI): int =
  cli.api = newAPI()
  if cli.usage:
    return cli.do_usage()
  if cli.layout:
    return cli.do_layout()
  if cli.list:
    return cli.do_list()
