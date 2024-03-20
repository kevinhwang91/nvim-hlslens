# nvim-hlslens

nvim-hlslens helps you better glance at matched information, seamlessly jump between matched
instances.

<https://user-images.githubusercontent.com/17562139/144654751-0d439610-b913-4e72-b473-e49db3317fab.mp4>

## Table of contents

- [Table of contents](#table-of-contents)
- [Features](#features)
- [Quickstart](#quickstart)
  - [Requirements](#requirements)
  - [Installation](#installation)
  - [Minimal configuration](#minimal-configuration)
  - [Usage](#usage)
    - [Start hlslens](#start-hlslens)
    - [Stop hlslens](#stop-hlslens)
- [Documentation](#documentation)
  - [Setup and description](#setup-and-description)
  - [Highlight](#highlight)
  - [Commands](#commands)
  - [API](#api)
- [Advanced configuration](#advanced-configuration)
  - [Customize configuration](#customize-configuration)
  - [Customize virtual text](#customize-virtual-text)
  - [Integrate with other plugins](#integrate-with-other-plugins)
    - [vim-asterisk](https://github.com/haya14busa/vim-asterisk)
    - [nvim-ufo](https://github.com/kevinhwang91/nvim-ufo)
    - [vim-visual-multi](https://github.com/mg979/vim-visual-multi)
- [Feedback](#feedback)
- [License](#license)

## Features

- Fully customizable style of virtual text
- Clear highlighting and virtual text when cursor is out of range
- Display search result dynamically while cursor is moving
- Display search result for the current matched instance while searching
- Display search result for some built-in commands that support incsearch (need Neovim 0.8.0)

> Need `vim.api.nvim_parse_cmd` to parse built-in commands if incsearch is enabled.

## Quickstart

### Requirements

- [Neovim](https://github.com/neovim/neovim) 0.7.2 or later
- [nvim-ufo](https://github.com/kevinhwang91/nvim-ufo) (optional)

### Installation

Install nvim-hlslens with [Packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {'kevinhwang91/nvim-hlslens'}
```

### Minimal configuration

```lua
require('hlslens').setup()

local kopts = {noremap = true, silent = true}

vim.api.nvim_set_keymap('n', 'n',
    [[<Cmd>execute('normal! ' . v:count1 . 'n')<CR><Cmd>lua require('hlslens').start()<CR>]],
    kopts)
vim.api.nvim_set_keymap('n', 'N',
    [[<Cmd>execute('normal! ' . v:count1 . 'N')<CR><Cmd>lua require('hlslens').start()<CR>]],
    kopts)
vim.api.nvim_set_keymap('n', '*', [[*<Cmd>lua require('hlslens').start()<CR>]], kopts)
vim.api.nvim_set_keymap('n', '#', [[#<Cmd>lua require('hlslens').start()<CR>]], kopts)
vim.api.nvim_set_keymap('n', 'g*', [[g*<Cmd>lua require('hlslens').start()<CR>]], kopts)
vim.api.nvim_set_keymap('n', 'g#', [[g#<Cmd>lua require('hlslens').start()<CR>]], kopts)

vim.api.nvim_set_keymap('n', '<Leader>l', '<Cmd>noh<CR>', kopts)
```

### Usage

After using [Minimal configuration](#minimal-configuration):

Hlslens will add virtual text at the end of the line if the room is enough for virtual text,
otherwise, add a floating window to overlay the statusline to display lens.

You can glance at the result provided by lens while searching when `incsearch` is on. Hlslens also
supports `<C-g>` and `<C-t>` to move to the next and previous match.

#### Start hlslens

1. Press `/` or `?` to search text, `/s` and `/e` offsets are supported;
2. Invoke API `require('hlslens').start()`;

#### Stop hlslens

1. Run ex command `nohlsearch`;
2. Map key to `:nohlsearch`;
3. Invoke API `require('hlslens').stop()`;

## Documentation

### Setup and description

```lua
{
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
        description = [[If calm_down is true, clear all lens and highlighting When the cursor is
            out of the position range of the matched instance or any texts are changed]],
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
            changed, it will be listed in the CHANGES file.
            @param render table an inner module for hlslens, use `setVirt` to set virtual text
            @param splist table (1,1)-indexed position
            @param nearest boolean whether nearest lens
            @param idx number nearest index in the plist
            @param relIdx number relative index, negative means before current position,
                                  positive means after
        ]],
        default = nil
    },
}
```

### Highlight

```vim
hi default link HlSearchNear IncSearch
hi default link HlSearchLens WildMenu
hi default link HlSearchLensNear IncSearch
```

1. HlSearchLensNear: highlight the nearest virtual text for the floating window
2. HlSearchLens: highlight virtual text except for the nearest one
3. HlSearchNear: highlight the nearest matched instance

### Commands

- `HlSearchLensToggle`: Toggle nvim-hlslens enable/disable
- `HlSearchLensEnable`: Enable nvim-hlslens
- `HlSearchLensDisable`: Disable nvim-hlslens

### API

[hlslens.lua](./lua/hlslens.lua)

## Advanced configuration

### Customize configuration

```lua
require('hlslens').setup({
    calm_down = true,
    nearest_only = true,
    nearest_float_when = 'always'
})

-- run `:nohlsearch` and export results to quickfix
-- if Neovim is 0.8.0 before, remap yourself.
vim.keymap.set({'n', 'x'}, '<Leader>L', function()
    vim.schedule(function()
        if require('hlslens').exportLastSearchToQuickfix() then
            vim.cmd('cw')
        end
    end)
    return ':noh<CR>'
end, {expr = true})
```

<https://user-images.githubusercontent.com/17562139/144655283-f5e3cf34-6c14-464d-9e09-6f57140c0dda.mp4>

### Customize virtual text

```lua
require('hlslens').setup({
    override_lens = function(render, posList, nearest, idx, relIdx)
        local sfw = vim.v.searchforward == 1
        local indicator, text, chunks
        local absRelIdx = math.abs(relIdx)
        if absRelIdx > 1 then
            indicator = ('%d%s'):format(absRelIdx, sfw ~= (relIdx > 1) and '▲' or '▼')
        elseif absRelIdx == 1 then
            indicator = sfw ~= (relIdx == 1) and '▲' or '▼'
        else
            indicator = ''
        end

        local lnum, col = unpack(posList[idx])
        if nearest then
            local cnt = #posList
            if indicator ~= '' then
                text = ('[%s %d/%d]'):format(indicator, idx, cnt)
            else
                text = ('[%d/%d]'):format(idx, cnt)
            end
            chunks = {{' '}, {text, 'HlSearchLensNear'}}
        else
            text = ('[%s %d]'):format(indicator, idx)
            chunks = {{' '}, {text, 'HlSearchLens'}}
        end
        render.setVirt(0, lnum - 1, col - 1, chunks, nearest)
    end
})
```

<p align="center">
    <img width="864px" src=https://user-images.githubusercontent.com/17562139/115062493-fd26a100-9f1c-11eb-9305-20ef83d08e40.png>
</p>

### Integrate with other plugins

#### [vim-asterisk](https://github.com/haya14busa/vim-asterisk)

```lua
-- packer
use 'haya14busa/vim-asterisk'

vim.api.nvim_set_keymap('n', '*', [[<Plug>(asterisk-z*)<Cmd>lua require('hlslens').start()<CR>]], {})
vim.api.nvim_set_keymap('n', '#', [[<Plug>(asterisk-z#)<Cmd>lua require('hlslens').start()<CR>]], {})
vim.api.nvim_set_keymap('n', 'g*', [[<Plug>(asterisk-gz*)<Cmd>lua require('hlslens').start()<CR>]], {})
vim.api.nvim_set_keymap('n', 'g#', [[<Plug>(asterisk-gz#)<Cmd>lua require('hlslens').start()<CR>]], {})

vim.api.nvim_set_keymap('x', '*', [[<Plug>(asterisk-z*)<Cmd>lua require('hlslens').start()<CR>]], {})
vim.api.nvim_set_keymap('x', '#', [[<Plug>(asterisk-z#)<Cmd>lua require('hlslens').start()<CR>]], {})
vim.api.nvim_set_keymap('x', 'g*', [[<Plug>(asterisk-gz*)<Cmd>lua require('hlslens').start()<CR>]], {})
vim.api.nvim_set_keymap('x', 'g#', [[<Plug>(asterisk-gz#)<Cmd>lua require('hlslens').start()<CR>]], {})
```

#### [nvim-ufo](https://github.com/kevinhwang91/nvim-ufo)

The lens has been adapted to the folds of nvim-ufo, still need remap `n` and `N` action if you want
to peek at folded lines.

```lua
-- packer
use {'kevinhwang91/nvim-ufo', requires = 'kevinhwang91/promise-async'}

-- if Neovim is 0.8.0 before, remap yourself.
local function nN(char)
    local ok, winid = hlslens.nNPeekWithUFO(char)
    if ok and winid then
        -- Safe to override buffer scope keymaps remapped by ufo,
        -- ufo will restore previous buffer keymaps before closing preview window
        -- Type <CR> will switch to preview window and fire `trace` action
        vim.keymap.set('n', '<CR>', function()
            return '<Tab><CR>'
        end, {buffer = true, remap = true, expr = true})
    end
end

vim.keymap.set({'n', 'x'}, 'n', function() nN('n') end)
vim.keymap.set({'n', 'x'}, 'N', function() nN('N') end)
```

#### [vim-visual-multi](https://github.com/mg979/vim-visual-multi)

<https://user-images.githubusercontent.com/17562139/144655345-9185df0e-e27e-4877-9ee6-d0acb811c907.mp4>

```lua
-- packer
use 'mg979/vim-visual-multi'

local hlslens = require('hlslens')
if hlslens then
    local overrideLens = function(render, posList, nearest, idx, relIdx)
        local _ = relIdx
        local lnum, col = unpack(posList[idx])

        local text, chunks
        if nearest then
            text = ('[%d/%d]'):format(idx, #posList)
            chunks = {{' ', 'Ignore'}, {text, 'VM_Extend'}}
        else
            text = ('[%d]'):format(idx)
            chunks = {{' ', 'Ignore'}, {text, 'HlSearchLens'}}
        end
        render.setVirt(0, lnum - 1, col - 1, chunks, nearest)
    end
    local lensBak
    local config = require('hlslens.config')
    local gid = vim.api.nvim_create_augroup('VMlens', {})
    vim.api.nvim_create_autocmd('User', {
        pattern = {'visual_multi_start', 'visual_multi_exit'},
        group = gid,
        callback = function(ev)
            if ev.match == 'visual_multi_start' then
                lensBak = config.override_lens
                config.override_lens = overrideLens
            else
                config.override_lens = lensBak
            end
            hlslens.start()
        end
    })
end
```

## Feedback

- If you get an issue or come up with an awesome idea, don't hesitate to open an issue in github.
- If you think this plugin is useful or cool, consider rewarding it a star.

## License

The project is licensed under a BSD-3-clause license. See [LICENSE](./LICENSE) file for details.
