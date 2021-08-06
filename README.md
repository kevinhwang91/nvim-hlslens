# nvim-hlslens

nvim-hlslens helps you better glance at matched information, seamlessly jump between matched instances.

<p align="center">
    <img width="864px" src=https://user-images.githubusercontent.com/17562139/115105257-5a0f6f00-9f90-11eb-92cf-801fe73a45fb.gif>
</p>

## Table of contents

* [Table of contents](#table-of-contents)
* [Features](#features)
* [Quickstart](#quickstart)
  * [Requirements](#requirements)
  * [Installation](#installation)
  * [Minimal configuration](#minimal-configuration)
  * [Usage](#usage)
    * [3 ways to start hlslens](#3-ways-to-start-hlslens)
    * [Stop hlslens](#stop-hlslens)
* [Documentation](#documentation)
  * [Setup and description](#setup-and-description)
  * [Highlight](#highlight)
  * [Commands](#commands)
* [Advanced configuration](#advanced-configuration)
  * [Customize configuration](#customize-configuration)
  * [Customize virtual text](#customize-virtual-text)
  * [Integrate with other plugins](#integrate-with-other-plugins)
* [Feedback](#feedback)
* [License](#license)

## Features

- Fully customizable style of virtual text
- Display virtual text dynamicly while cursor is moving
- Clear highlighting and virtual text when cursor is out of range
- Add virtual text for the current matched instance while searching
- Thanks to the cache and asynchronous rendering, it is very fast

## Quickstart

### Requirements

- [Neovim](https://github.com/neovim/neovim) 0.5 or later

### Installation

Install nvim-hlslens with [Vim-plug](https://github.com/junegunn/vim-plug):

```vim
Plug 'kevinhwang91/nvim-hlslens'
```

Install nvim-hlslens with [Packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {'kevinhwang91/nvim-hlslens'}
```

### Minimal configuration

```vim
" vimscript
Plug 'kevinhwang91/nvim-hlslens'

noremap <silent> n <Cmd>execute('normal! ' . v:count1 . 'n')<CR>
            \<Cmd>lua require('hlslens').start()<CR>
noremap <silent> N <Cmd>execute('normal! ' . v:count1 . 'N')<CR>
            \<Cmd>lua require('hlslens').start()<CR>
noremap * *<Cmd>lua require('hlslens').start()<CR>
noremap # #<Cmd>lua require('hlslens').start()<CR>
noremap g* g*<Cmd>lua require('hlslens').start()<CR>
noremap g# g#<Cmd>lua require('hlslens').start()<CR>

" use : instead of <Cmd>
nnoremap <silent> <leader>l :noh<CR>
```

### Usage

After using [Minimal configuration](#Minimal-configuration):

Hlslens will add virtual text at the end of the line if the room is enough for virtual text,
otherwise, add a floating window to overlay the statusline to display lens.

You can glance at the result provided by lens while searching when `incsearch` is on.
Hlslens also supports `<C-g>` and `<C-t>` to move to the next and previous match.

#### 3 ways to start hlslens

1. Press `/` or `?` to search text, `/s` and `/e` offsets are supported
2. Press `n` or `N` to jump to the instance matched by last pattern
3. Press `*`, `#`, `g*` or `g#` to search word nearest to the cursor

> run ex command :help search-commands for more information.

#### Stop hlslens

Hlslens will observe whether `nohlsearch` command is accepted.

1. Run ex command `nohlsearch`
2. Map key to `:nohlsearch`, make sure that to use `:` instead of `<Cmd>`

## Documentation

### Setup and description

```lua
root = {
    auto_enable = {
        description = [[Enable nvim-hlslens automatically]],
        default = true
    },
    enable_incsearch = {
        description = [[When `incsearch` option is on and enable_incsearch is true, add lens
            for the current matched instance]],
        default = true
    },
    calm_down = {
        description = [[When the cursor is out of the position range of the matched instance
            and calm_down is true, clear all lens]],
        default = false,
    },
    nearest_only = {
        description = [[Only add lens for the nearest matched instance and ignore others]],
        default = false
    },
    nearest_float_when = {
        description = [[When to open the floating window for the nearest lens.
            'auto': floating window will be opened if room isn't enough for virtual text;
            'always': always use floating window instead of virtual text;
            'never': never use floating window for the nearest lens]],
        default = 'auto',
    },
    float_shadow_blend = {
        description = [[Winblend of the nearest floating window. `:h winbl` for more details]],
        default = 50,
    },
    virt_priority = {
        description = [[Priority of virtual text, set it lower to overlay others.
        `:h nvim_buf_set_extmark` for more details]],
        default = 100,
    },
    override_lens  = {
        description = [[Hackable function for customizing the lens. If you like hacking, you
            should search `override_lens` and inspect the corresponding source code.
            There's no guarantee that this function will not be changed in the future. If it is
            changed, it will be listed in the CHANGES file.]],
        default = nil
    },
}
```

### Highlight

```vim
hi default link HlSearchNear IncSearch
hi default link HlSearchLens WildMenu
hi default link HlSearchLensNear IncSearch
hi default link HlSearchFloat IncSearch
```

1. HlSearchLensNear: highlight the nearest virtual text
2. HlSearchLens: highlight virtual text except for the nearest one
3. HlSearchNear: highlight the nearest matched instance
4. HlSearchFloat: highlight the nearest text for the floating window

### Commands

- `HlSearchLensToggle`: Toggle nvim-hlslens enable/disable

## Advanced configuration

### Customize configuration

```lua
-- lua
require('hlslens').setup({
    calm_down = true,
    nearest_only = true,
    nearest_float_when = 'always'
})
```

<p align="center">
    <img width="864px" src=https://user-images.githubusercontent.com/17562139/115060780-dd8e7900-9f1a-11eb-9fff-6593dbc10e51.gif>
</p>

### Customize virtual text

```lua
-- lua
require('hlslens').setup({
    override_lens = function(render, plist, nearest, idx, r_idx)
        local sfw = vim.v.searchforward == 1
        local indicator, text, chunks
        local abs_r_idx = math.abs(r_idx)
        if abs_r_idx > 1 then
            indicator = ('%d%s'):format(abs_r_idx, sfw ~= (r_idx > 1) and '▲' or '▼')
        elseif abs_r_idx == 1 then
            indicator = sfw ~= (r_idx == 1) and '▲' or '▼'
        else
            indicator = ''
        end

        local lnum, col = unpack(plist[idx])
        if nearest then
            local cnt = #plist
            if indicator ~= '' then
                text = ('[%s %d/%d]'):format(indicator, idx, cnt)
            else
                text = ('[%d/%d]'):format(idx, cnt)
            end
            chunks = {{' ', 'Ignore'}, {text, 'HlSearchLensNear'}}
        else
            text = ('[%s %d]'):format(indicator, idx)
            chunks = {{' ', 'Ignore'}, {text, 'HlSearchLens'}}
        end
        render.set_virt(0, lnum - 1, col - 1, chunks, nearest)
    end
})
```

<p align="center">
    <img width="864px" src=https://user-images.githubusercontent.com/17562139/115062493-fd26a100-9f1c-11eb-9305-20ef83d08e40.png>
</p>

### Integrate with other plugins

```vim
" vimscript
call plug#begin('~/.config/nvim/plugged')

Plug 'kevinhwang91/nvim-hlslens'

" integrate with vim-asterisk
Plug 'haya14busa/vim-asterisk'
map *  <Plug>(asterisk-z*)<Cmd>lua require('hlslens').start()<CR>
map #  <Plug>(asterisk-z#)<Cmd>lua require('hlslens').start()<CR>
map g* <Plug>(asterisk-gz*)<Cmd>lua require('hlslens').start()<CR>
map g# <Plug>(asterisk-gz#)<Cmd>lua require('hlslens').start()<CR>

" integrate with vim-visual-multi
Plug 'mg979/vim-visual-multi'
aug VMlens
    au!
    au User visual_multi_start lua require('vmlens').start()
    au User visual_multi_exit lua require('vmlens').exit()
aug END

call plug#end()
```

Add vmlens.lua under your lua path, for instance: `~/.config/nvim/lua/vmlens.lua`

```lua
-- lua
local M = {}
local hlslens = require('hlslens')
local config
local lens_backup

local override_lens = function(render, plist, nearest, idx, r_idx)
    local _ = r_idx
    local lnum, col = unpack(plist[idx])

    local text, chunks
    if nearest then
        text = ('[%d/%d]'):format(idx, #plist)
        chunks = {{' ', 'Ignore'}, {text, 'VM_Extend'}}
    else
        text = ('[%d]'):format(idx)
        chunks = {{' ', 'Ignore'}, {text, 'HlSearchLens'}}
    end
    render.set_virt(0, lnum - 1, col - 1, chunks, nearest)
end

function M.start()
    if hlslens then
        config = require('hlslens.config')
        lens_backup = config.override_lens
        config.override_lens = override_lens
        hlslens.start()
    end
end

function M.exit()
    if hlslens then
        config.override_lens = lens_backup
        hlslens.start()
    end
end

return M
```

<p align="center">
    <img width="864px" src=https://user-images.githubusercontent.com/17562139/115060810-e41cf080-9f1a-11eb-9196-f49897f34b39.gif>
</p>

## Feedback

- If you get an issue or come up with an awesome idea, don't hesitate to open an issue in github.
- If you think this plugin is useful or cool, consider rewarding it a star.

## License

The project is licensed under a BSD-3-clause license. See [LICENSE](./LICENSE) file for details.
