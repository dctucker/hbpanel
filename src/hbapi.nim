import
  json,
  std/[
    os,
    httpclient,
    #asyncdispatch,
    strutils,
    tables,
    options,
  ]

type
  API* = object
    base_url: string
    headers: HttpHeaders

  Value* = string | BiggestInt | float | bool

  ServiceChar* = object
    aid*, iid*: int
    uuid*, `type`*, serviceType*, serviceName*, description*: string
    perms*: seq[string]
    canRead*, canWrite*, ev*: bool
    format*: string
    unit*: Option[string]
    value*: Option[JsonNode]
    minValue*, maxValue*, minStep*: Option[int]

  AccessoryInfo = Table[string, string]

  Accessory* = object
    serviceCharacteristics*: seq[ServiceChar]
    accessoryInformation*: AccessoryInfo
    aid*, iid*: int
    uuid*: string
    `type`*, humanType*, serviceName*: string
    uniqueId*: string
    values*: JsonNode

  Accessories* = seq[Accessory]

  AccessoryMap = Table[string, Accessory]

  LayoutService* = object
    uniqueId*: string
    aid*, iid*: int
    uuid*: string
    onDashboard*: Option[bool]

  Room* = object
    name*: string
    services*: seq[LayoutService]

  Layout* = seq[Room]

proc `$`*[T](opt: Option[T]): string =
  if opt.isNone:
    var t: T
    return $t
  return $opt.get()

converter toAccessoryMap*(accessories: Accessories): AccessoryMap =
  return accessories.indexBy(proc(accessory: Accessory): string = accessory.uniqueId)

proc find_service(accessory: var Accessory, svc_type: string): int =
  for i in 0..<accessory.serviceCharacteristics.len:
    if accessory.serviceCharacteristics[i].`type` == svc_type:
      return i

proc service*(accessory: var Accessory, svc_type: string): var ServiceChar =
  return accessory.serviceCharacteristics[accessory.find_service(svc_type)]

proc service_value*(accessory: var Accessory, svc_type: string): JsonNode =
  return accessory.values[svc_type]

proc update*(accessory: var Accessory, updated_accessory: Accessory) =
  accessory.serviceCharacteristics = updated_accessory.serviceCharacteristics
  accessory.values = updated_accessory.values


proc token_dir(): string = getCacheDir("hbpanel")
proc token_file(): string = token_dir() / "token.json"

proc newAPI*: API =
  const host = getEnv("HB_HOST", "homebridge.local")
  const port = getEnv("HB_PORT", "8581")
  result.base_url = "http://" & host & ":" & port
  result.headers = newHttpHeaders()
  result.headers["Content-type"] = "application/json"
  result.headers["accept"] = "*/*"

proc call(api: API, mtd: HttpMethod, endpoint: string, data: string = ""): Response =
  var client = newHttpClient(defUserAgent, headers=api.headers)
  try:
    return client.request(api.base_url & "/api/" & endpoint, mtd, body=data)
  finally:
    client.close()

proc read_token_cache*(api: API): bool =
  try:
    token_dir().createDir()
    let token_json = token_file().readFile().parseJson()
    let access_token = token_json["access_token"].getStr()
    api.headers["Authorization"] = "Bearer " & access_token
    return true
  except:
    return false

proc auth_login*(api: API): bool =
  let username = getEnv("HB_USER", getEnv("USER"))
  let password = getEnv("HB_PASS", "")
  let response = api.call(HttpPost, "auth/login", $(%*
    {
      "username": username,
      "password": password
    }
  ))
  if response.code.is2xx:
    token_file().writeFile(response.body)
    return api.read_token_cache()
  else:
    stderr.write response.code, "\n"
    for message in response.body.parseJson(){"message"}:
      stderr.write message.getStr(), "\n"
    return false

proc auth_check*(api: API): bool =
  let response = api.call(HttpGet, "auth/check")
  if not response.code.is2xx:
    return false
  return true

proc get_accessories*(api: API): Accessories =
  let response = api.call(HttpGet, "accessories")
  return response.body.parseJson().to(Accessories)

proc put_accessory_json*[T](char_type: string, value: T): JsonNode =
  %* {
    "characteristicType": char_type,
    "value": value,
  }

proc put_accessory*(api: API, unique_id: string, json: JsonNode): Accessory =
  let response = api.call(HttpPut, "accessories/" & unique_id, $json)
  return response.body.parseJson().to(Accessory)

proc put_accessory*[T: Value](api: API, unique_id, char_type: string, value: T): Accessory =
  return api.put_accessory(unique_id, put_accessory_json(char_type, value))

proc put_accessory*(api: API, unique_id, char_type: string, value: JsonNode): Accessory =
  return api.put_accessory(unique_id, put_accessory_json(char_type, value))

proc put*(api: API, accessory: Accessory, char_type: string, val: string): Accessory =
  let id = accessory.uniqueId
  let value: JsonNode = case accessory.values[char_type].kind
  of JFloat: %(val.parseFloat())
  of JInt: %(val.parseInt())
  of JBool: %(val.parseBool())
  of JNull: %nil
  of JString: %($val)
  else:
    stderr.write "Unsupported type for PUT accessories/", id, "\n"
    %val
  api.put_accessory(id, char_type, value)

proc get_layout*(api: API): Layout =
  let response = api.call(HttpGet, "accessories/layout")
  return response.body.parseJson().to(Layout)

proc attempt_login*(api: API): bool =
  if not api.read_token_cache():
    if not api.auth_login():
      return
  if not api.auth_check():
      if not api.auth_login():
        return

# attempts to login and fetch accessories
proc fetch_accessories*(api: API): Accessories =
  discard api.attempt_login()
  return api.get_accessories()

# attempts to login and fetch accessories layout
proc fetch_layout*(api: API): Layout =
  discard api.attempt_login()
  return api.get_layout()
