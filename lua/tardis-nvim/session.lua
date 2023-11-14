local buffer = require('tardis-nvim.buffer')
local adapters = require('tardis-nvim.adapters')

local M = {}

---@class TardisSession
---@field id integer
---@field parent TardisSessionManager
---@field augroup integer
---@field filename string
---@field filetype string
---@field path string
---@field origin integer
---@field buffers TardisBuffer[]
---@field adapter TardisAdapter
M.Session = {}

---@param id integer
---@param parent TardisSessionManager
function M.Session:new(id, parent)
    local session = {}
    setmetatable(session, self)
    self.__index = self
    session:init(id, parent)

    return session
end

---comment
---@param fd integer
---@param parent TardisSession
local function set_keymaps_for_buffer(fd, parent)
    local keymap = parent.parent.config.keymap
    vim.keymap.set('n', keymap.next, function() parent:next_buffer() end, { buffer = fd })
    vim.keymap.set('n', keymap.prev, function() parent:prev_buffer() end, { buffer = fd })
    vim.keymap.set('n', keymap.quit, function() parent:close() end, { buffer = fd })
    vim.keymap.set('n', keymap.revision_message, function() parent:close() end, { buffer = fd })
end

---@param id integer
---@param parent TardisSessionManager
---@param adapter_type string
function M.Session:init(id, parent, adapter_type)
    local adapter = adapters.get_adapter(adapter_type)
    if not adapter then return end

    self.adapter = adapter
    self.filetype = vim.api.nvim_buf_get_option(0, 'filetype')
    self.origin = vim.api.nvim_get_current_buf()
    self.id = id
    self.parent = parent
    self.path = vim.fn.expand('%:p')
    self.buffers = {}

    local log = self.adapter.get_revisions_for_current_file(self)
    if vim.tbl_isempty(log) then
        vim.notify('No previous revisions of this file were found', vim.log.levels.WARN)
        return
    end

    for i, revision in ipairs(log) do
        local fd = nil
        if i < parent.config.settings.initial_revisions then
            fd = self.adapter.create_revision_buffer(revision, self)
            set_keymaps_for_buffer(fd, self)
        end
        table.insert(self.buffers, buffer.Buffer:new(revision, fd))
    end
    parent:on_session_opened(self)
end

function M.Session:close()
    for _, buf in ipairs(self.buffers) do
        buf:close()
    end
    if self.parent then
        self.parent:on_session_closed(self)
    end
end

---@return TardisBuffer
function M.Session:get_current_buffer()
    return self.buffers[self.curret_buffer_index]
end

---@param index integer
function M.Session:goto_buffer(index)
    local buf = self.buffers[index]
    if not buf then return end
    if not buf.fd then
        buf.fd = self.adapter.create_revision_buffer(buf.revision, self)
        set_keymaps_for_buffer(buf.fd, self)
    end
    buf:focus()
    self.curret_buffer_index = index
end

function M.Session:next_buffer()
    self:goto_buffer(self.curret_buffer_index + 1)
end

function M.Session:prev_buffer()
    self:goto_buffer(self.curret_buffer_index - 1)
end

return M
