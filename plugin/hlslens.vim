" Actually, want to remove this file, but it will break change :(
if exists('g:loaded_nvim_hlslens')
    finish
endif

if !has('nvim-0.6.1')
    call v:lua.vim.notify('nvim-hlslens failed to initialize, RTFM.')
    finish
endif

let g:loaded_nvim_hlslens = 1

let s:lua_loc = expand("<sfile>:h:r") . "./../lua"
exe "lua package.path = package.path .. ';" . s:lua_loc . "'"

lua vim.schedule(function() require('hlslens').setup(nil, true) end)

