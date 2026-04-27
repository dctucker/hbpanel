import ./[hbapi, hbui]

when isMainModule:
  set_accessories(fetch_accessories())
  gui_main()
