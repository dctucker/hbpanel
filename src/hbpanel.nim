import ./[hbapi, hbui]

proc fetch_accessories: Accessories =
  if not read_token_cache():
    if not auth_login():
      return
  if not auth_check():
      if not auth_login():
        return

  #get_accessories_layout()
  return get_accessories()

when isMainModule:
  set_accessories(fetch_accessories())
  gui_main()
