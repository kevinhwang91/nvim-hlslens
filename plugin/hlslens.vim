if exists('g:loaded_nvim_hlslens')
    finish
endif

if !has('nvim-0.5')
    echohl ErrorMsg | echo 'nvim-hlslens failed to initialize, RTFM.' | echohl None
    finish
endif

let g:loaded_nvim_hlslens = 1

highlight default link HlSearchLens WildMenu
highlight default link HlSearchLensCur IncSearch
highlight default link HlSearchCur IncSearch

lua require('hlslens').setup()
