local FileSystem = require("agentic.utils.file_system")
local BufHelpers = require("agentic.utils.buf_helpers")

--- @alias agentic.ui.ContextItemType "file"|"image"

--- @class agentic.ui.ContextItem
--- @field type agentic.ui.ContextItemType
--- @field data string File path for files, or base64 data for images
--- @field mimeType? string Only for images

--- @class agentic.ui.ContextList
--- @field _items agentic.ui.ContextItem[]
--- @field _bufnr integer The same buffer number as the ChatWidget's files buffer
--- @field _on_change fun(contextList: agentic.ui.ContextList)
local ContextList = {}
ContextList.__index = ContextList

--- @param bufnr integer The files buffer number from ChatWidget
--- @param on_change fun(contextList: agentic.ui.ContextList) Callback when context changes
--- @return agentic.ui.ContextList
function ContextList:new(bufnr, on_change)
    local instance = setmetatable({
        _items = {},
        _bufnr = bufnr,
        _on_change = on_change,
    }, self)

    instance:_setup_keybindings()

    return instance
end

--- Add a file to the context list if not already present
--- @param file_path string
--- @return boolean success
function ContextList:add_file(file_path)
    -- Check if file already exists
    for _, item in ipairs(self._items) do
        if item.type == "file" and item.data == file_path then
            return true
        end
    end

    local _ok, stat = pcall(vim.uv.fs_stat, file_path)

    if stat and stat.type == "file" then
        table.insert(self._items, {
            type = "file",
            data = file_path,
        })
        self:_render()
        return true
    end

    return false
end

--- Add an image to the context list
--- @param base64_data string Base64 encoded image data
--- @param mime_type string MIME type (e.g., "image/png")
function ContextList:add_image(base64_data, mime_type)
    table.insert(self._items, {
        type = "image",
        data = base64_data,
        mimeType = mime_type,
    })
    self:_render()
end

--- Remove item at the given index
--- @param index integer
function ContextList:remove_item_at(index)
    if index < 1 or index > #self._items then
        return
    end

    table.remove(self._items, index)
    self:_render()
end

--- Get all files from the context list
--- @return string[]
function ContextList:get_files()
    local files = {}
    for _, item in ipairs(self._items) do
        if item.type == "file" then
            table.insert(files, item.data)
        end
    end
    return files
end

--- Get all images from the context list
--- @return agentic.ui.ImageData[]
function ContextList:get_images()
    local images = {}
    for _, item in ipairs(self._items) do
        if item.type == "image" then
            table.insert(images, {
                data = item.data,
                mimeType = item.mimeType,
            })
        end
    end
    return images
end

--- Clear all context items
function ContextList:clear()
    self._items = {}
    self:_render()
end

--- Check if context list is empty
--- @return boolean
function ContextList:is_empty()
    return #self._items == 0
end

--- Render the context list to the buffer
--- @private
function ContextList:_render()
    local lines = {}

    for i, item in ipairs(self._items) do
        if item.type == "file" then
            table.insert(
                lines,
                string.format("-   %s", FileSystem.to_smart_path(item.data))
            )
        elseif item.type == "image" then
            table.insert(lines, string.format("-   [Image #%d]", i))
        end
    end

    BufHelpers.with_modifiable(self._bufnr, function(bufnr)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    end)

    self._on_change(self)
end

--- Setup keybindings for removing context items
--- @private
function ContextList:_setup_keybindings()
    BufHelpers.keymap_set(self._bufnr, "n", "d", function()
        local cursor = vim.api.nvim_win_get_cursor(0)
        local line = cursor[1]

        local line_content =
            vim.api.nvim_buf_get_lines(self._bufnr, line - 1, line, false)[1]

        if line_content and line_content:match("%S") then
            self:remove_item_at(line)
        end
    end, { nowait = true })

    BufHelpers.keymap_set(self._bufnr, "v", "d", function()
        local start_pos = vim.fn.getpos("v")
        local end_pos = vim.fn.getpos(".")
        local start_line = start_pos[2]
        local end_line = end_pos[2]

        -- Ensure start_line is always smaller than end_line
        if start_line > end_line then
            start_line, end_line = end_line, start_line
        end

        -- Remove items in reverse order to maintain correct indices
        for line = end_line, start_line, -1 do
            local line_content = vim.api.nvim_buf_get_lines(
                self._bufnr,
                line - 1,
                line,
                false
            )[1]

            if line_content and line_content:match("%S") then
                self:remove_item_at(line)
            end
        end

        -- Exit visual mode
        BufHelpers.feed_ESC_key()
    end, { nowait = true })
end

return ContextList
