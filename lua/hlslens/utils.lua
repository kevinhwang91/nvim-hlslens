local M = {}

function M.bin_search(items, e, comp)
    if type(comp) ~= 'function' then
        return nil, 0
    end
    local min, max, mid = 1, #items, 1
    local ret = 0
    local count = 0
    while min <= max do
        mid = math.floor((min + max) / 2)
        ret = comp(e, items[mid])
        if ret == 0 then
            break
        elseif ret == 1 then
            min = mid + 1
        else
            max = mid - 1
        end
        count = count + 1
    end
    return mid, ret
end

function M.compare_pos(p1, p2)
    if p1[1] == p2[1] then
        if p1[2] == p2[2] then
            return 0
        elseif p1[2] > p2[2] then
            return 1
        else
            return -1
        end
    elseif p1[1] > p2[1] then
        return 1
    else
        return -1
    end
end

return M
