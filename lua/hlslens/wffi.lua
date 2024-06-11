---@diagnostic disable: undefined-field
local M = {}

local utils = require('hlslens.utils')
local C
local ffi

local Cpattern
local Cchar_u_VLA
local Cregmmatch_T

function M.getWin(winid)
    local err = ffi.new('Error')
    return C.find_window_by_handle(winid, err)
end

function M.getBuf(bufnr)
    local err = ffi.new('Error')
    return C.find_buffer_by_handle(bufnr, err)
end

function M.mlGetBufLen(buf, lnum)
    local ml = C.ml_get_buf(buf, lnum, false)
    return tonumber(C.strlen(ml))
end

function M.buildRegmatchT(pat)
    -- https://luajit.org/ext_ffi_semantics.html#gc
    -- Cpat must be referenced, it will be used during `vim_regexec_multi`
    Cpattern = Cchar_u_VLA(#pat + 1)
    ffi.copy(Cpattern, pat)

    local regProg = C.vim_regcomp(Cpattern, vim.o.magic and 1 or 0)
    -- `if not regProg then` doesn't work with cdata<struct regprog *>: NULL from C
    if regProg == nil then
        return
    end
    local regm = Cregmmatch_T()
    regm.regprog = regProg
    regm.rmm_ic = C.ignorecase(Cpattern)
    regm.rmm_maxcol = 0
    return regm
end

function M.regmatchPos(regm)
    local startPos, endPos = regm.startpos[0], regm.endpos[0]
    return {lnum = tonumber(startPos.lnum), col = startPos.col},
        {lnum = tonumber(endPos.lnum), col = endPos.col}
end

function M.vimRegExecMulti(buf, wp, regm, lnum, col)
    return tonumber(C.vim_regexec_multi(regm, wp, buf, lnum, col, nil, nil))
end

local function init()
    ffi = require('ffi')
    setmetatable(M, {__index = ffi})
    C = ffi.C

    if utils.has08() then
        ffi.cdef([[
            typedef int32_t linenr_T;
        ]])
    else
        ffi.cdef([[
            typedef long linenr_T;
        ]])
    end
    ffi.cdef([[
        typedef unsigned char char_u;
        typedef struct regprog regprog_T;

        typedef int colnr_T;

        typedef struct {
            linenr_T lnum;
            colnr_T col;
        } lpos_T;
    ]])
    if utils.has09() then
        -- Add rmm_matchcol field to regmmatch_T
        -- https://github.com/neovim/neovim/commit/7e9981d246a9d46f19dc6283664c229ae2efe727
        ffi.cdef([[
            typedef struct {
                regprog_T *regprog;
                lpos_T startpos[10];
                lpos_T endpos[10];
                colnr_T rmm_matchcol;
                int rmm_ic;
                colnr_T rmm_maxcol;
            } regmmatch_T;
        ]])
    else
        ffi.cdef([[
            typedef struct {
                regprog_T *regprog;
                lpos_T startpos[10];
                lpos_T endpos[10];
                int rmm_ic;
                colnr_T rmm_maxcol;
            } regmmatch_T;
        ]])
    end

    ffi.cdef([[
        typedef struct {} Error;
        typedef struct window_S win_T;
        typedef struct file_buffer buf_T;

        buf_T *find_buffer_by_handle(int buffer, Error *err);
        win_T *find_window_by_handle(int window, Error *err);

        regprog_T *vim_regcomp(char_u *expr_arg, int re_flags);

        char_u *ml_get_buf(buf_T *buf, linenr_T lnum, bool will_change);

        int ignorecase(char_u *pat);

        long vim_regexec_multi(regmmatch_T *rmp, win_T *win, buf_T *buf, linenr_T lnum, colnr_T col,
            void *dummy_ptr, int *timed_out);

        size_t strlen(const char *s);
    ]])


    Cchar_u_VLA = ffi.typeof('char_u[?]')
    Cregmmatch_T = ffi.typeof('regmmatch_T')
end

init()

return M
