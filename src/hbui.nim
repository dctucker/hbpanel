import ./hbapi
import glib2, gtk2

nim_init()

var
  accessories: Accessories
  window: PWindow
  buttons: seq[PWidget]
  vbox: PBox

proc destroy(widget: PWidget, data: Pgpointer) {.cdecl.} =
  main_quit()

proc click_accessory(widget: PWidget, accessory: var Accessory) {.cdecl.} =
  const svc_type = "On"
  var svc = accessory.service(svc_type)
  let new_value = svc.toggled_value()
  let updated_accessory = put_accessory(accessory.uniqueId, svc_type, new_value)
  accessory.serviceCharacteristics = updated_accessory.serviceCharacteristics

proc set_accessories*(a: Accessories) =
  accessories = a

  vbox = vbox_new(true, accessories.len.gint)
  for accessory in accessories:
    let name = cstring(accessory.serviceName)
    var button = button_new(name)
    buttons.add button
    discard button.signal_connect(
      "clicked",
      SIGNAL_FUNC(hbui.click_accessory),
      accessory.addr
    )

proc gui_main* =
  const title: cstring = "Accessories"
  window = window_new(WINDOW_TOPLEVEL)
  window.set_title(title)

  for button in buttons:
    vbox.pack_start(button, false, false, 0)

  PContainer(window).add vbox

  discard signal_connect(window, "destroy", SIGNAL_FUNC(hbui.destroy), nil)
  window.show_all()
  main()
