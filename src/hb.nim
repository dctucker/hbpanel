import ./[
  hbcli, hbgui
]

when isMainModule:
  var cli: CLI
  cli.setup()

  if cli.tray or cli.panel:
    gui_main(cli)
  else:
    quit(cli.main())
