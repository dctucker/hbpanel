import
  ../api/hbapi,
  ../hbflags,
  ./icon,
  cairo,
  glib2,
  gtk2,
  gdk2pixbuf,
  gdk2,
  std/[
    json,
    options
  ]

when defined macos:
  import gtkmacintegration

from gdk2 import
  TScreen,
  TRectangle,
  PEventFocus,
  PEventExpose,
  PEventButton,
  PEventMotion,
  EXPOSURE_MASK,
  BUTTON_PRESS_MASK,
  BUTTON_RELEASE_MASK,
  POINTER_MOTION_MASK

type
  Tray = object
    icon: PStatusIcon
    menu: PMenu
    menu_items: seq[PMenuItem]
  UI = object
    flags: Flags
    api: API
    timer: guint
    panel: gtk2.PWindow
    vbox: PBox
    hbox: PBox
    table: PTable
    quit_button: PWidget
    buttons: seq[PWidget]
    dragging: ptr Accessory
    dragged: bool
    updating: bool
    prev_coords: tuple[x: gdouble, y: gdouble]
    next_update: Option[JsonNode]
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

proc on_signal(obj: PObject, sig: cstring, fn: TSignalFunc, data: gpointer) =
  if signal_connect(obj, sig, fn, data) == 0:
    stderr.write "Unable to connect signal " & $sig & "\n"

proc on_signal(obj: PGObject, sig: cstring, fn: TGCallback, data: gpointer) =
  if g_signal_connect(obj, sig, fn, data) == 0:
    stderr.write "Unable to connect signal " & $sig & "\n"

proc disable_focus(widget: PWidget) =
  var value: TGValue
  var pvalue: PGValue
  pvalue = value.addr.init(G_TYPE_BOOLEAN)
  widget.set_property("can-focus", pvalue)

const gtklib = "libgtk-x11-2.0.so(|.0)"
proc get_window*(widget: PWidget): gtk2.PWindow {.cdecl, dynlib: gtklib, importc: "gtk_widget_get_window".}

proc light_button(accessory: var Accessory): PWidget =
  var button = button_new()
  button.add_events (EXPOSURE_MASK + BUTTON_PRESS_MASK + POINTER_MOTION_MASK + BUTTON_RELEASE_MASK).gint
  button.set_size_request(100, 80)

  button.on_signal("expose-event", SIGNAL_FUNC(
    proc(widget: PWidget, event: PEventExpose, accessory: var Accessory): gboolean {.cdecl.} =
      var win = DRAWABLE(widget.get_window())
      var cr = win.cairo_create()
      #let label = accessory.light_label()
      #var win = PDrawable(widget.window)
      #let gc = widget.style.fg_gc[widget.state]
      #win.line(gc, 0.gint, 20.gint, 20.gint, 30.gint)

      #let display = widget.get_display()
      #let font = display.font_from_description_for_display(widget.style.font_desc)
      #win.text(font, gc, 0.gint, 10.gint, label, label.len.gint)

      cr.move_to(20, 20)
      cr.show_text(accessory.light_label())
      cr.destroy()
    ),
    accessory.addr
  )

  button.on_signal("button-press-event", SIGNAL_FUNC(
    proc(widget: PWidget, event: PEventButton, accessory: var Accessory): bool {.cdecl.} =
      ui.dragged = false
      ui.dragging = accessory.addr
      ui.prev_coords = (event.x, event.y)
      return true
    ),
    accessory.addr
  )

  button.on_signal("motion-notify-event", SIGNAL_FUNC(
    proc(widget: PWidget, event: PEventMotion, accessory: var Accessory): bool {.cdecl.} =
      if ui.dragging != accessory.addr:
        return false
      result = true

      ui.dragged = true
      let dy = (ui.prev_coords.y - event.y).int
      if dy.abs < 2:
        return
      ui.prev_coords = (event.x, event.y)

      const svc_type = "Brightness"
      let service = accessory.service(svc_type)
      let max_value = service.maxValue.get()
      let min_value = service.minValue.get()
      let value = accessory.values[svc_type].getInt() #service.value.get().getInt()
      let new_value = (value + dy div 2).min(max_value).max(min_value)

      accessory.values[svc_type] = newJInt(new_value)
      PButton(widget).set_label(accessory.light_label())

      ui.next_update = some(put_accessory_json(svc_type, new_value))
    ),
    accessory.addr
  )

  button.on_signal("button-release-event", SIGNAL_FUNC(
    proc(widget: PWidget, event: PEventButton, accessory: var Accessory): bool {.cdecl.} =
      if not ui.dragged:
        const svc_type = "On"
        let new_value = 1 - accessory.service_value(svc_type).getInt()
        let updated_accessory = ui.api.put_accessory(accessory.uniqueId, svc_type, new_value)
        accessory.update(updated_accessory)
        PButton(widget).set_label(accessory.light_label())
        result = true
      ui.dragging = nil
    ),
    accessory.addr
  )

  return button

proc set_accessories*(ui: var UI, a: Accessories) =
  accessories = a

  for accessory in accessories.mitems():
    if accessory.`type` != "Lightbulb":
      continue
    ui.buttons.add light_button(accessory)

proc hide(window: gtk2.PWindow, event: PEventFocus, ui: ref UI) {.cdecl.} =
  ui.panel.hide()
  if ui.flags.panel:
    main_quit()

proc rect(tray: Tray): gdk2.TRectangle =
  var
    scn: gdk2.TScreen
    rect: gdk2.TRectangle
    ori: TOrientation
  discard tray.icon.status_icon_get_geometry(scn.addr, rect.addr, ori.addr)
  return rect

proc destroy(widget: PWidget, data: Pgpointer) {.cdecl.} =
  main_quit()

proc show_panel(ui: var UI) =
  ui.panel.show_all()
  ui.panel.present()

proc setup_tray(ui: var UI) =
  let uiptr = cast[pointer](ui.addr)
  var pixbuf = pixbuf_new_from_xpm_data(cast[PPchar](hbpanel_xpm.addr))
  ui.tray.icon = status_icon_new()
  ui.tray.icon.status_icon_set_from_pixbuf(pixbuf)
  ui.tray.icon.status_icon_set_title(title)
  ui.tray.menu = menu_new()

  var menu_quit = menu_item_new("Quit")
  menu_quit.on_signal("activate", SIGNAL_FUNC(destroy), uiptr)
  ui.tray.menu_items.add menu_quit

  for item in ui.tray.menu_items:
    ui.tray.menu.menu_append item
    item.show()

  ui.tray.icon.status_icon_set_visible(true)

  ui.tray.icon.on_signal("activate", G_CALLBACK(
    proc(status_icon: PStatusIcon, ui: var UI) {.cdecl,gcsafe.} =
      if ui.panel.is_active():
        ui.panel.hide()
        return

      var
        width, height: gint
        rect = ui.tray.rect()

      ui.show_panel()
      ui.panel.get_size(width.addr, height.addr)
      ui.panel.move(rect.x - width + rect.width, rect.y + rect.height)
    ),
    uiptr
  )

  ui.tray.icon.on_signal("popup_menu", G_CALLBACK(
    proc(status_icon: PStatusIcon, button: guint, activate_time: guint32, ui: ref UI) {.cdecl.} =
      ui.tray.menu.popup(nil, nil, status_icon_position_menu, status_icon, button, activate_time)
    ),
    uiptr
  )

proc add_to(widget: PWidget, container: PContainer) =
  container.add widget

proc setup_panel(ui: var UI) =
  ui.panel = window_new(WINDOW_TOPLEVEL)
  ui.panel.set_skip_taskbar_hint(true)
  ui.panel.set_resizable(false)
  ui.panel.set_decorated(false)
  ui.panel.set_title(title)
  ui.panel.set_border_width 4

  ui.vbox = vbox_new(false, 4)
  block:
    var hbox = hbox_new(false, 0)
    ui.hbox = hbox
    block:
      ui.quit_button = button_new("✕")
      ui.quit_button.on_signal("clicked", SIGNAL_FUNC(destroy), ui.addr)
      ui.quit_button.set_size_request(28, 28)
      ui.quit_button.disable_focus
      ui.hbox.pack_end ui.quit_button, false, false, 0
    ui.hbox.add_to ui.vbox

    ui.table = table_new((1 + ui.buttons.len.guint) div 2, 2, true)
    ui.table.set_row_spacings 8
    ui.table.set_col_spacings 8
    var i, j: guint
    for button in ui.buttons:
      ui.table.attach_defaults(button, j, j+1, i, i+1)
      j += 1
      if j >= 2:
        j = 0
        i += 1
    ui.table.add_to ui.vbox
  ui.vbox.add_to ui.panel

  ui.panel.on_signal("destroy",         SIGNAL_FUNC(destroy), ui.addr)
  ui.panel.on_signal("focus_out_event", SIGNAL_FUNC(hide)   , ui.addr)

proc timer_proc(ui: var UI): gboolean {.cdecl,gcsafe.} =
  if ui.next_update.isSome:
    let json = ui.next_update.get()
    ui.next_update = none(JsonNode)
    var accessory = ui.dragging[]
    let updated_accessory = ui.api.put_accessory(accessory.uniqueId, json)
    accessory.update(updated_accessory)
  return true

proc setup_timer(ui: var UI) =
  ui.timer = timeout_add(500, cast[gtk2.TFunction](timerproc), ui.addr)

proc setup(ui: var UI) =
  ui.setup_panel()
  ui.setup_timer()

  if ui.flags.tray:
    ui.setup_tray()

  if ui.flags.panel:
    ui.show_panel()

proc newUI(flags: Flags): UI =
  result.flags = flags
  result.api = newAPI()

proc gui_main*(flags: Flags): int =
  ui = newUI(flags)
  nim_init()
  let accessories = ui.api.fetch_accessories()
  ui.set_accessories(accessories)
  ui.setup()
  main()

when isMainModule:
  quit gui_main(newFlags())
