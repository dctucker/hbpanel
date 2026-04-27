import
  ./icon,
  ./hbapi,
  glib2,
  gtk2,
  gdk2pixbuf,
  json,
  std/options

from gdk2 import
  TScreen,
  TRectangle,
  PEventFocus,
  PEventButton,
  PEventMotion,
  BUTTON_PRESS_MASK,
  BUTTON_RELEASE_MASK,
  POINTER_MOTION_MASK

nim_init()

type
  Tray = object
    icon: PStatusIcon
    menu: PMenu
    menu_items: seq[PMenuItem]
  UI = object
    panel: PWindow
    vbox: PBox
    buttons: seq[PWidget]
    dragging: ptr Accessory
    dragged: bool
    tray: Tray

const title: cstring = "Homebridge"
var
  accessories: Accessories
  ui: UI

proc light_label(accessory: Accessory): string =
  let svc_on = accessory.service("On")
  let svc_bright = accessory.service("Brightness")
  let brightness = svc_bright.value.get().getInt()
  result =
    if svc_on.value.get().getInt() == 0:
      "\n" & accessory.serviceName & "\n"
    else:
      "💡\n" & accessory.serviceName & "\n" & $brightness & "%"

proc light_button(accessory: Accessory): PButton =
  let label = cstring(accessory.light_label())
  var button = button_new(label)
  var value: TGValue
  var pvalue: PGValue
  pvalue = value.addr.init(G_TYPE_BOOLEAN)
  button.set_property("can-focus", pvalue)
  PWidget(button).add_events(gint(BUTTON_PRESS_MASK + POINTER_MOTION_MASK + BUTTON_RELEASE_MASK))

  discard button.signal_connect("button-press-event", SIGNAL_FUNC(
    proc(widget: PWidget, event: PEventButton, data: var Accessory) {.cdecl.} =
      ui.dragged = false
      ui.dragging = data.addr
    ),
    accessory.addr
  )

  discard button.signal_connect("motion-notify-event", SIGNAL_FUNC(
    proc(widget: PWidget, event: PEventMotion, data: var Accessory) {.cdecl.} =
      if ui.dragging == data.addr:
        ui.dragged = true
        #echo data.serviceName, ": ", $event.x, ",", $event.y
    ),
    accessory.addr
  )

  discard button.signal_connect("button-release-event", SIGNAL_FUNC(
    proc(widget: PWidget, event: PEventButton, accessory: var Accessory) {.cdecl.} =
      if not ui.dragged:
        const svc_type = "On"
        var svc = accessory.service(svc_type)
        let new_value = svc.toggled_value()
        let updated_accessory = put_accessory(accessory.uniqueId, svc_type, new_value)
        accessory.serviceCharacteristics = updated_accessory.serviceCharacteristics
        let label = accessory.light_label()
        PButton(widget).set_label(cstring(label))
      ui.dragging = nil
    ),
    accessory.addr
  )

  return button

proc set_accessories*(a: Accessories) =
  accessories = a

  ui.vbox = vbox_new(true, accessories.len.gint)
  for accessory in accessories:
    if accessory.`type` != "Lightbulb":
      continue
    ui.buttons.add light_button(accessory)

proc hide(window: PWindow, event: PEventFocus, ui: ref UI) {.cdecl.} =
  ui.panel.hide()

proc rect(tray: Tray): TRectangle =
  var
    scn: gdk2.TScreen
    rect: TRectangle
    ori: TOrientation
    width, height: gint
  discard tray.icon.status_icon_get_geometry(scn.addr, rect.addr, ori.addr)
  return rect

proc destroy(widget: PWidget, data: Pgpointer) {.cdecl.} =
  main_quit()

proc setup_tray(ui: var UI) =
  let uiptr = cast[pointer](ui.addr)
  var pixbuf = pixbuf_new_from_xpm_data(cast[PPchar](hbpanel_xpm.addr))
  ui.tray.icon = status_icon_new()
  ui.tray.icon.status_icon_set_from_pixbuf(pixbuf)
  ui.tray.icon.status_icon_set_title(title)
  ui.tray.menu = menu_new()

  var menu_quit = menu_item_new("Quit")
  discard menu_quit.signal_connect("activate", SIGNAL_FUNC(destroy), uiptr)
  ui.tray.menu_items.add menu_quit

  for item in ui.tray.menu_items:
    ui.tray.menu.menu_append item
    item.show()

  ui.tray.icon.status_icon_set_visible(true)

  discard ui.tray.icon.g_signal_connect("activate", G_CALLBACK(
    proc(status_icon: PStatusIcon, ui: ref UI) {.cdecl,gcsafe.} =
      if ui.panel.is_active():
        ui.panel.hide()
        return

      var
        width, height: gint
        rect: TRectangle = ui.tray.rect()

      ui.panel.show_all()
      ui.panel.get_size(width.addr, height.addr)
      ui.panel.move(rect.x - width + rect.width, rect.y + rect.height)
      ui.panel.present()
    ),
    uiptr
  )

  discard ui.tray.icon.g_signal_connect("popup_menu", G_CALLBACK(
    proc(status_icon: PStatusIcon, button: guint, activate_time: guint32, ui: ref UI) {.cdecl.} =
      ui.tray.menu.popup(nil, nil, status_icon_position_menu, status_icon, button, activate_time)
    ),
    uiptr
  )

proc setup_panel(ui: var UI) =
  ui.panel = window_new(WINDOW_TOPLEVEL)
  ui.panel.set_skip_taskbar_hint(true)
  ui.panel.set_resizable(false)
  ui.panel.set_decorated(false)
  ui.panel.set_title(title)

  for button in ui.buttons:
    ui.vbox.pack_start(button, false, false, 0)
  PContainer(ui.panel).add ui.vbox

  let uiptr = cast[pointer](ui.addr)
  discard ui.panel.signal_connect("destroy",         SIGNAL_FUNC(destroy), uiptr)
  discard ui.panel.signal_connect("focus_out_event", SIGNAL_FUNC(hide)   , uiptr)

proc setup(ui: var UI) =
  ui.setup_tray()
  ui.setup_panel()

proc gui_main* =
  ui.setup()
  main()
