import ./[
  hbflags, hbcli, hbgui
]

when isMainModule:
  let flags = newFlags()

  if flags.tray or flags.panel:
    quit gui_main(flags)
  else:
    quit cli_main(flags)
