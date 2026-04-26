import
  ./icon,
  ./hbapi,
  glib2,
  gtk2,
  gdk2pixbuf,
  json,
  std/options

from gdk2 import TScreen, TRectangle

nim_init()

var
  accessories: Accessories
  window: PWindow
  buttons: seq[PWidget]
  tray_icon: PStatusIcon
  vbox: PBox

proc destroy(widget: PWidget, data: Pgpointer) {.cdecl.} =
  main_quit()

proc light_label(accessory: Accessory): string =
  let svc_on = accessory.service("On")
  let svc_bright = accessory.service("Brightness")
  let brightness = svc_bright.value.get().getInt()
  result =
    if svc_on.value.get().getInt() == 0:
      accessory.serviceName
    else:
      "💡" & accessory.serviceName & " (" & $brightness & ")"

proc click_accessory(widget: PWidget, accessory: var Accessory) {.cdecl.} =
  const svc_type = "On"
  var svc = accessory.service(svc_type)
  let new_value = svc.toggled_value()
  let updated_accessory = put_accessory(accessory.uniqueId, svc_type, new_value)
  accessory.serviceCharacteristics = updated_accessory.serviceCharacteristics
  let label = accessory.light_label()
  PButton(widget).set_label(cstring(label))

proc set_accessories*(a: Accessories) =
  accessories = a

  vbox = vbox_new(true, accessories.len.gint)
  for accessory in accessories:
    if accessory.`type` != "Lightbulb":
      continue
    let label = cstring(accessory.light_label())
    var button = button_new(label)
    buttons.add button
    discard button.signal_connect(
      "clicked",
      SIGNAL_FUNC(hbui.click_accessory),
      accessory.addr
    )

proc tray_activate() {.cdecl.} =
  var
    scn: gdk2.TScreen
    rect: TRectangle
    ori: TOrientation
    width, height: gint

  discard tray_icon.status_icon_get_geometry(scn.addr, rect.addr, ori.addr)

  window.show_all()
  window.get_size(width.addr, height.addr)

  window.move(rect.x - width + rect.width, rect.y + rect.height)
  window.present()

proc hide() {.cdecl.} =
  window.hide()

proc gui_main* =
  const title: cstring = "Accessories"
  var pixbuf = pixbuf_new_from_xpm_data(cast[PPchar](hbpanel_xpm.addr))
  tray_icon = status_icon_new()
  tray_icon.status_icon_set_from_pixbuf(pixbuf)

  window = window_new(WINDOW_TOPLEVEL)
  #window.set_resizable(false)
  window.set_title(title)

  for button in buttons:
    vbox.pack_start(button, false, false, 0)

  PContainer(window).add vbox

  discard window.signal_connect("destroy", SIGNAL_FUNC(hbui.destroy), nil)
  discard window.signal_connect("focus_out_event", SIGNAL_FUNC(hbui.hide), nil)
  discard tray_icon.g_signal_connect("activate", hbui.tray_activate, nil)
  tray_icon.status_icon_set_visible(true)
  main()
