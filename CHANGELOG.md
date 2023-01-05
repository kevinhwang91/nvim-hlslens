# Changelog

## [1.0.0] - 2022-12-10

### Features

#### Cmdline

- Support incsearch for `smagic` and `snomagic`
- Highlight selection for `\%V`

#### API

- Add qf API `exportLastSearchToQuickfix` [#49]

#### External

- Support nvim-ufo [#43]

### Bug Fixes

#### WFFI

- Add `rmm_matchcol` field to `regmmatch_T` in nightly

#### Miscellaneous

- Listen `v:hlsearch` value, `:noh<CR>` remapping is not necessary
- [**breaking**] Bump Neovim to 0.6.1

### Performance

- Use throttle and debounce to improve performance

## [0.2.0] - 2022-09-11

Release the stable version, will rework some tasks.

### Features

- Improve `calm_down` option
- Respect foldopen option while searching
- Use FFI to build position index
- Support `;` offset
- Support ffi for Windows

### Performance

- Improve performance while moving cursor
- Use `searchcount` to get better performance while searching

## [0.1.0]

- rename `HlSearchCur` to `HlSearchNear`.
- rename `HlSearchLensCur` to `HlSearchLensNear`.
- replace `override_line_lens` with `override_lens`.
- add `HlSearchFloat` highlight the nearest text for the floating window.
- add `nearest_only` option to add lens for the nearest instance and ignore others.
- add `nearest_float_when` and `float_shadow_blend` options for displaying nearest instance lens
- with floating window.
- add `virt_priority` option to specify the priority of `nvim_buf_set_extmark`.
- add `enable_incsearch` option to display the current matched instance lens while searching.
- support `/s` and `/e` offsets for search, but don't support offset number.
