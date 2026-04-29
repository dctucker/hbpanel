import ./[
  hbcli,
  hbui
]

when isMainModule:
  var cli: CLI
  cli.setup()

  if cli.tray:
    gui_main()
  else:
    quit(cli.main())
