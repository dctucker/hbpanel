import
  json,
  std/[
    os,
    httpclient,
    #asyncdispatch,
    tables,
    options,
  ],
  system/iterators

type
  ServiceChar = object
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
let base_url = "http://homebridge.local:8581"
let headers = newHttpHeaders()
headers["Content-type"] = "application/json"
headers["accept"] = "*/*"

proc hb_api(mtd: HttpMethod, endpoint: string, data: string = ""): Response =
  var client = newHttpClient(defUserAgent, headers=headers)
  try:
    return client.request(base_url & "/api/" & endpoint, mtd, body=data)
  finally:
    client.close()

proc read_token_cache*: bool =
  try:
    let token_json = readFile(token_file).parseJson()
    let access_token = token_json["access_token"].getStr()
    headers["Authorization"] = "Bearer " & access_token
    return true
  except:
    return false

proc auth_login*: bool =
  let username = getEnv("HB_USER", getEnv("USER"))
  let password = getEnv("HB_PASS", "")
  let response = hb_api(HttpPost, "auth/login", $(%*
    {
      "username": username,
      "password": password
    }
  ))
  if response.code.is2xx:
    writeFile(token_file, response.body)
    return read_token_cache()
  else:
    echo response.code
    echo response.body
    return false

proc auth_check*: bool =
  let response = hb_api(HttpGet, "auth/check")
  if not response.code.is2xx:
    return false
  return true

proc get_accessories*: Accessories =
  let response = hb_api(HttpGet, "accessories")
  return response.body.parseJson().to(Accessories)

proc put_accessory*(unique_id, char_type: string, value: string): Accessory =
  let response = hb_api(HttpPut, "accessories/" & unique_id, $(%*
    {
      "characteristicType": char_type,
      "value": value,
    }
  ))
  return response.body.parseJson().to(Accessory)

proc put_accessory*(unique_id, char_type: string, value: int): Accessory =
  let response = hb_api(HttpPut, "accessories/" & unique_id, $(%*
    {
      "characteristicType": char_type,
      "value": value,
    }
  ))
  return response.body.parseJson().to(Accessory)

proc get_accessories_layout* =
  let response = hb_api(HttpGet, "accessories/layout")
  echo response.body

# attempts to login and fetch accessories
proc fetch_accessories*: Accessories =
  if not read_token_cache():
    if not auth_login():
      return
  if not auth_check():
      if not auth_login():
        return

  #get_accessories_layout()
  return get_accessories()

