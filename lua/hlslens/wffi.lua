---@diagnostic disable: undefined-field
local M = {}

local utils
local C
local ffi

local Cpattern
local Cchar_u_VLA
local Cregmmatch_T

local function getCurWin()
    local curWin
    if utils.isWindows() then
        local err = ffi.new('Error')
        curWin = C.find_window_by_handle(0, err)
    else
        curWin = C.curwin
    end
    return curWin
end

local function getCurBuf()
    local curBuf
    if utils.isWindows() then
        local err = ffi.new('Error')
        curBuf = C.find_buffer_by_handle(0, err)
    else
        curBuf = C.curbuf
    end
    return curBuf
end

function M.mlGetBufLen(lnum)
    return tonumber(C.strlen(C.ml_get_buf(getCurBuf(), lnum, false)))
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

function M.vimRegExecMulti(regm, lnum, col)
    return tonumber(C.vim_regexec_multi(regm, getCurWin(), getCurBuf(), lnum, col, nil, nil))
end

function M.curWinColOff()
    return C.curwin_col_off()
end

local function init()
    ffi = require('ffi')
    setmetatable(M, {__index = ffi})
    C = ffi.C
    ffi.cdef([[
        typedef unsigned char char_u;
        typedef struct regprog regprog_T;

        typedef long linenr_T;
        typedef int colnr_T;

        typedef uint64_t proftime_T;

        typedef struct {
            linenr_T lnum;
            colnr_T col;
        } lpos_T;

        typedef struct {
            regprog_T *regprog;
            lpos_T startpos[10];
            lpos_T endpos[10];
            int rmm_ic;
            colnr_T rmm_maxcol;
        } regmmatch_T;

        typedef struct window_S win_T;
        typedef struct file_buffer buf_T;

        regprog_T *vim_regcomp(char_u *expr_arg, int re_flags);

        char_u *ml_get_buf(buf_T *buf, linenr_T lnum, bool will_change);

        int ignorecase(char_u *pat);

        long vim_regexec_multi(regmmatch_T *rmp, win_T *win, buf_T *buf, linenr_T lnum, colnr_T col,
            proftime_T *tm, int *timed_out);

        size_t strlen(const char *s);

        int curwin_col_off(void);
    ]])

    utils = require('hlslens.utils')
    if utils.isWindows() then
        ffi.cdef([[
            typedef struct {} Error;
            buf_T *find_buffer_by_handle(int buffer, Error *err);
            win_T *find_window_by_handle(int window, Error *err);
        ]])
    else
        ffi.cdef([[
            win_T *curwin;
            buf_T *curbuf;
        ]])
    end

    Cchar_u_VLA = ffi.typeof('char_u[?]')
    Cregmmatch_T = ffi.typeof('regmmatch_T')
end

init()

return M
