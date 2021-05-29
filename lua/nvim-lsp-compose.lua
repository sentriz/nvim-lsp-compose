local lsp = require "lspconfig"
local configs = require "lspconfig/configs"
local util = require "lspconfig/util"

local registered_actions = {}

-- register_actions should be called when a server connect to a buffer.
-- here we append in order to a global list of actions to be called on save
local function register_actions(client, buff_num, actions)
    registered_actions[buff_num] = registered_actions[buff_num] or {}
    for _, action in pairs(actions) do
        table.insert(
            registered_actions[buff_num],
            function()
                action(client, buff_num)
            end
        )
    end
end

-- register_server registers a server from the list
local function register_server(index, server)
    local ctx = {filetypes = {}, default_config = {}, actions = {}}
    for _, aspect in pairs(server) do
        aspect(ctx)
    end
    ctx.default_config.filetypes = ctx.filetypes

    local name = string.format("compose-%d-%s", index, table.concat(ctx.filetypes, "-"))
    configs[name] = {default_config = ctx.default_config}
    lsp[name].setup(
        {
            on_attach = function(client, buff_num)
                register_actions(client, buff_num, ctx.actions)
            end
        }
    )
end

-- auto_format is an action that asks the specified client to format the document
local function auto_format(client, buff_num)
    local params = vim.lsp.util.make_formatting_params(options)
    local result, err = client.request_sync("textDocument/formatting", params, 2000)

    if result and result.result then
        vim.lsp.util.apply_text_edits(result.result)
    end
end

local M = {}

-- write is to be called by the user, eg
-- augroup AutoFormat
--     autocmd!
--     autocmd BufWritePre * lua require("nvim-lsp-compose").write()
-- augroup END
function M.write()
    local buff_num = vim.api.nvim_get_current_buf()
    local actions = registered_actions[buff_num] or {}
    for _, action in pairs(actions) do
        action()
    end
end

-- setup registers a list of servers
function M.setup(servers)
    for i, server in pairs(servers) do
        register_server(i, server)
    end
end

-- aspect filetypes
function M.filetypes(...)
    local filetypes = {...}
    return function(ctx)
        for _, filetype in pairs(filetypes) do
            table.insert(ctx.filetypes, filetype)
        end
    end
end

-- aspect server
function M.server(server)
    return function(ctx)
        for k, v in pairs(server()) do
            ctx.default_config[k] = v
        end
    end
end

-- aspect action
-- a function to run on BuffWritePre
-- executed in the order defined by the list
function M.action(action)
    return function(ctx)
        table.insert(ctx.actions, action)
    end
end

-- aspect efm formatter
function M.formatter(...)
    local formatter = table.concat({...}, " ")
    return function(ctx)
        local c = ctx.default_config
        c.init_options.documentFormatting = true
        for _, filetype in pairs(ctx.filetypes) do
            c.settings.languages[filetype] = c.settings.languages[filetype] or {}
            table.insert(c.settings.languages[filetype], {formatCommand = formatter, formatStdin = true})
        end
    end
end

-- aspect efm linter
function M.linter(linter)
    return function(ctx)
        local c = ctx.default_config
        for _, filetype in pairs(ctx.filetypes) do
            c.settings.languages[filetype] = c.settings.languages[filetype] or {}
            table.insert(c.settings.languages[filetype], linter)
        end
    end
end

-- aspect action with auto_format pre filled
M.auto_format = M.action(auto_format)

return M
