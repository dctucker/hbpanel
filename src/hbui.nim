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
  tray_menu: PMenu
  tray_menu_quit: PMenuItem
  vbox: PBox

proc destroy(widget: PWidget, data: Pgpointer) {.cdecl.} =
  main_quit()

proc light_label(accessory: Accessory): string =
  let svc_on = accessory.service("On")
  let svc_bright = accessory.service("Brightness")
  let brightness = svc_bright.value.get().getInt()
  result =
    if svc_on.value.get().getInt() == 0:
      "  " & accessory.serviceName & "      "
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

proc hide() {.cdecl.} =
  window.hide()

proc tray_rect(): TRectangle =
  var
    scn: gdk2.TScreen
    rect: TRectangle
    ori: TOrientation
    width, height: gint

  discard tray_icon.status_icon_get_geometry(scn.addr, rect.addr, ori.addr)
  return rect

proc tray_activate() {.cdecl.} =
  if window.is_active():
    hide()
    return

  var
    rect: TRectangle
    width, height: gint

  rect = tray_rect()

  window.show_all()
  window.get_size(width.addr, height.addr)

  window.move(rect.x - width + rect.width, rect.y + rect.height)
  window.present()

proc popup_menu_pos(menu: PMenu, x: Pgint, y: Pgint, push_in: Pgboolean, user_data: gpointer) {.cdecl.} =
  let rect = tray_rect()
  x[] = rect.x
  y[] = rect.y + rect.height

proc popup_menu {.cdecl.} =
  #tray_icon.status_icon_position_menu(0, 0)
  tray_menu_quit.show()
  tray_menu.popup(nil, nil, popup_menu_pos, nil, 0, get_current_event_time())
  #status_icon_position_menu(tray_menu, 0, 0, true, nil)

proc gui_main* =
  const title: cstring = "Accessories"
  var pixbuf = pixbuf_new_from_xpm_data(cast[PPchar](hbpanel_xpm.addr))
  tray_icon = status_icon_new()
  tray_icon.status_icon_set_from_pixbuf(pixbuf)
  tray_menu = menu_new()
  tray_menu_quit = menu_item_new("Quit")
  tray_menu.menu_append tray_menu_quit

  window = window_new(WINDOW_TOPLEVEL)
  window.set_resizable(false)
  window.set_decorated(false)
  #window.set_title(title)

  for button in buttons:
    vbox.pack_start(button, false, false, 0)

  PContainer(window).add vbox

  discard window.signal_connect("destroy", SIGNAL_FUNC(hbui.destroy), nil)
  discard window.signal_connect("focus_out_event", SIGNAL_FUNC(hbui.hide), nil)
  discard tray_icon.g_signal_connect("activate", hbui.tray_activate, nil)
  discard tray_icon.g_signal_connect("popup_menu", hbui.popup_menu, nil)
  discard tray_menu_quit.signal_connect("activate", SIGNAL_FUNC(hbui.destroy), nil)

  tray_icon.status_icon_set_visible(true)
  main()
