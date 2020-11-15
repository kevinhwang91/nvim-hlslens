---
name: Bug report
about: Create a report to help us improve
title: ''
labels: ''
assignees: ''
---

<!-- Before reporting: search existing issues and check the FAQ. -->

- `nvim --version`:
- Operating system/version:

**Describe the bug**
A clear and concise description of what the bug is.

**To Reproduce using `nvim -u mini.vim`**

Example:
`cat mini.vim`

```vim
" use your plugin manager, here is `vim-plug`
call plug#begin('~/.config/nvim/plugged')
Plug 'kevinhwang91/nvim-hlslens'

call plug#end()
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

Steps to reproduce the behavior:

1.
2.
3.

**Expected behavior**
A clear and concise description of what you expected to happen.

**Screenshots**
If applicable, add screenshots to help explain your problem.

**Additional context**
Add any other context about the problem here.
