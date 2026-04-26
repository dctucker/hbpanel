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

type
  UI = object
    window: PWindow
    vbox: PBox
    buttons: seq[PWidget]
    tray_icon: PStatusIcon
    tray_menu: PMenu
    tray_menu_quit: PMenuItem

var
  accessories: Accessories
  ui: UI

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

  ui.vbox = vbox_new(true, accessories.len.gint)
  for accessory in accessories:
    if accessory.`type` != "Lightbulb":
      continue
    let label = cstring(accessory.light_label())
    var button = button_new(label)
    ui.buttons.add button
    discard button.signal_connect(
      "clicked",
      SIGNAL_FUNC(hbui.click_accessory),
      accessory.addr
    )

proc hide() {.cdecl.} =
  ui.window.hide()

proc rect(tray_icon: PStatusIcon): TRectangle =
  var
    scn: gdk2.TScreen
    rect: TRectangle
    ori: TOrientation
    width, height: gint
  discard tray_icon.status_icon_get_geometry(scn.addr, rect.addr, ori.addr)
  return rect

proc popup_menu_pos(menu: PMenu, x: Pgint, y: Pgint, push_in: Pgboolean, data: gpointer) {.cdecl.} =
  let ui = cast[ref UI](data)
  let rect = ui.tray_icon.rect()
  x[] = rect.x
  y[] = rect.y + rect.height

proc popup_menu(tray_icon: PStatusIcon, button: guint, activate_time: guint32, ui: ref UI) {.cdecl.} =
  ui.tray_menu.popup(nil, nil, status_icon_position_menu, tray_icon, button, activate_time)

proc tray_activate(tray_icon: PStatusIcon, ui: ref UI) {.cdecl,gcsafe.} =
  if ui.window.is_active():
    ui.window.hide()
    return

  var
    rect: TRectangle
    width, height: gint

  rect = ui.tray_icon.rect()

  ui.window.show_all()
  ui.window.get_size(width.addr, height.addr)

  ui.window.move(rect.x - width + rect.width, rect.y + rect.height)
  ui.window.present()

proc setup_tray(ui: var UI) =
  var pixbuf = pixbuf_new_from_xpm_data(cast[PPchar](hbpanel_xpm.addr))
  ui.tray_icon = status_icon_new()
  ui.tray_icon.status_icon_set_from_pixbuf(pixbuf)
  ui.tray_menu = menu_new()
  ui.tray_menu_quit = menu_item_new("Quit")
  ui.tray_menu.menu_append ui.tray_menu_quit
  ui.tray_menu_quit.show()

  let uiptr = cast[pointer](ui.addr)
  discard ui.tray_icon.g_signal_connect("activate", G_CALLBACK(hbui.tray_activate), uiptr)
  discard ui.tray_icon.g_signal_connect("popup_menu", G_CALLBACK(hbui.popup_menu), uiptr)
  discard ui.tray_menu_quit.signal_connect("activate", SIGNAL_FUNC(hbui.destroy), nil)

  ui.tray_icon.status_icon_set_visible(true)

proc setup_panel(ui: var UI) =
  const title: cstring = "Accessories"
  ui.window = window_new(WINDOW_TOPLEVEL)
  ui.window.set_skip_taskbar_hint(true)
  ui.window.set_resizable(false)
  ui.window.set_decorated(false)
  ui.window.set_title(title)

  for button in ui.buttons:
    ui.vbox.pack_start(button, false, false, 0)
  PContainer(ui.window).add ui.vbox

  discard ui.window.signal_connect("destroy", SIGNAL_FUNC(hbui.destroy), nil)
  discard ui.window.signal_connect("focus_out_event", SIGNAL_FUNC(hbui.hide), nil)

proc setup(ui: var UI) =
  ui.setup_tray()
  ui.setup_panel()

proc gui_main* =
  ui.setup()
  main()
