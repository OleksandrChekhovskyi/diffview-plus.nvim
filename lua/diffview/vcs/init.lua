local config = require("diffview.config")
local GitAdapter = require("diffview.vcs.adapters.git").GitAdapter
local HgAdapter = require("diffview.vcs.adapters.hg").HgAdapter
local JjAdapter = require("diffview.vcs.adapters.jj").JjAdapter
local P4Adapter = require("diffview.vcs.adapters.p4").P4Adapter

local M = {}

---@class vcs.init.get_adapter.Opt
---@field top_indicators string[]?
---@field cmd_ctx vcs.init.get_adapter.Opt.Cmd_Ctx? # Context data from a command call.

---@class vcs.init.get_adapter.Opt.Cmd_Ctx
---@field path_args? string[] # Raw path args
---@field cpath? string # Cwd path given by the `-C` flag option
---@field adapter_kind? string # If set, restrict the adapter search to the kind whose `config_key` matches, bypassing `preferred_adapter` entirely. For callers that MUST have a specific adapter (e.g., the worktree overview, which built its args in Git's revision grammar and must not be re-dispatched to Jujutsu in a colocated repo).

---@param opt vcs.init.get_adapter.Opt
---@return string? err
---@return VCSAdapter? adapter
function M.get_adapter(opt)
  local adapter_kinds = { GitAdapter, JjAdapter, HgAdapter, P4Adapter }

  if not opt.cmd_ctx then
    opt.cmd_ctx = {}
  end

  if opt.cmd_ctx.adapter_kind then
    -- Caller pinned a specific adapter kind. Collapse the search to that
    -- one so `preferred_adapter` cannot reshuffle it away, and so other
    -- VCS plugins installed in a colocated repo cannot win the probe.
    local pinned = opt.cmd_ctx.adapter_kind
    local matched
    for _, kind in ipairs(adapter_kinds) do
      if kind.config_key == pinned then
        matched = kind
        break
      end
    end
    if not matched then
      return ("Unknown adapter kind: %q"):format(pinned)
    end
    adapter_kinds = { matched }
  else
    -- Move the preferred adapter to the front so it is tried first.
    local preferred = config.get_config().preferred_adapter
    if preferred then
      for i, kind in ipairs(adapter_kinds) do
        if kind.config_key == preferred then
          table.remove(adapter_kinds, i)
          table.insert(adapter_kinds, 1, kind)
          break
        end
      end
    end
  end

  for _, kind in ipairs(adapter_kinds) do
    local path_args
    local top_indicators = opt.top_indicators

    if not kind.bootstrap.done then
      kind.run_bootstrap()
    end
    if not kind.bootstrap.ok then
      goto continue
    end

    if not top_indicators then
      path_args, top_indicators = kind.get_repo_paths(opt.cmd_ctx.path_args, opt.cmd_ctx.cpath)
    end

    local err, toplevel = kind.find_toplevel(top_indicators)

    if not err then
      -- Create a new adapter instance. Store the resolved path args and the
      -- cpath in the adapter context.
      return kind.create(toplevel, path_args, opt.cmd_ctx.cpath)
    end

    ::continue::
  end

  return "Not a repo (or any parent), or no supported VCS adapter!"
end

return M
