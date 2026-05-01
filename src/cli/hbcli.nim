import
  std/[
    json,
    strformat,
    sequtils,
    tables
  ],
  ../api/hbapi,
  ../hbflags

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
    flags: Flags
    api: API

proc args(cli: CLI): Args = cli.flags.args

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
    if cli.flags.verbose:
      stdout.write "  (", accessory.humanType, ")"
      stdout.write " ", accessory.uniqueId
    stdout.write "\n"

proc list(cli: CLI, services: seq[ServiceChar]) =
  #let len_1 = services.map(proc(s: ServiceChar): int = s.`type`.len).max
  for service in services:
    stdout.write service.`type`
    if cli.flags.verbose:
      stdout.write " = ", $service.value
    stdout.write "\n"

proc do_put(cli: CLI, accessory: Accessory): int =
  let accessory_id = accessory.uniqueId
  discard cli.api.put(accessory, cli.args.service, cli.args.value)

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

  cli.do_put(accessory[])

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

proc newCLI(flags: Flags): CLI =
  result.flags = flags
  if flags.tray:
    stderr.write "not supported in CLI mode: --tray\n"
  elif flags.panel:
    stderr.write "not supported in CLI mode: --panel\n"
  else:
    result.api = newAPI()

proc cli_main*(flags: Flags): int =
  var cli = newCLI(flags)
  if cli.flags.tray or cli.flags.panel:
    return 2
  if cli.flags.usage:
    return cli.do_usage()
  if cli.flags.layout:
    return cli.do_layout()
  return cli.do_list()

when isMainModule:
  quit cli_main(newFlags())
