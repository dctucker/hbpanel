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
    updating: bool
    prev_coords: tuple[x: gdouble, y: gdouble]
    tray: Tray

const title: cstring = "Homebridge"
var
  accessories: Accessories
  ui: UI

proc light_label(accessory: var Accessory): cstring =
  let brightness = accessory.service_value("Brightness").getInt()
  let on = accessory.service_value("On").getInt()
  result = cstring(
    if on == 0:
      "\n" & accessory.serviceName & "\n"
    else:
      "💡\n" & accessory.serviceName & "\n" & $brightness & "%"
  )

proc light_button(accessory: var Accessory): PButton =
  var button = button_new(accessory.light_label())
  var value: TGValue
  var pvalue: PGValue
  pvalue = value.addr.init(G_TYPE_BOOLEAN)
  button.set_property("can-focus", pvalue)
  PWidget(button).add_events(gint(BUTTON_PRESS_MASK + POINTER_MOTION_MASK + BUTTON_RELEASE_MASK))

  discard button.signal_connect("button-press-event", SIGNAL_FUNC(
    proc(widget: PWidget, event: PEventButton, accessory: var Accessory): bool {.cdecl.} =
      ui.dragged = false
      ui.dragging = accessory.addr
      ui.prev_coords = (event.x, event.y)
      return true
    ),
    accessory.addr
  )

  discard button.signal_connect("motion-notify-event", SIGNAL_FUNC(
    proc(widget: PWidget, event: PEventMotion, accessory: var Accessory): bool {.cdecl.} =
      if ui.dragging != accessory.addr:
        return false
      result = true

      ui.dragged = true
      let dy = (ui.prev_coords.y - event.y).int
      ui.prev_coords = (event.x, event.y)

      if dy == 0:
        return

      const svc_type = "Brightness"
      let new_value = accessory.service_value(svc_type).getInt() + dy

      #svc.value = some(newJInt(new_value))
      #PButton(widget).set_label(accessory.light_label())

      if ui.updating:
        return

      ui.updating = true
      let updated_accessory = put_accessory(accessory.uniqueId, svc_type, new_value)
      #echo $updated_accessory.values
      accessory.update(updated_accessory)
      PButton(widget).set_label(accessory.light_label())
      ui.updating = false
    ),
    accessory.addr
  )

  discard button.signal_connect("button-release-event", SIGNAL_FUNC(
    proc(widget: PWidget, event: PEventButton, accessory: var Accessory): bool {.cdecl.} =
      if not ui.dragged:
        const svc_type = "On"
        let new_value = 1 - accessory.service_value(svc_type).getInt()
        let updated_accessory = put_accessory(accessory.uniqueId, svc_type, new_value)
        accessory.update(updated_accessory)
        PButton(widget).set_label(accessory.light_label())
        result = true
      ui.dragging = nil
    ),
    accessory.addr
  )

  return button

proc set_accessories*(a: Accessories) =
  accessories = a

  ui.vbox = vbox_new(true, accessories.len.gint)
  for accessory in accessories.mitems():
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
