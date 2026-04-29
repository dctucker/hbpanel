import
  json,
  std/[
    os,
    httpclient,
    #asyncdispatch,
    tables,
    options,
  ]

type
  API* = object
    base_url: string
    headers: HttpHeaders

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

proc `$`*[T](opt: Option[T]): string = $opt.get()

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


const token_file = getCacheDir("hbpanel") / "token.json"

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
    let token_json = readFile(token_file).parseJson()
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
    writeFile(token_file, response.body)
    return api.read_token_cache()
  else:
    echo response.code
    echo response.body
    return false

proc auth_check*(api: API): bool =
  let response = api.call(HttpGet, "auth/check")
  if not response.code.is2xx:
    return false
  return true

proc get_accessories*(api: API): Accessories =
  let response = api.call(HttpGet, "accessories")
  return response.body.parseJson().to(Accessories)

proc put_accessory_json*[T: string | int](char_type: string, value: T): JsonNode =
  %* {
    "characteristicType": char_type,
    "value": value,
  }

proc put_accessory*(api: API, unique_id: string, json: JsonNode): Accessory =
  let response = api.call(HttpPut, "accessories/" & unique_id, $json)
  return response.body.parseJson().to(Accessory)

proc put_accessory*[T](api: API, unique_id, char_type: string, value: T): Accessory =
  return api.put_accessory(unique_id, put_accessory_json(char_type, value))

proc get_accessories_layout*(api: API) =
  let response = api.call(HttpGet, "accessories/layout")
  echo response.body

# attempts to login and fetch accessories
proc fetch_accessories*(api: API): Accessories =
  if not api.read_token_cache():
    if not api.auth_login():
      return
  if not api.auth_check():
      if not api.auth_login():
        return

  #get_accessories_layout()
  return api.get_accessories()

