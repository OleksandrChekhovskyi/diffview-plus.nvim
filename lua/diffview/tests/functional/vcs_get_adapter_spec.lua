local async = require("diffview.async")
local config = require("diffview.config")
local test_utils = require("diffview.tests.helpers")
local vcs = require("diffview.vcs")

-- Tear down a fixture repo, yield to the scheduler, then re-throw a caught
-- error. Runs after any per-test stub restoration so cleanup always happens.
local function finish(repo, ok, err)
  test_utils.cleanup_repo(repo)
  async.await(async.scheduler())
  if not ok then
    error(err)
  end
end

describe("diffview.vcs.get_adapter adapter_kind pin", function()
  local original_config

  before_each(function()
    original_config = vim.deepcopy(config.get_config())
  end)

  after_each(function()
    config.setup(original_config)
  end)

  it(
    'returns a GitAdapter when `adapter_kind = "git"` is passed',
    test_utils.async_test(function()
      local repo = test_utils.make_repo()

      local ok, err = pcall(function()
        local probe_err, adapter = vcs.get_adapter({
          cmd_ctx = { path_args = {}, cpath = repo, adapter_kind = "git" },
        })
        assert.is_nil(probe_err)
        assert.is_not_nil(adapter)
        -- `config_key` is each adapter's canonical name; the Git adapter
        -- declares `"git"`, so this is the strongest check we can make
        -- without importing the GitAdapter class into the spec.
        assert.equals("git", adapter.config_key)
      end)

      finish(repo, ok, err)
    end)
  )

  it(
    "ignores `preferred_adapter` when `adapter_kind` is pinned",
    test_utils.async_test(function()
      -- The regression this guards: a user with `preferred_adapter = "jj"`
      -- in a colocated git/jj repo would have the overview's rev arg
      -- re-dispatched to the Jujutsu adapter (whose revset grammar does
      -- not match `A...B`). Pinning `adapter_kind = "git"` must beat
      -- `preferred_adapter` so the dispatch stays on Git.
      --
      -- `make_repo()` only builds a Git repository, so simulate colocation
      -- by stubbing `JjAdapter`'s probe: without the pin the stub wins; with
      -- the pin the search must collapse to Git and the stub is skipped.
      local repo = test_utils.make_repo()
      local JjAdapter = require("diffview.vcs.adapters.jj").JjAdapter
      local saved_bootstrap = JjAdapter.bootstrap
      local saved_find_toplevel = JjAdapter.find_toplevel
      local saved_create = JjAdapter.create
      JjAdapter.bootstrap = { done = true, ok = true, version = {} }
      JjAdapter.find_toplevel = function()
        return nil, repo
      end
      JjAdapter.create = function()
        return nil, { config_key = "jj" }
      end

      local ok, err = pcall(function()
        config.setup({ preferred_adapter = "jj" })

        -- Sanity: without the pin, the stub makes Jujutsu win.
        local unpinned_err, unpinned = vcs.get_adapter({
          cmd_ctx = { path_args = {}, cpath = repo },
        })
        assert.is_nil(unpinned_err)
        assert.is_not_nil(unpinned)
        assert.equals("jj", unpinned.config_key)

        -- With the pin, Git wins despite `preferred_adapter = "jj"`.
        local pinned_err, pinned = vcs.get_adapter({
          cmd_ctx = { path_args = {}, cpath = repo, adapter_kind = "git" },
        })
        assert.is_nil(pinned_err)
        assert.is_not_nil(pinned)
        assert.equals("git", pinned.config_key)
      end)

      JjAdapter.bootstrap = saved_bootstrap
      JjAdapter.find_toplevel = saved_find_toplevel
      JjAdapter.create = saved_create
      finish(repo, ok, err)
    end)
  )

  it(
    "returns an error for an unknown `adapter_kind`",
    test_utils.async_test(function()
      local repo = test_utils.make_repo()

      local ok, err = pcall(function()
        local probe_err, adapter = vcs.get_adapter({
          cmd_ctx = { path_args = {}, cpath = repo, adapter_kind = "bogus" },
        })
        assert.is_nil(adapter)
        assert.is_string(probe_err)
        assert.is_truthy(probe_err:find("bogus", 1, true))
      end)

      finish(repo, ok, err)
    end)
  )
end)
