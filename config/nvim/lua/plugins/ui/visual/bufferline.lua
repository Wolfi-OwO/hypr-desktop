return {
  "akinsho/bufferline.nvim",
	event = "BufReadPre",
	lazy = false,
  opts = function(_, opts)
    local Offset = require("bufferline.offset")
    if not Offset.edgy then
      local get = Offset.get
      Offset.get = function()
        if package.loaded.edgy then
          local old_offset = get()
          local layout = require("edgy.config").layout
          local ret = { left = "", left_size = 0, right = "", right_size = 0 }
          for _, pos in ipairs({ "left", "right" }) do
            local sb = layout[pos]
            local title = " Sidebar" .. string.rep(" ", sb.bounds.width - 8)
            if sb and #sb.wins > 0 then
              ret[pos] = old_offset[pos .. "_size"] > 0 and old_offset[pos]
                or pos == "left" and ("%#Bold#" .. title .. "%*" .. "%#BufferLineOffsetSeparator#│%*")
                or pos == "right" and ("%#BufferLineOffsetSeparator#│%*" .. "%#Bold#" .. title .. "%*")
              ret[pos .. "_size"] = old_offset[pos .. "_size"] > 0 and old_offset[pos .. "_size"] or sb.bounds.width
            end
          end
          ret.total_size = ret.left_size + ret.right_size
          if ret.total_size > 0 then
            return ret
          end
        end
        return get()
      end
      Offset.edgy = true
    end

    opts.options = vim.tbl_deep_extend("force", opts.options or {}, {
      offsets = {
        {
          filetype = "neo-tree",
          text = "Explorer",
          text_align = "center",
        },
      },
    })
  end,
}
