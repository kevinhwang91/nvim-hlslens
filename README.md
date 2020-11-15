# Hlslens

Hlslens helps you better glance searched information, seamlessly jump matched instances.

<p align="center">
    <img width="864px" src=https://user-images.githubusercontent.com/17562139/102744299-7d386200-4394-11eb-9c86-e12e228a76e8.gif>
</p>

## Features

- Fully customizable style of virtual text
- Display virtual text dynamicly while cursor is moving
- Clear highlighting and virtual text when cursor is out of range

## Quickstart

### Requirements

- Neovim [nightly](https://github.com/neovim/neovim#install-from-source)

### Installation

Install nvim-hlslens with your favorite plugin manager! For instance: [Vim-plug](https://github.com/junegunn/vim-plug):

```vim
Plug 'kevinhwang91/nvim-hlslens'
```

### Minimal configuration

```vim
Plug 'kevinhwang91/nvim-hlslens'

" below code after `call plug#end()`, make sure 'hlslens' have been loaded in lua path
lua require('hlslens').setup()
noremap <silent> n <Cmd>execute('normal! ' . v:count1 . 'n')<CR>
            \<Cmd>lua require('hlslens').start()<CR>
noremap <silent> N <Cmd>execute('normal! ' . v:count1 . 'N')<CR>
            \<Cmd>lua require('hlslens').start()<CR>
noremap * *<Cmd>lua require('hlslens').start()<CR>
noremap # #<Cmd>lua require('hlslens').start()<CR>
noremap g* g*<Cmd>lua require('hlslens').start()<CR>
noremap g# g#<Cmd>lua require('hlslens').start()<CR>

" use : instead of <Cmd>
nnoremap <silent> <leader>l :nohlsearch<CR>
```

#### 3 ways to start hlslens

1. Press `/` or `?` to search text
2. Press `n` or `N` to jump to the instance matched by last pattern
3. Press `*`, `#`, `g*` or `g#` to search word nearest to the cursor

> run ex command :help search-commands for more information.

#### Stop hlslens

In `CmdlineLeave` event, hlslens will listen whether `nohlsearch` is entered.

1. Run ex command `nohlsearch`
2. Map key to `:nohlsearch`, make sure that to use `:` instead of `<Cmd>`

## Default Settings

### Setup

```lua
setup({
    -- enable hlslens after searching
    -- type: boolean
    auto_enable = true,
    -- if calm_down is true, stop hlslens when cursor is out of position range
    -- type: boolean
    calm_down = false,
    -- hackable function for customizing the virtual text
    -- type: function(lnum, loc, idx, r_idx, count, hls_ns)
    override_line_lens = nil
})
```

### Highlight

```vim
highlight default link HlSearchLensCur IncSearch
highlight default link HlSearchLens WildMenu
highlight default link HlSearchCur IncSearch
```

1. HlSearchLensCur: highlight the current or the nearest virtual text
2. HlSearchLens: highlight virtual texts but except for `HlSearchLensCur`
3. HlSearchCur: highlight the current or the nearest text instance

### Function

1. enable(): enable hlslens, create autocmd event
2. disable(): disable hlslens, clear any context and autocmd event of hlslens
3. start(): enable hlslens and refresh virtual text immediately
4. setup(): when `auto_enable` = false, must manually invoke enable() or start() for enabling hlslens
5. get_config(): return current configuration, must be called after the first setup()
6. override_line_lens: override [add_line_lens](./lua/hlslens/vtext.lua)

## Advanced configuration

### Customize virtual text

```vim
Plug 'kevinhwang91/nvim-hlslens'

" below code after `call plug#end()`, make sure 'hlslens' have been loaded in lua path
lua <<EOF
require('hlslens').setup({
    override_line_lens = function(lnum, loc, idx, r_idx, count, hls_ns)
        local sfw = vim.v.searchforward == 1
        local indicator, text, chunks
        local a_r_idx = math.abs(r_idx)
        if a_r_idx > 1 then
            indicator = string.format('%d%s', a_r_idx, sfw ~= (r_idx > 1) and '▲' or '▼')
        elseif a_r_idx == 1 then
            indicator = sfw ~= (r_idx == 1) and '▲' or '▼'
        else
            indicator = ''
        end

        if loc ~= 'c' then
            text = string.format('[%s %d]', indicator, idx)
            chunks = {{' ', 'Ignore'}, {text, 'HlSearchLens'}}
        else
            if indicator ~= '' then
                text = string.format('[%s %d/%d]', indicator, idx, count)
            else
                text = string.format('[%d/%d]', idx, count)
            end
            chunks = {{' ', 'Ignore'}, {text, 'HlSearchLensCur'}}
        end
        vim.api.nvim_buf_clear_namespace(0, -1, lnum - 1, lnum)
        vim.api.nvim_buf_set_extmark(0, hls_ns, lnum - 1, 0, {virt_text = chunks})
    end
})
EOF
```

<p align="center">
    <img width="864px" src=https://user-images.githubusercontent.com/17562139/102747535-69dcc500-439b-11eb-9afe-f153742b196b.png>
</p>

### Integrate with other plugins

```vim
Plug 'kevinhwang91/nvim-hlslens'

" integrate with vim-asterisk
Plug 'haya14busa/vim-asterisk'
map *  <Plug>(asterisk-z*)<Cmd>lua require('hlslens').start()<CR>
map #  <Plug>(asterisk-z#)<Cmd>lua require('hlslens').start()<CR>
map g* <Plug>(asterisk-gz*)<Cmd>lua require('hlslens').start()<CR>
map g# <Plug>(asterisk-gz#)<Cmd>lua require('hlslens').start()<CR>

" integrate with vim-visual-multi
Plug 'mg979/vim-visual-multi'
augroup VMlens
    autocmd!
    autocmd User visual_multi_start lua require('vmlens').vmlens_start()
    autocmd User visual_multi_exit lua require('vmlens').vmlens_exit()
augroup END

" below code after `call plug#end()`, make sure 'hlslens' have been loaded in lua path
lua require('hlslens').setup({calm_down = true})
```

Add vmlens.lua under your lua path, for instance: `~/.config/nvim/lua/vmlens.lua`

```lua
M = {}
local hlslens = require('hlslens')
local hlslens_started = false
local line_lens_bak

local override_line_lens = function(lnum, loc, idx, r_idx, count, hls_ns)
    local text, chunks
    if loc ~= 'c' then
        text = string.format('[%d]', idx)
        chunks = {{' ', 'Ignore'}, {text, 'HlSearchLens'}}
    else
        text = string.format('[%d/%d]', idx, count)
        chunks = {{' ', 'Ignore'}, {text, 'HlSearchLensCur'}}
    end
    vim.api.nvim_buf_clear_namespace(0, -1, lnum - 1, lnum)
    vim.api.nvim_buf_set_extmark(0, hls_ns, lnum - 1, 0, {virt_text = chunks})
end

function M.vmlens_start()
    if not hlslens then
        return
    end
    local config = hlslens.get_config()
    line_lens_bak = config.override_line_lens
    config.override_line_lens = override_line_lens
    hlslens_started = config.started
    if hlslens_started then
        hlslens.disable()
    end
    hlslens.start()

end

function M.vmlens_exit()
    if not hlslens then
        return
    end
    local config = hlslens.get_config()
    config.override_line_lens = line_lens_bak
    hlslens.disable()
    if hlslens_started then
        hlslens.start()
    end
end

return M
```

## Status

WIP

I'm moving from Vimscript to pure Lua, so things may break sometimes.


## License

The project is licensed under a BSD-3-clause license. See [LICENSE](./LICENSE) file for details.
