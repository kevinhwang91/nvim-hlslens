local M = {}

local C
local ffi

function M.ml_get_buf_len(lnum)
    return #ffi.string(C.ml_get_buf(C.curbuf, lnum, false))
end

function M.build_regmatch_T(pat)
    local c_pat = ffi.new('char_u[?]', #pat + 1, pat)
    local regm = ffi.new('regmmatch_T [1]')
    regm[0].regprog = C.vim_regcomp(c_pat, vim.o.magic and 1 or 0)
    regm[0].rmm_ic = C.ignorecase(c_pat)
    regm[0].rmm_maxcol = 0
    return regm
end

function M.regmatch_pos(regm)
    local start_pos, end_pos = regm[0].startpos[0], regm[0].endpos[0]
    return {lnum = tonumber(start_pos.lnum), col = start_pos.col},
        {lnum = tonumber(end_pos.lnum), col = end_pos.col}
end

function M.vim_regexec_multi(regm, lnum, col)
    return tonumber(C.vim_regexec_multi(regm[0], C.curwin, C.curbuf, lnum, col, nil, nil))
end

function M.curwin_col_off()
    return C.curwin_col_off()
end

local function init()
    local ok
    ok, ffi = pcall(require, 'ffi')
    assert(ok, [[Need FFI module, please switch the repository to 'non-ffi' branch!]])
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

        win_T *curwin;
        buf_T *curbuf;

        regprog_T *vim_regcomp(char_u *expr_arg, int re_flags);

        char_u *ml_get_buf(buf_T *buf, linenr_T lnum, bool will_change);

        int ignorecase(char_u *pat);

        long vim_regexec_multi(regmmatch_T *rmp, win_T *win, buf_T *buf, linenr_T lnum, colnr_T col,
            proftime_T *tm, int *timed_out);

        int curwin_col_off(void);
    ]])
end

init()

return M
