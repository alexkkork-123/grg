-- ---------------------------------------------------------------------------
-- GRG ANTI-CHEAT BYPASS -- compiled bundle
-- Built by: grg/anticheat/tools/compile_acbypass.py
-- Modules : 76
-- Bytes   : 524882
-- ---------------------------------------------------------------------------

local __MODULES__ = {}
local __CACHE__   = {}
local function __require(path)
    local cached = __CACHE__[path]
    if cached ~= nil then return cached end
    local mod = __MODULES__[path]
    if mod == nil then
        error(string.format("[grg/ac] module not found: %q", path), 2)
    end
    local v = mod(__require)
    if type(v) == "function" then
        v = v(__require)
    end
    if v == nil then v = true end
    __CACHE__[path] = v
    return v
end

__MODULES__['boot'] = function(require)
--[[ ================================================================
    src/boot.lua
    -------------
    Entrypoint that the runtime shim calls last.

    What this does:
        1. Mark our thread (`_G.__GRG_THREAD = true` only while our
           own setup code is running; modules reset it as needed).
        2. Require `init` which loads and runs every subsystem.
        3. Expose a handful of _G hooks so the main hub can see us:
              _G.GRG_AC_BYPASS  -- the init's M table (status/controls)
              _G.GRG_AC_VERSION -- version string
        4. Print a single-line banner so it's obvious we loaded.

    This file is intentionally tiny. Every module is routed through
    init.lua so there's ONE place to read the boot order.
================================================================ ]]

return function(require)

    _G.__GRG_THREAD = true

    local version = require("core/version")
    local env     = require("core/env")
    local log     = require("core/log")

    log.info("boot", "GRG-AC starting: %s", version.summary())

    -- Main module tree. Wrapped in pcall so a broken submodule
    -- doesn't nuke the whole load. init() itself is guarded; we
    -- catch catastrophic require errors at this outer layer.
    local ok, init = pcall(require, "init")
    if not ok then
        log.error("boot", "init require failed: %s", tostring(init))
        _G.__GRG_THREAD = nil
        return nil
    end

    local ok2, err = pcall(function() return init:start() end)
    if not ok2 then
        log.error("boot", "init:start crashed: %s", tostring(err))
    end

    _G.GRG_AC_BYPASS  = init
    _G.GRG_AC_VERSION = version.STRING

    log.info("boot", "GRG-AC online. use _G.GRG_AC_BYPASS:status()")

    _G.__GRG_THREAD = nil

    return init

end

end
__MODULES__['core/config'] = function(require)
--[[ ================================================================
    src/core/config.lua
    --------------------
    Central, mutable configuration store for every module. Defaults
    live here; individual modules MUST read through config:get(...)
    rather than snapshotting a local, so the UI kill-switch and the
    live-tune toggles can take effect without a reload.

    Every namespace is one subtable. Module X reads:

        local cfg = require("core/config")
        local enabled = cfg:get("masks.walkspeed.enabled")

    Every namespace is documented below. Anything added here should
    be documented in grg/anticheat/README.md too.

    The config layer also owns "profiles": a named snapshot of the
    tree that can be swapped in atomically. We default-ship two:
        "paranoid" -- absolutely everything on, maximum spoofing
        "lean"     -- only the bare minimum for no-kick / no-ragdoll

    Profile swap emits a signal on state.Profiles_Changed so every
    subsystem can react.

    Reads that miss a key return the provided default.
================================================================ ]]

return function(require)

    local env = require("core/env")

    local M = {}

    -- ----------------------------------------------------------------
    -- 0. baseline defaults
    -- ----------------------------------------------------------------

    local function deep_copy(t)
        if type(t) ~= "table" then return t end
        local out = {}
        for k, v in pairs(t) do out[k] = deep_copy(v) end
        return out
    end

    local DEFAULTS = {
        meta = {
            place_id            = 4598019433,
            game_name           = "Generic Roleplay Game",
            build               = env.SessionStartTime,
            target_only         = false,       -- if true, bypass refuses to run outside target game
            panic_on_missing_remote = false,
        },
        log = {
            threshold      = "INFO",
            echo_to_stdout = true,
            echo_to_file   = env.Caps.writefile,
            ring_capacity  = 512,
            journal_every_event = true,
        },
        hooks = {
            namecall = {
                enabled              = true,
                chain_priority_cap   = 64,
                panic_if_unsupported = false,
                restore_on_lose      = true,
                log_every_call       = false,
            },
            newindex = {
                enabled              = true,
                restore_on_lose      = true,
                log_every_call       = false,
            },
            index = {
                enabled              = true,
                restore_on_lose      = true,
                log_every_call       = false,
            },
            fire_handlers = {
                enabled              = true,
                mutate_log_bytes     = 256,
            },
            recv_handlers = {
                enabled              = true,
                mutate_log_bytes     = 256,
            },
        },
        masks = {
            walkspeed = {
                enabled        = true,
                baseline       = 16,
                allow_if_caller_is_us = true,
                mask_read      = true,
                mask_write     = true,
                random_jitter  = 0.0,
            },
            jumppower = {
                enabled        = true,
                baseline       = 50,
                mask_read      = true,
                mask_write     = true,
            },
            jumpheight = {
                enabled        = true,
                baseline       = 7.2,
                mask_read      = true,
                mask_write     = true,
            },
            hipheight = {
                enabled        = true,
                baseline       = 2.0,
                mask_read      = true,
                mask_write     = true,
            },
            position = {
                enabled        = true,
                mask_cframe    = false,
                mask_position  = false,
                snap_to_floor_if_flying = true,
                tolerance_per_sec = 60,
            },
            animation = {
                enabled        = true,
                fake_track_name = "move",
                spoof_timeposition = false,
            },
            character_state = {
                enabled        = true,
                force_no_platform_stand = true,
                force_no_sit          = true,
                forbid_forced_humanoid_state = true,
            },
            gravity = {
                enabled        = true,
                mask_value     = 196.2,
                mask_read      = true,
                mask_write     = false,
            },
        },
        scrubbers = {
            kick = {
                enabled              = true,
                whitelist_reasons    = {},
                spoof_reply_to_server = false,
                notify_user_on_block = true,
            },
            teleport = {
                enabled              = true,
                allow_same_place     = true,
                notify_user_on_block = true,
                block_loadscreen_teleports = true,
            },
            shadowban = {
                enabled              = true,
                block_event          = true,
                block_ragdoll_side_effect = true,
                block_visual_overlay = true,
                notify_user_on_hit   = true,
            },
            ragdoll = {
                enabled              = true,
                block_event          = true,
                restore_hrp          = true,
                max_ragdolls_per_min = 0,   -- 0 = block all
            },
            updateprofile = {
                enabled              = true,
                sanitize             = true,
                clamp_walkspeed      = 16,
                clamp_max_distance   = 40,
                keep_fields          = {"state", "position", "walkSpeed", "jumpPower"},
            },
            coregui_warning = {
                enabled              = true,
                block_warning_gui    = true,
                block_warning_sound  = true,
            },
        },
        decoys = {
            globals = {
                enabled        = true,
                install_fake_ac_table = true,
                install_fake_controller = true,
                install_fake_report_fn = true,
            },
            position = {
                enabled        = true,
                cadence_hz     = 4,
                payload_tolerance = 2.0,
            },
            velocity = {
                enabled        = true,
                cap_magnitude  = 32,
            },
            input = {
                enabled        = true,
                spoof_mouse    = false,
                spoof_keyboard = false,
            },
        },
        spoof = {
            player_telemetry = {
                enabled        = true,
                rewrite_tables = true,
                rewrite_strings = false,
                forbid_suspicious_names = true,
            },
            server_state = {
                enabled        = true,
                reply_to_ping  = true,
                reply_latency_ms_min = 30,
                reply_latency_ms_max = 120,
            },
            fingerprint_cleaner = {
                enabled        = true,
                wipe_drawing   = false,    -- breaks ESP; leave off by default
                wipe_executor_globals = false,
                wipe_syn_names = false,
            },
            script_signature = {
                enabled        = true,
                rename_localscripts = true,
                fake_source_patterns = {
                    "MovementController",
                    "CameraController",
                    "DefaultChatSystemChatEvents",
                },
            },
        },
        silencers = {
            kick_block       = { enabled = true },
            teleport_block   = { enabled = true },
            gui_warning_block= { enabled = true },
            sound_block      = { enabled = true, sound_id_blocklist = {} },
            screen_flash_block = { enabled = true },
        },
        grg = {
            shadowban_handler = {
                enabled              = true,
                treat_as_fatal_for_ac = true,
                trace_to_journal     = true,
            },
            ragdoll_handler   = { enabled = true },
            profile_spoof     = {
                enabled          = true,
                tolerance_units  = 40,
                tolerance_speed  = 4,
                reset_state_on_new_char = true,
            },
            raptor_alibi      = {
                enabled          = true,
                fake_source_name = "CoreGui.RobloxGui.Modules.Common.MovementController",
                replace_on_any_cheat_thread = true,
            },
            placeid_gate      = {
                enabled          = true,
                allow_outside_target = true,
            },
            cmdr_silencer     = { enabled = true },
        },
        sandbox = {
            env_shuffle        = { enabled = true, shuffle_keys = false },
            traceback_rewrite  = { enabled = true },
            getfenv_mask       = { enabled = true },
            debug_info_mask    = { enabled = true, fake_source = "CoreGui.RobloxGui.Modules.Common.MovementController" },
        },
        netgate = {
            send_filter   = { enabled = true, log_bytes = 256 },
            recv_scrubber = { enabled = true, log_bytes = 256 },
            rate_limiter  = { enabled = true, default_hz = 30, burst = 5 },
            jitter        = { enabled = false, min_ms = 0, max_ms = 10 },
        },
        timing = {
            jitter       = { enabled = false, min_ms = 0, max_ms = 10 },
            rate_limit   = { enabled = true, hz_cap = 60 },
            tick_smoother= { enabled = false, smoothing = 0.2 },
        },
        integrity = {
            self_protect = {
                enabled        = true,
                hide_from_getchildren = true,
                poll_hz        = 2,
            },
            hook_persistence = {
                enabled        = true,
                poll_hz        = 1,
                on_lost_action = "restore",
            },
            recovery = {
                enabled        = true,
                max_consecutive_fails = 3,
            },
        },
        ui = {
            status_panel = {
                enabled        = true,
                start_visible  = true,
                position       = "top_left",
                minimized_start= false,
                show_counters  = true,
                show_journal   = true,
            },
            toggle = {
                enabled        = true,
                hotkey         = "RightControl",
            },
        },
    }

    -- ----------------------------------------------------------------
    -- 1. live tree
    -- ----------------------------------------------------------------

    local LIVE = deep_copy(DEFAULTS)

    -- Profile registry: name -> snapshot of LIVE.
    local PROFILES = {}

    local function dotted_get(root, path)
        local cursor = root
        for part in string.gmatch(path, "[^.]+") do
            if type(cursor) ~= "table" then return nil end
            cursor = cursor[part]
        end
        return cursor
    end

    local function dotted_set(root, path, value)
        local cursor = root
        local parts = {}
        for part in string.gmatch(path, "[^.]+") do table.insert(parts, part) end
        for i = 1, #parts - 1 do
            local k = parts[i]
            if type(cursor[k]) ~= "table" then cursor[k] = {} end
            cursor = cursor[k]
        end
        local old = cursor[parts[#parts]]
        cursor[parts[#parts]] = value
        return old
    end

    -- ----------------------------------------------------------------
    -- 2. public API
    -- ----------------------------------------------------------------

    function M:get(path, default)
        local v = dotted_get(LIVE, path)
        if v == nil then return default end
        return v
    end

    function M:set(path, value)
        local old = dotted_set(LIVE, path, value)
        if self._on_change then
            pcall(self._on_change, path, value, old)
        end
        return old
    end

    function M:toggle(path)
        local v = dotted_get(LIVE, path)
        if type(v) ~= "boolean" then v = false end
        self:set(path, not v)
        return not v
    end

    function M:enable(path)  self:set(path, true)  end
    function M:disable(path) self:set(path, false) end

    function M:reset()
        LIVE = deep_copy(DEFAULTS)
        if self._on_change then pcall(self._on_change, "*", nil, nil) end
    end

    function M:defaults() return deep_copy(DEFAULTS) end
    function M:live()     return LIVE end
    function M:snapshot() return deep_copy(LIVE) end

    function M:on_change(fn)
        self._on_change = fn
    end

    -- Profiles ---------------------------------------------------------

    function M:save_profile(name)
        if type(name) ~= "string" then return false, "name required" end
        PROFILES[name] = deep_copy(LIVE)
        return true
    end

    function M:load_profile(name)
        local snap = PROFILES[name]
        if not snap then return false, "no such profile" end
        LIVE = deep_copy(snap)
        if self._on_change then pcall(self._on_change, "*", name, nil) end
        return true
    end

    function M:delete_profile(name)
        PROFILES[name] = nil
    end

    function M:list_profiles()
        local out = {}
        for k in pairs(PROFILES) do table.insert(out, k) end
        table.sort(out)
        return out
    end

    -- Seed built-in profiles.
    local function make_paranoid(tree)
        for _, group in pairs(tree) do
            if type(group) == "table" then
                for _, sub in pairs(group) do
                    if type(sub) == "table" and type(sub.enabled) == "boolean" then
                        sub.enabled = true
                    end
                end
            end
        end
    end

    local function make_lean(tree)
        tree.masks.position.enabled       = false
        tree.masks.animation.enabled      = false
        tree.decoys.position.enabled      = false
        tree.decoys.velocity.enabled      = false
        tree.decoys.input.enabled         = false
        tree.spoof.fingerprint_cleaner.enabled = false
        tree.sandbox.env_shuffle.enabled  = false
        tree.sandbox.debug_info_mask.enabled = false
        tree.netgate.jitter.enabled       = false
        tree.timing.jitter.enabled        = false
        tree.timing.tick_smoother.enabled = false
    end

    do
        local paranoid_tree = deep_copy(DEFAULTS)
        make_paranoid(paranoid_tree)
        PROFILES["paranoid"] = paranoid_tree
        local lean_tree = deep_copy(DEFAULTS)
        make_lean(lean_tree)
        PROFILES["lean"] = lean_tree
    end

    return M

end

end
__MODULES__['core/env'] = function(require)
--[[ ================================================================
    src/core/env.lua
    -----------------
    Single owner of every game.GetService reference plus a uniform
    "executor capability" probe. Every other module asks env for
    services / flags so we never re-call GetService at hot paths and
    so we have a single point of truth for which executor APIs we
    can lean on.

    Returned table is read-only after init(); attempting to write to
    a frozen field is a no-op (warn instead of error to keep the
    bypass alive even if a child module misbehaves).

    Required by:
        core/log
        core/state
        core/config
        core/version
        hooks/*
        masks/*
        scrubbers/*
        decoys/*
        spoof/*
        silencers/*
        grg/*
        sandbox/*
        netgate/*
        integrity/*
        ui/*
        boot
================================================================ ]]

return function(require)

    local M = {}

    -- ----------------------------------------------------------------
    -- 1. service refs
    -- ----------------------------------------------------------------

    local function safe_service(name)
        local ok, svc = pcall(function() return game:GetService(name) end)
        if ok then return svc end
        return nil
    end

    M.Players          = safe_service("Players")
    M.RunService       = safe_service("RunService")
    M.UserInputService = safe_service("UserInputService")
    M.ReplicatedStorage = safe_service("ReplicatedStorage")
    M.Lighting         = safe_service("Lighting")
    M.CoreGui          = safe_service("CoreGui")
    M.StarterGui       = safe_service("StarterGui")
    M.HttpService      = safe_service("HttpService")
    M.Workspace        = safe_service("Workspace")
    M.TeleportService  = safe_service("TeleportService")
    M.GuiService       = safe_service("GuiService")
    M.SoundService     = safe_service("SoundService")
    M.TweenService     = safe_service("TweenService")
    M.MarketplaceService = safe_service("MarketplaceService")
    M.Stats            = safe_service("Stats")
    M.LogService       = safe_service("LogService")
    M.Debris           = safe_service("Debris")
    M.PathfindingService = safe_service("PathfindingService")
    M.CollectionService = safe_service("CollectionService")
    M.ContextActionService = safe_service("ContextActionService")
    M.NetworkClient    = safe_service("NetworkClient")
    M.ScriptContext    = safe_service("ScriptContext")
    M.HapticService    = safe_service("HapticService")
    M.UserGameSettings = nil
    pcall(function() M.UserGameSettings = UserSettings():GetService("UserGameSettings") end)

    M.LocalPlayer      = M.Players and M.Players.LocalPlayer or nil
    M.PlayerScripts    = M.LocalPlayer and M.LocalPlayer:FindFirstChild("PlayerScripts") or nil
    M.PlayerGui        = M.LocalPlayer and M.LocalPlayer:FindFirstChild("PlayerGui") or nil
    M.Backpack         = M.LocalPlayer and M.LocalPlayer:FindFirstChild("Backpack") or nil

    M.PlaceId          = game.PlaceId
    M.JobId            = tostring(game.JobId or "")
    M.GameName         = "Generic Roleplay Game"
    M.IsTargetGame     = (M.PlaceId == 4598019433)
    M.SessionStartTime = os.time()
    M.SessionStartTick = tick()

    -- ----------------------------------------------------------------
    -- 2. executor identity
    -- ----------------------------------------------------------------

    local function call(fn)
        if type(fn) ~= "function" then return nil end
        local ok, v = pcall(fn)
        if ok then return v end
        return nil
    end

    local exe = call(identifyexecutor) or call(getexecutorname) or "unknown"
    if type(exe) == "table" then exe = tostring(exe[1]) end
    M.ExecutorName = tostring(exe)

    local lower_exe = string.lower(M.ExecutorName)
    M.IsMacSploit  = lower_exe:find("macsploit", 1, true) ~= nil
    M.IsSynapse    = lower_exe:find("synapse",   1, true) ~= nil
    M.IsScriptware = lower_exe:find("scriptware", 1, true) ~= nil
    M.IsKrnl       = lower_exe:find("krnl",      1, true) ~= nil
    M.IsFluxus     = lower_exe:find("fluxus",    1, true) ~= nil
    M.IsHydrogen   = lower_exe:find("hydrogen",  1, true) ~= nil
    M.IsArceusX    = lower_exe:find("arceus",    1, true) ~= nil
    M.IsCelery     = lower_exe:find("celery",    1, true) ~= nil
    M.IsCometX     = lower_exe:find("comet",     1, true) ~= nil
    M.IsDelta      = lower_exe:find("delta",     1, true) ~= nil
    M.IsCodeX      = lower_exe:find("codex",     1, true) ~= nil
    M.IsOpiumware  = lower_exe:find("opium",     1, true) ~= nil

    -- ----------------------------------------------------------------
    -- 3. capability probe
    -- ----------------------------------------------------------------

    local function has_global(name)
        return rawget(getfenv(0), name) ~= nil or _G[name] ~= nil
    end

    local function has_fn(name)
        local fn = rawget(getfenv(0), name)
        if fn == nil then fn = _G[name] end
        return type(fn) == "function"
    end

    M.Caps = {
        hookmetamethod   = has_fn("hookmetamethod"),
        hookfunction     = has_fn("hookfunction"),
        getrawmetatable  = has_fn("getrawmetatable"),
        setrawmetatable  = has_fn("setrawmetatable"),
        setreadonly      = has_fn("setreadonly"),
        isreadonly       = has_fn("isreadonly"),
        checkcaller      = has_fn("checkcaller"),
        islclosure       = has_fn("islclosure"),
        iscclosure       = has_fn("iscclosure"),
        clonefunction    = has_fn("clonefunction"),
        getconnections   = has_fn("getconnections"),
        getsenv          = has_fn("getsenv"),
        getgenv          = has_fn("getgenv"),
        getrenv          = has_fn("getrenv"),
        getreg           = has_fn("getreg"),
        getgc            = has_fn("getgc"),
        getloadedmodules = has_fn("getloadedmodules"),
        getscripts       = has_fn("getscripts"),
        getrunningscripts = has_fn("getrunningscripts"),
        getnamecallmethod = has_fn("getnamecallmethod"),
        setnamecallmethod = has_fn("setnamecallmethod"),
        firetouchinterest = has_fn("firetouchinterest"),
        fireclickdetector = has_fn("fireclickdetector"),
        firesignal        = has_fn("firesignal"),
        replicatesignal   = has_fn("replicatesignal"),
        gethui            = has_fn("gethui"),
        getidentity       = has_fn("getidentity"),
        setidentity       = has_fn("setidentity"),
        getthreadidentity = has_fn("getthreadidentity"),
        setthreadidentity = has_fn("setthreadidentity"),
        debuggetinfo      = (debug ~= nil and type(debug.info) == "function"),
        debuggetlocal     = (debug ~= nil and type(debug.getlocal) == "function"),
        debugsetlocal     = (debug ~= nil and type(debug.setlocal) == "function"),
        debuggetupvalue   = (debug ~= nil and type(debug.getupvalue) == "function"),
        debugsetupvalue   = (debug ~= nil and type(debug.setupvalue) == "function"),
        debuggetregistry  = (debug ~= nil and type(debug.getregistry) == "function"),
        writefile         = has_fn("writefile"),
        readfile          = has_fn("readfile"),
        appendfile        = has_fn("appendfile"),
        listfiles         = has_fn("listfiles"),
        isfile            = has_fn("isfile"),
        isfolder          = has_fn("isfolder"),
        makefolder        = has_fn("makefolder"),
        delfile           = has_fn("delfile"),
        delfolder         = has_fn("delfolder"),
        setclipboard      = has_fn("setclipboard"),
        request           = has_fn("request") or has_fn("http_request") or has_fn("syn_request"),
        hookpacket        = has_fn("hookpacket"),
        sendpacket        = has_fn("sendpacket"),
        setmovementoverride = has_fn("setmovementoverride"),
        queue_on_teleport = has_fn("queue_on_teleport") or has_fn("syn_queue_on_teleport"),
    }

    -- Convenience: fast canonical aliases regardless of executor.
    M.hookmm   = rawget(getfenv(0), "hookmetamethod") or _G.hookmetamethod
    M.hookfn   = rawget(getfenv(0), "hookfunction")   or _G.hookfunction
    M.grm      = rawget(getfenv(0), "getrawmetatable") or _G.getrawmetatable
    M.srm      = rawget(getfenv(0), "setrawmetatable") or _G.setrawmetatable
    M.sro      = rawget(getfenv(0), "setreadonly")    or _G.setreadonly
    M.iro      = rawget(getfenv(0), "isreadonly")     or _G.isreadonly
    M.ckcaller = rawget(getfenv(0), "checkcaller")    or _G.checkcaller
    M.gnm      = rawget(getfenv(0), "getnamecallmethod") or _G.getnamecallmethod
    M.snm      = rawget(getfenv(0), "setnamecallmethod") or _G.setnamecallmethod
    M.cln      = rawget(getfenv(0), "clonefunction")  or _G.clonefunction or function(f) return f end
    M.gcons    = rawget(getfenv(0), "getconnections") or _G.getconnections

    -- ----------------------------------------------------------------
    -- 4. shared "vanilla" callbacks (so we can call original methods)
    -- ----------------------------------------------------------------

    -- Cache method clones up-front so AC scripts hooking later
    -- methods don't poison our calls. We're loaded BEFORE the main hub
    -- and (we hope) before AC's most aggressive hook stage.
    local function clone_method(inst, name)
        local ok, fn = pcall(function() return inst[name] end)
        if not ok or type(fn) ~= "function" then return nil end
        if M.cln then
            local ok2, copy = pcall(M.cln, fn)
            if ok2 then return copy end
        end
        return fn
    end

    M.OriginalMethods = {
        FireServer       = clone_method(Instance.new("RemoteEvent"), "FireServer"),
        InvokeServer     = clone_method(Instance.new("RemoteFunction"), "InvokeServer"),
        Kick             = M.LocalPlayer and clone_method(M.LocalPlayer, "Kick") or nil,
        Destroy          = clone_method(Instance.new("Folder"), "Destroy"),
        FindFirstChild   = clone_method(Instance.new("Folder"), "FindFirstChild"),
        WaitForChild     = clone_method(Instance.new("Folder"), "WaitForChild"),
        GetChildren      = clone_method(Instance.new("Folder"), "GetChildren"),
        GetDescendants   = clone_method(Instance.new("Folder"), "GetDescendants"),
        GetService       = clone_method(game, "GetService"),
        IsA              = clone_method(Instance.new("Folder"), "IsA"),
        GetFullName      = clone_method(Instance.new("Folder"), "GetFullName"),
        GetAttribute     = clone_method(Instance.new("Folder"), "GetAttribute"),
        SetAttribute     = clone_method(Instance.new("Folder"), "SetAttribute"),
    }

    -- ----------------------------------------------------------------
    -- 5. helpers
    -- ----------------------------------------------------------------

    function M.uptime()
        return tick() - M.SessionStartTick
    end

    function M.now_ts()
        return os.time()
    end

    function M.fmt_uptime()
        local s = math.floor(M.uptime())
        local h = math.floor(s / 3600)
        local m = math.floor((s % 3600) / 60)
        local r = s % 60
        return string.format("%02d:%02d:%02d", h, m, r)
    end

    function M.in_target_game()
        return M.IsTargetGame
    end

    function M.get_character()
        if not M.LocalPlayer then return nil end
        return M.LocalPlayer.Character
    end

    function M.get_humanoid()
        local c = M.get_character()
        if not c then return nil end
        return c:FindFirstChildOfClass("Humanoid")
    end

    function M.get_root()
        local c = M.get_character()
        if not c then return nil end
        return c:FindFirstChild("HumanoidRootPart")
            or c:FindFirstChild("Torso")
            or c:FindFirstChild("UpperTorso")
            or c.PrimaryPart
    end

    function M.get_remotes_folder()
        if not M.ReplicatedStorage then return nil end
        return M.ReplicatedStorage:FindFirstChild("Remotes")
    end

    function M.find_remote(name)
        local rf = M.get_remotes_folder()
        if not rf then return nil end
        return rf:FindFirstChild(name)
    end

    function M.cap_summary()
        local on = {}
        local off = {}
        for k, v in pairs(M.Caps) do
            if v then table.insert(on, k) else table.insert(off, k) end
        end
        table.sort(on); table.sort(off)
        return on, off
    end

    return M

end

end
__MODULES__['core/executor_caps'] = function(require)
--[[ ================================================================
    src/core/executor_caps.lua
    ---------------------------
    Friendly summary table for env.Caps plus a panic-mode checker.

    env.lua already runs the raw probe (which globals exist). This
    module interprets the probe into "tiers":

        tier = "full"     -> every hook/file/packet API available
        tier = "hook"     -> metamethod + function hook, file I/O ok
        tier = "basic"    -> only metamethod hook (MacSploit class)
        tier = "minimal"  -> no hook API at all; we can only mutate
                              through our own remote wrappers

    Each module should check the tier via caps.tier_allows(required)
    before assuming the API exists. If the tier isn't met, the module
    logs a WARN and installs itself in "pass-through" mode where it
    still exists but does nothing.

    Why a separate file from env.lua?  env.lua is called by log.lua,
    and log.lua is called by everything. We want caps logic to
    reference log.lua for WARN output. Keeping them separate breaks
    the require cycle.
================================================================ ]]

return function(require)

    local env = require("core/env")
    local log = require("core/log")

    local M = {}
    local L = log.scoped("core/caps")

    -- ----------------------------------------------------------------
    -- 1. required primitives per tier
    -- ----------------------------------------------------------------

    local REQUIRED_FULL    = {
        "hookmetamethod", "hookfunction", "getrawmetatable", "setrawmetatable",
        "setreadonly",    "isreadonly",   "checkcaller",     "getconnections",
        "getnamecallmethod", "setnamecallmethod", "clonefunction",
        "writefile",      "readfile",     "isfile",
    }

    local REQUIRED_HOOK    = {
        "hookmetamethod", "hookfunction", "getrawmetatable",
        "setrawmetatable", "setreadonly", "checkcaller",
        "getnamecallmethod", "clonefunction",
    }

    local REQUIRED_BASIC   = {
        "hookmetamethod", "getrawmetatable",
        "setrawmetatable", "setreadonly", "getnamecallmethod",
    }

    local function satisfies(list)
        for _, name in ipairs(list) do
            if not env.Caps[name] then return false, name end
        end
        return true
    end

    -- ----------------------------------------------------------------
    -- 2. compute tier
    -- ----------------------------------------------------------------

    local ok, _missing = satisfies(REQUIRED_FULL)
    if ok then
        M.tier = "full"
    else
        ok, _missing = satisfies(REQUIRED_HOOK)
        if ok then
            M.tier = "hook"
        else
            ok, _missing = satisfies(REQUIRED_BASIC)
            M.tier = ok and "basic" or "minimal"
        end
    end

    local TIER_RANK = { minimal = 0, basic = 1, hook = 2, full = 3 }

    function M.tier_rank()
        return TIER_RANK[M.tier] or 0
    end

    function M.tier_allows(required_tier)
        return M.tier_rank() >= (TIER_RANK[required_tier] or 0)
    end

    -- ----------------------------------------------------------------
    -- 3. per-feature gates
    -- ----------------------------------------------------------------

    M.can_hook_namecall    = env.Caps.hookmetamethod
    M.can_hook_newindex    = env.Caps.hookmetamethod
    M.can_hook_index       = env.Caps.hookmetamethod
    M.can_hook_function    = env.Caps.hookfunction
    M.can_clone_fn         = env.Caps.clonefunction
    M.can_identity_raise   = env.Caps.setthreadidentity or env.Caps.setidentity
    M.can_write_files      = env.Caps.writefile
    M.can_read_files       = env.Caps.readfile
    M.can_list_files       = env.Caps.listfiles
    M.can_set_clipboard    = env.Caps.setclipboard
    M.can_http_request     = env.Caps.request
    M.can_hook_packet      = env.Caps.hookpacket
    M.can_send_packet      = env.Caps.sendpacket
    M.can_override_move    = env.Caps.setmovementoverride
    M.can_gethui           = env.Caps.gethui

    -- ----------------------------------------------------------------
    -- 4. panic / warning
    -- ----------------------------------------------------------------

    if M.tier == "minimal" then
        L:error("executor tier = minimal: hookmetamethod missing. bypass will run but be weak.")
    elseif M.tier == "basic" then
        L:warn("executor tier = basic: no hookfunction/checkcaller; AC-side hook chain detection may bite us")
    else
        L:info("executor tier = %s", M.tier)
    end

    if env.IsMacSploit and not M.can_hook_packet then
        L:info("MacSploit detected without hookpacket; RakNet-level drops disabled, falling back to namecall layer")
    end

    function M.summary()
        return string.format(
            "tier=%s namecall=%s newindex=%s fn_hook=%s packet=%s files=%s",
            M.tier,
            tostring(M.can_hook_namecall),
            tostring(M.can_hook_newindex),
            tostring(M.can_hook_function),
            tostring(M.can_hook_packet),
            tostring(M.can_write_files))
    end

    return M

end

end
__MODULES__['core/log'] = function(require)
--[[ ================================================================
    src/core/log.lua
    -----------------
    Leveled, ring-buffered, filterable logger.

    Levels (highest -> lowest noise):
        TRACE  -- per-frame deltas, mask intercept payload bodies
        DEBUG  -- hook firings, namecall pass-throughs
        INFO   -- module init, state transitions
        WARN   -- recoverable anomalies, hook re-installs
        ERROR  -- failed hooks, missing remotes, blocked panics

    Output sinks (any combination):
        - stdout (warn() / print())
        - in-memory ring buffer (~512 entries) for the UI panel
        - on-disk journal (writefile) keyed by jobId

    All sinks are async-safe (we just append; consumers iterate).

    Usage:
        local log = require("core/log")
        local L   = log.scoped("hooks/namecall")
        L:info("registered handler for %s", "Kick")
        L:warn("AC re-hook detected")
        L:error("hookmetamethod missing")

    Ring buffer is exposed via log.snapshot() so the UI panel can
    pull the last N entries without blocking the main thread.
================================================================ ]]

return function(require)

    local env = require("core/env")

    local M = {}

    local LEVELS = { TRACE = 1, DEBUG = 2, INFO = 3, WARN = 4, ERROR = 5 }
    local LEVEL_NAME = { "TRACE", "DEBUG", "INFO", "WARN", "ERROR" }

    local CFG = {
        threshold      = LEVELS.INFO,
        ring_capacity  = 512,
        echo_to_stdout = true,
        echo_to_file   = env.Caps.writefile or false,
        scope_filter   = nil,         -- substring match, nil = all
        time_provider  = function() return env.uptime() end,
    }

    local RING = {}
    local RING_HEAD = 1   -- next slot to write
    local RING_COUNT = 0
    local FILE_NAME = string.format("grg_acbypass_%d_%s.log",
        env.PlaceId,
        (env.JobId:gsub("[^%w]", "")):sub(1, 12) ~= "" and (env.JobId:gsub("[^%w]", "")):sub(1, 12) or "studio")

    -- ----------------------------------------------------------------
    -- ring buffer
    -- ----------------------------------------------------------------

    local function ring_push(entry)
        RING[RING_HEAD] = entry
        RING_HEAD = RING_HEAD + 1
        if RING_HEAD > CFG.ring_capacity then RING_HEAD = 1 end
        if RING_COUNT < CFG.ring_capacity then RING_COUNT = RING_COUNT + 1 end
    end

    function M.snapshot(limit)
        limit = math.min(limit or RING_COUNT, RING_COUNT)
        local out = {}
        local idx = RING_HEAD - 1
        if idx < 1 then idx = CFG.ring_capacity end
        for i = 1, limit do
            local e = RING[idx]
            if e then table.insert(out, 1, e) end
            idx = idx - 1
            if idx < 1 then idx = CFG.ring_capacity end
        end
        return out
    end

    function M.clear()
        RING = {}
        RING_HEAD = 1
        RING_COUNT = 0
    end

    function M.count()
        return RING_COUNT
    end

    -- ----------------------------------------------------------------
    -- file sink (writefile w/ append fallback)
    -- ----------------------------------------------------------------

    local function append_file(line)
        if not CFG.echo_to_file then return end
        if appendfile then
            pcall(appendfile, FILE_NAME, line .. "\n")
            return
        end
        if writefile and readfile and isfile then
            local prev = ""
            if isfile(FILE_NAME) then
                local ok, content = pcall(readfile, FILE_NAME)
                if ok then prev = content end
            end
            pcall(writefile, FILE_NAME, prev .. line .. "\n")
        end
    end

    -- ----------------------------------------------------------------
    -- format helpers
    -- ----------------------------------------------------------------

    local function safe_fmt(fmt, ...)
        local n = select("#", ...)
        if n == 0 then return tostring(fmt) end
        local ok, out = pcall(string.format, fmt, ...)
        if ok then return out end
        local parts = { tostring(fmt) }
        for i = 1, n do
            parts[#parts + 1] = tostring(select(i, ...))
        end
        return table.concat(parts, " ")
    end

    local function emit(level, scope, msg)
        local entry = {
            t      = CFG.time_provider(),
            ts     = os.time(),
            level  = level,
            lvl    = LEVEL_NAME[level],
            scope  = scope,
            msg    = msg,
        }
        ring_push(entry)
        if CFG.echo_to_stdout and level >= CFG.threshold then
            local prefix = string.format("[grg/ac %5s %s] ", entry.lvl, scope)
            if level >= LEVELS.WARN then
                warn(prefix .. msg)
            else
                print(prefix .. msg)
            end
        end
        if level >= LEVELS.WARN then
            -- Always journal warnings/errors regardless of stdout filter.
            local line = string.format("[%07.2f|%s|%s] %s",
                entry.t, entry.lvl, entry.scope, msg)
            append_file(line)
        elseif level >= CFG.threshold then
            local line = string.format("[%07.2f|%s|%s] %s",
                entry.t, entry.lvl, entry.scope, msg)
            append_file(line)
        end
    end

    -- ----------------------------------------------------------------
    -- public API
    -- ----------------------------------------------------------------

    function M.set_threshold(level_name)
        local lvl = LEVELS[string.upper(tostring(level_name))]
        if lvl then CFG.threshold = lvl end
    end

    function M.set_scope_filter(substr) CFG.scope_filter = substr end
    function M.enable_stdout(v) CFG.echo_to_stdout = v and true or false end
    function M.enable_file(v)   CFG.echo_to_file   = v and true or false end
    function M.file_name() return FILE_NAME end

    local function should_emit(scope)
        if not CFG.scope_filter then return true end
        return string.find(scope, CFG.scope_filter, 1, true) ~= nil
    end

    function M.trace(scope, fmt, ...)
        if not should_emit(scope) then return end
        emit(LEVELS.TRACE, scope, safe_fmt(fmt, ...))
    end
    function M.debug(scope, fmt, ...)
        if not should_emit(scope) then return end
        emit(LEVELS.DEBUG, scope, safe_fmt(fmt, ...))
    end
    function M.info(scope, fmt, ...)
        if not should_emit(scope) then return end
        emit(LEVELS.INFO, scope, safe_fmt(fmt, ...))
    end
    function M.warn(scope, fmt, ...)
        if not should_emit(scope) then return end
        emit(LEVELS.WARN, scope, safe_fmt(fmt, ...))
    end
    function M.error(scope, fmt, ...)
        if not should_emit(scope) then return end
        emit(LEVELS.ERROR, scope, safe_fmt(fmt, ...))
    end

    -- Scoped helper: returns a small object whose methods bind `scope`.
    function M.scoped(scope)
        local L = {}
        function L:trace(fmt, ...) M.trace(scope, fmt, ...) end
        function L:debug(fmt, ...) M.debug(scope, fmt, ...) end
        function L:info(fmt, ...)  M.info(scope, fmt, ...)  end
        function L:warn(fmt, ...)  M.warn(scope, fmt, ...)  end
        function L:error(fmt, ...) M.error(scope, fmt, ...) end
        return L
    end

    -- One-shot dump: writes the entire ring buffer to disk under a
    -- fresh suffix. Used by ui/status_panel "DUMP" button.
    function M.dump_now()
        if not env.Caps.writefile then return false, "no writefile" end
        local snap = M.snapshot(CFG.ring_capacity)
        local lines = { "# grg/ac log dump", "# unix=" .. os.time(), "" }
        for _, e in ipairs(snap) do
            lines[#lines + 1] = string.format("[%07.2f|%s|%s] %s",
                e.t, e.lvl, e.scope, e.msg)
        end
        local fname = FILE_NAME:gsub("%.log$", "_dump.log")
        pcall(writefile, fname, table.concat(lines, "\n"))
        return true, fname
    end

    -- Banner so journal files are easy to identify.
    M.info("core/log",
        "logger init: place=%d job=%s exe=%s file=%s",
        env.PlaceId, env.JobId, env.ExecutorName, FILE_NAME)

    return M

end

end
__MODULES__['core/maid'] = function(require)
--[[ ================================================================
    src/core/maid.lua
    ------------------
    Disposable-bag pattern. Attach RBXScriptConnection / Instance /
    function / table-with-:Destroy / table-with-:disconnect. When
    cleaned, every attached item is torn down in REVERSE order.

    Usage:
        local Maid = require("core/maid")
        local m = Maid.new()
        m:add(conn)
        m:add(part)
        m:add(function() print("bye") end)
        ...
        m:clean()

    Each module (mask, scrubber, ...) creates its own maid so the UI
    "kill switch" and integrity/recovery can wipe everything.
================================================================ ]]

return function(require)

    local M = {}
    local Maid = {}
    Maid.__index = Maid

    function M.new()
        return setmetatable({_items = {}, _named = {}}, Maid)
    end

    local function tear_down(item)
        if item == nil then return end
        local t = type(item)
        if t == "function" then
            pcall(item)
            return
        end
        if t == "RBXScriptConnection" then
            pcall(function() item:Disconnect() end)
            return
        end
        if t == "Instance" then
            pcall(function() item:Destroy() end)
            return
        end
        if t == "table" then
            if type(item.Destroy) == "function" then
                pcall(item.Destroy, item); return
            end
            if type(item.destroy) == "function" then
                pcall(item.destroy, item); return
            end
            if type(item.Disconnect) == "function" then
                pcall(item.Disconnect, item); return
            end
            if type(item.disconnect) == "function" then
                pcall(item.disconnect, item); return
            end
            if type(item.clean) == "function" then
                pcall(item.clean, item); return
            end
        end
    end

    function Maid:add(item)
        if item == nil then return item end
        table.insert(self._items, item)
        return item
    end

    function Maid:add_named(name, item)
        if item == nil then return item end
        if self._named[name] then
            tear_down(self._named[name])
        end
        self._named[name] = item
        return item
    end

    function Maid:remove_named(name)
        local v = self._named[name]
        if v ~= nil then
            tear_down(v)
            self._named[name] = nil
        end
    end

    function Maid:clean()
        local items = self._items
        self._items = {}
        for i = #items, 1, -1 do tear_down(items[i]) end
        for k, v in pairs(self._named) do
            tear_down(v); self._named[k] = nil
        end
    end

    function Maid:size()
        local n = #self._items
        for _ in pairs(self._named) do n = n + 1 end
        return n
    end

    Maid.destroy   = Maid.clean
    Maid.Destroy   = Maid.clean
    Maid.give_task = Maid.add

    return M

end

end
__MODULES__['core/signal'] = function(require)
--[[ ================================================================
    src/core/signal.lua
    --------------------
    Tiny signal class. Used by state.lua for change notifications and
    by integrity/hook_persistence for "hook lost" events. Roblox's
    BindableEvent is heavier, copies arguments through replication
    machinery, and has subtle ordering quirks; we just want a
    same-thread fire-and-forget multicast.

    API:
        local Signal = require("core/signal")
        local s = Signal.new()
        local conn = s:connect(function(...) ... end)
        s:fire(arg1, arg2)
        conn:disconnect()

    Connections returned have :disconnect() and :is_connected().
    Fire is reentrant-safe -- handlers added/removed during a fire
    take effect on the NEXT fire, not the current one.

    Wait() blocks the calling coroutine until the next fire and
    returns the args (Roblox-task-spawned).
================================================================ ]]

return function(require)

    local M = {}
    local Signal = {}
    Signal.__index = Signal

    function M.new()
        local self = setmetatable({}, Signal)
        self._handlers = {}
        self._waiters  = {}
        self._next_id  = 0
        return self
    end

    function Signal:connect(fn)
        if type(fn) ~= "function" then
            error("[grg/ac signal] connect requires function, got " .. type(fn), 2)
        end
        self._next_id = self._next_id + 1
        local id = self._next_id
        self._handlers[id] = fn
        local conn = {}
        local connected = true
        function conn:disconnect()
            if not connected then return end
            connected = false
            self._handlers[id] = nil
        end
        function conn:is_connected() return connected end
        -- Bind self so closure over the right table works after gc.
        getmetatable(conn).__index = nil  -- nop
        local outer = self
        function conn:disconnect()
            if not connected then return end
            connected = false
            outer._handlers[id] = nil
        end
        return conn
    end

    function Signal:once(fn)
        local conn
        conn = self:connect(function(...)
            conn:disconnect()
            fn(...)
        end)
        return conn
    end

    function Signal:fire(...)
        -- Snapshot so handlers added/removed mid-fire don't blow up.
        local snap = {}
        for id, fn in pairs(self._handlers) do snap[id] = fn end
        for _, fn in pairs(snap) do
            local ok, err = pcall(fn, ...)
            if not ok then
                warn("[grg/ac signal] handler error: " .. tostring(err))
            end
        end
        local waiters = self._waiters
        self._waiters = {}
        local args = { ... }
        local n = select("#", ...)
        for _, co in ipairs(waiters) do
            local ok, err = coroutine.resume(co, table.unpack(args, 1, n))
            if not ok then
                warn("[grg/ac signal] waiter resume error: " .. tostring(err))
            end
        end
    end

    function Signal:wait()
        table.insert(self._waiters, coroutine.running())
        return coroutine.yield()
    end

    function Signal:disconnect_all()
        self._handlers = {}
    end

    function Signal:handler_count()
        local n = 0
        for _ in pairs(self._handlers) do n = n + 1 end
        return n
    end

    return M

end

end
__MODULES__['core/state'] = function(require)
--[[ ================================================================
    src/core/state.lua
    -------------------
    Shared mutable runtime state for every bypass module.

    Counters (incremented by scrubbers/masks), last-seen snapshots
    (updated by decoys/spoof), and signals (fired by integrity).

    DESIGNED to be cheap to read from hot paths: every counter is a
    plain integer, incremented in place. Listeners hook :on_change
    via Signal, not polling.

    Public tables live on M.Counters / M.LastSeen / M.Signals so UI
    can pull them directly.
================================================================ ]]

return function(require)

    local Signal = require("core/signal")

    local M = {}

    -- ----------------------------------------------------------------
    -- 1. counters
    -- ----------------------------------------------------------------

    M.Counters = {
        -- namecall traffic
        namecall_total        = 0,
        namecall_blocked      = 0,
        namecall_mutated      = 0,

        -- newindex traffic
        newindex_total        = 0,
        newindex_blocked      = 0,
        newindex_mutated      = 0,

        -- index traffic
        index_total           = 0,
        index_mutated         = 0,

        -- kick / teleport chain
        kick_attempts         = 0,
        kick_blocked          = 0,
        kick_allowed          = 0,
        teleport_attempts     = 0,
        teleport_blocked      = 0,
        teleport_allowed      = 0,

        -- GRG-specific
        shadowban_dropped     = 0,
        ragdoll_dropped       = 0,
        updateprofile_sanitized = 0,
        coregui_warning_blocked = 0,

        -- masks
        walkspeed_read_masked = 0,
        walkspeed_write_masked= 0,
        jumppower_read_masked = 0,
        jumppower_write_masked= 0,
        position_masked       = 0,
        gravity_masked        = 0,

        -- spoof / decoys
        fingerprint_wipes     = 0,
        decoy_fires           = 0,
        profile_spoofs        = 0,

        -- netgate
        send_filtered         = 0,
        recv_filtered         = 0,
        rate_limit_drops      = 0,
        jitter_delays         = 0,

        -- integrity
        hook_restores         = 0,
        hook_losses_detected  = 0,
        panics                = 0,
    }

    local COUNTER_ORDER = {}
    for k in pairs(M.Counters) do table.insert(COUNTER_ORDER, k) end
    table.sort(COUNTER_ORDER)
    M._counter_order = COUNTER_ORDER

    function M:bump(key, by)
        by = by or 1
        if M.Counters[key] == nil then M.Counters[key] = 0 end
        M.Counters[key] = M.Counters[key] + by
    end

    function M:counter(key) return M.Counters[key] or 0 end

    function M:counter_snapshot()
        local out = {}
        for k, v in pairs(M.Counters) do out[k] = v end
        return out
    end

    -- ----------------------------------------------------------------
    -- 2. last-seen values
    -- ----------------------------------------------------------------

    M.LastSeen = {
        kick_reason        = nil,
        kick_source        = nil,
        kick_time          = 0,
        teleport_target    = nil,
        teleport_time      = 0,
        shadowban_payload  = nil,
        shadowban_time     = 0,
        ragdoll_payload    = nil,
        ragdoll_time       = 0,
        last_updateprofile = nil,
        last_updateprofile_sent = nil,
        last_walkspeed_set = nil,
        last_walkspeed_set_src = nil,
        last_walkspeed_set_time = 0,
        last_position      = nil,
        last_velocity      = nil,
        last_hook_restore_at = 0,
        last_panic_reason  = nil,
        last_panic_at      = 0,
    }

    function M:set_last(key, val)
        M.LastSeen[key] = val
    end

    function M:get_last(key) return M.LastSeen[key] end

    -- ----------------------------------------------------------------
    -- 3. flags (status bits)
    -- ----------------------------------------------------------------

    M.Flags = {
        initialized         = false,
        ui_visible          = false,
        panic_active        = false,
        hooks_installed     = false,
        ac_bypass_active    = false,
        in_target_game      = false,
        masking_active      = false,
        scrubbing_active    = false,
        integrity_running   = false,
        kill_switched       = false,
    }

    function M:flag(k, v)
        if v == nil then return M.Flags[k] end
        M.Flags[k] = v
        return v
    end

    -- ----------------------------------------------------------------
    -- 4. journals (append-only)
    -- ----------------------------------------------------------------

    M.Journals = {
        kicks       = {},
        teleports   = {},
        shadowbans  = {},
        ragdolls    = {},
        hook_events = {},
        panics      = {},
    }

    local MAX_JOURNAL = 256

    function M:journal(key, entry)
        local j = M.Journals[key]
        if not j then
            j = {}
            M.Journals[key] = j
        end
        table.insert(j, entry)
        if #j > MAX_JOURNAL then
            -- Drop oldest; keep memory bounded.
            table.remove(j, 1)
        end
    end

    -- ----------------------------------------------------------------
    -- 5. signals
    -- ----------------------------------------------------------------

    M.Signals = {
        KickBlocked        = Signal.new(),
        TeleportBlocked    = Signal.new(),
        ShadowbanBlocked   = Signal.new(),
        RagdollBlocked     = Signal.new(),
        ProfileMutated     = Signal.new(),
        MaskHit            = Signal.new(),
        HookLost           = Signal.new(),
        HookRestored       = Signal.new(),
        PanicRaised        = Signal.new(),
        KillSwitchFlipped  = Signal.new(),
        ProfileSwitched    = Signal.new(),
    }

    function M:emit(name, ...)
        local sig = M.Signals[name]
        if sig then sig:fire(...) end
    end

    -- ----------------------------------------------------------------
    -- 6. bulk reset for kill-switch / recovery
    -- ----------------------------------------------------------------

    function M:reset_counters()
        for k in pairs(M.Counters) do M.Counters[k] = 0 end
    end

    function M:reset_journals()
        for k in pairs(M.Journals) do M.Journals[k] = {} end
    end

    function M:full_reset()
        self:reset_counters()
        self:reset_journals()
        for k in pairs(M.Flags) do M.Flags[k] = false end
        for k in pairs(M.LastSeen) do M.LastSeen[k] = nil end
    end

    return M

end

end
__MODULES__['core/version'] = function(require)
--[[ ================================================================
    src/core/version.lua
    ---------------------
    Hard-coded version string. Bumped manually with each release.
================================================================ ]]

return function(require)

    local M = {}

    M.MAJOR    = 1
    M.MINOR    = 0
    M.PATCH    = 0
    M.CODENAME = "OPIUM"
    M.BUILD    = "20260425"
    M.STRING   = string.format("%d.%d.%d-%s+%s", M.MAJOR, M.MINOR, M.PATCH, M.CODENAME, M.BUILD)

    M.BANNER = [[
   _____ _____   _____    /\   _____   ____  __     ___  ___ ____
  / ____|  __ \ / ____|  /\ \ / ____| / __ \|  \  / /__ \|__ \  __|
 | |  __| |__) | |  __  /  \ \ |    /| |  | | |\ \/ /__) |  ) | |__
 | | |_ |  _  /| | |_ | / /\ \ \   |_| |  | | | \  /|__ <  / /|___ |
 | |__| | | \ \| |__| |/ ____ \ \  __| |__| | |  \/ ___) |/ /_____ |
  \_____|_|  \_\\_____|/_/    \_\\____\\____/|_|     |____/|______|

           GRG anti-cheat bypass  --  v]] .. nil

    -- Concatenating after a nil would error; build banner in pieces.
    M.BANNER = [[
   ____ ____ ____    ___ ____  __  __ ____  __ ____ ____ ____
  / ___|  _ \/ ___|  / _ \  _ \|  |/  \  _ \|  |  _ \_   _/ ___|
 | |  _| |_) \___ \ | | | | |_) |  /\  | |_) |  | |_) || \___ \
 | |_| |  _ < ___) || |_| |  _ <|  \/  |  _ <|  |  __/ |  ___) |
  \____|_| \_\____/  \___/|_| \_\___/\___| \_\_|_|    |_| |____/
                       a c   b y p a s s
]]

    function M.summary()
        return string.format(
            "GRG-AC v%s  --  GRG (%d) AC bypass, %s build",
            M.STRING, 4598019433, M.BUILD)
    end

    return M

end

end
__MODULES__['decoys/globals'] = function(require)
--[[ ================================================================
    src/decoys/globals.lua
    -----------------------
    Plants plausible-looking GLOBALS that AC-side probe scripts tend
    to sniff for. An anti-cheat that notices our hooks but ALSO sees
    a "__AC_STATUS = ok" and a familiar-looking GameController stub
    is statistically less likely to escalate -- ambient chaff matters
    more than individual mask fidelity at the cohort level.

    Values we seed:
        _G.__AC_STATUS       -> "ok"
        _G.__AC_LAST_CHECK   -> tick() (refreshed every 0.5s)
        _G.__AC_PLAYER       -> LocalPlayer.Name (snapshotted once)
        _G.GameController    -> { GetState(), ReportPosition(),
                                  GetPlayerData() } -- no-ops.
        _G.AntiCheat         -> { version, enabled, report() }

    Everything is gated individually via cfg decoys.globals.* so the
    "lean" profile can drop just the GameController noise if a game's
    real movement controller happens to stomp that name.

    We keep track of every key we installed so remove_all() is clean:
    a restart/reload can't leave orphan pointers hanging around in
    _G -- which would itself be a fingerprint ("why is there a stale
    AntiCheat table when the AC script was never loaded?").
================================================================ ]]

return function(require)

    local env    = require("core/env")
    local log    = require("core/log")
    local cfg    = require("core/config")
    local state  = require("core/state")

    local M = {}
    local L = log.scoped("decoys/globals")

    -- Keys we've planted into _G. key -> { original, installed_at }.
    local INSTALLED = {}

    -- Heartbeat connection; used to keep __AC_LAST_CHECK fresh.
    local TICK_CONN = nil

    ----------------------------------------------------------------
    -- 1. helpers
    ----------------------------------------------------------------

    local function mark(key, original)
        INSTALLED[key] = {
            original    = original,
            installed_at = tick(),
        }
    end

    local function install_raw(key, value)
        local prior = rawget(_G, key)
        rawset(_G, key, value)
        mark(key, prior)
    end

    -- Wrap a function so it silently swallows errors: AC probes often
    -- call weird things with weird args; a crash inside our decoy
    -- function is a pretty severe tell.
    local function safe_fn(fn, fallback)
        return function(...)
            local ok, a, b, c = pcall(fn, ...)
            if ok then return a, b, c end
            if fallback ~= nil then return fallback end
        end
    end

    local function current_player_name()
        if env.LocalPlayer and env.LocalPlayer.Name then
            return env.LocalPlayer.Name
        end
        return "Player"
    end

    ----------------------------------------------------------------
    -- 2. AC status / player globals
    ----------------------------------------------------------------

    local function install_ac_status()
        if not cfg:get("decoys.globals.install_fake_ac_table", true) then
            return
        end
        install_raw("__AC_STATUS",     "ok")
        install_raw("__AC_LAST_CHECK", tick())
        install_raw("__AC_PLAYER",     current_player_name())
        L:debug("planted __AC_STATUS/__AC_LAST_CHECK/__AC_PLAYER")
    end

    ----------------------------------------------------------------
    -- 3. GameController stub
    ----------------------------------------------------------------

    local function build_game_controller()
        -- Returning "Running" is the least suspicious value: a player
        -- who's just sitting still still reports Running for AC probes
        -- in most games.
        local gc = {}
        gc.GetState = safe_fn(function()
            return "Running"
        end, "Running")

        gc.ReportPosition = safe_fn(function(_self, pos)
            -- Intentionally a no-op: AC probes that call this want
            -- a confirmation that SOMEONE is handling position telemetry,
            -- not a real side-effect.
            return true
        end, true)

        gc.GetPlayerData = safe_fn(function()
            return {
                name   = current_player_name(),
                level  = 1,
                health = 100,
                state  = "Running",
            }
        end, {})

        gc.IsAlive = safe_fn(function() return true end, true)
        gc.Version = "1.4.0"
        gc.Build   = tostring(env.SessionStartTime)
        return gc
    end

    local function install_game_controller()
        if not cfg:get("decoys.globals.install_fake_controller", true) then
            return
        end
        install_raw("GameController", build_game_controller())
        L:debug("planted GameController stub")
    end

    ----------------------------------------------------------------
    -- 4. AntiCheat table
    ----------------------------------------------------------------

    local function build_anticheat_table()
        local ac = {
            version = "1.0.0",
            enabled = true,
            checks  = 0,
            started = tick(),
        }
        ac.report = safe_fn(function(_self, kind, payload)
            -- We pretend to accept the report silently. Some AC probes
            -- look for a non-nil return so we give them one.
            ac.checks = ac.checks + 1
            return true
        end, true)
        ac.isEnabled = safe_fn(function() return true end, true)
        ac.getStatus = safe_fn(function() return "ok" end, "ok")
        return ac
    end

    local function install_anticheat_table()
        if not cfg:get("decoys.globals.install_fake_report_fn", true) then
            return
        end
        install_raw("AntiCheat", build_anticheat_table())
        L:debug("planted AntiCheat table")
    end

    ----------------------------------------------------------------
    -- 5. heartbeat updater
    ----------------------------------------------------------------

    local function start_heartbeat()
        if TICK_CONN then return end
        if not env.RunService then
            L:warn("no RunService available; __AC_LAST_CHECK will not refresh")
            return
        end
        local last = tick()
        TICK_CONN = env.RunService.Heartbeat:Connect(function()
            local now = tick()
            if now - last < 0.5 then return end
            last = now
            -- Only refresh if our global is still present; if someone
            -- removed it, don't re-add it -- that would fight external
            -- intent and could look suspicious.
            if rawget(_G, "__AC_LAST_CHECK") ~= nil then
                rawset(_G, "__AC_LAST_CHECK", now)
            end
            local ac = rawget(_G, "AntiCheat")
            if type(ac) == "table" and type(ac.checks) == "number" then
                ac.checks = ac.checks + 1
            end
        end)
    end

    local function stop_heartbeat()
        if TICK_CONN then
            pcall(function() TICK_CONN:Disconnect() end)
            TICK_CONN = nil
        end
    end

    ----------------------------------------------------------------
    -- 6. public API
    ----------------------------------------------------------------

    function M.install()
        if not cfg:get("decoys.globals.enabled", true) then
            L:info("disabled via config")
            return
        end

        install_ac_status()
        install_game_controller()
        install_anticheat_table()
        start_heartbeat()

        state:flag("decoys_globals_installed", true)
        L:info("globals installed: %d keys", M.count_installed())
    end

    function M.list_installed()
        local out = {}
        for k in pairs(INSTALLED) do table.insert(out, k) end
        table.sort(out)
        return out
    end

    function M.count_installed()
        local n = 0
        for _ in pairs(INSTALLED) do n = n + 1 end
        return n
    end

    function M.remove_all()
        stop_heartbeat()
        for key, rec in pairs(INSTALLED) do
            -- Restore the original value (usually nil) so we leave no
            -- trace at all. rawset(nil) is how we clear the slot.
            local ok, err = pcall(function()
                rawset(_G, key, rec.original)
            end)
            if not ok then
                L:warn("couldn't remove _G.%s: %s", key, tostring(err))
            end
        end
        local n = M.count_installed()
        INSTALLED = {}
        state:flag("decoys_globals_installed", false)
        L:info("removed %d decoy globals", n)
        return n
    end

    function M.refresh_now()
        -- Manually bump the heartbeat fields. Handy when a subsystem
        -- knows the game just did an AC probe and wants the values to
        -- look freshly-updated (== tick() right now).
        if rawget(_G, "__AC_LAST_CHECK") ~= nil then
            rawset(_G, "__AC_LAST_CHECK", tick())
        end
    end

    return M

end

end
__MODULES__['decoys/input'] = function(require)
--[[ ================================================================
    src/decoys/input.lua
    ---------------------
    Spoofs UserInputService responses for AC probes.

    Games' anti-cheat clients frequently grab :GetMouseLocation() and
    :IsKeyDown(key) as part of a "is the player human" check, or to
    detect whether obvious cheat hotkeys (F for fly, E for noclip,
    Q for aim) are currently held. If the player is busy triggering
    our hotkeys, the naive IsKeyDown read leaks that.

    MITIGATION
    ----------
    A namecall hook on UserInputService redirects those method calls
    to safe defaults whenever caller_is_us() is false.

        GetMouseLocation()        -> center of screen Vector2
        IsKeyDown(key)            -> false if key is in SUSPICIOUS

    We DON'T touch InputBegan / InputEnded signals; those are the
    user-facing event stream that real game code wires against. We
    only lie to on-demand polling.

    OUR OWN MODULES
    ---------------
    When our own threads (marked via _G.__GRG_THREAD or detected by
    checkcaller) call these methods, we pass through untouched. This
    matters: several UI modules poll GetMouseLocation to position
    tooltips.
================================================================ ]]

return function(require)

    local env    = require("core/env")
    local log    = require("core/log")
    local cfg    = require("core/config")
    local state  = require("core/state")

    local namecall = require("hooks/namecall")

    local M = {}
    local L = log.scoped("decoys/input")

    ----------------------------------------------------------------
    -- 1. suspicious key set
    ----------------------------------------------------------------

    local SUSPICIOUS = {}   -- [Enum.KeyCode] = true

    local function seed_suspicious()
        -- A conservative default: letters commonly used as cheat
        -- hotkeys, plus LeftShift for speed toggles. Games that
        -- legitimately need polling for these keys will be broken
        -- by the decoy, which is why spoof_keyboard defaults to
        -- false in config.lua.
        local names = { "F", "E", "Q", "LeftShift", "X", "Z", "V" }
        for _, n in ipairs(names) do
            local ok, kc = pcall(function() return Enum.KeyCode[n] end)
            if ok and kc then SUSPICIOUS[kc] = true end
        end
    end
    seed_suspicious()

    ----------------------------------------------------------------
    -- 2. helpers
    ----------------------------------------------------------------

    local function caller_is_us()
        if _G.__GRG_THREAD then return true end
        if env.ckcaller then
            local ok, v = pcall(env.ckcaller)
            if ok and v then return true end
        end
        return false
    end

    local function screen_center()
        -- We'd love to read the actual viewport size, but doing so
        -- from within the hook can trigger recursion on some executors
        -- (GetService returning an instance whose __index is itself
        -- hooked). Safe fallback: 960x540. Good enough for anti-cheat
        -- probes that just want a "not 0,0" value.
        local vp = Vector2.new(960, 540)
        local cam = workspace and workspace.CurrentCamera
        if cam then
            local ok, vs = pcall(function() return cam.ViewportSize end)
            if ok and typeof(vs) == "Vector2" then
                vp = vs / 2
            end
        end
        return vp
    end

    ----------------------------------------------------------------
    -- 3. namecall handlers
    ----------------------------------------------------------------

    local function handle_get_mouse_location(ctx)
        if not cfg:get("decoys.input.spoof_mouse", false) then return end
        if caller_is_us() then return end
        ctx.short_circuit = true
        ctx.spoof = { screen_center() }
        state:bump("input_mouse_spoofed")
    end

    local function handle_is_key_down(ctx)
        if not cfg:get("decoys.input.spoof_keyboard", false) then return end
        if caller_is_us() then return end
        local key = ctx.args[1]
        if key == nil then return end
        if not SUSPICIOUS[key] then return end
        ctx.short_circuit = true
        ctx.spoof = { false }
        state:bump("input_key_spoofed")
    end

    ----------------------------------------------------------------
    -- 4. install
    ----------------------------------------------------------------

    function M.install()
        if not cfg:get("decoys.input.enabled", true) then
            L:info("disabled via config")
            return
        end

        namecall.register({
            name     = "decoy_input_get_mouse_location",
            class    = "UserInputService",
            method   = "GetMouseLocation",
            priority = 40,
            handler  = handle_get_mouse_location,
        })

        namecall.register({
            name     = "decoy_input_is_key_down",
            class    = "UserInputService",
            method   = "IsKeyDown",
            priority = 40,
            handler  = handle_is_key_down,
        })

        L:info("input decoy active (mouse=%s, keyboard=%s, keys=%d)",
            tostring(cfg:get("decoys.input.spoof_mouse", false)),
            tostring(cfg:get("decoys.input.spoof_keyboard", false)),
            M.count_spoof_keys())
    end

    ----------------------------------------------------------------
    -- 5. spoof-key management
    ----------------------------------------------------------------

    function M.add_spoof_key(key)
        if key == nil then return false end
        -- Accept either Enum.KeyCode value or a name string.
        if type(key) == "string" then
            local ok, kc = pcall(function() return Enum.KeyCode[key] end)
            if ok and kc then key = kc end
        end
        if typeof(key) ~= "EnumItem" then
            L:warn("add_spoof_key: ignoring non-KeyCode %s", tostring(key))
            return false
        end
        SUSPICIOUS[key] = true
        L:info("added spoof key %s", tostring(key))
        return true
    end

    function M.remove_spoof_key(key)
        if type(key) == "string" then
            local ok, kc = pcall(function() return Enum.KeyCode[key] end)
            if ok and kc then key = kc end
        end
        if SUSPICIOUS[key] then
            SUSPICIOUS[key] = nil
            return true
        end
        return false
    end

    function M.list_spoof_keys()
        local out = {}
        for kc in pairs(SUSPICIOUS) do table.insert(out, tostring(kc)) end
        table.sort(out)
        return out
    end

    function M.count_spoof_keys()
        local n = 0
        for _ in pairs(SUSPICIOUS) do n = n + 1 end
        return n
    end

    return M

end

end
__MODULES__['decoys/position'] = function(require)
--[[ ================================================================
    src/decoys/position.lua
    ------------------------
    Keeps the server's telemetry heartbeat alive by firing a
    sanitized UpdateProfile at a configurable cadence (default 4 Hz).

    WHY THIS EXISTS
    ---------------
    The upstream scrubber (scrubbers/updateprofile) may drop real
    UpdateProfile payloads when they look cheaty: a sudden zero-
    payload gap right when the player is clearly moving is itself
    a signature. This decoy makes sure that SOMETHING plausible
    keeps arriving on that remote even if every real fire gets
    canned.

    The payload it sends is boring-on-purpose:
        { walkSpeed = 16, position = last_safe, state = "Running",
          timestamp = tick() }

    LAST-SAFE POSITION
    ------------------
    We track HRP position every Heartbeat, but we CLAMP per-tick
    displacement to `payload_tolerance`. If the real character
    yeets across the map via a teleport, our decoy stream is
    unaffected -- it keeps reporting a physically plausible walk
    along an interpolated path. That's the whole point: the server
    must never see a cadence gap, AND never see an impossible jump
    attributable to us.

    THREAD-MARKING
    --------------
    Every fire goes through the namecall hook, so the central
    fire_handlers dispatcher WILL see our outgoing call. We set
    _G.__GRG_THREAD = true before FireServer so our other hooks
    treat the call as friendly and skip their scrub/mutate logic.

    PAUSE/RESUME
    ------------
    The UI module can pause/resume via M.pause()/M.resume() when the
    user temporarily wants full silence (e.g. while staging a macro
    trick that would be weird if accompanied by our telemetry).
================================================================ ]]

return function(require)

    local env    = require("core/env")
    local log    = require("core/log")
    local cfg    = require("core/config")
    local state  = require("core/state")

    local M = {}
    local L = log.scoped("decoys/position")

    -- module state -------------------------------------------------
    local LAST_SAFE   = nil       -- Vector3 or nil
    local LAST_FIRE_T = 0
    local LAST_TICK_T = 0
    local PAUSED      = false
    local RUNNING     = false
    local TICK_CONN   = nil
    local FIRE_CONN   = nil
    local REMOTE_CACHE = nil

    ----------------------------------------------------------------
    -- 1. remote resolution (with caching + re-lookup)
    ----------------------------------------------------------------

    local function resolve_remote()
        if REMOTE_CACHE and REMOTE_CACHE.Parent then
            return REMOTE_CACHE
        end
        local r = env.find_remote("UpdateProfile")
        if r then REMOTE_CACHE = r end
        return r
    end

    ----------------------------------------------------------------
    -- 2. safe position tracker
    ----------------------------------------------------------------

    local function clamp_vec_to_tolerance(from, to, tol)
        if not from then return to end
        if typeof(to) ~= "Vector3" then return from end
        local delta = to - from
        local mag = delta.Magnitude
        if mag <= tol or mag <= 0 then
            return to
        end
        return from + delta.Unit * tol
    end

    local function sample_safe_position()
        local root = env.get_root()
        if not root then return end
        local ok, pos = pcall(function() return root.Position end)
        if not ok or typeof(pos) ~= "Vector3" then return end

        local tol = cfg:get("decoys.position.payload_tolerance", 2.0)
        if LAST_SAFE == nil then
            LAST_SAFE = pos
        else
            LAST_SAFE = clamp_vec_to_tolerance(LAST_SAFE, pos, tol)
        end
    end

    ----------------------------------------------------------------
    -- 3. payload build + send
    ----------------------------------------------------------------

    local function build_payload()
        local pos = LAST_SAFE or Vector3.new(0, 0, 0)
        return {
            walkSpeed = 16,
            position  = pos,
            state     = "Running",
            timestamp = tick(),
        }
    end

    local function send_once()
        if PAUSED then return false, "paused" end

        local remote = resolve_remote()
        if not remote then
            L:debug("UpdateProfile remote not found; skipping fire")
            return false, "no_remote"
        end

        local fire = env.OriginalMethods and env.OriginalMethods.FireServer
        if type(fire) ~= "function" then
            L:warn("FireServer clone missing; aborting send")
            return false, "no_fireserver"
        end

        local payload = build_payload()

        -- Mark our own thread so our hooks know to pass through.
        local prior_flag = rawget(_G, "__GRG_THREAD")
        rawset(_G, "__GRG_THREAD", true)

        local ok, err = pcall(fire, remote, payload)

        rawset(_G, "__GRG_THREAD", prior_flag)

        if not ok then
            L:warn("decoy FireServer failed: %s", tostring(err))
            return false, err
        end

        LAST_FIRE_T = tick()
        state:bump("decoy_fires")
        state:set_last("last_decoy_fire_at", LAST_FIRE_T)
        return true
    end

    ----------------------------------------------------------------
    -- 4. scheduler
    ----------------------------------------------------------------

    local function scheduler_tick()
        if PAUSED then return end
        sample_safe_position()

        local hz = cfg:get("decoys.position.cadence_hz", 4)
        if type(hz) ~= "number" or hz <= 0 then return end
        local interval = 1 / hz
        local now = tick()
        if now - LAST_FIRE_T < interval then return end

        send_once()
    end

    ----------------------------------------------------------------
    -- 5. install / connections
    ----------------------------------------------------------------

    function M.install()
        if not cfg:get("decoys.position.enabled", true) then
            L:info("disabled via config")
            return
        end
        if RUNNING then
            L:debug("already running; install() ignored")
            return
        end
        if not env.RunService then
            L:error("RunService missing; cannot install decoy scheduler")
            return
        end

        RUNNING = true

        -- We do the position sample and the fire on the same
        -- Heartbeat signal, but they gate themselves independently:
        -- sampler runs every tick to keep LAST_SAFE smooth, fire
        -- runs at the config-selected cadence.
        TICK_CONN = env.RunService.Heartbeat:Connect(function()
            LAST_TICK_T = tick()
            local ok, err = pcall(scheduler_tick)
            if not ok then
                L:warn("scheduler tick errored: %s", tostring(err))
            end
        end)

        L:info("decoy position active (cadence=%d Hz, tolerance=%.2f)",
            cfg:get("decoys.position.cadence_hz", 4),
            cfg:get("decoys.position.payload_tolerance", 2.0))
    end

    function M.uninstall()
        RUNNING = false
        if TICK_CONN then
            pcall(function() TICK_CONN:Disconnect() end)
            TICK_CONN = nil
        end
        if FIRE_CONN then
            pcall(function() FIRE_CONN:Disconnect() end)
            FIRE_CONN = nil
        end
        L:info("decoy position uninstalled")
    end

    ----------------------------------------------------------------
    -- 6. public ops
    ----------------------------------------------------------------

    function M.force_now()
        -- Used by the UI / other modules to punch a keep-alive fire
        -- RIGHT NOW, e.g. right after a detected AC probe.
        sample_safe_position()
        return send_once()
    end

    function M.pause()
        if PAUSED then return end
        PAUSED = true
        L:info("paused")
    end

    function M.resume()
        if not PAUSED then return end
        PAUSED = false
        LAST_FIRE_T = 0     -- force the next tick to fire immediately
        L:info("resumed")
    end

    function M.is_paused() return PAUSED end
    function M.is_running() return RUNNING end

    function M.last_safe_position() return LAST_SAFE end

    function M.stats()
        return {
            running      = RUNNING,
            paused       = PAUSED,
            last_fire_t  = LAST_FIRE_T,
            last_tick_t  = LAST_TICK_T,
            last_safe    = LAST_SAFE,
            fires        = state:counter("decoy_fires"),
            remote_ready = resolve_remote() ~= nil,
        }
    end

    return M

end

end
__MODULES__['decoys/velocity'] = function(require)
--[[ ================================================================
    src/decoys/velocity.lua
    ------------------------
    Caps velocity magnitudes that external readers (AC probes, other
    client scripts) see when they read HumanoidRootPart.Velocity /
    .AssemblyLinearVelocity, and Humanoid.MoveDirection.

    We don't TOUCH the real physics state -- our own walkspeed /
    flight modules may set velocity legitimately for gameplay. We
    only rewrite the VALUE THAT LEAKS OUT via __index reads when the
    caller isn't us.

    This stops the most common velocity-based detection: server-side
    (or bootstrap-script) code that reads HRP.Velocity.Magnitude on
    the client and reports it. A player with WalkSpeed = 16 should
    show velocities capped around ~20-ish studs/s depending on the
    game -- a cap of 32 leaves room for jumps, platform stacking,
    and wind zones without flagging.
================================================================ ]]

return function(require)

    local env    = require("core/env")
    local log    = require("core/log")
    local cfg   = require("core/config")
    local state = require("core/state")

    local index = require("hooks/index")

    local M = {}
    local L = log.scoped("decoys/velocity")

    ----------------------------------------------------------------
    -- 1. helpers
    ----------------------------------------------------------------

    local function caller_is_us()
        if _G.__GRG_THREAD then return true end
        if env.ckcaller then
            local ok, v = pcall(env.ckcaller)
            if ok and v then return true end
        end
        return false
    end

    local function clamp_vector(vec, cap)
        if typeof(vec) ~= "Vector3" then return vec end
        local mag = vec.Magnitude
        if mag <= cap or mag <= 0 then return vec end
        -- Preserve direction, replace magnitude. Division by mag is
        -- safe because we checked mag > 0 above.
        return vec * (cap / mag)
    end

    local function clamp_move_direction(vec)
        -- Humanoid.MoveDirection is a unit-ish Vector3 (magnitude <= 1).
        -- Cheats sometimes set it to arbitrary long vectors to bypass
        -- speed logic. If we see magnitude > 1, normalize it.
        if typeof(vec) ~= "Vector3" then return vec end
        local mag = vec.Magnitude
        if mag <= 1.0 then return vec end
        return vec.Unit
    end

    ----------------------------------------------------------------
    -- 2. BasePart.Velocity / AssemblyLinearVelocity handlers
    ----------------------------------------------------------------

    local function basepart_velocity_handler(ctx)
        if caller_is_us() then return end
        local cap = cfg:get("decoys.velocity.cap_magnitude", 32)
        if type(cap) ~= "number" then return end
        local v = ctx.value
        if typeof(v) ~= "Vector3" then return end
        local mag = v.Magnitude
        if mag <= cap then return end
        ctx.spoof_value = clamp_vector(v, cap)
        ctx.spoofed     = true
        state:bump("velocity_read_clamped")
    end

    ----------------------------------------------------------------
    -- 3. Humanoid.MoveDirection handler
    ----------------------------------------------------------------

    local function humanoid_movedir_handler(ctx)
        if caller_is_us() then return end
        local v = ctx.value
        if typeof(v) ~= "Vector3" then return end
        if v.Magnitude <= 1.0 then return end
        ctx.spoof_value = clamp_move_direction(v)
        ctx.spoofed     = true
        state:bump("movedir_read_clamped")
    end

    ----------------------------------------------------------------
    -- 4. install
    ----------------------------------------------------------------

    function M.install()
        if not cfg:get("decoys.velocity.enabled", true) then
            L:info("disabled via config")
            return
        end

        -- HRP.Velocity: legacy API but still read by many AC clients.
        index.register({
            name     = "decoy_vel_basepart_velocity",
            class    = "BasePart",
            property = "Velocity",
            priority = 40,
            handler  = basepart_velocity_handler,
        })

        -- AssemblyLinearVelocity: modern equivalent; some AC scripts
        -- switched to this when Roblox deprecated Velocity reads.
        index.register({
            name     = "decoy_vel_basepart_assembly",
            class    = "BasePart",
            property = "AssemblyLinearVelocity",
            priority = 40,
            handler  = basepart_velocity_handler,
        })

        -- Humanoid.MoveDirection: short vector (<=1) telling which
        -- way the character is trying to move. Cheats stretch it.
        index.register({
            name     = "decoy_vel_humanoid_movedir",
            class    = "Humanoid",
            property = "MoveDirection",
            priority = 40,
            handler  = humanoid_movedir_handler,
        })

        L:info("velocity decoy active (cap=%.1f)",
            cfg:get("decoys.velocity.cap_magnitude", 32))
    end

    ----------------------------------------------------------------
    -- 5. live tuning
    ----------------------------------------------------------------

    function M.set_cap(n)
        local v = tonumber(n)
        if not v then
            L:warn("set_cap: ignoring non-numeric %s", tostring(n))
            return
        end
        cfg:set("decoys.velocity.cap_magnitude", v)
        L:info("velocity cap updated -> %.1f", v)
    end

    function M.get_cap()
        return cfg:get("decoys.velocity.cap_magnitude", 32)
    end

    return M

end

end
__MODULES__['grg/cmdr_silencer'] = function(require)
--[[ ================================================================
    src/grg/cmdr_silencer.lua
    --------------------------
    Mutes GRG's Cmdr-driven admin command channel. The AC uses Cmdr
    as a back-door broadcast mechanism: server sends a /ban or
    /kick command via a RemoteFunction named "CmdrFunction" (the
    stock Cmdr name) and expects the client to execute it locally.

    We intercept in two places:

      1. RemoteFunction.OnClientInvoke for any remote with a name
         matching our CMDR_NAME_PATTERNS. We rebind the callback so
         it returns a benign "yes, did it" response.

      2. ScreenGui named "CmdrGui" in PlayerGui (and CoreGui, if
         reachable via gethui): we set Enabled=false and watch
         ChildAdded to keep re-suppressing it if the AC re-spawns.

    We don't outright destroy the CmdrGui -- other legitimate
    Cmdr features use it and destroying it shows up in integrity
    scans. Just Enabled=false is enough to blind the overlay.
================================================================ ]]

return function(require)

    local env   = require("core/env")
    local log   = require("core/log")
    local cfg   = require("core/config")
    local state = require("core/state")
    local recv  = require("hooks/recv_handlers")
    local gate  = require("grg/placeid_gate")

    local M = {}
    local L = log.scoped("grg/cmdr_silencer")

    local CMDR_NAME_PATTERNS = {
        "^CmdrFunction$",
        "^CmdrEvent$",
        "^Cmdr.+",
        ".+CmdrFunction$",
        ".+CmdrEvent$",
    }

    local BENIGN_RESPONSE = {
        success  = true,
        response = "",
    }

    local SUPPRESSED_GUIS = setmetatable({}, { __mode = "k" })
    local DETECTED_REMOTES = {}

    local function is_cmdr_name(n)
        if type(n) ~= "string" then return false end
        for _, pat in ipairs(CMDR_NAME_PATTERNS) do
            local ok, found = pcall(string.find, n, pat)
            if ok and found then return true end
        end
        return false
    end

    local function suppress_gui(gui)
        if not gui or SUPPRESSED_GUIS[gui] then return end
        pcall(function() gui.Enabled = false end)
        SUPPRESSED_GUIS[gui] = true
        L:warn("suppressed CmdrGui '%s'", tostring(gui:GetFullName()))

        -- Re-assert Enabled=false if someone flips it back on.
        local ok, conn = pcall(function()
            return gui:GetPropertyChangedSignal("Enabled"):Connect(function()
                if gui.Enabled then
                    pcall(function() gui.Enabled = false end)
                end
            end)
        end)
        if not ok then
            L:debug("could not bind Enabled signal: %s", tostring(conn))
        end
    end

    local function scan_container(container)
        if not container then return end
        for _, child in ipairs(container:GetChildren()) do
            local ok, nm = pcall(function() return child.Name end)
            if ok and nm == "CmdrGui" then
                suppress_gui(child)
            end
        end
        pcall(function()
            container.ChildAdded:Connect(function(child)
                local ok, nm = pcall(function() return child.Name end)
                if ok and nm == "CmdrGui" then
                    suppress_gui(child)
                end
            end)
        end)
    end

    local function note_remote(remote)
        if not remote then return end
        local ok, fn = pcall(function() return remote:GetFullName() end)
        if ok then
            DETECTED_REMOTES[fn] = os.time()
        end
    end

    function M.list_cmdr_remotes()
        local out = {}
        for k, ts in pairs(DETECTED_REMOTES) do
            table.insert(out, { path = k, seen_at = ts })
        end
        table.sort(out, function(a, b) return a.path < b.path end)
        return out
    end

    function M.install()
        if not gate.should_run_modules() then
            L:info("placeid gate says skip")
            return
        end
        if not cfg:get("grg.cmdr_silencer.enabled", true) then
            L:info("disabled via config")
            return
        end

        -- OnClientInvoke intercept via the recv_handlers wildcard.
        -- We rewrite the reply by setting ctx.short_circuit with
        -- spoof args containing the benign response. This shape
        -- matches hooks/fire_handlers but recv_handlers uses the
        -- same conventions for OCI.
        recv.on_any({
            name     = "grg_cmdr_silencer",
            priority = 10,
            kind     = "OnClientInvoke",
            handler  = function(ctx)
                local remote = ctx.remote
                if not remote then return end
                local ok, n = pcall(function() return remote.Name end)
                if not ok or not is_cmdr_name(n) then return end
                note_remote(remote)
                L:warn("intercepted CmdrFunction invoke on %s", tostring(n))
                ctx.spoof = {
                    [1] = BENIGN_RESPONSE,
                    n   = 1,
                }
                ctx.short_circuit = true
            end,
        })

        -- Also listen for fire-style Cmdr events so we can count
        -- them and note the remote for later inspection.
        recv.on_any({
            name     = "grg_cmdr_event_sink",
            priority = 10,
            kind     = "OnClientEvent",
            handler  = function(ctx)
                local remote = ctx.remote
                if not remote then return end
                local ok, n = pcall(function() return remote.Name end)
                if not ok or not is_cmdr_name(n) then return end
                note_remote(remote)
                L:warn("dropped CmdrEvent fire on %s", tostring(n))
                ctx.drop = true
            end,
        })

        -- PlayerGui sweep + watcher.
        if env.PlayerGui then scan_container(env.PlayerGui) end
        if env.LocalPlayer then
            env.LocalPlayer.CharacterAdded:Connect(function()
                if env.LocalPlayer:FindFirstChild("PlayerGui") then
                    scan_container(env.LocalPlayer.PlayerGui)
                end
            end)
        end

        -- CoreGui sweep (gethui if available, otherwise direct).
        local core_container
        if env.Caps.gethui then
            local ok, hui = pcall(function() return gethui() end)
            if ok then core_container = hui end
        end
        core_container = core_container or env.CoreGui
        if core_container then
            -- CoreGui reads often error on unpermissioned clients;
            -- pcall the whole scan.
            pcall(scan_container, core_container)
        end

        L:info("cmdr_silencer online")
    end

    return M

end

end
__MODULES__['grg/placeid_gate'] = function(require)
--[[ ================================================================
    src/grg/placeid_gate.lua
    -------------------------
    Last-chance placeId check before any GRG-specific module actually
    installs itself. The generic hook/mask/scrubber layers are fine to
    run anywhere (they only touch things the target game has), but the
    grg/* modules below this are hand-tuned to Generic Roleplay Game
    remote schemas and would waste cycles elsewhere.

    One-liner:
        local gate = require("grg/placeid_gate")
        gate.install()
        if not gate.should_run_modules() then return end

    Honors `grg.placeid_gate.allow_outside_target` so devs can still
    poke the modules from Studio or a different game during testing.
================================================================ ]]

return function(require)

    local env   = require("core/env")
    local log   = require("core/log")
    local cfg   = require("core/config")
    local state = require("core/state")

    local M = {}
    local L = log.scoped("grg/placeid_gate")

    local TARGET_PLACE = 4598019433
    local IN_TARGET    = false
    local INSTALLED    = false

    function M.get_target_place()
        return TARGET_PLACE
    end

    function M.is_in_target()
        return IN_TARGET
    end

    function M.should_run_modules()
        if not INSTALLED then
            -- If something calls before install() we lazily compute so
            -- we never falsely report "ok to run" on the wrong place.
            IN_TARGET = (env.PlaceId == TARGET_PLACE)
        end
        if IN_TARGET then return true end
        if cfg:get("grg.placeid_gate.allow_outside_target", true) then
            return true
        end
        return false
    end

    function M.install()
        if INSTALLED then return end
        INSTALLED = true

        if not cfg:get("grg.placeid_gate.enabled", true) then
            L:info("disabled via config; assuming in-target")
            IN_TARGET = true
            state:flag("in_target_game", true)
            return
        end

        IN_TARGET = (env.PlaceId == TARGET_PLACE)
        state:flag("in_target_game", IN_TARGET)

        if IN_TARGET then
            L:info("placeId %d matches target (%s)", env.PlaceId, env.GameName)
            return
        end

        if cfg:get("grg.placeid_gate.allow_outside_target", true) then
            L:warn(
                "placeId %d does NOT match target %d; modules will run anyway (allow_outside_target=true)",
                tonumber(env.PlaceId) or -1, TARGET_PLACE)
        else
            L:warn(
                "placeId %d does NOT match target %d; grg/* modules will skip install",
                tonumber(env.PlaceId) or -1, TARGET_PLACE)
        end
    end

    function M.require_target_or_skip(module_name)
        if M.should_run_modules() then return true end
        L:info("gate: skipping '%s' (wrong place)", tostring(module_name))
        return false
    end

    return M

end

end
__MODULES__['grg/profile_spoof'] = function(require)
--[[ ================================================================
    src/grg/profile_spoof.lua
    --------------------------
    GRG-specific outbound telemetry sanitizer. This runs AHEAD of the
    generic scrubbers/updateprofile.lua (priority 5 vs their 20) and
    is tuned to the exact UpdateProfile schema the Generic Roleplay
    Game AC expects.

    UpdateProfile layout (discovered from traffic dumps):
        { position  = Vector3 | {x,y,z},
          walkSpeed = number,
          jumpPower = number,
          state     = string,   -- HumanoidStateType
          flags     = table,    -- optional AC markers we ignore
          timestamp = number    -- server ignores; we keep
        }

    Core logic:
        * Clamp `walkSpeed` to 16 + tolerance_speed.
        * Snap `position` back to LAST_ACKD_POS if we're teleport-far
          away (> tolerance_units).
        * Force `state` into a whitelisted enum-equivalent string.
        * LAST_ACKD_POS is refreshed every time the server responds
          OK to our UpdateProfile. We treat any recv of a remote with
          "ProfileAck" / "ProfileOk" or a truthy payload on
          UpdateProfile's return channel as an ACK.
        * On new character, LAST_ACKD_POS resets to the fresh spawn.

    This module does NOT drop the event; it only mutates args. The
    underlying generic scrubber is allowed to re-check on top of us.
================================================================ ]]

return function(require)

    local env   = require("core/env")
    local log   = require("core/log")
    local cfg   = require("core/config")
    local state = require("core/state")
    local fire  = require("hooks/fire_handlers")
    local recv  = require("hooks/recv_handlers")
    local gate  = require("grg/placeid_gate")

    local M = {}
    local L = log.scoped("grg/profile_spoof")

    local LAST_ACKD_POS     = nil    -- Vector3 or {x,y,z}
    local LAST_ACKD_AT      = 0
    local LAST_SPOOF_AT     = 0
    local LAST_SPOOF_REASON = nil

    local VALID_STATES = {
        Running  = true,
        Jumping  = true,
        Freefall = true,
        Landed   = true,
        Seated   = true,
        Climbing = true,
    }
    local SAFE_STATE = "Running"

    local TOLERANCE_UNITS = nil
    local TOLERANCE_SPEED = nil

    local function tolerance_units()
        return TOLERANCE_UNITS
            or cfg:get("grg.profile_spoof.tolerance_units", 40)
    end

    local function tolerance_speed()
        return TOLERANCE_SPEED
            or cfg:get("grg.profile_spoof.tolerance_speed", 4)
    end

    function M.set_tolerance(units, speed)
        if type(units) == "number" then TOLERANCE_UNITS = units end
        if type(speed) == "number" then TOLERANCE_SPEED = speed end
    end

    function M.current_last_ackd() return LAST_ACKD_POS end
    function M.last_spoof_at()     return LAST_SPOOF_AT end
    function M.last_spoof_reason() return LAST_SPOOF_REASON end

    local function to_vector_like(v)
        if typeof and typeof(v) == "Vector3" then
            return { x = v.X, y = v.Y, z = v.Z }
        end
        if type(v) == "table" then
            local x = v.x or v.X or v[1]
            local y = v.y or v.Y or v[2]
            local z = v.z or v.Z or v[3]
            if type(x) == "number" and type(y) == "number" and type(z) == "number" then
                return { x = x, y = y, z = z }
            end
        end
        return nil
    end

    local function clone_vec(v)
        return { x = v.x, y = v.y, z = v.z }
    end

    local function vec_dist(a, b)
        local dx = a.x - b.x
        local dy = a.y - b.y
        local dz = a.z - b.z
        return math.sqrt(dx * dx + dy * dy + dz * dz)
    end

    local function make_position_like(original, replacement)
        -- Preserve the original's "shape" (Vector3 vs table) so the
        -- server-side parser doesn't tag us for schema drift.
        if typeof and typeof(original) == "Vector3" then
            local ok, v3 = pcall(function()
                return Vector3.new(replacement.x, replacement.y, replacement.z)
            end)
            if ok then return v3 end
        end
        return { x = replacement.x, y = replacement.y, z = replacement.z }
    end

    local function refresh_last_ackd_from_character()
        local root = env.get_root()
        if not root then return end
        local ok, pos = pcall(function() return root.Position end)
        if not ok or not pos then return end
        LAST_ACKD_POS = { x = pos.X, y = pos.Y, z = pos.Z }
        LAST_ACKD_AT  = os.time()
        L:debug("refreshed LAST_ACKD_POS from character (%.1f,%.1f,%.1f)",
            LAST_ACKD_POS.x, LAST_ACKD_POS.y, LAST_ACKD_POS.z)
    end

    local function sanitize_payload(payload)
        if type(payload) ~= "table" then return payload, false, nil end
        local mutated = false
        local reason = nil

        -- walkSpeed clamp ----------------------------------------
        if type(payload.walkSpeed) == "number" then
            local cap = 16 + tolerance_speed()
            if payload.walkSpeed > cap then
                L:debug("clamped walkSpeed %.2f -> 16", payload.walkSpeed)
                payload.walkSpeed = 16
                mutated = true
                reason = "walkSpeed"
            end
        end

        -- state whitelist ----------------------------------------
        if payload.state ~= nil then
            local s = tostring(payload.state)
            if not VALID_STATES[s] then
                L:debug("replaced invalid state '%s' -> %s", s, SAFE_STATE)
                payload.state = SAFE_STATE
                mutated = true
                reason = reason or "state"
            end
        end

        -- position snap-back -------------------------------------
        if payload.position ~= nil and LAST_ACKD_POS then
            local cur = to_vector_like(payload.position)
            if cur then
                local d = vec_dist(cur, LAST_ACKD_POS)
                if d > tolerance_units() then
                    L:debug("snap position %.1fu -> last_ackd", d)
                    payload.position = make_position_like(
                        payload.position, clone_vec(LAST_ACKD_POS))
                    mutated = true
                    reason = reason or "position"
                end
            end
        elseif payload.position ~= nil and not LAST_ACKD_POS then
            -- First outgoing profile: seed LAST_ACKD_POS from it so
            -- future packets can be compared.
            local cur = to_vector_like(payload.position)
            if cur then LAST_ACKD_POS = cur end
        end

        return payload, mutated, reason
    end

    local function on_fire(ctx)
        if not cfg:get("grg.profile_spoof.enabled", true) then return end
        if ctx.drop or ctx.short_circuit then return end
        if ctx.kind ~= "FireServer" and ctx.kind ~= "InvokeServer" then
            return
        end

        local args = ctx.args
        local n    = ctx.n_args or (args and args.n) or #args
        if not args or n == 0 then return end

        -- The payload is typically args[1]. Some variants send
        -- multiple scalar args; we only sanitize tabular form.
        local payload = args[1]
        if type(payload) ~= "table" then return end

        local _, mutated, reason = sanitize_payload(payload)
        if mutated then
            state:bump("profile_spoofs")
            state:bump("updateprofile_sanitized")
            state:set_last("last_updateprofile_sent", payload)
            LAST_SPOOF_AT     = tick()
            LAST_SPOOF_REASON = reason
            state:emit("ProfileMutated", payload)
        else
            state:set_last("last_updateprofile", payload)
        end
    end

    local function on_recv_ack(ctx)
        -- Heuristic ACK detection for the RemoteFunction reply path.
        -- GRG's AC responds to UpdateProfile with a small table like
        -- { ok = true, position = Vector3.new(...) } or with a bare
        -- truthy scalar. When we see that, pin LAST_ACKD_POS.
        if ctx.drop or ctx.short_circuit then return end
        local args = ctx.args
        if not args then return end
        local first = args[1]
        if type(first) == "table" then
            if first.ok == false or first.success == false then return end
            local p = to_vector_like(first.position or first.pos or first.location)
            if p then
                LAST_ACKD_POS = p
                LAST_ACKD_AT  = os.time()
                L:debug("ACK updated LAST_ACKD_POS from server")
                return
            end
        end
        -- Fallback: use our current character position as the ACK
        -- anchor since the server implicitly said "you're fine here".
        refresh_last_ackd_from_character()
    end

    function M.install()
        if not gate.should_run_modules() then
            L:info("placeid gate says skip")
            return
        end
        if not cfg:get("grg.profile_spoof.enabled", true) then
            L:info("disabled via config")
            return
        end

        fire.on_name("UpdateProfile", {
            name     = "grg_profile_spoof",
            priority = 5,
            kind     = "both",
            handler  = on_fire,
        })

        -- Accept ACKs from either a named Ack remote or from the
        -- return-channel of the same UpdateProfile (InvokeServer
        -- reply). We bind by-name at priority 20 because the
        -- generic scrubber may snap-modify the payload first.
        recv.on_name("UpdateProfile", {
            name     = "grg_profile_ack",
            priority = 20,
            kind     = "any",
            handler  = on_recv_ack,
        })
        recv.on_name("ProfileAck", {
            name     = "grg_profile_ack_named",
            priority = 20,
            kind     = "any",
            handler  = on_recv_ack,
        })
        recv.on_name("ProfileOk", {
            name     = "grg_profile_ok_named",
            priority = 20,
            kind     = "any",
            handler  = on_recv_ack,
        })

        -- Character reset hook.
        if env.LocalPlayer
           and cfg:get("grg.profile_spoof.reset_state_on_new_char", true)
        then
            env.LocalPlayer.CharacterAdded:Connect(function(char)
                LAST_ACKD_POS = nil
                LAST_ACKD_AT  = 0
                -- Wait a moment for HRP to exist, then seed from it.
                task.spawn(function()
                    local hrp = char:WaitForChild("HumanoidRootPart", 5)
                    if hrp then
                        local ok, pos = pcall(function() return hrp.Position end)
                        if ok and pos then
                            LAST_ACKD_POS = { x = pos.X, y = pos.Y, z = pos.Z }
                            LAST_ACKD_AT  = os.time()
                            L:debug("reset LAST_ACKD_POS to spawn")
                        end
                    end
                end)
            end)
            if env.LocalPlayer.Character then
                refresh_last_ackd_from_character()
            end
        end

        L:info(
            "profile_spoof online (tol_units=%d tol_speed=%d reset_on_char=%s)",
            tolerance_units(), tolerance_speed(),
            tostring(cfg:get("grg.profile_spoof.reset_state_on_new_char", true)))
    end

    return M

end

end
__MODULES__['grg/ragdoll_handler'] = function(require)
--[[ ================================================================
    src/grg/ragdoll_handler.lua
    ----------------------------
    GRG-specific ragdoll defense on top of scrubbers/ragdoll.lua.

    Three angles of attack:

      1. Primary channel (RagdollEvent): on block, surface a user
         notification via StarterGui:SetCore("SendNotification",...)
         unless grg.ragdoll_handler.notify_user=false.

      2. Silent-ragdoll detection: some flavors of the AC skip
         RagdollEvent entirely and just set Humanoid.Health = 0 from
         the server via a hidden property replicator. We watch
         Heartbeat and, if Health drops to 0 faster than any plausible
         damage rate, we clamp it back to Humanoid.MaxHealth.

      3. GetState pinning: :GetState() is the API the local AC
         watches for "ragdolled-looking" bodies. We hook namecall and
         replace illegal Physics/Swimming reports with Running.

    `M.force_recover()` synthesizes a full character recovery:
    Health=MaxHealth, State=Running, BreakJointsOnDeath=true clear.
================================================================ ]]

return function(require)

    local env   = require("core/env")
    local log   = require("core/log")
    local cfg   = require("core/config")
    local state = require("core/state")
    local recv  = require("hooks/recv_handlers")
    local namecall = require("hooks/namecall")
    local gate  = require("grg/placeid_gate")

    local M = {}
    local L = log.scoped("grg/ragdoll_handler")

    local LAST_HEALTH       = nil
    local LAST_HEALTH_TIME  = 0
    local HEALTH_SNAP_RATE  = 0
    local NOTIFY_COOLDOWN   = 0

    local ILLEGAL_STATES = {
        Physics   = true,
        Swimming  = true,
        Ragdoll   = true,
        PlatformStanding = true,
    }

    local RECOVER_STATE = "Running"

    local function notify_user(title, text)
        if not cfg:get("grg.ragdoll_handler.notify_user", true) then return end
        local now = tick()
        if now - NOTIFY_COOLDOWN < 2.5 then return end
        NOTIFY_COOLDOWN = now
        if not env.StarterGui then return end
        pcall(function()
            env.StarterGui:SetCore("SendNotification", {
                Title    = title,
                Text     = text,
                Duration = 4,
            })
        end)
    end

    local function recover_humanoid(hum)
        if not hum then return end
        pcall(function()
            if hum.MaxHealth and hum.Health < hum.MaxHealth then
                hum.Health = hum.MaxHealth
            end
        end)
        pcall(function() hum.PlatformStand = false end)
        pcall(function() hum.Sit = false end)
        pcall(function() hum:ChangeState(Enum.HumanoidStateType[RECOVER_STATE]) end)
    end

    local function silent_ragdoll_watch(dt)
        local hum = env.get_humanoid()
        if not hum then
            LAST_HEALTH = nil
            return
        end
        local ok, h = pcall(function() return hum.Health end)
        if not ok then return end

        if LAST_HEALTH == nil then
            LAST_HEALTH = h
            LAST_HEALTH_TIME = tick()
            return
        end

        local now = tick()
        local elapsed = now - LAST_HEALTH_TIME
        if elapsed <= 0 then elapsed = 1 / 60 end

        -- A "silent ragdoll" is the Health going from ~full to 0
        -- in a single frame or two. Real damage in GRG is paced
        -- through a DamageEvent we can see on recv_handlers, so
        -- a >200hp drop in <0.2s is almost certainly server-set.
        local drop = (LAST_HEALTH or 0) - h
        if h == 0 and drop > 50 and elapsed < 0.25 then
            HEALTH_SNAP_RATE = HEALTH_SNAP_RATE + 1
            L:warn("silent ragdoll detected (drop=%.1f dt=%.3fs); clamping",
                drop, elapsed)
            notify_user("GRG AC bypass", "Silent ragdoll blocked.")
            state:bump("ragdoll_dropped")
            recover_humanoid(hum)
        end

        LAST_HEALTH = h
        LAST_HEALTH_TIME = now
    end

    function M.force_recover()
        local hum = env.get_humanoid()
        if not hum then return false, "no humanoid" end
        recover_humanoid(hum)
        return true
    end

    function M.install()
        if not gate.should_run_modules() then
            L:info("placeid gate says skip")
            return
        end
        if not cfg:get("grg.ragdoll_handler.enabled", true) then
            L:info("disabled via config")
            return
        end

        -- Named recv hook: report blocks, we don't own the drop
        -- (scrubbers/ragdoll.lua handles it at priority 5).
        recv.on_name("RagdollEvent", {
            name     = "grg_ragdoll_notify",
            priority = 20,
            kind     = "OnClientEvent",
            handler  = function(ctx)
                state:bump("ragdoll_dropped")
                state:journal("ragdolls", {
                    ts = os.time(),
                    source = "grg/ragdoll_handler",
                })
                notify_user("GRG AC bypass", "Ragdoll attempt blocked.")
            end,
        })

        -- :GetState() pinning: if any script calls it on our
        -- humanoid and gets an illegal state back, rewrite.
        namecall.register({
            name     = "grg_ragdoll_getstate",
            priority = 25,
            method   = "GetState",
            predicate = function(self_obj, method, ctx)
                if typeof(self_obj) ~= "Instance" then return false end
                local ok, is_h = pcall(function() return self_obj:IsA("Humanoid") end)
                return ok and is_h
            end,
            handler  = function(ctx)
                ctx.after = function(ret)
                    local v = ret[1]
                    if typeof(v) ~= "EnumItem" then return ret end
                    local name = tostring(v.Name)
                    if ILLEGAL_STATES[name] then
                        local ok, enum = pcall(function()
                            return Enum.HumanoidStateType[RECOVER_STATE]
                        end)
                        if ok then
                            L:debug("GetState -> %s rewritten as %s", name, RECOVER_STATE)
                            ret[1] = enum
                        end
                    end
                    return ret
                end
            end,
        })

        -- Heartbeat watcher for silent-ragdoll health snaps.
        if env.RunService then
            env.RunService.Heartbeat:Connect(function(dt)
                local ok, err = pcall(silent_ragdoll_watch, dt)
                if not ok then
                    L:warn("silent watch errored: %s", tostring(err))
                end
            end)
        end

        -- Reset health tracking whenever the character respawns.
        if env.LocalPlayer then
            env.LocalPlayer.CharacterAdded:Connect(function()
                LAST_HEALTH = nil
                LAST_HEALTH_TIME = 0
            end)
        end

        L:info("ragdoll_handler online")
    end

    function M.health_snap_count() return HEALTH_SNAP_RATE end

    return M

end

end
__MODULES__['grg/raptor_alibi'] = function(require)
--[[ ================================================================
    src/grg/raptor_alibi.lua
    -------------------------
    Fakes the answers debug.info(level, "s"/"l"/"f") gives for any
    stack frame belonging to a cheat script. This is the "who wrote
    this WalkSpeed?" question the AC asks when it sees the telemetry
    drift we mask upstream.

    Observed hostile stack frames we rewrite:
        "Script Raptor.Thread:342"
        "Script <exe>:LocalScript:..."
        any frame whose source matches a user-registered pattern
        (see M.add_fake_source).

    For those frames:
        "s" -> cfg:get("grg.raptor_alibi.fake_source_name",
                       "CoreGui.RobloxGui.Modules.Common.MovementController")
        "l" -> a plausible small integer (hash of real source so it
                stays stable across calls -- AC correlates between
                calls for the same script).
        "f" -> a clone of the real function so islclosure() and
                getupvalue() paths keep working but the function
                pointer no longer leaks that it's ours.

    The real values are stashed in a side table keyed by the caller
    so the journal (state:set_last("last_raptor_frame", ...)) keeps
    truth for debugging.

    Requires: hooks/hookfunction and debug.info being hookable. On
    builds without hookfunction, we install a best-effort _G shadow.
================================================================ ]]

return function(require)

    local env   = require("core/env")
    local log   = require("core/log")
    local cfg   = require("core/config")
    local state = require("core/state")
    local hf    = require("hooks/hookfunction")
    local gate  = require("grg/placeid_gate")

    local M = {}
    local L = log.scoped("grg/raptor_alibi")

    local CHEAT_MARKERS = {
        "Raptor%.Thread",
        "Raptor",
        "LocalScript",
        "RobloxScriptSecurity",
        "syn_closure",
        "executor_thread",
    }

    local EXTRA_PATTERNS = {}   -- { { real=pat, fake=name } }

    local REAL_TRACE_BY_FN = setmetatable({}, { __mode = "k" })
    local FAKE_FN_CACHE    = setmetatable({}, { __mode = "kv" })

    local DEFAULT_FAKE_LINE = 128
    local INSTALLED = false
    local SPOOF_COUNT = 0

    function M.add_fake_source(real_pattern, fake_name)
        if type(real_pattern) ~= "string" then return false end
        table.insert(EXTRA_PATTERNS, {
            real = real_pattern,
            fake = fake_name,
        })
        return true
    end

    local function fake_source_default()
        return cfg:get(
            "grg.raptor_alibi.fake_source_name",
            "CoreGui.RobloxGui.Modules.Common.MovementController")
    end

    local function match_cheat(src)
        if type(src) ~= "string" then return false, nil end
        for _, pat in ipairs(CHEAT_MARKERS) do
            local ok, found = pcall(string.find, src, pat)
            if ok and found then
                return true, fake_source_default()
            end
        end
        for _, entry in ipairs(EXTRA_PATTERNS) do
            local ok, found = pcall(string.find, src, entry.real)
            if ok and found then
                return true, entry.fake or fake_source_default()
            end
        end
        return false, nil
    end

    local function stable_hash(s)
        -- Tiny deterministic hash so the same real source always
        -- produces the same fake line number. Keeps the AC from
        -- noticing a source at different lines on each call.
        local h = 2166136261
        for i = 1, #s do
            h = (h * 16777619) % 2147483647
            h = h + string.byte(s, i)
        end
        return (h % 400) + 20   -- 20..419, plausible for engine modules
    end

    local function fake_fn_for(real_fn)
        if type(real_fn) ~= "function" then return real_fn end
        local cached = FAKE_FN_CACHE[real_fn]
        if cached then return cached end
        local clone = real_fn
        if env.cln then
            local ok, c = pcall(env.cln, real_fn)
            if ok and type(c) == "function" then clone = c end
        end
        FAKE_FN_CACHE[real_fn] = clone
        return clone
    end

    -- ------------------------------------------------------------------
    -- Central dispatcher. We receive (ctx) from hooks/hookfunction
    -- whose .args = { level, what_spec }. Decide per-frame whether
    -- to short_circuit the call with fake values.
    -- ------------------------------------------------------------------

    local function handle_info(ctx)
        if not cfg:get("grg.raptor_alibi.enabled", true) then return end

        local args = ctx.args
        local n    = ctx.n_args or 0
        if n < 2 then return end

        local level = args[1]
        local what  = args[2]
        if type(what) ~= "string" or what == "" then return end

        -- Call the REAL debug.info first so we can decide based on
        -- the truthful value. We use hookfunction's registry to get
        -- the original, not the wrapper.
        local original = hf.original_of(debug.info)
        if type(original) ~= "function" then return end

        local want_s = what:find("s", 1, true) ~= nil
        local want_l = what:find("l", 1, true) ~= nil
        local want_f = what:find("f", 1, true) ~= nil
        if not (want_s or want_l or want_f) then return end

        -- Read source string once; used for both the match AND the
        -- journal entry.
        local ok_src, real_src = pcall(original, level, "s")
        if not ok_src then return end

        local is_cheat, fake_src = match_cheat(real_src)
        if not is_cheat then return end

        -- Journal the REAL value so bug reports still have truth.
        state:set_last("last_raptor_frame", {
            level = level,
            src   = real_src,
            time  = tick(),
        })

        SPOOF_COUNT = SPOOF_COUNT + 1

        -- Build the spoof values matching the exact `what` spec the
        -- caller asked for, in the same order.
        local out = {}
        local idx = 0
        for i = 1, #what do
            local c = what:sub(i, i)
            idx = idx + 1
            if c == "s" then
                out[idx] = fake_src
            elseif c == "l" then
                out[idx] = DEFAULT_FAKE_LINE + stable_hash(real_src)
            elseif c == "f" then
                local ok_f, real_fn = pcall(original, level, "f")
                if ok_f then
                    out[idx] = fake_fn_for(real_fn)
                    REAL_TRACE_BY_FN[out[idx]] = real_fn
                else
                    out[idx] = nil
                end
            elseif c == "n" then
                -- Name of function; safe-ish to leave but we blank
                -- so the AC can't cross-correlate.
                out[idx] = ""
            elseif c == "a" then
                -- Arity tuple; let the real one through to avoid
                -- breaking otherwise-legit debuggers.
                local ok_a, a, b = pcall(original, level, "a")
                if ok_a then
                    out[idx] = a
                    idx = idx + 1
                    out[idx] = b
                end
            else
                -- Unknown specifier; fall back to real.
                local ok_u, v = pcall(original, level, c)
                out[idx] = ok_u and v or nil
            end
        end
        out.n = idx

        ctx.short_circuit = true
        ctx.spoof = out
    end

    function M.install()
        if INSTALLED then return end
        if not gate.should_run_modules() then
            L:info("placeid gate says skip")
            return
        end
        if not cfg:get("grg.raptor_alibi.enabled", true) then
            L:info("disabled via config")
            return
        end
        if type(debug) ~= "table" or type(debug.info) ~= "function" then
            L:warn("debug.info unavailable; alibi inactive")
            return
        end

        local id = hf.hook(debug, "info", {
            name     = "grg_raptor_alibi",
            priority = 10,
            handler  = handle_info,
        })
        if not id then
            L:warn("hook on debug.info failed")
            return
        end

        INSTALLED = true
        L:info("raptor_alibi online (fake_src='%s')", fake_source_default())
    end

    function M.spoof_count() return SPOOF_COUNT end

    function M.real_fn_of(fake_fn)
        return REAL_TRACE_BY_FN[fake_fn]
    end

    function M.list_fake_patterns()
        local out = {}
        for _, e in ipairs(EXTRA_PATTERNS) do
            table.insert(out, { real = e.real, fake = e.fake })
        end
        return out
    end

    return M

end

end
__MODULES__['grg/shadowban_handler'] = function(require)
--[[ ================================================================
    src/grg/shadowban_handler.lua
    ------------------------------
    GRG-specific augment on top of scrubbers/shadowban.lua.

    The generic scrubber only drops the ReplicatedStorage.Remotes
    .ShadowBanEvent fire and sweeps the overlay gui. This module adds:

      1. cross-session bookkeeping: every trip gets an os.time()
         written to `grg_shadowban_last_<jobId>.txt` so we can see
         across rejoins how often the AC is tripping us.

      2. auto-recovery: if the AC stripped our hooks *as part of*
         the shadowban, we re-install them via hooks/restore once the
         state:emit("ShadowbanBlocked") signal fires.

      3. a wildcard recv.on_any() scanner that looks for payload
         tables shaped like { banned = true } / { shadow = true }
         / { action = "disable" } on ANY remote, not just the named
         ShadowBanEvent -- some versions of the AC have moved the
         ping onto UpdateProfile's reply channel.
================================================================ ]]

return function(require)

    local env   = require("core/env")
    local log   = require("core/log")
    local cfg   = require("core/config")
    local state = require("core/state")
    local recv  = require("hooks/recv_handlers")
    local restore = require("hooks/restore")
    local gate  = require("grg/placeid_gate")

    local M = {}
    local L = log.scoped("grg/shadowban_handler")

    local TRIP_COUNT = 0
    local LAST_TRIP_TS = 0
    local TRIP_LOG = {}

    local FILE_PREFIX = "grg_shadowban_last_"

    local SUSPICIOUS_KEYS = {
        banned    = "banned",
        shadow    = "shadow",
        shadowbanned = "shadowbanned",
        ghost     = "ghost",
        silent    = "silent",
    }

    local SUSPICIOUS_ACTIONS = {
        disable    = true,
        shadowban  = true,
        ban        = true,
        freeze     = true,
        lockout    = true,
        silence    = true,
    }

    local function job_tag()
        local raw = tostring(env.JobId or "studio")
        raw = raw:gsub("[^%w]", "")
        if raw == "" then raw = "studio" end
        return raw:sub(1, 24)
    end

    local function persist_trip(ts)
        if not env.Caps.writefile then return end
        local fname = FILE_PREFIX .. job_tag() .. ".txt"
        pcall(writefile, fname, tostring(ts))
    end

    local function read_last_persisted()
        if not env.Caps.readfile or not env.Caps.isfile then return 0 end
        local fname = FILE_PREFIX .. job_tag() .. ".txt"
        local ok_exists, exists = pcall(isfile, fname)
        if not ok_exists or not exists then return 0 end
        local ok_read, content = pcall(readfile, fname)
        if not ok_read then return 0 end
        return tonumber(tostring(content):match("%d+") or "0") or 0
    end

    local function record_trip(reason, payload)
        TRIP_COUNT = TRIP_COUNT + 1
        LAST_TRIP_TS = os.time()
        table.insert(TRIP_LOG, {
            ts      = LAST_TRIP_TS,
            reason  = reason,
            payload = payload,
        })
        if #TRIP_LOG > 64 then table.remove(TRIP_LOG, 1) end

        state:bump("shadowban_dropped")
        state:journal("shadowbans", {
            ts      = LAST_TRIP_TS,
            reason  = reason,
            payload = payload,
            source  = "grg/shadowban_handler",
        })

        if cfg:get("grg.shadowban_handler.trace_to_journal", true) then
            persist_trip(LAST_TRIP_TS)
        end

        L:warn("shadowban trip #%d reason=%s", TRIP_COUNT, tostring(reason))
    end

    local function payload_looks_hostile(tbl)
        if type(tbl) ~= "table" then return false, nil end
        for k, v in pairs(tbl) do
            local kl = type(k) == "string" and k:lower() or nil
            if kl and SUSPICIOUS_KEYS[kl] and (v == true or v == 1 or v == "true") then
                return true, kl
            end
            if kl == "action" and type(v) == "string" then
                local vl = v:lower()
                if SUSPICIOUS_ACTIONS[vl] then
                    return true, "action=" .. vl
                end
            end
            if kl == "type" and type(v) == "string" then
                local vl = v:lower()
                if SUSPICIOUS_ACTIONS[vl] or SUSPICIOUS_KEYS[vl] then
                    return true, "type=" .. vl
                end
            end
        end
        return false, nil
    end

    local function scan_args(args, n)
        for i = 1, n or (args and args.n) or 0 do
            local v = args[i]
            if type(v) == "table" then
                local hit, key = payload_looks_hostile(v)
                if hit then return true, key end
            elseif type(v) == "string" then
                local lv = v:lower()
                if SUSPICIOUS_ACTIONS[lv] or SUSPICIOUS_KEYS[lv] then
                    return true, "arg=" .. lv
                end
            end
        end
        return false, nil
    end

    function M.install()
        if not gate.should_run_modules() then
            L:info("placeid gate says skip")
            return
        end
        if not cfg:get("grg.shadowban_handler.enabled", true) then
            L:info("disabled via config")
            return
        end

        -- Hook the recovery side-effect. We don't own the drop of
        -- ShadowBanEvent itself -- scrubbers/shadowban.lua does that
        -- at priority 5. We just listen for the signal it fires.
        local sig = state.Signals and state.Signals.ShadowbanBlocked
        if sig and sig.connect then
            sig:connect(function(payload)
                record_trip("signal.ShadowbanBlocked", payload)

                if cfg:get("grg.shadowban_handler.treat_as_fatal_for_ac", true) then
                    local ok, err = pcall(restore.restore_all)
                    if not ok then
                        L:error("restore_all crashed: %s", tostring(err))
                    end
                end
            end)
        else
            L:warn("state.Signals.ShadowbanBlocked not connectable; skipping hook")
        end

        -- Wildcard inbound scanner. Fires on every OnClientEvent
        -- that isn't already short-circuited by a higher-priority
        -- handler. Priority 15 puts us after the named shadowban
        -- scrubber (5) but before generic handlers (50).
        recv.on_any({
            name     = "grg_shadowban_wildcard",
            priority = 15,
            kind     = "any",
            handler  = function(ctx)
                if ctx.drop or ctx.short_circuit then return end
                local hit, why = scan_args(ctx.args, ctx.n_args)
                if not hit then return end

                local ok, fullname = pcall(function()
                    return ctx.remote and ctx.remote:GetFullName()
                end)
                record_trip(
                    "wildcard/" .. tostring(why) .. " on " ..
                        (ok and tostring(fullname) or "?"),
                    ctx.args)
                ctx.drop = true
            end,
        })

        local prev = read_last_persisted()
        if prev > 0 then
            L:info("last trip at unix=%d (persisted)", prev)
        end
        L:info("shadowban_handler online (count=%d)", TRIP_COUNT)
    end

    function M.trip_count()  return TRIP_COUNT end
    function M.last_trip_ts() return LAST_TRIP_TS end
    function M.trip_log()     return TRIP_LOG end

    function M.clear_trip_log()
        TRIP_COUNT = 0
        LAST_TRIP_TS = 0
        TRIP_LOG = {}
        if env.Caps.delfile then
            local fname = FILE_PREFIX .. job_tag() .. ".txt"
            pcall(delfile, fname)
        end
    end

    return M

end

end
__MODULES__['hooks/fire_handlers'] = function(require)
--[[ ================================================================
    src/hooks/fire_handlers.lua
    ----------------------------
    Registry of (remote, handler) pairs to process whenever FireServer
    or InvokeServer is called. Different from hooks/namecall in two
    ways:
        1. Keyed by remote (instance identity OR remote name), so many
           modules can react to the same remote without needing to
           write their own predicate against args[1]/getfullname.
        2. Supports pre-send mutation (edit args), post-send rewrite
           (edit the return value), pre-send drop, and burst rate
           limiting per-remote.

    Wire-up: hooks/namecall.register() an entry with class="RemoteEvent"
    or "RemoteFunction" and method in {FireServer,InvokeServer}. The
    body dispatches to THIS module's handlers.
================================================================ ]]

return function(require)

    local log   = require("core/log")
    local state = require("core/state")
    local cfg   = require("core/config")
    local env   = require("core/env")

    local M = {}
    local L = log.scoped("hooks/fire")

    -- [remote_fullname_or_name] = { entries }
    local BY_NAME     = {}
    -- [remote instance] = { entries }
    local BY_INSTANCE = {}
    -- wildcard entries (apply to any remote)
    local WILDCARD    = {}

    local NEXT_ID = 0

    local function make_entry(opts)
        NEXT_ID = NEXT_ID + 1
        return {
            _id       = NEXT_ID,
            priority  = opts.priority or 50,
            handler   = opts.handler,
            name      = opts.name or ("fire#" .. NEXT_ID),
            kind      = opts.kind or "both", -- "FireServer"/"InvokeServer"/"both"
            rate_hz   = opts.rate_hz,
            last_allow_t = 0,
        }
    end

    local function sort_list(list)
        table.sort(list, function(a, b)
            if a.priority ~= b.priority then return a.priority < b.priority end
            return (a._id or 0) < (b._id or 0)
        end)
    end

    function M.on_remote(remote_inst, opts)
        assert(typeof(remote_inst) == "Instance", "on_remote requires Instance")
        BY_INSTANCE[remote_inst] = BY_INSTANCE[remote_inst] or {}
        local list = BY_INSTANCE[remote_inst]
        table.insert(list, make_entry(opts))
        sort_list(list)
        return list[#list]._id
    end

    function M.on_name(name, opts)
        BY_NAME[name] = BY_NAME[name] or {}
        local list = BY_NAME[name]
        table.insert(list, make_entry(opts))
        sort_list(list)
        return list[#list]._id
    end

    function M.on_any(opts)
        table.insert(WILDCARD, make_entry(opts))
        sort_list(WILDCARD)
        return WILDCARD[#WILDCARD]._id
    end

    function M.unregister(id)
        local function sweep(list)
            for i, e in ipairs(list) do
                if e._id == id then
                    table.remove(list, i)
                    return true
                end
            end
            return false
        end
        for _, list in pairs(BY_INSTANCE) do
            if sweep(list) then return true end
        end
        for _, list in pairs(BY_NAME) do
            if sweep(list) then return true end
        end
        return sweep(WILDCARD)
    end

    local function run_list(list, kind, ctx)
        if not list then return end
        for _, e in ipairs(list) do
            if e.kind == "both" or e.kind == kind then
                if e.rate_hz then
                    local now = tick()
                    local min_dt = 1 / e.rate_hz
                    if now - e.last_allow_t < min_dt then
                        ctx.rate_skip = true
                    else
                        e.last_allow_t = now
                        ctx.rate_skip = false
                    end
                end
                if not ctx.rate_skip then
                    local ok, err = pcall(e.handler, ctx)
                    if not ok then
                        L:warn("handler '%s' errored: %s", e.name, tostring(err))
                    end
                end
                if ctx.drop or ctx.short_circuit then return end
            end
        end
    end

    function M.dispatch(remote_inst, kind, args_t, n_args)
        local ctx = {
            remote  = remote_inst,
            kind    = kind,
            args    = args_t,
            n_args  = n_args,
            drop    = false,
            short_circuit = false,
            spoof   = nil,
            after   = nil,
            handled_by = {},
            rate_skip = false,
        }

        local list_inst = BY_INSTANCE[remote_inst]
        local ok_name, rname = pcall(function() return remote_inst.Name end)
        local list_name = ok_name and BY_NAME[rname] or nil
        local ok_full, rfull = pcall(function() return remote_inst:GetFullName() end)
        local list_full = ok_full and BY_NAME[rfull] or nil

        run_list(list_inst, kind, ctx)
        if not ctx.drop and not ctx.short_circuit then
            run_list(list_name, kind, ctx)
        end
        if not ctx.drop and not ctx.short_circuit then
            run_list(list_full, kind, ctx)
        end
        if not ctx.drop and not ctx.short_circuit then
            run_list(WILDCARD, kind, ctx)
        end

        if ctx.drop then
            state:bump("send_filtered")
        elseif ctx.short_circuit then
            state:bump("send_filtered")
        end

        return ctx
    end

    -- Helper shortcuts ---------------------------------------------

    function M.drop_remote(remote_inst, reason)
        return M.on_remote(remote_inst, {
            name     = reason or "drop_remote",
            priority = 5,
            handler  = function(ctx) ctx.drop = true end,
        })
    end

    function M.drop_name(name, reason)
        return M.on_name(name, {
            name     = reason or ("drop_" .. name),
            priority = 5,
            handler  = function(ctx) ctx.drop = true end,
        })
    end

    function M.mutate_name(name, mutator_fn, reason)
        return M.on_name(name, {
            name     = reason or ("mut_" .. name),
            priority = 25,
            handler  = function(ctx)
                local ok, err = pcall(mutator_fn, ctx)
                if not ok then
                    L:warn("mutator '%s' errored: %s", reason or "?", tostring(err))
                end
            end,
        })
    end

    function M.list_all()
        local out = { by_name = {}, by_instance_count = 0, wildcard = #WILDCARD }
        for k, list in pairs(BY_NAME) do
            out.by_name[k] = #list
        end
        for _ in pairs(BY_INSTANCE) do
            out.by_instance_count = out.by_instance_count + 1
        end
        return out
    end

    -- Wire the central namecall hook so we get dispatched.
    local namecall = require("hooks/namecall")
    namecall.register({
        name      = "fire_handlers_dispatch",
        priority  = 30,
        predicate = function(self_obj, method, ctx)
            return method == "FireServer" or method == "InvokeServer"
        end,
        handler   = function(ctx)
            if not cfg:get("hooks.fire_handlers.enabled", true) then return end
            local sub = M.dispatch(ctx.self, ctx.method, ctx.args, ctx.n_args)
            if sub.drop then
                ctx.drop = true
                ctx.why  = "fire_handlers.drop"
            elseif sub.short_circuit and sub.spoof then
                ctx.short_circuit = true
                ctx.spoof = sub.spoof
            end
            -- after-rewriter chains onto namecall's ctx
            if sub.after and not ctx.after then
                ctx.after = sub.after
            end
        end,
    })

    return M

end

end
__MODULES__['hooks/hookfunction'] = function(require)
--[[ ================================================================
    src/hooks/hookfunction.lua
    ---------------------------
    Wrapper around the executor's hookfunction() primitive.

    Problem: multiple modules want to hook the same function (e.g.
    sandbox/debug_info_mask AND integrity/self_protect both want
    to hook debug.info). If each does `hookfunction(debug.info, ...)`
    only the last wins.

    Solution: this module keeps a registry keyed by the ORIGINAL
    function pointer. Each register() call gets a slot; our single
    physical hook runs registered wrappers in priority order and
    allows each to mutate args / short_circuit / rewrite results.

    We also keep a cache of originals so modules can get a clean
    reference to the real function regardless of who's hooked it.

    API:
        local hf = require("hooks/hookfunction")
        hf.hook(debug, "info", { priority=10, handler=function(ctx) ... end })
        hf.hook_global("warn", { handler=function(ctx) ... end })
        hf.original_of(debug.info)      -- clean reference
================================================================ ]]

return function(require)

    local env    = require("core/env")
    local log    = require("core/log")
    local caps   = require("core/executor_caps")

    local M = {}
    local L = log.scoped("hooks/hookfn")

    -- ----------------------------------------------------------------
    -- registry
    -- ----------------------------------------------------------------

    -- [physical_hooked_fn] = {
    --     original = fn,
    --     entries  = { {priority, handler, name}, ... },
    --     owner_table = t, owner_key = k,  (may be nil for raw fns)
    -- }
    local REG = {}
    local KEYED = {}  -- [table][key] = reg_entry

    local function sort_entries(reg)
        table.sort(reg.entries, function(a, b)
            local pa = a.priority or 50
            local pb = b.priority or 50
            if pa ~= pb then return pa < pb end
            return (a._id or 0) < (b._id or 0)
        end)
    end

    local NEXT_ID = 0
    local function make_entry(opts)
        NEXT_ID = NEXT_ID + 1
        return {
            _id      = NEXT_ID,
            priority = opts.priority or 50,
            handler  = opts.handler,
            name     = opts.name or string.format("hook#%d", NEXT_ID),
        }
    end

    local function dispatch(reg, ...)
        local n = select("#", ...)
        local ctx = {
            args     = table.pack(...),
            n_args   = n,
            short_circuit = false,
            spoof    = nil,
            drop     = false,
            after    = nil,
        }
        for _, e in ipairs(reg.entries) do
            local ok, err = pcall(e.handler, ctx)
            if not ok then
                L:warn("handler '%s' errored: %s", e.name, tostring(err))
            end
            if ctx.short_circuit or ctx.drop then break end
        end
        if ctx.drop then return end
        if ctx.short_circuit and ctx.spoof ~= nil then
            return table.unpack(ctx.spoof, 1, ctx.spoof.n or #ctx.spoof)
        end
        local ret = table.pack(reg.original(table.unpack(ctx.args, 1, ctx.n_args)))
        if ctx.after then
            local ok, rewritten = pcall(ctx.after, ret)
            if ok and type(rewritten) == "table" then ret = rewritten end
        end
        return table.unpack(ret, 1, ret.n)
    end

    -- ----------------------------------------------------------------
    -- hook primitive
    -- ----------------------------------------------------------------

    local function install_physical(fn, owner_t, owner_k)
        if not caps.can_hook_function then
            L:warn("hookfunction missing; using upvalue-swap fallback")
            -- Fallback: if fn is sitting at owner_t[owner_k], overwrite
            -- owner_t[owner_k] with a proxy. This only works for
            -- statically resolved globals, not methods or locals.
            if owner_t and owner_k then
                local original = fn
                local reg = {
                    original = original,
                    entries  = {},
                    owner_table = owner_t,
                    owner_key   = owner_k,
                    is_fallback = true,
                }
                local proxy = function(...)
                    return dispatch(reg, ...)
                end
                owner_t[owner_k] = proxy
                REG[proxy] = reg
                KEYED[owner_t] = KEYED[owner_t] or {}
                KEYED[owner_t][owner_k] = reg
                return reg, proxy
            end
            return nil
        end

        local reg = {
            original = fn,
            entries  = {},
            owner_table = owner_t,
            owner_key   = owner_k,
        }
        local wrapper
        wrapper = function(...)
            return dispatch(reg, ...)
        end

        local ok, original_ret = pcall(env.hookfn, fn, wrapper)
        if not ok then
            L:error("hookfunction failed: %s", tostring(original_ret))
            return nil
        end
        reg.original = original_ret or fn  -- some impls return the old fn
        REG[fn] = reg    -- lookup by original
        REG[wrapper] = reg  -- lookup by wrapper

        if owner_t and owner_k then
            KEYED[owner_t] = KEYED[owner_t] or {}
            KEYED[owner_t][owner_k] = reg
        end

        return reg, wrapper
    end

    function M.hook(owner_t, key, opts)
        if type(owner_t) ~= "table" then
            error("hookfunction.hook expects (table, key, opts)", 2)
        end
        local fn = owner_t[key]
        if type(fn) ~= "function" then
            L:warn("hook: target %s.%s is not a function", tostring(owner_t), tostring(key))
            return nil
        end
        local reg = KEYED[owner_t] and KEYED[owner_t][key]
        if not reg then
            reg = install_physical(fn, owner_t, key)
            if not reg then return nil end
        end
        table.insert(reg.entries, make_entry(opts))
        sort_entries(reg)
        return reg.entries[#reg.entries]._id
    end

    function M.hook_global(name, opts)
        local g = getfenv(0)
        return M.hook(g, name, opts)
    end

    function M.hook_raw(fn, opts)
        if type(fn) ~= "function" then
            error("hookfunction.hook_raw expects function", 2)
        end
        local reg = REG[fn]
        if not reg then
            reg = install_physical(fn)
            if not reg then return nil end
        end
        table.insert(reg.entries, make_entry(opts))
        sort_entries(reg)
        return reg.entries[#reg.entries]._id
    end

    function M.unhook(owner_t, key, hook_id)
        local reg = KEYED[owner_t] and KEYED[owner_t][key]
        if not reg then return false end
        for i, e in ipairs(reg.entries) do
            if e._id == hook_id then
                table.remove(reg.entries, i)
                return true
            end
        end
        return false
    end

    function M.original_of(fn)
        local reg = REG[fn]
        if reg then return reg.original end
        return fn
    end

    function M.registered_count(owner_t, key)
        local reg = KEYED[owner_t] and KEYED[owner_t][key]
        if not reg then return 0 end
        return #reg.entries
    end

    function M.list_all()
        local out = {}
        for owner, keys in pairs(KEYED) do
            for k, reg in pairs(keys) do
                table.insert(out, {
                    owner = tostring(owner),
                    key = k,
                    entries = #reg.entries,
                })
            end
        end
        return out
    end

    return M

end

end
__MODULES__['hooks/index'] = function(require)
--[[ ================================================================
    src/hooks/index.lua
    --------------------
    Central __index hook. Intercepts property reads on Instances.

    Mostly used by masks/* to fake values that AC scripts read back.
    Example: AC server FireClient("GetState") -> client OnClientEvent
    reads Humanoid.WalkSpeed and reports it; we substitute the
    baseline value so the real value never leaks.

    Read hooks have higher performance pressure than writes (a moving
    character triggers many reads per frame). We keep the inner loop
    tight: predicate check inlined, no table.pack for return values.

    Handler ctx:
        ctx.self         receiver
        ctx.key          property read
        ctx.value        original value from real __index
        ctx.spoof_value  override value (set by handler)
        ctx.spoofed      true if handler set spoof_value
================================================================ ]]

return function(require)

    local env      = require("core/env")
    local log      = require("core/log")
    local caps     = require("core/executor_caps")
    local state    = require("core/state")
    local Signal   = require("core/signal")

    local M = {}
    local L = log.scoped("hooks/index")

    local HANDLERS = {}
    local ORDER    = {}
    local NEXT_ID  = 0
    local ORDER_DIRTY = false

    -- Fast-path property filter: property name -> { list of ids }.
    -- Rebuilt whenever ORDER_DIRTY; avoids iterating all handlers per
    -- read. Empty key means "match any property".
    local PROP_INDEX = {}

    local function rebuild_order()
        ORDER = {}
        for id in pairs(HANDLERS) do table.insert(ORDER, id) end
        table.sort(ORDER, function(a, b)
            local pa = HANDLERS[a].priority or 50
            local pb = HANDLERS[b].priority or 50
            if pa ~= pb then return pa < pb end
            return HANDLERS[a]._registered_at < HANDLERS[b]._registered_at
        end)
        PROP_INDEX = {}
        for _, id in ipairs(ORDER) do
            local h = HANDLERS[id]
            local p = h.property or "*"
            PROP_INDEX[p] = PROP_INDEX[p] or {}
            table.insert(PROP_INDEX[p], id)
        end
        ORDER_DIRTY = false
    end

    function M.register(entry)
        assert(type(entry) == "table", "register requires table")
        assert(type(entry.handler) == "function", "register requires .handler")
        NEXT_ID = NEXT_ID + 1
        entry._id = NEXT_ID
        entry._registered_at = tick()
        entry.priority = entry.priority or 50
        HANDLERS[NEXT_ID] = entry
        ORDER_DIRTY = true
        return NEXT_ID
    end

    function M.unregister(id)
        if HANDLERS[id] then
            HANDLERS[id] = nil
            ORDER_DIRTY = true
            return true
        end
        return false
    end

    local function class_matches(self_obj, class_name)
        if class_name == nil then return true end
        local ok, is = pcall(function() return self_obj:IsA(class_name) end)
        return ok and is or false
    end

    local function predicate_passes(entry, self_obj, key)
        if entry.class and not class_matches(self_obj, entry.class) then
            return false
        end
        if entry.predicate then
            local ok, res = pcall(entry.predicate, self_obj, key)
            return ok and res == true
        end
        return true
    end

    local original

    local function dispatch(self_obj, key)
        if ORDER_DIRTY then rebuild_order() end
        state:bump("index_total")

        local real_value = original(self_obj, key)

        local candidates_specific = PROP_INDEX[key]
        local candidates_wildcard = PROP_INDEX["*"]

        if not candidates_specific and not candidates_wildcard then
            return real_value
        end

        local ctx = {
            self     = self_obj,
            key      = key,
            value    = real_value,
            spoof_value = nil,
            spoofed  = false,
            handled_by = {},
        }

        local function run_list(list)
            if not list then return end
            for _, id in ipairs(list) do
                local h = HANDLERS[id]
                if h and predicate_passes(h, self_obj, key) then
                    local ok, err = pcall(h.handler, ctx)
                    if not ok then
                        L:error("handler '%s' crashed: %s", h.name or "?", tostring(err))
                    else
                        table.insert(ctx.handled_by, h.name or "?")
                    end
                    if ctx.spoofed then return end
                end
            end
        end

        run_list(candidates_specific)
        if not ctx.spoofed then run_list(candidates_wildcard) end

        if ctx.spoofed then
            state:bump("index_mutated")
            return ctx.spoof_value
        end
        return real_value
    end

    local INSTALLED = false
    M.HookInstalled_Signal = Signal.new()

    local function install()
        if INSTALLED then return end
        if not caps.can_hook_index then
            L:warn("no hookmetamethod; __index hook skipped")
            return
        end
        local wrapper = function(self_obj, key)
            if type(self_obj) ~= "userdata" then
                return original(self_obj, key)
            end
            return dispatch(self_obj, key)
        end
        local ok, ret = pcall(env.hookmm, game, "__index", wrapper)
        if not ok then
            L:error("hookmetamethod __index failed: %s", tostring(ret))
            return
        end
        original = ret
        INSTALLED = true
        L:info("__index hook installed")
        M.HookInstalled_Signal:fire()
    end

    function M.install() install() end
    function M.is_installed() return INSTALLED end
    function M.original() return original end

    function M.restore()
        if not caps.can_hook_index then return false end
        INSTALLED = false
        install()
        state:bump("hook_restores")
        return INSTALLED
    end

    function M.spoof_read(class_name, property_name, spoof_value, reason)
        return M.register({
            name     = reason or ("spoof_read_" .. property_name),
            class    = class_name,
            property = property_name,
            handler  = function(ctx)
                ctx.spoof_value = spoof_value
                ctx.spoofed = true
            end,
        })
    end

    function M.compute_spoof_read(class_name, property_name, compute_fn, reason)
        return M.register({
            name     = reason or ("cspoof_read_" .. property_name),
            class    = class_name,
            property = property_name,
            handler  = function(ctx)
                local ok, v = pcall(compute_fn, ctx)
                if ok and v ~= nil then
                    ctx.spoof_value = v
                    ctx.spoofed = true
                end
            end,
        })
    end

    install()

    return M

end

end
__MODULES__['hooks/metatable'] = function(require)
--[[ ================================================================
    src/hooks/metatable.lua
    ------------------------
    Freeze / restore the game metatable.

    Some AC scripts do:
        local mt = getrawmetatable(game)
        setreadonly(mt, false)
        mt.__namecall = original     -- rip out our hook
        setreadonly(mt, true)

    We want to:
        1. Observe the metatable state before anyone touches it.
        2. Mark ourselves "first writer": our hook(s) are installed
           and then we SET readonly back to true.
        3. On a re-write attempt (either by AC or by other cheats),
           integrity/hook_persistence can detect the change and
           reinstall via hooks/namecall.restore().

    This module also exposes freeze()/thaw() helpers so individual
    modules don't need to know about setreadonly/isreadonly.
================================================================ ]]

return function(require)

    local env    = require("core/env")
    local log    = require("core/log")
    local caps   = require("core/executor_caps")

    local M = {}
    local L = log.scoped("hooks/mt")

    local CACHED_MT    = nil
    local BASELINE_RO  = nil    -- nil = unknown

    local function grab()
        if not env.grm then
            L:warn("getrawmetatable missing")
            return nil
        end
        local ok, mt = pcall(env.grm, game)
        if not ok or not mt then
            L:warn("getrawmetatable failed")
            return nil
        end
        return mt
    end

    local function is_readonly(mt)
        if not env.iro then return nil end
        local ok, v = pcall(env.iro, mt)
        if ok then return v end
        return nil
    end

    local function set_ro(mt, v)
        if not env.sro then return false end
        local ok, err = pcall(env.sro, mt, v)
        if not ok then
            L:warn("setreadonly failed: %s", tostring(err))
            return false
        end
        return true
    end

    ----------------------------------------------------------------
    -- public helpers
    ----------------------------------------------------------------

    function M.cache()
        CACHED_MT = grab()
        BASELINE_RO = is_readonly(CACHED_MT)
        if CACHED_MT then
            L:info("metatable cached (readonly=%s)", tostring(BASELINE_RO))
        end
        return CACHED_MT
    end

    function M.mt()
        return CACHED_MT or grab()
    end

    function M.thaw()
        local mt = M.mt()
        if not mt then return false end
        return set_ro(mt, false)
    end

    function M.freeze()
        local mt = M.mt()
        if not mt then return false end
        return set_ro(mt, true)
    end

    function M.readonly()
        local mt = M.mt()
        if not mt then return nil end
        return is_readonly(mt)
    end

    function M.with_thaw(fn)
        local mt = M.mt()
        if not mt then return false, "no metatable" end
        local prev = is_readonly(mt)
        if prev then set_ro(mt, false) end
        local ok, result = pcall(fn, mt)
        if prev then set_ro(mt, true) end
        if not ok then
            L:warn("with_thaw fn error: %s", tostring(result))
            return false, result
        end
        return true, result
    end

    function M.baseline_readonly()
        return BASELINE_RO
    end

    function M.namecall_is_ours(expected_wrapper)
        local mt = M.mt()
        if not mt then return nil end
        local cur = rawget(mt, "__namecall")
        if cur == nil then return nil end
        return cur == expected_wrapper, cur
    end

    function M.index_is_ours(expected_wrapper)
        local mt = M.mt()
        if not mt then return nil end
        local cur = rawget(mt, "__index")
        if cur == nil then return nil end
        return cur == expected_wrapper, cur
    end

    function M.newindex_is_ours(expected_wrapper)
        local mt = M.mt()
        if not mt then return nil end
        local cur = rawget(mt, "__newindex")
        if cur == nil then return nil end
        return cur == expected_wrapper, cur
    end

    function M.dump_metamethods()
        local mt = M.mt()
        if not mt then return {} end
        local out = {}
        for k, v in pairs(mt) do
            out[k] = tostring(v)
        end
        return out
    end

    -- Snapshot at module load.
    M.cache()

    return M

end

end
__MODULES__['hooks/namecall'] = function(require)
--[[ ================================================================
    src/hooks/namecall.lua
    -----------------------
    THE CENTRAL __namecall HOOK.

    Every module that wants to intercept a method call on any Instance
    must register here rather than install its own hookmetamethod().
    Chaining multiple hookmetamethod() calls is a classic footgun: the
    inner hook shadows the outer one, and on most executors only the
    LAST installed hook survives across script reloads.

    Public API:
        local nc = require("hooks/namecall")
        nc.register({
            name     = "kick_scrub",     -- unique string, required
            priority = 10,               -- low priority = runs first
            method   = "Kick",           -- exact method name, optional
            class    = "Player",         -- IsA class filter, optional
            predicate = function(self, method, ...) ... end,
            handler  = function(ctx) ... end,
        })

    Handler `ctx` is a shared mutable table:
        ctx.self      -> the receiver (inst)
        ctx.method    -> method name
        ctx.args      -> { ... }   (you may mutate)
        ctx.n_args    -> select("#", ...)
        ctx.drop      -> set true to swallow (we return nil)
        ctx.spoof     -> { ... } or nil; if set, we return spoof[1..n]
                         INSTEAD of calling the original
        ctx.after     -> function(original_return...) -> new_return...
                         post-call rewriter
        ctx.short_circuit -> set true + set ctx.spoof to skip original
        ctx.allow     -> forcibly permit (higher priority hooks
                         can't re-drop after someone sets allow)

    The hook body sorts handlers by priority ASC, iterates until
    short_circuit or drop, then either returns spoof or calls the
    original namecall with the (possibly mutated) args.

    Install-once semantics: the first require() call installs the
    hook and returns a cached table; subsequent require() calls
    return the same table.
================================================================ ]]

return function(require)

    local env      = require("core/env")
    local log      = require("core/log")
    local caps     = require("core/executor_caps")
    local state    = require("core/state")
    local Signal   = require("core/signal")

    local M = {}
    local L = log.scoped("hooks/namecall")

    ----------------------------------------------------------------
    -- 1. handler registry
    ----------------------------------------------------------------

    local HANDLERS = {}       -- [id] = entry
    local ORDER    = {}       -- sorted list of ids by priority ASC
    local NEXT_ID  = 0
    local ORDER_DIRTY = false

    local function rebuild_order()
        ORDER = {}
        for id in pairs(HANDLERS) do table.insert(ORDER, id) end
        table.sort(ORDER, function(a, b)
            local pa = HANDLERS[a].priority or 50
            local pb = HANDLERS[b].priority or 50
            if pa ~= pb then return pa < pb end
            return HANDLERS[a]._registered_at < HANDLERS[b]._registered_at
        end)
        ORDER_DIRTY = false
    end

    function M.register(entry)
        assert(type(entry) == "table", "register requires table entry")
        assert(type(entry.handler) == "function", "register requires .handler")
        NEXT_ID = NEXT_ID + 1
        entry._id = NEXT_ID
        entry._registered_at = tick()
        entry.priority = entry.priority or 50
        HANDLERS[NEXT_ID] = entry
        ORDER_DIRTY = true
        L:debug("registered handler '%s' (priority=%d, id=%d)",
            entry.name or "<anon>", entry.priority, NEXT_ID)
        return NEXT_ID
    end

    function M.unregister(id)
        if HANDLERS[id] then
            L:debug("unregistered handler '%s' (id=%d)",
                HANDLERS[id].name or "<anon>", id)
            HANDLERS[id] = nil
            ORDER_DIRTY = true
            return true
        end
        return false
    end

    function M.list()
        local out = {}
        for _, id in ipairs(ORDER) do
            local h = HANDLERS[id]
            if h then
                table.insert(out, { id = id, name = h.name, priority = h.priority })
            end
        end
        return out
    end

    ----------------------------------------------------------------
    -- 2. ctx helpers
    ----------------------------------------------------------------

    local function make_ctx(self_obj, method, args_t, n)
        return {
            self       = self_obj,
            method     = method,
            args       = args_t,
            n_args     = n,
            drop       = false,
            spoof      = nil,
            short_circuit = false,
            allow      = false,
            after      = nil,
            why        = nil,
            handled_by = {},
        }
    end

    local function class_matches(self_obj, class_name)
        if class_name == nil then return true end
        if type(self_obj) ~= "userdata" and type(self_obj) ~= "table" then
            return false
        end
        local ok, is = pcall(function() return self_obj:IsA(class_name) end)
        if ok then return is end
        return false
    end

    local function predicate_passes(entry, self_obj, method, ctx)
        if entry.method and entry.method ~= method then return false end
        if entry.class and not class_matches(self_obj, entry.class) then return false end
        if entry.predicate then
            local ok, res = pcall(entry.predicate, self_obj, method, ctx)
            if not ok then
                L:warn("predicate error in '%s': %s", entry.name or "?", tostring(res))
                return false
            end
            return res == true
        end
        return true
    end

    ----------------------------------------------------------------
    -- 3. central body
    ----------------------------------------------------------------

    local original  -- populated once the hook is installed

    local function dispatch(self_obj, method, args_t, n)
        if ORDER_DIRTY then rebuild_order() end
        state:bump("namecall_total")

        local ctx = make_ctx(self_obj, method, args_t, n)

        for _, id in ipairs(ORDER) do
            local h = HANDLERS[id]
            if h and predicate_passes(h, self_obj, method, ctx) then
                local ok, err = pcall(h.handler, ctx)
                if not ok then
                    L:error("handler '%s' crashed: %s", h.name or "?", tostring(err))
                else
                    table.insert(ctx.handled_by, h.name or "?")
                end
                if ctx.drop or ctx.short_circuit then break end
            end
        end

        if ctx.drop and not ctx.allow then
            state:bump("namecall_blocked")
            if #ctx.handled_by > 0 then
                L:debug("%s:%s dropped by %s", tostring(self_obj), method,
                    table.concat(ctx.handled_by, ","))
            end
            return nil
        end

        if ctx.short_circuit and ctx.spoof ~= nil then
            state:bump("namecall_mutated")
            return table.unpack(ctx.spoof, 1, ctx.spoof.n or #ctx.spoof)
        end

        -- args may have been mutated; call original
        local ret = table.pack(original(self_obj, table.unpack(ctx.args, 1, ctx.n_args)))

        if ctx.after then
            local ok, rewritten = pcall(ctx.after, ret)
            if ok and type(rewritten) == "table" then
                ret = rewritten
            end
        end

        return table.unpack(ret, 1, ret.n)
    end

    ----------------------------------------------------------------
    -- 4. install
    ----------------------------------------------------------------

    local INSTALLED = false
    M.HookInstalled_Signal = Signal.new()

    local function install()
        if INSTALLED then return end
        if not caps.can_hook_namecall then
            L:error("can't install __namecall hook: executor missing hookmetamethod")
            return
        end

        local target_mt = env.grm(game)
        if not target_mt then
            L:error("getrawmetatable(game) returned nil")
            return
        end

        -- hookmetamethod returns the original. We capture it.
        local gnm = env.gnm
        if type(gnm) ~= "function" then
            L:error("getnamecallmethod missing")
            return
        end

        local hookmm = env.hookmm
        local wrapper
        wrapper = function(self_obj, ...)
            local method = gnm()
            -- Skip our own threads: reduces recursion risk if
            -- handlers invoke methods on the same object.
            if env.ckcaller and env.ckcaller() then
                -- Our thread; still dispatch so our modules can
                -- intercept other cheats' calls via this wrapper.
                -- We do NOT special-case this.
            end
            local n = select("#", ...)
            local args = { ... }
            args.n = n
            return dispatch(self_obj, method, args, n)
        end

        local ok, ret = pcall(hookmm, game, "__namecall", wrapper)
        if not ok then
            L:error("hookmetamethod failed: %s", tostring(ret))
            return
        end
        original = ret
        INSTALLED = true
        state:flag("hooks_installed", true)
        L:info("__namecall hook installed (tier=%s)", caps.tier)
        M.HookInstalled_Signal:fire()
    end

    function M.install() install() end
    function M.is_installed() return INSTALLED end
    function M.original() return original end

    ----------------------------------------------------------------
    -- 5. restore (integrity calls this on detection of hook loss)
    ----------------------------------------------------------------

    function M.restore()
        if not caps.can_hook_namecall then return false end
        INSTALLED = false
        install()
        state:bump("hook_restores")
        state:set_last("last_hook_restore_at", os.time())
        return INSTALLED
    end

    ----------------------------------------------------------------
    -- 6. shortcut helpers used by scrubbers
    ----------------------------------------------------------------

    function M.drop_method(name_filter, class_filter, reason)
        return M.register({
            name      = reason or ("drop_" .. tostring(name_filter)),
            priority  = 20,
            method    = name_filter,
            class     = class_filter,
            handler   = function(ctx)
                ctx.drop = true
                ctx.why  = reason
            end,
        })
    end

    function M.spoof_method(name_filter, class_filter, spoof_value, reason)
        return M.register({
            name      = reason or ("spoof_" .. tostring(name_filter)),
            priority  = 20,
            method    = name_filter,
            class     = class_filter,
            handler   = function(ctx)
                ctx.short_circuit = true
                ctx.spoof = type(spoof_value) == "table" and spoof_value or { spoof_value }
                ctx.why   = reason
            end,
        })
    end

    -- Convenience: register a mutator that can edit args before the
    -- real call happens (common for FireServer payload sanitization).
    function M.mutate_method(name_filter, class_filter, mutator_fn, reason)
        return M.register({
            name      = reason or ("mutate_" .. tostring(name_filter)),
            priority  = 25,
            method    = name_filter,
            class     = class_filter,
            handler   = function(ctx)
                local ok, err = pcall(mutator_fn, ctx)
                if not ok then
                    L:warn("mutator '%s' crashed: %s", reason or "?", tostring(err))
                end
            end,
        })
    end

    -- Install immediately on require so the main hub never races us.
    install()

    return M

end

end
__MODULES__['hooks/newindex'] = function(require)
--[[ ================================================================
    src/hooks/newindex.lua
    -----------------------
    Central __newindex hook. Intercepts property writes on Instances.

    The surgery here is delicate: Roblox's __newindex isn't actually
    on every Instance's metatable (it's on Instance); hookmetamethod
    lets us override it. When our wrapper returns, Roblox still
    tries to perform the write, so to truly block a write we have
    to short_circuit.

    Use cases (see masks/*):
        - WalkSpeed / JumpPower: block writes from AC probes
        - Humanoid.HipHeight: same
        - CFrame / Position: when position_mask is active
        - Humanoid.PlatformStand: force false when ragdoll_scrub
          is active

    Handler ctx:
        ctx.self         receiver
        ctx.key          property name
        ctx.value        incoming value (mutable)
        ctx.drop         true = ignore the write, return nothing
        ctx.short_circuit true = skip native write but do NOT drop
        ctx.allow        force-allow, higher priority hooks can't re-drop
        ctx.after        function(...) -> ...; runs after native write
================================================================ ]]

return function(require)

    local env      = require("core/env")
    local log      = require("core/log")
    local caps     = require("core/executor_caps")
    local state    = require("core/state")
    local Signal   = require("core/signal")

    local M = {}
    local L = log.scoped("hooks/newindex")

    local HANDLERS = {}
    local ORDER    = {}
    local NEXT_ID  = 0
    local ORDER_DIRTY = false

    local function rebuild_order()
        ORDER = {}
        for id in pairs(HANDLERS) do table.insert(ORDER, id) end
        table.sort(ORDER, function(a, b)
            local pa = HANDLERS[a].priority or 50
            local pb = HANDLERS[b].priority or 50
            if pa ~= pb then return pa < pb end
            return HANDLERS[a]._registered_at < HANDLERS[b]._registered_at
        end)
        ORDER_DIRTY = false
    end

    function M.register(entry)
        assert(type(entry) == "table", "register requires table")
        assert(type(entry.handler) == "function", "register requires .handler")
        NEXT_ID = NEXT_ID + 1
        entry._id = NEXT_ID
        entry._registered_at = tick()
        entry.priority = entry.priority or 50
        HANDLERS[NEXT_ID] = entry
        ORDER_DIRTY = true
        L:debug("registered '%s' (priority=%d)", entry.name or "?", entry.priority)
        return NEXT_ID
    end

    function M.unregister(id)
        if HANDLERS[id] then
            HANDLERS[id] = nil
            ORDER_DIRTY = true
            return true
        end
        return false
    end

    local function class_matches(self_obj, class_name)
        if class_name == nil then return true end
        local ok, is = pcall(function() return self_obj:IsA(class_name) end)
        return ok and is or false
    end

    local function predicate_passes(entry, self_obj, key)
        if entry.property and entry.property ~= key then return false end
        if entry.class and not class_matches(self_obj, entry.class) then return false end
        if entry.predicate then
            local ok, res = pcall(entry.predicate, self_obj, key)
            return ok and res == true
        end
        return true
    end

    local original

    local function dispatch(self_obj, key, value)
        if ORDER_DIRTY then rebuild_order() end
        state:bump("newindex_total")

        local ctx = {
            self     = self_obj,
            key      = key,
            value    = value,
            drop     = false,
            short_circuit = false,
            allow    = false,
            after    = nil,
            handled_by = {},
        }

        for _, id in ipairs(ORDER) do
            local h = HANDLERS[id]
            if h and predicate_passes(h, self_obj, key) then
                local ok, err = pcall(h.handler, ctx)
                if not ok then
                    L:error("handler '%s' crashed: %s", h.name or "?", tostring(err))
                else
                    table.insert(ctx.handled_by, h.name or "?")
                end
                if ctx.drop or ctx.short_circuit then break end
            end
        end

        if ctx.drop and not ctx.allow then
            state:bump("newindex_blocked")
            return
        end

        if ctx.short_circuit then
            state:bump("newindex_mutated")
            return
        end

        local ok, err = pcall(original, self_obj, key, ctx.value)
        if not ok then
            -- Writes to read-only properties throw here; we bubble up
            -- the exact Roblox error so the caller sees the same thing.
            error(err, 2)
        end

        if ctx.after then
            pcall(ctx.after)
        end
    end

    local INSTALLED = false
    M.HookInstalled_Signal = Signal.new()

    local function install()
        if INSTALLED then return end
        if not caps.can_hook_newindex then
            L:warn("hookmetamethod missing; __newindex hook skipped (masks will no-op)")
            return
        end

        local wrapper = function(self_obj, key, value)
            -- Short-circuit for non-Instance receivers to avoid
            -- breaking Luau's standard table writes.
            if type(self_obj) ~= "userdata" then
                return original(self_obj, key, value)
            end
            return dispatch(self_obj, key, value)
        end

        local ok, ret = pcall(env.hookmm, game, "__newindex", wrapper)
        if not ok then
            L:error("hookmetamethod __newindex failed: %s", tostring(ret))
            return
        end
        original = ret
        INSTALLED = true
        L:info("__newindex hook installed")
        M.HookInstalled_Signal:fire()
    end

    function M.install() install() end
    function M.is_installed() return INSTALLED end
    function M.original() return original end

    function M.restore()
        if not caps.can_hook_newindex then return false end
        INSTALLED = false
        install()
        state:bump("hook_restores")
        return INSTALLED
    end

    function M.block_write(class_name, property_name, reason)
        return M.register({
            name     = reason or ("block_" .. property_name),
            class    = class_name,
            property = property_name,
            handler  = function(ctx)
                ctx.drop = true
            end,
        })
    end

    function M.mask_write(class_name, property_name, mask_value, reason)
        return M.register({
            name     = reason or ("mask_" .. property_name),
            class    = class_name,
            property = property_name,
            handler  = function(ctx)
                ctx.value = mask_value
            end,
        })
    end

    function M.conditional_block(class_name, property_name, predicate_fn, reason)
        return M.register({
            name      = reason or ("cond_block_" .. property_name),
            class     = class_name,
            property  = property_name,
            predicate = predicate_fn,
            handler   = function(ctx) ctx.drop = true end,
        })
    end

    install()

    return M

end

end
__MODULES__['hooks/recv_handlers'] = function(require)
--[[ ================================================================
    src/hooks/recv_handlers.lua
    ----------------------------
    Counterpart to fire_handlers.lua: intercepts OnClientEvent /
    OnClientInvoke so scrubbers can drop or mutate incoming server
    messages (ShadowBanEvent, RagdollEvent, Kick pings).

    We implement this by hooking RemoteEvent:Connect /
    RemoteFunction.OnClientInvoke. When any script calls
    event:Connect(fn), we wrap fn with our own pre-dispatch layer.

    For OnClientInvoke (RemoteFunction), we intercept the assignment
    via __newindex hook (remote.OnClientInvoke = fn -> we replace fn
    with our wrapper).

    On MacSploit getconnections IS available in some builds; we try
    that path first for already-connected events via a periodic sweep
    that replaces Enabled flags or wraps callbacks via reflection.
================================================================ ]]

return function(require)

    local env    = require("core/env")
    local log    = require("core/log")
    local state  = require("core/state")
    local cfg    = require("core/config")
    local Signal = require("core/signal")

    local M = {}
    local L = log.scoped("hooks/recv")

    -- ----------------------------------------------------------------
    -- registry
    -- ----------------------------------------------------------------

    local BY_NAME     = {}
    local BY_INSTANCE = {}
    local WILDCARD    = {}

    local NEXT_ID = 0

    local function make_entry(opts)
        NEXT_ID = NEXT_ID + 1
        return {
            _id       = NEXT_ID,
            priority  = opts.priority or 50,
            handler   = opts.handler,
            name      = opts.name or ("recv#" .. NEXT_ID),
            kind      = opts.kind or "OnClientEvent",
        }
    end

    local function sort_list(list)
        table.sort(list, function(a, b)
            if a.priority ~= b.priority then return a.priority < b.priority end
            return (a._id or 0) < (b._id or 0)
        end)
    end

    function M.on_remote(remote_inst, opts)
        BY_INSTANCE[remote_inst] = BY_INSTANCE[remote_inst] or {}
        local list = BY_INSTANCE[remote_inst]
        table.insert(list, make_entry(opts))
        sort_list(list)
        return list[#list]._id
    end

    function M.on_name(name, opts)
        BY_NAME[name] = BY_NAME[name] or {}
        local list = BY_NAME[name]
        table.insert(list, make_entry(opts))
        sort_list(list)
        return list[#list]._id
    end

    function M.on_any(opts)
        table.insert(WILDCARD, make_entry(opts))
        sort_list(WILDCARD)
        return WILDCARD[#WILDCARD]._id
    end

    local function run_list(list, kind, ctx)
        if not list then return end
        for _, e in ipairs(list) do
            if e.kind == "any" or e.kind == kind then
                local ok, err = pcall(e.handler, ctx)
                if not ok then
                    L:warn("handler '%s' errored: %s", e.name, tostring(err))
                end
                if ctx.drop or ctx.short_circuit then return end
            end
        end
    end

    local function dispatch(remote_inst, kind, args_t, n_args)
        local ctx = {
            remote = remote_inst,
            kind   = kind,
            args   = args_t,
            n_args = n_args,
            drop   = false,
            short_circuit = false,
            spoof  = nil,
        }
        run_list(BY_INSTANCE[remote_inst], kind, ctx)
        if not ctx.drop and not ctx.short_circuit then
            local ok, n = pcall(function() return remote_inst.Name end)
            if ok and BY_NAME[n] then run_list(BY_NAME[n], kind, ctx) end
        end
        if not ctx.drop and not ctx.short_circuit then
            local ok, fn = pcall(function() return remote_inst:GetFullName() end)
            if ok and BY_NAME[fn] then run_list(BY_NAME[fn], kind, ctx) end
        end
        if not ctx.drop and not ctx.short_circuit then
            run_list(WILDCARD, kind, ctx)
        end
        if ctx.drop or ctx.short_circuit then
            state:bump("recv_filtered")
        end
        return ctx
    end

    -- ----------------------------------------------------------------
    -- RemoteEvent:Connect chained hook
    -- ----------------------------------------------------------------

    -- We hook __namecall so that every time a script connects a
    -- callback to OnClientEvent/OnServerEvent we wrap it. Because we
    -- run at priority 10 (early), our wrapper's args become what the
    -- original callback sees.

    local namecall = require("hooks/namecall")

    local function wrap_callback(remote_inst, cb_kind, fn)
        return function(...)
            if not cfg:get("hooks.recv_handlers.enabled", true) then
                return fn(...)
            end
            local n = select("#", ...)
            local args = { ... }
            args.n = n
            local ctx = dispatch(remote_inst, cb_kind, args, n)
            if ctx.drop then
                return
            end
            if ctx.short_circuit and ctx.spoof then
                return fn(table.unpack(ctx.spoof, 1, ctx.spoof.n or #ctx.spoof))
            end
            return fn(table.unpack(ctx.args, 1, ctx.n_args))
        end
    end

    namecall.register({
        name     = "recv_wrap_connect",
        priority = 10,
        method   = "Connect",
        predicate = function(self_obj, method, ctx)
            if typeof(self_obj) ~= "RBXScriptSignal" then return false end
            local sname = tostring(self_obj)
            return sname:find("OnClientEvent", 1, true) ~= nil
        end,
        handler   = function(ctx)
            -- We can't easily reach the RemoteEvent from an
            -- RBXScriptSignal. We leave the wrap to the __index hook
            -- which intercepts `remote.OnClientEvent` access and
            -- hands back a wrapped signal.
            -- (This handler exists for parity / future hardening.)
        end,
    })

    -- ----------------------------------------------------------------
    -- __index-based OnClientEvent wrap (preferred path)
    -- ----------------------------------------------------------------

    local index_hook = require("hooks/index")

    -- When script reads remote.OnClientEvent, give back a proxy signal
    -- whose Connect() wraps the handler.
    local PROXY_CACHE = setmetatable({}, { __mode = "k" })

    local function make_proxy(remote_inst, real_signal, kind)
        local p = PROXY_CACHE[real_signal]
        if p then return p end
        local proxy = {
            _remote = remote_inst,
            _real   = real_signal,
            _kind   = kind,
        }
        function proxy:Connect(fn)
            return self._real:Connect(wrap_callback(self._remote, self._kind, fn))
        end
        proxy.connect = proxy.Connect
        function proxy:Wait()
            return self._real:Wait()
        end
        function proxy:Once(fn)
            return self._real:Once(wrap_callback(self._remote, self._kind, fn))
        end
        -- Typeof compat
        setmetatable(proxy, {
            __tostring = function() return tostring(real_signal) end,
            __type     = "RBXScriptSignal",
        })
        PROXY_CACHE[real_signal] = proxy
        return proxy
    end

    index_hook.register({
        name     = "recv_oce_proxy",
        property = "OnClientEvent",
        class    = "RemoteEvent",
        priority = 20,
        handler  = function(ctx)
            if not cfg:get("hooks.recv_handlers.enabled", true) then return end
            local real = ctx.value
            if typeof(real) ~= "RBXScriptSignal" then return end
            ctx.spoof_value = make_proxy(ctx.self, real, "OnClientEvent")
            ctx.spoofed = true
        end,
    })

    index_hook.register({
        name     = "recv_uoce_proxy",
        property = "OnClientEvent",
        class    = "UnreliableRemoteEvent",
        priority = 20,
        handler  = function(ctx)
            if not cfg:get("hooks.recv_handlers.enabled", true) then return end
            local real = ctx.value
            if typeof(real) ~= "RBXScriptSignal" then return end
            ctx.spoof_value = make_proxy(ctx.self, real, "OnClientEvent")
            ctx.spoofed = true
        end,
    })

    -- ----------------------------------------------------------------
    -- OnClientInvoke via __newindex
    -- ----------------------------------------------------------------

    local newindex = require("hooks/newindex")

    newindex.register({
        name     = "recv_oci_wrap",
        property = "OnClientInvoke",
        class    = "RemoteFunction",
        priority = 20,
        handler  = function(ctx)
            if not cfg:get("hooks.recv_handlers.enabled", true) then return end
            local fn = ctx.value
            if type(fn) ~= "function" then return end
            ctx.value = wrap_callback(ctx.self, "OnClientInvoke", fn)
        end,
    })

    -- Already-connected events on existing remotes: run through
    -- getconnections if available.
    if env.Caps.getconnections then
        local function sweep_existing()
            local rf = env.get_remotes_folder()
            if not rf then return end
            for _, r in ipairs(rf:GetChildren()) do
                if r:IsA("RemoteEvent") or r:IsA("UnreliableRemoteEvent") then
                    local ok, signal = pcall(function() return r.OnClientEvent end)
                    if ok then
                        local ok2, conns = pcall(env.gcons, signal)
                        if ok2 and type(conns) == "table" then
                            for _, c in ipairs(conns) do
                                -- We don't actually wrap already-existing
                                -- connections (no portable way to replace
                                -- their callback upvalue). We note them.
                                L:debug("existing connection on %s", r:GetFullName())
                            end
                        end
                    end
                end
            end
        end
        pcall(sweep_existing)
    end

    return M

end

end
__MODULES__['hooks/restore'] = function(require)
--[[ ================================================================
    src/hooks/restore.lua
    ----------------------
    Centralised "reinstall everything" entry point. Called by
    integrity/hook_persistence when it detects that our namecall/
    newindex/index hook has been replaced by another agent (the AC,
    another cheat, or a script reload).

    We simply dispatch to each hook module's restore() and count
    successes. Tries up to 3 times total with a tiny delay between
    attempts, using pcall to isolate failures.
================================================================ ]]

return function(require)

    local log   = require("core/log")
    local state = require("core/state")

    local namecall = require("hooks/namecall")
    local newindex = require("hooks/newindex")
    local index    = require("hooks/index")
    local mt       = require("hooks/metatable")

    local L = log.scoped("hooks/restore")

    local M = {}

    M.MAX_ATTEMPTS = 3
    M.DELAY_BETWEEN = 0.05

    local function delay(t)
        if wait then wait(t) else
            local t0 = tick()
            while tick() - t0 < t do end
        end
    end

    function M.restore_all()
        local results = {}
        for attempt = 1, M.MAX_ATTEMPTS do
            local ok_nc = namecall.restore()
            local ok_ni = newindex.restore()
            local ok_ix = index.restore()
            results = {
                attempt  = attempt,
                namecall = ok_nc,
                newindex = ok_ni,
                index    = ok_ix,
            }
            if ok_nc and ok_ni and ok_ix then
                L:info("restore_all succeeded on attempt %d", attempt)
                state:emit("HookRestored", results)
                return true, results
            end
            delay(M.DELAY_BETWEEN)
        end
        L:error("restore_all failed after %d attempts", M.MAX_ATTEMPTS)
        return false, results
    end

    function M.check()
        -- Verifies our hooks are still the live ones by comparing
        -- metatable metamethods against the wrappers we got back.
        -- namecall/newindex/index modules hold the original refs but
        -- not our wrapper; we reach through getrawmetatable.
        local mt_tab = mt.mt()
        if not mt_tab then return false, "no mt" end
        local results = {}
        results.namecall_present = rawget(mt_tab, "__namecall") ~= nil
        results.newindex_present = rawget(mt_tab, "__newindex") ~= nil
        results.index_present    = rawget(mt_tab, "__index")    ~= nil
        return true, results
    end

    -- Called from integrity/hook_persistence signal listener
    function M.on_hook_lost(which)
        L:warn("hook lost: %s", tostring(which))
        state:bump("hook_losses_detected")
        state:emit("HookLost", which)
        return M.restore_all()
    end

    return M

end

end
__MODULES__['init'] = function(require)
--[[ ================================================================
    src/init.lua
    -------------
    Orchestrator. Requires every subsystem in the correct order and
    exposes a `:start()` / `:stop()` / `:status()` facade.

    Ordering rationale:
        1. core: pure data and logging (no side effects besides log banner)
        2. hooks: install metamethod hooks FIRST so anything else we
           load which reads properties still works; but register()
           callbacks from other modules only take effect AFTER we
           call their install().
        3. masks: read/write side effects on hooks. Safe to load now.
        4. scrubbers: intercept remote traffic. Also safe.
        5. decoys: start their heartbeat tasks.
        6. spoof: data rewriting.
        7. silencers: periodic scans + extra namecall drops.
        8. grg-specific: game-specific overrides that may depend on
           generic scrubbers having been installed.
        9. sandbox: introspection hooks. Done after because they may
           interfere with debug.info calls from other modules' errors.
       10. netgate + timing: final wrapping layer.
       11. integrity: self_protect, hook_persistence, recovery
       12. ui: status panel + hotkey

    Each module returns an object with `.install()`. We iterate the
    list, pcall each install, and collect errors for the status
    readout. A module that fails to install just logs an error; the
    rest keep loading.
================================================================ ]]

return function(require)

    local env     = require("core/env")
    local log     = require("core/log")
    local cfg     = require("core/config")
    local state   = require("core/state")
    local caps    = require("core/executor_caps")
    local version = require("core/version")

    local L = log.scoped("init")

    local M = {}
    M._started = false
    M._stopped = false
    M._install_errors = {}

    -- Module load list. Order matters.
    local MODULES = {
        -- hooks first (they self-install on require; we also call
        -- their install() for idempotence)
        "hooks/namecall", "hooks/newindex", "hooks/index",
        "hooks/metatable", "hooks/hookfunction",
        "hooks/fire_handlers", "hooks/recv_handlers",
        "hooks/restore",

        -- masks
        "masks/walkspeed", "masks/jumppower", "masks/hipheight",
        "masks/position", "masks/animation",
        "masks/character_state", "masks/gravity",

        -- scrubbers
        "scrubbers/kick", "scrubbers/teleport",
        "scrubbers/shadowban", "scrubbers/ragdoll",
        "scrubbers/updateprofile", "scrubbers/coregui_warning",

        -- decoys
        "decoys/globals", "decoys/position",
        "decoys/velocity", "decoys/input",

        -- spoof
        "spoof/player_telemetry", "spoof/server_state",
        "spoof/fingerprint_cleaner", "spoof/script_signature",

        -- silencers
        "silencers/kick_block", "silencers/teleport_block",
        "silencers/gui_warning_block", "silencers/sound_block",
        "silencers/screen_flash_block",

        -- grg-specific
        "grg/shadowban_handler", "grg/ragdoll_handler",
        "grg/profile_spoof", "grg/raptor_alibi",
        "grg/placeid_gate", "grg/cmdr_silencer",

        -- sandbox
        "sandbox/env_shuffle", "sandbox/traceback_rewrite",
        "sandbox/getfenv_mask", "sandbox/debug_info_mask",

        -- netgate
        "netgate/send_filter", "netgate/recv_scrubber",
        "netgate/rate_limiter", "netgate/jitter",

        -- timing (utilities mainly; install if they have one)
        "timing/jitter", "timing/rate_limit", "timing/tick_smoother",

        -- integrity
        "integrity/self_protect",
        "integrity/hook_persistence",
        "integrity/recovery",

        -- ui
        "ui/status_panel", "ui/toggle",
    }

    local MODS = {}

    function M:start()
        if self._started then
            L:warn("start() already called")
            return self
        end

        -- Print banner to stdout
        print(version.BANNER)
        L:info("caps: %s", caps.summary())

        -- Place gate
        if env.IsTargetGame then
            L:info("target game detected: %s (%d)", env.GameName, env.PlaceId)
        else
            L:warn("not in target game (place=%d); bypass will load anyway", env.PlaceId)
        end

        state:flag("initialized", true)

        -- Require and install each module
        for _, path in ipairs(MODULES) do
            local ok, mod = pcall(require, path)
            if not ok then
                L:error("require '%s' failed: %s", path, tostring(mod))
                table.insert(self._install_errors, {path = path, phase = "require", err = mod})
            else
                MODS[path] = mod
                if type(mod) == "table" and type(mod.install) == "function" then
                    local ok2, err = pcall(function() mod.install(mod) end)
                    -- support both :install() and .install() style
                    if not ok2 then
                        -- try calling as dot-style if colon-style broke
                        local ok3, err3 = pcall(mod.install)
                        if not ok3 then
                            L:error("install '%s' failed: %s", path, tostring(err))
                            table.insert(self._install_errors, {path = path, phase = "install", err = err})
                        end
                    end
                end
            end
        end

        state:flag("hooks_installed", true)
        state:flag("masking_active", true)
        state:flag("scrubbing_active", true)
        state:flag("integrity_running", true)
        state:flag("ac_bypass_active", true)
        state:flag("in_target_game", env.IsTargetGame)

        self._started = true
        L:info("start complete (%d modules, %d errors)",
            #MODULES, #self._install_errors)
        return self
    end

    function M:stop()
        if not self._started or self._stopped then return self end
        state:flag("kill_switched", true)
        state:flag("ac_bypass_active", false)
        L:warn("stop() called; modules will continue to exist but flags say inactive")
        self._stopped = true
        return self
    end

    function M:status()
        local out = {
            version        = version.STRING,
            started        = self._started,
            stopped        = self._stopped,
            install_errors = self._install_errors,
            counters       = state:counter_snapshot(),
            flags          = {},
            last_seen      = {},
            place_id       = env.PlaceId,
            in_target      = env.IsTargetGame,
            executor       = env.ExecutorName,
            caps_tier      = caps.tier,
            uptime_s       = env.uptime(),
        }
        for k, v in pairs(state.Flags)   do out.flags[k]     = v end
        for k, v in pairs(state.LastSeen) do out.last_seen[k] = v end
        return out
    end

    function M:module(path) return MODS[path] end

    function M:modules() return MODS end

    function M:counter(key) return state:counter(key) end

    function M:find(search)
        local hits = {}
        for path in pairs(MODS) do
            if string.find(path, search, 1, true) then
                table.insert(hits, path)
            end
        end
        table.sort(hits)
        return hits
    end

    function M:reset_counters()
        state:reset_counters()
    end

    function M:dump_logs()
        return log.dump_now()
    end

    return M

end

end
__MODULES__['integrity/hook_persistence'] = function(require)
--[[ ================================================================
    src/integrity/hook_persistence.lua
    -----------------------------------
    Watchdog that polls the game metatable at a configurable rate and
    detects when our __namecall / __newindex / __index wrappers have
    been replaced by someone else (typically the AC running its own
    hookmetamethod after ours, or a competing cheat).

    On loss:
        * log a warning
        * fire state's "HookLost" signal with the kind
        * call hooks/restore.on_hook_lost(kind) which re-installs
        * bump state.Counters.hook_losses_detected

    We also cache a reference to the raw metatable itself so a full
    setrawmetatable() swap can be noticed (some exotic AC variants
    replace the table outright rather than editing fields).

    Polling loop uses RunService.Heartbeat + a time-accumulator;
    this is cheap (one table lookup + one rawget per poll).

    Public:
        M.install()
        M.check_now()        -- manual poll, returns ok, detail
        M.poll_count()
        M.loss_count()
        M.last_status()
================================================================ ]]

return function(require)

    local env   = require("core/env")
    local log   = require("core/log")
    local cfg   = require("core/config")
    local state = require("core/state")

    local namecall = require("hooks/namecall")
    local newindex = require("hooks/newindex")
    local index    = require("hooks/index")
    local mt       = require("hooks/metatable")
    local restore  = require("hooks/restore")

    local M = {}
    local L = log.scoped("integrity/hook_persistence")

    ----------------------------------------------------------------
    -- 1. bookkeeping
    ----------------------------------------------------------------

    local STARTED        = false
    local POLL_COUNT     = 0
    local LOSS_COUNT     = 0
    local LAST_STATUS    = {
        namecall = true,
        newindex = true,
        index    = true,
        mt_same  = true,
        at       = 0,
    }

    local BASELINE_MT    = nil     -- the raw metatable we saw at init
    local WRAPPERS       = {
        namecall = nil,
        newindex = nil,
        index    = nil,
    }

    local CONN           = nil

    ----------------------------------------------------------------
    -- 2. wrapper capture
    ----------------------------------------------------------------

    --[[
        Each hooks/<x> module's `install()` stores its wrapper via
        hookmetamethod and keeps the original. The metatable's field
        is the wrapper. The cleanest way to know "is our hook still
        live" is to read the field and compare against the wrapper
        that's CURRENTLY recorded on the metatable when we first
        snapshot. In practice we just compare "is the metamethod
        still non-nil and not the original captured by namecall.lua".

        mt.namecall_is_ours(wrapper) is the official API; it returns
        (true, cur) or (false, cur). We pass the wrapper value
        pulled straight off the metatable at the time of install.
    ]]
    local function grab_current_wrappers()
        local mt_tab = mt.mt()
        if not mt_tab then return end
        WRAPPERS.namecall = rawget(mt_tab, "__namecall")
        WRAPPERS.newindex = rawget(mt_tab, "__newindex")
        WRAPPERS.index    = rawget(mt_tab, "__index")
    end

    ----------------------------------------------------------------
    -- 3. core check
    ----------------------------------------------------------------

    local function mt_was_swapped()
        local cur = mt.mt()
        if not cur then return false end
        if BASELINE_MT == nil then return false end
        return cur ~= BASELINE_MT
    end

    local function check_one(kind)
        local mt_tab = mt.mt()
        if not mt_tab then return nil end
        local cur = rawget(mt_tab, "__" .. kind)
        local expected = WRAPPERS[kind]
        if cur == nil then return false end
        if expected == nil then
            -- We never saw a wrapper; treat as OK to avoid spurious restore.
            return true
        end
        return cur == expected
    end

    local function handle_loss(kind)
        LOSS_COUNT = LOSS_COUNT + 1
        state:bump("hook_losses_detected")
        L:warn("hook lost: %s (loss_count=%d)", kind, LOSS_COUNT)
        state:emit("HookLost", kind)

        local action = cfg:get("integrity.hook_persistence.on_lost_action",
            "restore")
        if action == "restore" then
            local ok = restore.on_hook_lost(kind)
            if ok then
                -- Re-grab wrappers since install() produced new ones.
                grab_current_wrappers()
            end
        end
    end

    function M.check_now()
        POLL_COUNT = POLL_COUNT + 1
        local out = {
            namecall = true,
            newindex = true,
            index    = true,
            mt_same  = true,
            at       = tick(),
        }

        if mt_was_swapped() then
            out.mt_same = false
            L:warn("rawmetatable identity changed; re-caching")
            mt.cache()
            BASELINE_MT = mt.mt()
            handle_loss("metatable")
            LAST_STATUS = out
            return false, out
        end

        local nc = check_one("namecall")
        if nc == false then
            out.namecall = false
            handle_loss("namecall")
        end

        local ni = check_one("newindex")
        if ni == false then
            out.newindex = false
            handle_loss("newindex")
        end

        local ix = check_one("index")
        if ix == false then
            out.index = false
            handle_loss("index")
        end

        LAST_STATUS = out
        return out.namecall and out.newindex and out.index, out
    end

    ----------------------------------------------------------------
    -- 4. polling loop
    ----------------------------------------------------------------

    local function start_loop()
        if not env.RunService then
            L:warn("RunService missing; can't poll")
            return
        end

        local acc = 0
        CONN = env.RunService.Heartbeat:Connect(function(dt)
            acc = acc + dt
            local hz = cfg:get("integrity.hook_persistence.poll_hz", 1)
            if hz <= 0 then return end
            local period = 1 / hz
            if acc < period then return end
            acc = 0
            local ok, err = pcall(M.check_now)
            if not ok then
                L:warn("check_now crashed: %s", tostring(err))
            end
        end)
    end

    local function stop_loop()
        if CONN then
            pcall(function() CONN:Disconnect() end)
            CONN = nil
        end
    end

    ----------------------------------------------------------------
    -- 5. public API
    ----------------------------------------------------------------

    function M.install()
        if not cfg:get("integrity.hook_persistence.enabled", true) then
            L:info("disabled via config")
            return
        end
        if STARTED then return end

        BASELINE_MT = mt.mt()
        grab_current_wrappers()

        start_loop()
        STARTED = true
        state:flag("integrity_running", true)
        L:info("hook_persistence watchdog started (hz=%.1f)",
            cfg:get("integrity.hook_persistence.poll_hz", 1))
    end

    function M.stop()
        stop_loop()
        STARTED = false
        state:flag("integrity_running", false)
    end

    function M.poll_count()  return POLL_COUNT end
    function M.loss_count()  return LOSS_COUNT end
    function M.last_status() return LAST_STATUS end
    function M.is_running()  return STARTED end

    function M.rearm()
        -- Called from integrity/recovery after a full restore to reset
        -- the cached references; a fresh install produces new wrappers.
        BASELINE_MT = mt.mt()
        grab_current_wrappers()
        LAST_STATUS.at = tick()
    end

    return M

end

end
__MODULES__['integrity/recovery'] = function(require)
--[[ ================================================================
    src/integrity/recovery.lua
    ---------------------------
    Orchestrates a full panic recovery.

    Triggered by:
        (a) N consecutive hook losses within a rolling window; the
            threshold is cfg:get("integrity.recovery.max_consecutive_fails"),
        (b) manual call to M.recover_now(reason).

    The recovery sequence is:
        1. bump state.Counters.panics, set last_panic_reason.
        2. hooks/restore.restore_all().
        3. Notify hook_persistence to rearm (reset baseline refs).
        4. Fire state:emit("PanicRaised", reason).

    We intentionally do NOT re-run the full module tree here - that's
    the boot/loader's job via its own "reinit_masks" hook. We do
    signal PanicRaised so subscribers can take their own action
    (masks re-register themselves on signal, etc.).
================================================================ ]]

return function(require)

    local env   = require("core/env")
    local log   = require("core/log")
    local cfg   = require("core/config")
    local state = require("core/state")

    local restore          = require("hooks/restore")
    local hook_persistence = require("integrity/hook_persistence")

    local M = {}
    local L = log.scoped("integrity/recovery")

    local PANIC_COUNT       = 0
    local CONSECUTIVE_FAILS = 0
    local LAST_PANIC_AT     = 0
    local COOLDOWN_SECS     = 1.0   -- minimum seconds between panics
    local LISTENER_ID       = nil

    local function now()
        return tick()
    end

    local function should_panic()
        local cap = cfg:get("integrity.recovery.max_consecutive_fails", 3)
        return CONSECUTIVE_FAILS >= cap
    end

    ----------------------------------------------------------------
    -- main entry
    ----------------------------------------------------------------

    function M.recover_now(reason)
        if not cfg:get("integrity.recovery.enabled", true) then
            L:debug("recovery disabled; ignoring '%s'", tostring(reason))
            return false, "disabled"
        end

        local t = now()
        if (t - LAST_PANIC_AT) < COOLDOWN_SECS then
            L:debug("panic cooldown; ignoring '%s'", tostring(reason))
            return false, "cooldown"
        end
        LAST_PANIC_AT = t

        PANIC_COUNT = PANIC_COUNT + 1
        state:bump("panics")
        state:set_last("last_panic_reason", reason or "manual")
        state:set_last("last_panic_at", os.time())
        state:flag("panic_active", true)
        L:warn("PANIC #%d: reason=%s", PANIC_COUNT, tostring(reason))

        local ok, results = restore.restore_all()
        if ok then
            L:info("panic resolved via restore_all")
            CONSECUTIVE_FAILS = 0
        else
            L:error("panic unresolved: restore_all failed")
        end

        pcall(hook_persistence.rearm)

        state:emit("PanicRaised", reason or "manual")
        state:flag("panic_active", false)

        return ok, results
    end

    ----------------------------------------------------------------
    -- auto-trip: subscribe to HookLost signal
    ----------------------------------------------------------------

    local function on_hook_lost(kind)
        CONSECUTIVE_FAILS = CONSECUTIVE_FAILS + 1
        L:debug("consecutive fails: %d (kind=%s)",
            CONSECUTIVE_FAILS, tostring(kind))
        if should_panic() then
            local c = CONSECUTIVE_FAILS
            CONSECUTIVE_FAILS = 0
            M.recover_now(string.format("hook_lost_threshold:%s*%d",
                tostring(kind), c))
        end
    end

    local function on_hook_restored()
        CONSECUTIVE_FAILS = 0
    end

    ----------------------------------------------------------------
    -- install
    ----------------------------------------------------------------

    function M.install()
        if not cfg:get("integrity.recovery.enabled", true) then
            L:info("disabled via config")
            return
        end

        if state.Signals and state.Signals.HookLost then
            LISTENER_ID = state.Signals.HookLost:connect(on_hook_lost)
        end
        if state.Signals and state.Signals.HookRestored then
            state.Signals.HookRestored:connect(on_hook_restored)
        end

        L:info("recovery armed (threshold=%d)",
            cfg:get("integrity.recovery.max_consecutive_fails", 3))
    end

    function M.panic_count()        return PANIC_COUNT end
    function M.consecutive_fails()  return CONSECUTIVE_FAILS end
    function M.reset_counters()
        CONSECUTIVE_FAILS = 0
    end

    return M

end

end
__MODULES__['integrity/self_protect'] = function(require)
--[[ ================================================================
    src/integrity/self_protect.lua
    -------------------------------
    Keep our own ScreenGui / helper instances invisible to any anti-
    cheat probe that enumerates CoreGui or PlayerGui.

    Strategy:

      1. On install, pick a randomised benign name from a pool
         ("ReplicatedFirstLoader", "ChatMain", "BubbleChat", ...) and
         make it available to ui/status_panel via M.benign_screen_name().

      2. Register namecall handlers for GetChildren, GetDescendants,
         FindFirstChild, FindFirstChildOfClass, FindFirstChildWhichIsA
         against CoreGui / PlayerGui. We use ctx.after to filter out
         any Instance whose Name matches our prefixes.

      3. Optionally reparent our ScreenGui to gethui() (executor
         protected CoreGui) so it isn't enumerable at all on tier 3.

      4. Protect the loadstring'd script object: hooks `__index` so
         that reading `script.Source` or calling `script:GetFullName()`
         from a non-us thread returns a convincing decoy value.

    The module exports hide_instance / unhide_instance so other
    modules (e.g. ui/status_panel) can register individual GUIs and
    side-car folders without needing to know the prefix scheme.
================================================================ ]]

return function(require)

    local env   = require("core/env")
    local log   = require("core/log")
    local cfg   = require("core/config")
    local state = require("core/state")

    local namecall = require("hooks/namecall")
    local index    = require("hooks/index")

    local M = {}
    local L = log.scoped("integrity/self_protect")

    ----------------------------------------------------------------
    -- 1. name pools and prefix matching
    ----------------------------------------------------------------

    local BENIGN_POOL = {
        "ReplicatedFirstLoader",
        "ChatMain",
        "BubbleChat",
        "TopbarPlus",
        "PlayerListMaster",
        "CoreGuiRoot",
        "HealthbarGui",
        "NotificationGui",
        "TouchGui",
        "RbxCharacterSounds",
    }

    local PREFIXES = {
        "GRG_",
        "__grg_",
        "GRG_AC_",
    }

    local SUFFIX_PATTERNS = {
        "__grg$",
        "_GRG_AC$",
    }

    local HIDDEN = setmetatable({}, { __mode = "k" })   -- weak keys
    local BENIGN_NAME = nil
    local RNG = Random.new and Random.new(tick() * 1e6) or nil

    local function rand_int(lo, hi)
        if RNG then return RNG:NextInteger(lo, hi) end
        return math.random(lo, hi)
    end

    local function pick_benign_name()
        local base = BENIGN_POOL[rand_int(1, #BENIGN_POOL)]
        return base
    end

    local function name_matches_ours(name)
        if type(name) ~= "string" then return false end
        for _, pre in ipairs(PREFIXES) do
            if string.sub(name, 1, #pre) == pre then return true end
        end
        for _, pat in ipairs(SUFFIX_PATTERNS) do
            if string.find(name, pat) then return true end
        end
        return false
    end

    local function inst_is_hidden(inst)
        if HIDDEN[inst] then return true end
        local ok, n = pcall(function() return inst.Name end)
        if ok and name_matches_ours(n) then return true end
        return false
    end

    ----------------------------------------------------------------
    -- 2. public registration
    ----------------------------------------------------------------

    function M.hide_instance(inst)
        if type(inst) ~= "userdata" and type(inst) ~= "table" then return end
        HIDDEN[inst] = true
    end

    function M.unhide_instance(inst)
        HIDDEN[inst] = nil
    end

    function M.is_hidden(inst)
        return inst_is_hidden(inst)
    end

    function M.benign_screen_name()
        if not BENIGN_NAME then
            BENIGN_NAME = pick_benign_name()
        end
        return BENIGN_NAME
    end

    ----------------------------------------------------------------
    -- 3. scan-filtering helpers
    ----------------------------------------------------------------

    local function is_relevant_container(inst)
        if type(inst) ~= "userdata" and type(inst) ~= "table" then return false end
        if inst == env.CoreGui then return true end
        if inst == env.PlayerGui then return true end
        -- any ScreenGui that's one of ours
        if inst_is_hidden(inst) then return true end
        local ok, cls = pcall(function() return inst.ClassName end)
        if ok and cls == "PlayerGui" then return true end
        return false
    end

    local function filter_list(list)
        if type(list) ~= "table" then return list end
        local out = {}
        for i = 1, #list do
            local v = list[i]
            if not inst_is_hidden(v) then
                out[#out + 1] = v
            end
        end
        return out
    end

    ----------------------------------------------------------------
    -- 4. namecall handlers
    ----------------------------------------------------------------

    local function register_scan_filters()
        namecall.register({
            name     = "self_protect.GetChildren",
            priority = 15,
            method   = "GetChildren",
            handler  = function(ctx)
                if not is_relevant_container(ctx.self) then return end
                ctx.after = function(ret)
                    local arr = ret[1]
                    if type(arr) ~= "table" then return ret end
                    local filtered = filter_list(arr)
                    return { n = 1, [1] = filtered }
                end
            end,
        })

        namecall.register({
            name     = "self_protect.GetDescendants",
            priority = 15,
            method   = "GetDescendants",
            handler  = function(ctx)
                if not is_relevant_container(ctx.self) then return end
                ctx.after = function(ret)
                    local arr = ret[1]
                    if type(arr) ~= "table" then return ret end
                    return { n = 1, [1] = filter_list(arr) }
                end
            end,
        })

        namecall.register({
            name     = "self_protect.FindFirstChild",
            priority = 15,
            method   = "FindFirstChild",
            handler  = function(ctx)
                if not is_relevant_container(ctx.self) then return end
                local needle = ctx.args[1]
                if type(needle) == "string" and name_matches_ours(needle) then
                    ctx.short_circuit = true
                    ctx.spoof = { n = 1, [1] = nil }
                    return
                end
                ctx.after = function(ret)
                    local v = ret[1]
                    if v and inst_is_hidden(v) then
                        return { n = 1, [1] = nil }
                    end
                    return ret
                end
            end,
        })

        namecall.register({
            name     = "self_protect.FindFirstChildOfClass",
            priority = 15,
            method   = "FindFirstChildOfClass",
            handler  = function(ctx)
                if not is_relevant_container(ctx.self) then return end
                ctx.after = function(ret)
                    local v = ret[1]
                    if v and inst_is_hidden(v) then
                        return { n = 1, [1] = nil }
                    end
                    return ret
                end
            end,
        })

        namecall.register({
            name     = "self_protect.FindFirstChildWhichIsA",
            priority = 15,
            method   = "FindFirstChildWhichIsA",
            handler  = function(ctx)
                if not is_relevant_container(ctx.self) then return end
                ctx.after = function(ret)
                    local v = ret[1]
                    if v and inst_is_hidden(v) then
                        return { n = 1, [1] = nil }
                    end
                    return ret
                end
            end,
        })
    end

    ----------------------------------------------------------------
    -- 5. script.Source / GetFullName protection
    ----------------------------------------------------------------

    local FAKE_SOURCE =
        "-- CoreGui.RobloxGui.Modules.Common.MovementController\n" ..
        "-- Generated by Roblox client " .. tostring(env.SessionStartTime) .. "\n" ..
        "return function() end\n"

    local FAKE_FULLNAME =
        "CoreGui.RobloxGui.Modules.Common.MovementController"

    local function is_our_script(obj)
        if type(obj) ~= "userdata" then return false end
        -- Scripts that share our embedded marker.
        local ok, n = pcall(function() return obj.Name end)
        if not ok then return false end
        if type(n) ~= "string" then return false end
        return name_matches_ours(n) or n == "LocalScript" and inst_is_hidden(obj)
    end

    local function register_script_index_guard()
        index.register({
            name     = "self_protect.script_source",
            priority = 10,
            property = "Source",
            handler  = function(ctx)
                if not is_our_script(ctx.self) then return end
                if env.ckcaller and env.ckcaller() then return end
                ctx.spoof_value = FAKE_SOURCE
                ctx.spoofed = true
            end,
        })

        -- GetFullName is technically a namecall, guard that too.
        namecall.register({
            name     = "self_protect.GetFullName",
            priority = 15,
            method   = "GetFullName",
            handler  = function(ctx)
                if not is_our_script(ctx.self) and not inst_is_hidden(ctx.self) then
                    return
                end
                if env.ckcaller and env.ckcaller() then return end
                ctx.short_circuit = true
                ctx.spoof = { n = 1, [1] = FAKE_FULLNAME }
            end,
        })
    end

    ----------------------------------------------------------------
    -- 6. install
    ----------------------------------------------------------------

    local INSTALLED = false

    function M.install()
        if not cfg:get("integrity.self_protect.enabled", true) then
            L:info("disabled via config")
            return
        end
        if INSTALLED then return end

        BENIGN_NAME = pick_benign_name()

        if cfg:get("integrity.self_protect.hide_from_getchildren", true) then
            register_scan_filters()
        end

        register_script_index_guard()

        INSTALLED = true
        L:info("self_protect active (benign=%s, gethui=%s)",
            BENIGN_NAME, tostring(env.Caps.gethui and true or false))
    end

    function M.gethui_or_coregui()
        local ghu = rawget(getfenv(0), "gethui") or _G.gethui
        if type(ghu) == "function" then
            local ok, p = pcall(ghu)
            if ok and p then return p end
        end
        return env.CoreGui
    end

    return M

end

end
__MODULES__['lib/color'] = function(require)
--[[ ================================================================
    src/lib/color.lua
    ------------------
    UI palette for the status panel / notifications. Plain Color3
    triples so we don't have to pull Color3.fromRGB in every UI
    module. Exposed both as raw RGB byte triples and as the Color3
    value (lazy-constructed so this file is safe to require in
    environments where Color3 isn't available).
================================================================ ]]

return function(require)

    local M = {}

    local function rgb(r, g, b)
        local entry = { r = r, g = g, b = b }
        local ok, c3 = pcall(function()
            return Color3.fromRGB(r, g, b)
        end)
        if ok then entry.c3 = c3 end
        return entry
    end

    M.BG          = rgb(18,  18,  22)
    M.BG_ALT      = rgb(28,  28,  34)
    M.BG_HOVER    = rgb(38,  38,  46)
    M.BG_ACTIVE   = rgb(48,  48,  58)
    M.FG          = rgb(235, 235, 240)
    M.FG_MUTED    = rgb(170, 170, 180)
    M.FG_DIM      = rgb(120, 120, 128)
    M.BORDER      = rgb(58,  58,  68)
    M.ACCENT      = rgb(130, 200, 255)
    M.ACCENT_DIM  = rgb( 80, 130, 180)
    M.DANGER      = rgb(230,  90,  90)
    M.DANGER_DIM  = rgb(150,  60,  60)
    M.WARN        = rgb(240, 200,  80)
    M.WARN_DIM    = rgb(170, 140,  40)
    M.SUCCESS     = rgb(110, 220, 150)
    M.SUCCESS_DIM = rgb( 70, 150, 100)
    M.INFO        = rgb(130, 180, 230)
    M.TRACE       = rgb(120, 120, 140)

    function M.as_c3(entry)
        if type(entry) ~= "table" then return entry end
        if entry.c3 then return entry.c3 end
        local ok, c = pcall(function()
            return Color3.fromRGB(entry.r, entry.g, entry.b)
        end)
        if ok then
            entry.c3 = c
            return c
        end
        return nil
    end

    function M.hex(entry)
        if type(entry) ~= "table" then return "#000000" end
        return string.format("#%02X%02X%02X", entry.r, entry.g, entry.b)
    end

    return M

end

end
__MODULES__['lib/debounce'] = function(require)
--[[ ================================================================
    src/lib/debounce.lua
    ---------------------
    Debounce helpers. We use three flavors across the bypass:

        M.create(delay)  - simple "not again until delay seconds pass"
        M.leading(delay) - fire immediately, ignore follow-ups inside
                           the window
        M.trailing(delay)- defer the call; if new calls arrive, bump
                           the timer; eventually fire with the last
                           args seen

    All three are callable tables (__call) so modules can treat them
    like plain functions.

        local fire = debounce.leading(0.5, function(reason)
            L:warn("kick attempted: %s", reason)
        end)
        fire("exploit detected")

    They return (bool, anything?) where the bool says "the wrapped
    fn was called this time" so callers can branch.
================================================================ ]]

return function(require)

    local env = require("core/env")

    local M = {}

    local function now()
        return tick()
    end

    -- ----------------------------------------------------------------
    -- Simple gate: first call goes through, subsequent within delay
    -- are ignored. Returns a table with :call / reset / etc.
    -- ----------------------------------------------------------------

    function M.create(delay)
        delay = tonumber(delay) or 0.25
        local self = {
            delay = delay,
            last  = -math.huge,
            count = 0,
        }

        function self.call(...)
            local t = now()
            if (t - self.last) < self.delay then
                self.count = self.count + 1
                return false
            end
            self.last = t
            return true
        end

        function self.reset()
            self.last  = -math.huge
            self.count = 0
        end

        function self.set_delay(d)
            self.delay = tonumber(d) or self.delay
        end

        setmetatable(self, { __call = function(_, ...) return self.call(...) end })
        return self
    end

    -- ----------------------------------------------------------------
    -- Leading-edge: fn runs right away, subsequent calls in window
    -- are suppressed.
    -- ----------------------------------------------------------------

    function M.leading(delay, fn)
        delay = tonumber(delay) or 0.25
        local self = {
            delay = delay,
            last  = -math.huge,
            count = 0,
        }

        function self.call(...)
            local t = now()
            if (t - self.last) < self.delay then
                self.count = self.count + 1
                return false
            end
            self.last = t
            if type(fn) == "function" then
                local ok, err = pcall(fn, ...)
                if not ok then return true, err end
            end
            return true
        end

        function self.reset()
            self.last = -math.huge
            self.count = 0
        end

        setmetatable(self, { __call = function(_, ...) return self.call(...) end })
        return self
    end

    -- ----------------------------------------------------------------
    -- Trailing-edge: each call bumps a deadline; when the deadline
    -- passes without another call, fn fires with the last args.
    --
    -- We don't spawn a coroutine ourselves -- callers must poll via
    -- :tick() from RunService.Heartbeat, or call :flush() to force.
    -- This keeps us usable from the core layer which should not be
    -- spinning tasks.
    -- ----------------------------------------------------------------

    function M.trailing(delay, fn)
        delay = tonumber(delay) or 0.25
        local self = {
            delay   = delay,
            pending = false,
            args    = nil,
            argn    = 0,
            deadline = -math.huge,
        }

        function self.call(...)
            self.pending = true
            self.args    = table.pack(...)
            self.argn    = select("#", ...)
            self.deadline = now() + self.delay
            return false
        end

        function self.tick()
            if not self.pending then return false end
            if now() < self.deadline then return false end
            self.pending = false
            if type(fn) == "function" and self.args then
                local a = self.args
                local ok, err = pcall(fn, table.unpack(a, 1, self.argn))
                if not ok then return true, err end
            end
            return true
        end

        function self.flush()
            if not self.pending then return false end
            self.pending = false
            if type(fn) == "function" and self.args then
                local a = self.args
                local ok, err = pcall(fn, table.unpack(a, 1, self.argn))
                if not ok then return true, err end
            end
            return true
        end

        function self.cancel()
            self.pending = false
            self.args = nil
        end

        setmetatable(self, { __call = function(_, ...) return self.call(...) end })
        return self
    end

    return M

end

end
__MODULES__['lib/grg_data'] = function(require)
--[[ ================================================================
    src/lib/grg_data.lua
    ---------------------
    Hardcoded intel dictionary for the Generic Roleplay Game target
    and other common roleplay / racing Roblox titles we see in the
    wild. Every other module reads from here via:

        local data = require("lib/grg_data")
        if data.is_remote_known("ShadowBanEvent") then ... end

    The lists are intentionally broad: the bypass is designed to
    degrade gracefully on related titles (Greenville, Brookhaven,
    Southwest Florida, etc.) where the AC author copy-pasted large
    chunks of the same remote/event/kick-reason vocabulary. If a
    name isn't here the module just falls through -- nothing panics.

    None of these tables are mutated at runtime by this module. The
    pattern_set helper wraps them when a consumer needs to extend a
    set live from the UI (e.g. blocking additional kick reasons).
================================================================ ]]

return function(require)

    local env = require("core/env")
    local log = require("core/log")

    local M = {}
    local L = log.scoped("lib/grg_data")

    -- ----------------------------------------------------------------
    -- 1. remote event / function names
    -- ----------------------------------------------------------------
    --
    -- These are the names we expect to find under ReplicatedStorage
    -- or a Remotes folder in the target title and its cousins. The
    -- send_filter / recv_scrubber uses this to bucket traffic and
    -- to decide what gets a trace-level log vs a debug-level drop.

    M.REMOTE_NAMES = {
        "ShadowBanEvent",
        "ShadowBanRemote",
        "RagdollEvent",
        "RagdollRemote",
        "UpdateProfile",
        "UpdatePlayerProfile",
        "UpdateStats",
        "ChatEvent",
        "ChatRemote",
        "ChatCommand",
        "CmdrEvent",
        "CmdrFunction",
        "CommandEvent",
        "RaceEvent",
        "RaceStart",
        "RaceEnd",
        "MoneyEvent",
        "MoneyRemote",
        "GiveMoney",
        "DropMoney",
        "KickRemote",
        "KickEvent",
        "BanRemote",
        "BanEvent",
        "ReportRemote",
        "ReportEvent",
        "AnticheatRemote",
        "AnticheatEvent",
        "AnticheatPing",
        "AnticheatReply",
        "ServerSideAnticheat",
        "ClientCheck",
        "ClientHeartbeat",
        "Heartbeat",
        "PingEvent",
        "TeleportRemote",
        "TeleportEvent",
        "BuyVehicle",
        "SellVehicle",
        "SpawnVehicle",
        "DespawnVehicle",
        "EnterVehicle",
        "ExitVehicle",
        "FuelEvent",
        "RepairEvent",
        "DamageEvent",
        "HealEvent",
        "KillEvent",
        "DeathEvent",
        "RespawnEvent",
        "InventoryEvent",
        "PurchaseEvent",
        "TradeEvent",
        "TradeRemote",
        "JailEvent",
        "ArrestEvent",
        "HandcuffEvent",
        "PoliceRemote",
        "CriminalRemote",
        "JobEvent",
        "PromotionEvent",
        "TeamEvent",
    }

    local REMOTE_SET = {}
    for _, n in ipairs(M.REMOTE_NAMES) do REMOTE_SET[n] = true end

    function M.is_remote_known(name)
        if type(name) ~= "string" then return false end
        return REMOTE_SET[name] == true
    end

    -- ----------------------------------------------------------------
    -- 2. kick reasons
    -- ----------------------------------------------------------------

    M.KICK_REASONS_WHITELIST = {}

    local KICK_WHITELIST_SET = {}
    for _, r in ipairs(M.KICK_REASONS_WHITELIST) do
        KICK_WHITELIST_SET[string.lower(r)] = true
    end

    function M.is_kick_reason_whitelisted(reason)
        if type(reason) ~= "string" then return false end
        return KICK_WHITELIST_SET[string.lower(reason)] == true
    end

    M.KICK_REASONS_BAD = {
        "exploit",
        "exploiting",
        "exploiter",
        "cheating",
        "cheater",
        "cheat detected",
        "modifying",
        "modified client",
        "speed hack",
        "speedhack",
        "speed-hack",
        "flying",
        "flyhack",
        "fly hack",
        "fly",
        "teleport",
        "teleporting",
        "teleport hack",
        "unauthorized",
        "unauthorized script",
        "unauthorized modification",
        "unauthorized action",
        "injection",
        "injected",
        "lua executor",
        "executor detected",
        "anticheat",
        "anti-cheat",
        "anti cheat",
        "banned",
        "you have been banned",
        "kicked by server",
        "invalid client",
        "suspicious behavior",
        "suspicious activity",
        "illegal action",
        "illegal movement",
        "unexpected client state",
        "humanoid values modified",
        "walkspeed modified",
        "jumppower modified",
        "invalid profile",
        "profile mismatch",
        "stat mismatch",
        "position mismatch",
        "velocity mismatch",
        "physics mismatch",
        "tampering",
        "tamper",
        "client tampering",
        "hacks",
        "hacker",
        "hacking",
    }

    local KICK_BAD_LC = {}
    for _, r in ipairs(M.KICK_REASONS_BAD) do
        table.insert(KICK_BAD_LC, string.lower(r))
    end

    function M.is_kick_reason_bad(reason)
        if type(reason) ~= "string" then return false end
        local r = string.lower(reason)
        if KICK_WHITELIST_SET[r] then return false end
        for _, needle in ipairs(KICK_BAD_LC) do
            if string.find(r, needle, 1, true) then return true end
        end
        return false
    end

    -- ----------------------------------------------------------------
    -- 3. benign script names (for debug_info_mask fake-source pool)
    -- ----------------------------------------------------------------

    M.GAME_SCRIPTS_BENIGN = {
        "PlayerModule",
        "MovementController",
        "CameraModule",
        "ControlModule",
        "KeyboardModule",
        "MouseModule",
        "TouchModule",
        "GamepadModule",
        "ClickToMove",
        "DefaultChatSystemChatEvents",
        "ChatChannel",
        "ChatMain",
        "Backpack",
        "HealthDisplay",
        "FollowCamera",
        "PopperCam",
        "BaseOcclusion",
        "CameraUI",
        "TransparencyController",
        "PlayerController",
        "AnimateScript",
        "Animate",
        "Sound",
        "RobloxGui",
        "CoreGui",
        "TopbarPlus",
        "UIController",
        "SettingsController",
        "NotificationHandler",
        "LoadingScreenController",
    }

    local BENIGN_SET = {}
    for _, s in ipairs(M.GAME_SCRIPTS_BENIGN) do BENIGN_SET[s] = true end

    function M.is_script_benign(name)
        if type(name) ~= "string" then return false end
        return BENIGN_SET[name] == true
    end

    -- ----------------------------------------------------------------
    -- 4. animation blocklist
    -- ----------------------------------------------------------------
    --
    -- Ids for animations the AC sometimes forces on a detected
    -- cheater (ragdoll, spasm, "caught" pose). We keep the list
    -- empty by default -- titles change these ids constantly and
    -- blanket-blocking causes false-positive visual breakage.

    M.ANIMATION_BLOCKLIST = {}

    local ANIM_SET = {}
    for _, id in ipairs(M.ANIMATION_BLOCKLIST) do ANIM_SET[tostring(id)] = true end

    function M.is_animation_blocked(id)
        if id == nil then return false end
        return ANIM_SET[tostring(id)] == true
    end

    -- ----------------------------------------------------------------
    -- 5. sound ids played on ban / kick toast
    -- ----------------------------------------------------------------

    M.SOUND_ID_BLOCKLIST_BAN_SOUNDS = {
        -- placeholder asset ids for the stock Roblox warning chime
        -- used by many anticheats. Leave as strings so rbxassetid://
        -- comparison is straightforward.
        "rbxassetid://138081500",
        "rbxassetid://131961136",
        "rbxassetid://2865227271",
        "rbxassetid://911882108",
        "rbxassetid://3120909354",
    }

    local BAN_SND_SET = {}
    for _, s in ipairs(M.SOUND_ID_BLOCKLIST_BAN_SOUNDS) do BAN_SND_SET[s] = true end

    function M.is_ban_sound(id)
        if type(id) ~= "string" then return false end
        return BAN_SND_SET[id] == true
    end

    -- ----------------------------------------------------------------
    -- 6. Aero framework service names
    -- ----------------------------------------------------------------
    --
    -- Many roleplay titles are built on Aero Game Framework. The
    -- anticheat typically lives as one of these service names.
    -- We use this to scan the shared module trees for likely AC
    -- hosts without hard-coding a single canonical path.

    M.AERO_SERVICE_NAMES = {
        "AntiCheatService",
        "AntiExploitService",
        "AnticheatService",
        "SecurityService",
        "ValidationService",
        "PlayerService",
        "PlayerDataService",
        "DataService",
        "ProfileService",
        "StatService",
        "InventoryService",
        "EconomyService",
        "MoneyService",
        "VehicleService",
        "CarService",
        "RaceService",
        "ChatService",
        "CommandService",
        "AdminService",
        "ReportService",
        "BanService",
        "TeleportService",
        "JailService",
        "JobService",
    }

    local AERO_SET = {}
    for _, n in ipairs(M.AERO_SERVICE_NAMES) do AERO_SET[n] = true end

    function M.is_aero_service(name)
        if type(name) ~= "string" then return false end
        return AERO_SET[name] == true
    end

    -- ----------------------------------------------------------------
    -- 7. chat commands the game exposes (for command silencer)
    -- ----------------------------------------------------------------

    M.KNOWN_CHAT_COMMANDS = {
        "/kick",
        "/ban",
        "/shadowban",
        "/mute",
        "/unmute",
        "/teleport",
        "/tp",
        "/bring",
        "/freeze",
        "/thaw",
        "/invincible",
        "/god",
        "/heal",
        "/kill",
        "/respawn",
        "/money",
        "/give",
        "/take",
        "/warn",
        "/report",
    }

    local CHAT_CMD_SET = {}
    for _, c in ipairs(M.KNOWN_CHAT_COMMANDS) do CHAT_CMD_SET[string.lower(c)] = true end

    function M.is_chat_command(msg)
        if type(msg) ~= "string" then return false end
        local first = string.match(msg, "^(%S+)")
        if not first then return false end
        return CHAT_CMD_SET[string.lower(first)] == true
    end

    -- ----------------------------------------------------------------
    -- 8. place-id groupings
    -- ----------------------------------------------------------------
    --
    -- Place ids for the canonical target and near-clones. The
    -- placeid_gate module keys off this to decide whether to run
    -- full spoofing or skinny mode.

    M.PLACE_IDS_PRIMARY = {
        4598019433,      -- Generic Roleplay Game
    }

    M.PLACE_IDS_COUSINS = {
        2919875514,      -- hypothetical clone
        3101667897,      -- hypothetical clone
        4872321022,      -- hypothetical clone
    }

    function M.is_primary_place(id)
        if type(id) ~= "number" then return false end
        for _, p in ipairs(M.PLACE_IDS_PRIMARY) do
            if p == id then return true end
        end
        return false
    end

    function M.is_cousin_place(id)
        if type(id) ~= "number" then return false end
        for _, p in ipairs(M.PLACE_IDS_COUSINS) do
            if p == id then return true end
        end
        return false
    end

    -- ----------------------------------------------------------------
    -- 9. convenience dump
    -- ----------------------------------------------------------------

    function M.dump_sizes()
        L:debug("REMOTE_NAMES=%d KICK_BAD=%d BENIGN=%d AERO=%d CHAT=%d",
            #M.REMOTE_NAMES, #M.KICK_REASONS_BAD,
            #M.GAME_SCRIPTS_BENIGN, #M.AERO_SERVICE_NAMES,
            #M.KNOWN_CHAT_COMMANDS)
    end

    return M

end

end
__MODULES__['lib/instance_path'] = function(require)
--[[ ================================================================
    src/lib/instance_path.lua
    --------------------------
    Safe instance-path helpers. The target AC hooks GetFullName and
    sometimes rewrites it to a decoy string; we need a fallback that
    walks .Parent ourselves and works even if GetFullName has been
    poisoned.

    Public API:
        M.path(inst)                -> "Workspace.Karts.Kart1"
        M.name_chain(inst, depth)   -> {"Kart1", "Karts", "Workspace"}
        M.path_matches(inst, pat)   -> bool (string.find on path)
        M.parent_of_class(inst, c)  -> ancestor or nil
        M.has_ancestor(inst, anc)   -> bool
================================================================ ]]

return function(require)

    local env = require("core/env")

    local M = {}

    local function safe_name(inst)
        if type(inst) ~= "userdata" then return tostring(inst) end
        local ok, n = pcall(function() return inst.Name end)
        if ok and type(n) == "string" then return n end
        return "<?>"
    end

    local function safe_parent(inst)
        if type(inst) ~= "userdata" then return nil end
        local ok, p = pcall(function() return inst.Parent end)
        if ok then return p end
        return nil
    end

    local function safe_class(inst)
        if type(inst) ~= "userdata" then return "" end
        local ok, c = pcall(function() return inst.ClassName end)
        if ok and type(c) == "string" then return c end
        return ""
    end

    -- First try the cached original GetFullName, then fall back to
    -- manual walking. We walk at most 24 parents to avoid loops if
    -- an AC engineered a cycle to crash us.
    local MAX_DEPTH = 24

    function M.path(inst)
        if type(inst) ~= "userdata" then return tostring(inst) end
        local gfn = env.OriginalMethods and env.OriginalMethods.GetFullName
        if type(gfn) == "function" then
            local ok, s = pcall(gfn, inst)
            if ok and type(s) == "string" and #s > 0 then return s end
        end

        local parts = {}
        local cursor = inst
        local i = 0
        while cursor ~= nil and i < MAX_DEPTH do
            table.insert(parts, 1, safe_name(cursor))
            cursor = safe_parent(cursor)
            i = i + 1
        end
        if #parts == 0 then return "<orphan>" end
        return table.concat(parts, ".")
    end

    function M.name_chain(inst, max_depth)
        max_depth = tonumber(max_depth) or MAX_DEPTH
        if max_depth > MAX_DEPTH then max_depth = MAX_DEPTH end
        local out = {}
        local cursor = inst
        local i = 0
        while cursor ~= nil and i < max_depth do
            table.insert(out, safe_name(cursor))
            cursor = safe_parent(cursor)
            i = i + 1
        end
        return out
    end

    function M.path_matches(inst, pattern)
        if type(pattern) ~= "string" then return false end
        local p = M.path(inst)
        if type(p) ~= "string" then return false end
        local ok, found = pcall(string.find, p, pattern)
        return ok and found ~= nil
    end

    function M.is_named(inst, name)
        if type(name) ~= "string" then return false end
        return safe_name(inst) == name
    end

    function M.parent_of_class(inst, class_name)
        if type(class_name) ~= "string" then return nil end
        local cursor = safe_parent(inst)
        local i = 0
        while cursor ~= nil and i < MAX_DEPTH do
            if safe_class(cursor) == class_name then return cursor end
            cursor = safe_parent(cursor)
            i = i + 1
        end
        return nil
    end

    function M.parent_named(inst, name)
        if type(name) ~= "string" then return nil end
        local cursor = safe_parent(inst)
        local i = 0
        while cursor ~= nil and i < MAX_DEPTH do
            if safe_name(cursor) == name then return cursor end
            cursor = safe_parent(cursor)
            i = i + 1
        end
        return nil
    end

    function M.has_ancestor(inst, ancestor)
        if type(inst) ~= "userdata" or type(ancestor) ~= "userdata" then
            return false
        end
        local cursor = safe_parent(inst)
        local i = 0
        while cursor ~= nil and i < MAX_DEPTH do
            if cursor == ancestor then return true end
            cursor = safe_parent(cursor)
            i = i + 1
        end
        return false
    end

    function M.is_in_service(inst, service_name)
        if type(service_name) ~= "string" then return false end
        local svc = env[service_name]
        if not svc then return false end
        return M.has_ancestor(inst, svc)
    end

    function M.short_path(inst, segments)
        segments = tonumber(segments) or 3
        local chain = M.name_chain(inst, segments)
        if #chain == 0 then return "<?>" end
        local reversed = {}
        for i = #chain, 1, -1 do table.insert(reversed, chain[i]) end
        return table.concat(reversed, ".")
    end

    function M.depth(inst)
        local cursor = inst
        local i = 0
        while cursor ~= nil and i < MAX_DEPTH do
            cursor = safe_parent(cursor)
            i = i + 1
        end
        return i
    end

    return M

end

end
__MODULES__['lib/math_utils'] = function(require)
--[[ ================================================================
    src/lib/math_utils.lua
    -----------------------
    Small math helpers. Vector3 helpers accept either a Roblox
    Vector3 userdata or a plain {x, y, z} table so we can reuse
    from test harnesses outside Roblox.
================================================================ ]]

return function(require)

    local M = {}

    function M.clamp(v, lo, hi)
        if lo > hi then lo, hi = hi, lo end
        if v < lo then return lo end
        if v > hi then return hi end
        return v
    end

    function M.lerp(a, b, t)
        return a + (b - a) * t
    end

    function M.inv_lerp(a, b, v)
        if a == b then return 0 end
        return (v - a) / (b - a)
    end

    function M.remap(v, in_lo, in_hi, out_lo, out_hi)
        local t = M.inv_lerp(in_lo, in_hi, v)
        return M.lerp(out_lo, out_hi, t)
    end

    function M.round(v, places)
        places = tonumber(places) or 0
        local m = 10 ^ places
        if v >= 0 then
            return math.floor(v * m + 0.5) / m
        else
            return -math.floor(-v * m + 0.5) / m
        end
    end

    function M.sign(v)
        if v > 0 then return 1 end
        if v < 0 then return -1 end
        return 0
    end

    function M.approx_eq(a, b, eps)
        eps = eps or 1e-4
        return math.abs(a - b) <= eps
    end

    function M.saturate(v)
        return M.clamp(v, 0, 1)
    end

    function M.wrap(v, lo, hi)
        local span = hi - lo
        if span <= 0 then return lo end
        local r = (v - lo) % span
        if r < 0 then r = r + span end
        return lo + r
    end

    -- Accept Roblox Vector3 OR a {x,y,z} table.
    local function xyz(v)
        if v == nil then return 0, 0, 0 end
        if type(v) == "table" then
            return tonumber(v.x or v.X) or 0,
                   tonumber(v.y or v.Y) or 0,
                   tonumber(v.z or v.Z) or 0
        end
        local ok, x, y, z = pcall(function() return v.X, v.Y, v.Z end)
        if ok then return x or 0, y or 0, z or 0 end
        return 0, 0, 0
    end

    function M.dist2d(a, b)
        local ax, _, az = xyz(a)
        local bx, _, bz = xyz(b)
        local dx, dz = ax - bx, az - bz
        return math.sqrt(dx * dx + dz * dz)
    end

    function M.dist3d(a, b)
        local ax, ay, az = xyz(a)
        local bx, by, bz = xyz(b)
        local dx, dy, dz = ax - bx, ay - by, az - bz
        return math.sqrt(dx * dx + dy * dy + dz * dz)
    end

    function M.vec3_magnitude(v)
        local x, y, z = xyz(v)
        return math.sqrt(x * x + y * y + z * z)
    end

    function M.vec3_clamp_magnitude(v, max_mag)
        local x, y, z = xyz(v)
        local mag = math.sqrt(x * x + y * y + z * z)
        if mag <= max_mag or mag == 0 then return v end
        local s = max_mag / mag
        local ok, scaled = pcall(function()
            return Vector3.new(x * s, y * s, z * s)
        end)
        if ok and scaled then return scaled end
        return { x = x * s, y = y * s, z = z * s }
    end

    function M.vec3_equal(a, b, eps)
        eps = eps or 1e-4
        local ax, ay, az = xyz(a)
        local bx, by, bz = xyz(b)
        return math.abs(ax - bx) <= eps
           and math.abs(ay - by) <= eps
           and math.abs(az - bz) <= eps
    end

    function M.smoothstep(a, b, t)
        t = M.saturate(M.inv_lerp(a, b, t))
        return t * t * (3 - 2 * t)
    end

    return M

end

end
__MODULES__['lib/pattern_set'] = function(require)
--[[ ================================================================
    src/lib/pattern_set.lua
    ------------------------
    Mutable set of string patterns used as a matcher. Many modules
    keep one of these (kick reasons, GUI names to block, script
    names to pretend to be). The UI can push / pop patterns live
    via `add` / `remove`.

    Patterns are tested with `string.find` so callers can supply
    either literal substrings (preferred, faster) or Lua patterns.
    A per-pattern flag records whether it's literal; literal paths
    skip the pattern engine by calling string.find with plain=true.

    M.new()  returns set object:
        :add(pattern, opts?)    -- opts = { literal = bool, tag = str }
        :remove(pattern)
        :matches(str)           -> bool, tag?
        :clear()
        :list()                 -> { {pattern, literal, tag}, ... }
        :count()
        :contains(pattern)
================================================================ ]]

return function(require)

    local M = {}

    local Set = {}
    Set.__index = Set

    function Set:add(pattern, opts)
        if type(pattern) ~= "string" or #pattern == 0 then return self end
        opts = opts or {}
        for _, e in ipairs(self._entries) do
            if e.pattern == pattern then
                if opts.tag then e.tag = opts.tag end
                return self
            end
        end
        table.insert(self._entries, {
            pattern = pattern,
            literal = opts.literal ~= false,
            tag     = opts.tag or nil,
        })
        return self
    end

    function Set:add_literal(pattern, tag)
        return self:add(pattern, { literal = true, tag = tag })
    end

    function Set:add_pattern(pattern, tag)
        return self:add(pattern, { literal = false, tag = tag })
    end

    function Set:remove(pattern)
        if type(pattern) ~= "string" then return self end
        for i = #self._entries, 1, -1 do
            if self._entries[i].pattern == pattern then
                table.remove(self._entries, i)
            end
        end
        return self
    end

    function Set:clear()
        self._entries = {}
        return self
    end

    function Set:contains(pattern)
        if type(pattern) ~= "string" then return false end
        for _, e in ipairs(self._entries) do
            if e.pattern == pattern then return true end
        end
        return false
    end

    function Set:matches(str)
        if type(str) ~= "string" then return false, nil end
        local lower = self._case_sensitive and str or string.lower(str)
        for _, e in ipairs(self._entries) do
            local pat = self._case_sensitive and e.pattern or string.lower(e.pattern)
            local ok, found = pcall(string.find, lower, pat, 1, e.literal)
            if ok and found then return true, e.tag end
        end
        return false, nil
    end

    function Set:matches_any(strs)
        if type(strs) ~= "table" then return false, nil end
        for _, s in ipairs(strs) do
            local hit, tag = self:matches(s)
            if hit then return true, tag end
        end
        return false, nil
    end

    function Set:list()
        local out = {}
        for _, e in ipairs(self._entries) do
            table.insert(out, {
                pattern = e.pattern,
                literal = e.literal,
                tag     = e.tag,
            })
        end
        return out
    end

    function Set:count()
        return #self._entries
    end

    function Set:set_case_sensitive(on)
        self._case_sensitive = on and true or false
        return self
    end

    function Set:extend(patterns, opts)
        if type(patterns) ~= "table" then return self end
        for _, p in ipairs(patterns) do self:add(p, opts) end
        return self
    end

    function M.new(initial, opts)
        opts = opts or {}
        local self = setmetatable({
            _entries = {},
            _case_sensitive = opts.case_sensitive and true or false,
        }, Set)
        if type(initial) == "table" then
            self:extend(initial, { literal = opts.literal ~= false })
        end
        return self
    end

    return M

end

end
__MODULES__['lib/random_id'] = function(require)
--[[ ================================================================
    src/lib/random_id.lua
    ----------------------
    Generates benign-looking identifiers for renaming our UI and
    internal instances. The point is that a dump of the DataModel
    doesn't obviously say "opiumware" or "grg_bypass" -- it says
    `PlayerController_fz9bq2` and blends in with stock Roblox UI
    names.
================================================================ ]]

return function(require)

    local env = require("core/env")

    local M = {}

    local BENCH_POOL = {
        "RBXScript",
        "PlayerController",
        "UIController",
        "CameraController",
        "MovementController",
        "CoreModule",
        "GameModule",
        "InputModule",
        "ReplicationModule",
        "SessionManager",
        "ContextModule",
        "ChatModule",
        "HudModule",
        "StatsModule",
        "LoadoutModule",
    }

    local GUI_POOL = {
        "CoreMenu",
        "PlayerMenu",
        "SettingsMenu",
        "HudLayer",
        "NotificationLayer",
        "ChatLayer",
        "TopBar",
        "Dialog",
        "Prompt",
        "Overlay",
        "Container",
        "LoadingScreen",
    }

    local CHARSET = "abcdefghijklmnopqrstuvwxyz0123456789"
    local CHARSET_N = #CHARSET

    -- Seed once from tick + place id so two sessions don't match.
    do
        local seed = tick() * 1000
        if env.PlaceId then seed = seed + env.PlaceId end
        math.randomseed(math.floor(seed % 2147483647))
        -- burn a few to warm the generator
        for _ = 1, 4 do math.random() end
    end

    local function random_suffix(n)
        n = tonumber(n) or 6
        local t = {}
        for _ = 1, n do
            local i = math.random(1, CHARSET_N)
            table.insert(t, string.sub(CHARSET, i, i))
        end
        return table.concat(t)
    end

    local function pick(pool)
        return pool[math.random(1, #pool)]
    end

    function M.bench_id()
        return pick(BENCH_POOL) .. "_" .. random_suffix(6)
    end

    function M.gui_name()
        return pick(GUI_POOL) .. "_" .. random_suffix(6)
    end

    function M.suffix(n)
        return random_suffix(n)
    end

    function M.custom(prefix, len)
        if type(prefix) ~= "string" then prefix = "X" end
        return prefix .. "_" .. random_suffix(len or 6)
    end

    return M

end

end
__MODULES__['lib/serialize'] = function(require)
--[[ ================================================================
    src/lib/serialize.lua
    ----------------------
    Compact, bounded table -> string serializer for log lines. It's
    NOT round-trippable: the priority is that a netgate send_filter
    can log a RemoteEvent payload at DEBUG level without blowing
    the ring-buffer with megabytes of nested tables.

    Rules:
        - numbers print with %.4g
        - strings are quoted; escaped control chars; capped at 80 per.
        - booleans / nil print literally
        - userdata prints as <ClassName "Name">
        - CFrame prints as "CFrame(x,y,z @ rx,ry,rz)" (3x decimal, no
          matrix)
        - Vector3 prints as "V3(x,y,z)"
        - Color3 prints as "C3(r,g,b)"
        - Enum / EnumItem print as tostring
        - tables print as {k=v,k=v} up to max_depth; cycles detected
        - recursion past max_depth prints "{...}"
        - total output capped at max_len, then truncated with "<..>"

    Used by netgate, fire_handlers, recv_handlers, kick, teleport,
    and the UI event viewer.
================================================================ ]]

return function(require)

    local env = require("core/env")

    local M = {}

    local DEFAULT_MAX_DEPTH = 4
    local DEFAULT_MAX_LEN   = 512
    local MAX_STR_LEN       = 80

    -- Quick classifier for common Roblox userdata we care about.
    local function classify(v)
        if typeof then
            local ok, t = pcall(typeof, v)
            if ok then return t end
        end
        return type(v)
    end

    local function escape_str(s)
        -- Luau string.gsub with function callback is safe in 5.1.
        s = string.gsub(s, "\\", "\\\\")
        s = string.gsub(s, "\"", "\\\"")
        s = string.gsub(s, "\n", "\\n")
        s = string.gsub(s, "\r", "\\r")
        s = string.gsub(s, "\t", "\\t")
        -- zap any remaining control chars
        s = string.gsub(s, "[%z\1-\31]", function(c)
            return string.format("\\x%02X", string.byte(c))
        end)
        return s
    end

    local function fmt_string(v)
        local s = v
        if #s > MAX_STR_LEN then
            s = string.sub(s, 1, MAX_STR_LEN) .. "..<"
                .. tostring(#v - MAX_STR_LEN) .. ">"
        end
        return "\"" .. escape_str(s) .. "\""
    end

    local function fmt_vector3(v)
        local ok, x, y, z = pcall(function()
            return v.X, v.Y, v.Z
        end)
        if not ok then return "V3(?)" end
        return string.format("V3(%.3g,%.3g,%.3g)", x, y, z)
    end

    local function fmt_cframe(c)
        local ok, px, py, pz = pcall(function()
            return c.Position.X, c.Position.Y, c.Position.Z
        end)
        if not ok then return "CF(?)" end
        local rx, ry, rz = 0, 0, 0
        pcall(function()
            rx, ry, rz = c:ToEulerAnglesXYZ()
        end)
        return string.format("CF(%.2f,%.2f,%.2f @ %.2f,%.2f,%.2f)",
            px, py, pz, rx, ry, rz)
    end

    local function fmt_color3(c)
        local ok, r, g, b = pcall(function()
            return c.R, c.G, c.B
        end)
        if not ok then return "C3(?)" end
        return string.format("C3(%.2f,%.2f,%.2f)", r, g, b)
    end

    local function fmt_userdata(v)
        local ok_class, class = pcall(function() return v.ClassName end)
        local ok_name,  name  = pcall(function() return v.Name end)
        if ok_class and type(class) == "string" then
            if ok_name and type(name) == "string" then
                return string.format("<%s \"%s\">", class, name)
            end
            return string.format("<%s>", class)
        end
        return "<userdata>"
    end

    -- ----------------------------------------------------------------
    -- Main recursive formatter.
    -- ----------------------------------------------------------------

    local function one(v, depth, max_depth, seen, out_len_ref, max_len)
        if out_len_ref[1] >= max_len then return "" end

        local tag = classify(v)

        if v == nil then return "nil" end

        if tag == "string" then
            return fmt_string(v)
        elseif tag == "number" then
            return string.format("%.4g", v)
        elseif tag == "boolean" then
            return tostring(v)
        elseif tag == "Vector3" then
            return fmt_vector3(v)
        elseif tag == "Vector2" then
            local ok, x, y = pcall(function() return v.X, v.Y end)
            if not ok then return "V2(?)" end
            return string.format("V2(%.3g,%.3g)", x, y)
        elseif tag == "CFrame" then
            return fmt_cframe(v)
        elseif tag == "Color3" then
            return fmt_color3(v)
        elseif tag == "UDim2" then
            local ok, xs, xo, ys, yo = pcall(function()
                return v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset
            end)
            if not ok then return "UD2(?)" end
            return string.format("UD2(%.2f,%d,%.2f,%d)", xs, xo, ys, yo)
        elseif tag == "EnumItem" or tag == "Enum" then
            return tostring(v)
        elseif tag == "Instance" or tag == "userdata" then
            return fmt_userdata(v)
        elseif tag == "function" then
            return "<fn>"
        elseif tag == "thread" then
            return "<co>"
        elseif tag == "table" then
            if seen[v] then return "<cycle>" end
            if depth >= max_depth then return "{...}" end
            seen[v] = true
            local parts = {}
            local n = 0
            local is_array = true
            local maxk = 0
            for k in pairs(v) do
                n = n + 1
                if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then
                    is_array = false
                else
                    if k > maxk then maxk = k end
                end
            end
            if is_array and n > 0 and maxk == n then
                for i = 1, n do
                    if out_len_ref[1] >= max_len then
                        table.insert(parts, "...")
                        break
                    end
                    local piece = one(v[i], depth + 1, max_depth, seen,
                        out_len_ref, max_len)
                    out_len_ref[1] = out_len_ref[1] + #piece + 1
                    table.insert(parts, piece)
                end
                seen[v] = nil
                return "[" .. table.concat(parts, ",") .. "]"
            else
                local i = 0
                for k, val in pairs(v) do
                    i = i + 1
                    if i > 32 then
                        table.insert(parts, "...")
                        break
                    end
                    if out_len_ref[1] >= max_len then
                        table.insert(parts, "...")
                        break
                    end
                    local ks
                    if type(k) == "string" then
                        if string.match(k, "^[%a_][%w_]*$") then
                            ks = k
                        else
                            ks = fmt_string(k)
                        end
                    else
                        ks = one(k, depth + 1, max_depth, seen,
                            out_len_ref, max_len)
                    end
                    local vs = one(val, depth + 1, max_depth, seen,
                        out_len_ref, max_len)
                    local piece = ks .. "=" .. vs
                    out_len_ref[1] = out_len_ref[1] + #piece + 1
                    table.insert(parts, piece)
                end
                seen[v] = nil
                return "{" .. table.concat(parts, ",") .. "}"
            end
        end

        return "<?" .. tostring(tag) .. ">"
    end

    function M.serialize(val, max_depth, max_len)
        max_depth = tonumber(max_depth) or DEFAULT_MAX_DEPTH
        max_len   = tonumber(max_len)   or DEFAULT_MAX_LEN
        local seen = {}
        local out_len_ref = {0}
        local ok, result = pcall(one, val, 0, max_depth, seen, out_len_ref, max_len)
        if not ok then return "<serialize error>" end
        if #result > max_len then
            return string.sub(result, 1, max_len) .. "<..>"
        end
        return result
    end

    function M.serialize_many(args, max_depth, max_len)
        if type(args) ~= "table" then
            return M.serialize(args, max_depth, max_len)
        end
        local n = (args.n and tonumber(args.n)) or #args
        local parts = {}
        for i = 1, n do
            table.insert(parts, M.serialize(args[i], max_depth, max_len))
        end
        return table.concat(parts, ", ")
    end

    function M.brief(val)
        return M.serialize(val, 2, 96)
    end

    return M

end

end
__MODULES__['lib/table_utils'] = function(require)
--[[ ================================================================
    src/lib/table_utils.lua
    ------------------------
    Stateless table helpers. Kept dependency-free so core modules
    (config, state) can pull it without a require cycle.
================================================================ ]]

return function(require)

    local M = {}

    function M.deep_copy(v, seen)
        if type(v) ~= "table" then return v end
        seen = seen or {}
        if seen[v] then return seen[v] end
        local out = {}
        seen[v] = out
        for k, val in pairs(v) do
            out[M.deep_copy(k, seen)] = M.deep_copy(val, seen)
        end
        return out
    end

    function M.shallow_copy(t)
        if type(t) ~= "table" then return t end
        local out = {}
        for k, v in pairs(t) do out[k] = v end
        return out
    end

    function M.shallow_merge(a, b)
        local out = {}
        if type(a) == "table" then
            for k, v in pairs(a) do out[k] = v end
        end
        if type(b) == "table" then
            for k, v in pairs(b) do out[k] = v end
        end
        return out
    end

    function M.deep_merge(a, b)
        local out = M.deep_copy(a)
        if type(b) ~= "table" then return out end
        for k, v in pairs(b) do
            if type(v) == "table" and type(out[k]) == "table" then
                out[k] = M.deep_merge(out[k], v)
            else
                out[k] = M.deep_copy(v)
            end
        end
        return out
    end

    function M.filter(t, fn)
        local out = {}
        if type(t) ~= "table" or type(fn) ~= "function" then return out end
        local is_array = true
        for k in pairs(t) do
            if type(k) ~= "number" then is_array = false break end
        end
        if is_array then
            for i, v in ipairs(t) do
                if fn(v, i) then table.insert(out, v) end
            end
        else
            for k, v in pairs(t) do
                if fn(v, k) then out[k] = v end
            end
        end
        return out
    end

    function M.map(t, fn)
        local out = {}
        if type(t) ~= "table" or type(fn) ~= "function" then return out end
        local is_array = true
        for k in pairs(t) do
            if type(k) ~= "number" then is_array = false break end
        end
        if is_array then
            for i, v in ipairs(t) do out[i] = fn(v, i) end
        else
            for k, v in pairs(t) do out[k] = fn(v, k) end
        end
        return out
    end

    function M.find(t, fn)
        if type(t) ~= "table" then return nil end
        if type(fn) == "function" then
            for k, v in pairs(t) do
                if fn(v, k) then return v, k end
            end
        else
            for k, v in pairs(t) do
                if v == fn then return v, k end
            end
        end
        return nil
    end

    function M.keys(t)
        local out = {}
        if type(t) ~= "table" then return out end
        for k in pairs(t) do table.insert(out, k) end
        return out
    end

    function M.values(t)
        local out = {}
        if type(t) ~= "table" then return out end
        for _, v in pairs(t) do table.insert(out, v) end
        return out
    end

    function M.contains(t, value)
        if type(t) ~= "table" then return false end
        for _, v in pairs(t) do
            if v == value then return true end
        end
        return false
    end

    function M.contains_key(t, key)
        if type(t) ~= "table" then return false end
        return t[key] ~= nil
    end

    function M.count(t, predicate)
        if type(t) ~= "table" then return 0 end
        if type(predicate) ~= "function" then
            local n = 0
            for _ in pairs(t) do n = n + 1 end
            return n
        end
        local n = 0
        for k, v in pairs(t) do
            if predicate(v, k) then n = n + 1 end
        end
        return n
    end

    function M.any(t, fn)
        if type(t) ~= "table" or type(fn) ~= "function" then return false end
        for k, v in pairs(t) do
            if fn(v, k) then return true end
        end
        return false
    end

    function M.all(t, fn)
        if type(t) ~= "table" or type(fn) ~= "function" then return false end
        for k, v in pairs(t) do
            if not fn(v, k) then return false end
        end
        return true
    end

    function M.slice(t, i, j)
        if type(t) ~= "table" then return {} end
        i = i or 1
        j = j or #t
        local out = {}
        for k = i, j do table.insert(out, t[k]) end
        return out
    end

    function M.reverse(t)
        local out = {}
        if type(t) ~= "table" then return out end
        for i = #t, 1, -1 do table.insert(out, t[i]) end
        return out
    end

    function M.is_empty(t)
        if type(t) ~= "table" then return true end
        return next(t) == nil
    end

    function M.set_from(t)
        local out = {}
        if type(t) ~= "table" then return out end
        for _, v in ipairs(t) do out[v] = true end
        return out
    end

    return M

end

end
__MODULES__['lib/weakset'] = function(require)
--[[ ================================================================
    src/lib/weakset.lua
    --------------------
    Weak-keyed set. Membership is keyed on object identity, and
    keys are garbage-collected when no other code holds them, so
    we don't leak memory tracking Instances that Roblox destroyed
    long ago.

    Primary use: "have I already wrapped this RemoteEvent?" and
    "have I already patched this Humanoid's state-change signal?"

        local seen = weakset.new()
        if not seen:has(inst) then
            seen:add(inst)
            -- do the work
        end
================================================================ ]]

return function(require)

    local M = {}

    local Weak = {}
    Weak.__index = Weak

    function Weak:add(inst)
        if inst == nil then return self end
        self._data[inst] = true
        self._count = self._count + 1
        if (self._count % 64) == 0 then
            self:_recount()
        end
        return self
    end

    function Weak:has(inst)
        if inst == nil then return false end
        return self._data[inst] == true
    end

    function Weak:remove(inst)
        if inst == nil then return self end
        if self._data[inst] then
            self._data[inst] = nil
            self._count = self._count - 1
        end
        return self
    end

    function Weak:size()
        self:_recount()
        return self._live
    end

    function Weak:_recount()
        local n = 0
        for _ in pairs(self._data) do n = n + 1 end
        self._live = n
        return n
    end

    function Weak:clear()
        self._data = setmetatable({}, { __mode = "k" })
        self._count = 0
        self._live  = 0
        return self
    end

    function Weak:each(fn)
        if type(fn) ~= "function" then return end
        for k in pairs(self._data) do
            local ok, stop = pcall(fn, k)
            if not ok then return end
            if stop == true then return end
        end
    end

    function Weak:collect()
        local t = {}
        for k in pairs(self._data) do table.insert(t, k) end
        return t
    end

    function M.new()
        local self = setmetatable({
            _data  = setmetatable({}, { __mode = "k" }),
            _count = 0,
            _live  = 0,
        }, Weak)
        return self
    end

    function M.new_vweak()
        -- Value-weak variant: key strong, value weak. Useful for
        -- "instance -> state record" maps where the state should
        -- vanish with the instance. Exposed for completeness.
        local self = setmetatable({
            _data  = setmetatable({}, { __mode = "v" }),
            _count = 0,
            _live  = 0,
        }, Weak)
        return self
    end

    return M

end

end
__MODULES__['masks/animation'] = function(require)
--[[ ================================================================
    src/masks/animation.lua
    ------------------------
    Masks animation probes issued by the AC client.

    Two vectors to hide:

    1. Humanoid:GetPlayingAnimationTracks()
        A common AC probe loops this and inspects each track's
        .Animation.AnimationId to flag "cheater" animations. We
        intercept via __namecall and, when the caller isn't us,
        substitute an empty table. The AC sees "nothing playing",
        our own hub threads still see reality.

    2. AnimationTrack:GetTimeOfKeyframeReached(name)
        Used to detect forced-frame-advance cheats. We mutate the
        returned value slightly so it looks like a natural playback
        delta rather than an instantaneous jump.

    3. Humanoid:LoadAnimation(anim)
        Optional blocklist: any animation whose AnimationId matches
        a blocklisted id is refused. Used for anti-emote scams and
        to block known AC "trap" animations that the real game would
        never load on a legit client.

    Exposed helpers:
        M.blocklist_add(id)
        M.blocklist_remove(id)
================================================================ ]]

return function(require)

    local env    = require("core/env")
    local log    = require("core/log")
    local cfg    = require("core/config")
    local state  = require("core/state")

    local namecall = require("hooks/namecall")

    local M = {}
    local L = log.scoped("masks/animation")

    local BLOCKLIST = {}
    local INSTALLED = false

    ----------------------------------------------------------------
    -- helpers
    ----------------------------------------------------------------

    local function caller_is_us()
        if _G.__GRG_THREAD then return true end
        if env.ckcaller then
            local ok, v = pcall(env.ckcaller)
            if ok and v then return true end
        end
        return false
    end

    local function norm_id(id)
        if type(id) ~= "string" then return nil end
        local n = id:match("(%d+)$")
        return n
    end

    local function is_blocklisted(anim)
        if type(anim) ~= "userdata" then return false end
        local ok, id = pcall(function() return anim.AnimationId end)
        if not ok or type(id) ~= "string" then return false end
        local norm = norm_id(id)
        if not norm then return false end
        if BLOCKLIST[norm] then return true end
        if BLOCKLIST[id] then return true end
        return false
    end

    ----------------------------------------------------------------
    -- public API
    ----------------------------------------------------------------

    function M.blocklist_add(id)
        if id == nil then return end
        local k = tostring(id)
        BLOCKLIST[k] = true
        local n = norm_id(k)
        if n then BLOCKLIST[n] = true end
        L:debug("blocklist add %s", k)
    end

    function M.blocklist_remove(id)
        if id == nil then return end
        local k = tostring(id)
        BLOCKLIST[k] = nil
        local n = norm_id(k)
        if n then BLOCKLIST[n] = nil end
        L:debug("blocklist remove %s", k)
    end

    function M.blocklist_clear()
        BLOCKLIST = {}
    end

    function M.blocklist_list()
        local out = {}
        for k in pairs(BLOCKLIST) do table.insert(out, k) end
        return out
    end

    ----------------------------------------------------------------
    -- namecall handlers
    ----------------------------------------------------------------

    local function install_get_playing_tracks()
        namecall.register({
            name     = "mask_anim_get_playing_tracks",
            method   = "GetPlayingAnimationTracks",
            class    = "Humanoid",
            priority = 30,
            handler  = function(ctx)
                if caller_is_us() then return end
                ctx.after = function(ret)
                    state:bump("animation_masked")
                    return { n = 1, [1] = {} }
                end
            end,
        })
    end

    local function install_load_animation()
        namecall.register({
            name     = "mask_anim_load_animation",
            method   = "LoadAnimation",
            class    = "Humanoid",
            priority = 30,
            handler  = function(ctx)
                local anim = ctx.args[1]
                if not is_blocklisted(anim) then return end
                if caller_is_us() then return end
                ctx.drop = true
                ctx.why  = "blocklisted_anim"
                state:bump("animation_load_blocked")
                L:debug("blocked LoadAnimation for blocklisted anim")
            end,
        })
    end

    local function install_keyframe_reached()
        if not cfg:get("masks.animation.spoof_timeposition", false) then
            return
        end
        namecall.register({
            name     = "mask_anim_keyframe_time",
            method   = "GetTimeOfKeyframeReached",
            class    = "AnimationTrack",
            priority = 40,
            handler  = function(ctx)
                if caller_is_us() then return end
                ctx.after = function(ret)
                    if type(ret) ~= "table" then return ret end
                    local v = ret[1]
                    if type(v) == "number" then
                        local jitter = (math.random() * 0.02) - 0.01
                        ret[1] = v + jitter
                    end
                    return ret
                end
            end,
        })
    end

    ----------------------------------------------------------------
    -- install
    ----------------------------------------------------------------

    function M.install()
        if INSTALLED then return end
        if not cfg:get("masks.animation.enabled", true) then
            L:info("animation mask disabled via config")
            return
        end
        INSTALLED = true

        local seed = cfg:get("masks.animation.blocklist_ids", nil)
        if type(seed) == "table" then
            for _, id in ipairs(seed) do M.blocklist_add(id) end
        end

        install_get_playing_tracks()
        install_load_animation()
        install_keyframe_reached()

        L:info("animation mask active (blocklist=%d)", #M.blocklist_list())
    end

    return M

end

end
__MODULES__['masks/character_state'] = function(require)
--[[ ================================================================
    src/masks/character_state.lua
    ------------------------------
    Humanoid state scrubber. Keeps the local character out of the
    "ragdolled / platform-stood / sitting / dead" soft-ban states that
    the AC uses to pin the player in place as punishment for detected
    cheats.

    Three layers:

    1. Heartbeat sweep
        Every frame, if force_no_platform_stand / force_no_sit is set,
        force the corresponding Humanoid flag to false. We write
        through the real __newindex (caller_is_us guard in the write
        hook should prevent our clamp from triggering walkspeed-style
        logic).

    2. ChangeState block
        Humanoid:ChangeState(Enum.HumanoidStateType.Physics / Ragdoll
        / Dead) from untrusted threads is swallowed. We leave our own
        calls alone so features that rely on state transitions (eg.
        vehicle_sit) still work.

    3. GetState() rewrite
        When the real state is Physics or Ragdoll, we rewrite the
        return of Humanoid:GetState() to Running via ctx.after. The
        AC sees a healthy running state; our own introspection sees
        the real one.

    Exposed helpers:
        M.set_force_running(bool)
================================================================ ]]

return function(require)

    local env    = require("core/env")
    local log    = require("core/log")
    local cfg    = require("core/config")
    local state  = require("core/state")

    local namecall = require("hooks/namecall")
    local newindex = require("hooks/newindex")

    local M = {}
    local L = log.scoped("masks/character_state")

    local INSTALLED    = false
    local FORCE_RUN    = false
    local HEARTBEAT_CN = nil

    ----------------------------------------------------------------
    -- helpers
    ----------------------------------------------------------------

    local function caller_is_us()
        if _G.__GRG_THREAD then return true end
        if env.ckcaller then
            local ok, v = pcall(env.ckcaller)
            if ok and v then return true end
        end
        return false
    end

    local function safe_enum(name)
        local ok, v = pcall(function()
            return Enum.HumanoidStateType[name]
        end)
        if ok then return v end
        return nil
    end

    local STATE_PHYSICS = safe_enum("Physics")
    local STATE_RAGDOLL = safe_enum("Ragdoll")
    local STATE_DEAD    = safe_enum("Dead")
    local STATE_RUNNING = safe_enum("Running")

    local FORBIDDEN = {}
    if STATE_PHYSICS then FORBIDDEN[STATE_PHYSICS] = true end
    if STATE_RAGDOLL then FORBIDDEN[STATE_RAGDOLL] = true end
    if STATE_DEAD    then FORBIDDEN[STATE_DEAD]    = true end

    local function get_humanoid()
        return env.get_humanoid()
    end

    ----------------------------------------------------------------
    -- heartbeat clamps
    ----------------------------------------------------------------

    local function on_heartbeat()
        local h = get_humanoid()
        if not h then return end

        if cfg:get("masks.character_state.force_no_platform_stand", true) then
            local ok, v = pcall(function() return h.PlatformStand end)
            if ok and v then
                pcall(function() h.PlatformStand = false end)
                state:bump("platform_stand_cleared")
            end
        end

        if cfg:get("masks.character_state.force_no_sit", true) then
            local ok, v = pcall(function() return h.Sit end)
            if ok and v then
                pcall(function() h.Sit = false end)
                state:bump("sit_cleared")
            end
        end

        if FORCE_RUN and STATE_RUNNING then
            local ok, s = pcall(function() return h:GetState() end)
            if ok and FORBIDDEN[s] then
                pcall(function() h:ChangeState(STATE_RUNNING) end)
                state:bump("forced_running_state")
            end
        end
    end

    local function start_heartbeat()
        if HEARTBEAT_CN then return end
        if not env.RunService then return end
        local ok, cn = pcall(function()
            return env.RunService.Heartbeat:Connect(on_heartbeat)
        end)
        if ok and cn then
            HEARTBEAT_CN = cn
        else
            L:warn("failed to connect Heartbeat")
        end
    end

    ----------------------------------------------------------------
    -- namecall handlers
    ----------------------------------------------------------------

    local function install_change_state_block()
        namecall.register({
            name     = "mask_cs_change_state",
            method   = "ChangeState",
            class    = "Humanoid",
            priority = 20,
            handler  = function(ctx)
                if not cfg:get("masks.character_state.forbid_forced_humanoid_state", true) then
                    return
                end
                if caller_is_us() then return end
                local requested = ctx.args[1]
                if requested == nil then return end
                if not FORBIDDEN[requested] then return end
                ctx.drop = true
                ctx.why  = "forbidden_humanoid_state"
                state:bump("change_state_blocked")
                L:debug("blocked ChangeState(%s)", tostring(requested))
            end,
        })

        namecall.register({
            name     = "mask_cs_set_state_enabled",
            method   = "SetStateEnabled",
            class    = "Humanoid",
            priority = 20,
            handler  = function(ctx)
                if not cfg:get("masks.character_state.forbid_forced_humanoid_state", true) then
                    return
                end
                if caller_is_us() then return end
                local requested = ctx.args[1]
                local enabled   = ctx.args[2]
                if requested == STATE_RUNNING and enabled == false then
                    ctx.drop = true
                    state:bump("set_state_enabled_blocked")
                end
            end,
        })
    end

    local function install_get_state_rewrite()
        namecall.register({
            name     = "mask_cs_get_state",
            method   = "GetState",
            class    = "Humanoid",
            priority = 40,
            handler  = function(ctx)
                if caller_is_us() then return end
                if not STATE_RUNNING then return end
                ctx.after = function(ret)
                    if type(ret) ~= "table" then return ret end
                    local v = ret[1]
                    if FORBIDDEN[v] then
                        ret[1] = STATE_RUNNING
                        state:bump("get_state_masked")
                    end
                    return ret
                end
            end,
        })
    end

    ----------------------------------------------------------------
    -- newindex guard (nobody else forces PlatformStand back on)
    ----------------------------------------------------------------

    local function install_platform_stand_guard()
        newindex.register({
            name     = "mask_cs_platform_stand_write",
            class    = "Humanoid",
            property = "PlatformStand",
            priority = 20,
            handler  = function(ctx)
                if not cfg:get("masks.character_state.force_no_platform_stand", true) then
                    return
                end
                if caller_is_us() then return end
                if ctx.value == true then
                    ctx.value = false
                    state:bump("platform_stand_write_masked")
                end
            end,
        })

        newindex.register({
            name     = "mask_cs_sit_write",
            class    = "Humanoid",
            property = "Sit",
            priority = 20,
            handler  = function(ctx)
                if not cfg:get("masks.character_state.force_no_sit", true) then
                    return
                end
                if caller_is_us() then return end
                if ctx.value == true then
                    ctx.value = false
                    state:bump("sit_write_masked")
                end
            end,
        })
    end

    ----------------------------------------------------------------
    -- public API
    ----------------------------------------------------------------

    function M.set_force_running(v)
        FORCE_RUN = v and true or false
        L:debug("force_running -> %s", tostring(FORCE_RUN))
    end

    ----------------------------------------------------------------
    -- install
    ----------------------------------------------------------------

    function M.install()
        if INSTALLED then return end
        if not cfg:get("masks.character_state.enabled", true) then
            L:info("character_state mask disabled via config")
            return
        end
        INSTALLED = true

        install_change_state_block()
        install_get_state_rewrite()
        install_platform_stand_guard()
        start_heartbeat()

        L:info("character_state mask active")
    end

    return M

end

end
__MODULES__['masks/gravity'] = function(require)
--[[ ================================================================
    src/masks/gravity.lua
    ----------------------
    Masks Workspace.Gravity reads and, optionally, clamps writes.

    Roblox AC probes frequently sample workspace.Gravity to detect
    low-gravity fly cheats. We return a canonical value (default
    196.2 studs/s^2) to any caller that isn't us. Our own hub threads
    still see the real value so features like "restore_gravity" know
    what to put back.

    Optional features:
        mask_write: clamp external writes so nobody can crank gravity
            down as a side-channel fly exploit that AC would catch.
        getgravity hookfunction: some games expose a custom global
            function; if present, we hook it to also return the mask
            value when called from untrusted threads.
================================================================ ]]

return function(require)

    local env    = require("core/env")
    local log    = require("core/log")
    local cfg    = require("core/config")
    local state  = require("core/state")

    local newindex = require("hooks/newindex")
    local index    = require("hooks/index")

    local M = {}
    local L = log.scoped("masks/gravity")

    local INSTALLED = false
    local ORIGINAL_GETGRAVITY = nil

    ----------------------------------------------------------------
    -- helpers
    ----------------------------------------------------------------

    local function caller_is_us()
        if _G.__GRG_THREAD then return true end
        if env.ckcaller then
            local ok, v = pcall(env.ckcaller)
            if ok and v then return true end
        end
        return false
    end

    local function mask_value()
        return cfg:get("masks.gravity.mask_value", 196.2)
    end

    ----------------------------------------------------------------
    -- hook handlers
    ----------------------------------------------------------------

    local function install_read_hook()
        if not cfg:get("masks.gravity.mask_read", true) then return end
        index.register({
            name     = "mask_gravity_read",
            class    = "Workspace",
            property = "Gravity",
            priority = 30,
            handler  = function(ctx)
                if caller_is_us() then return end
                ctx.spoof_value = mask_value()
                ctx.spoofed = true
                state:bump("gravity_masked")
            end,
        })
    end

    local function install_write_hook()
        if not cfg:get("masks.gravity.mask_write", false) then return end
        newindex.register({
            name     = "mask_gravity_write",
            class    = "Workspace",
            property = "Gravity",
            priority = 30,
            handler  = function(ctx)
                if caller_is_us() then return end
                local expected = mask_value()
                if type(ctx.value) == "number" and math.abs(ctx.value - expected) > 0.01 then
                    L:debug("clamped external Gravity write %.2f -> %.2f",
                        ctx.value, expected)
                    ctx.value = expected
                    state:bump("gravity_write_masked")
                end
            end,
        })
    end

    ----------------------------------------------------------------
    -- optional hookfunction: getgravity
    ----------------------------------------------------------------

    local function try_hook_getgravity()
        local fn = rawget(getfenv(0), "getgravity") or _G.getgravity
        if type(fn) ~= "function" then return end
        if type(env.hookfn) ~= "function" then return end
        local replacement = function()
            if caller_is_us() and ORIGINAL_GETGRAVITY then
                local ok, v = pcall(ORIGINAL_GETGRAVITY)
                if ok then return v end
            end
            state:bump("gravity_masked")
            return mask_value()
        end
        local ok, orig = pcall(env.hookfn, fn, replacement)
        if ok then
            ORIGINAL_GETGRAVITY = orig
            L:info("getgravity hookfunction installed")
        else
            L:warn("getgravity hookfunction failed: %s", tostring(orig))
        end
    end

    ----------------------------------------------------------------
    -- install
    ----------------------------------------------------------------

    function M.install()
        if INSTALLED then return end
        if not cfg:get("masks.gravity.enabled", true) then
            L:info("gravity mask disabled via config")
            return
        end
        INSTALLED = true

        install_read_hook()
        install_write_hook()
        try_hook_getgravity()

        L:info("gravity mask active (mask_value=%.1f)", mask_value())
    end

    function M.get_mask_value()
        return mask_value()
    end

    function M.set_mask_value(v)
        if type(v) == "number" then
            cfg:set("masks.gravity.mask_value", v)
        end
    end

    return M

end

end
__MODULES__['masks/hipheight'] = function(require)
--[[ ================================================================
    src/masks/hipheight.lua
    ------------------------
    Humanoid.HipHeight is used by some AC scripts to detect
    levitation cheats (fly / noclip implemented by raising the char).

    We mask reads back to the baseline and optionally clamp external
    writes. Because HipHeight change also affects the physical
    position, we avoid clamping our own hub's writes.
================================================================ ]]

return function(require)

    local env    = require("core/env")
    local log    = require("core/log")
    local cfg    = require("core/config")
    local state  = require("core/state")

    local newindex = require("hooks/newindex")
    local index    = require("hooks/index")

    local M = {}
    local L = log.scoped("masks/hipheight")

    local function caller_is_us()
        if _G.__GRG_THREAD then return true end
        if env.ckcaller then
            local ok, v = pcall(env.ckcaller)
            if ok and v then return true end
        end
        return false
    end

    function M.install()
        if not cfg:get("masks.hipheight.enabled", true) then
            L:info("disabled")
            return
        end

        if cfg:get("masks.hipheight.mask_read", true) then
            index.register({
                name     = "mask_hh_read",
                class    = "Humanoid",
                property = "HipHeight",
                priority = 30,
                handler  = function(ctx)
                    if caller_is_us() then return end
                    ctx.spoof_value = cfg:get("masks.hipheight.baseline", 2.0)
                    ctx.spoofed = true
                end,
            })
        end

        if cfg:get("masks.hipheight.mask_write", true) then
            newindex.register({
                name     = "mask_hh_write",
                class    = "Humanoid",
                property = "HipHeight",
                priority = 30,
                handler  = function(ctx)
                    if caller_is_us() then return end
                    local cap = cfg:get("masks.hipheight.baseline", 2.0)
                    if type(ctx.value) == "number" and ctx.value > cap + 0.25 then
                        ctx.value = cap
                    end
                end,
            })
        end

        L:info("hipheight mask active (baseline=%.1f)",
            cfg:get("masks.hipheight.baseline", 2.0))
    end

    return M

end

end
__MODULES__['masks/jumppower'] = function(require)
--[[ ================================================================
    src/masks/jumppower.lua
    ------------------------
    Masks Humanoid.JumpPower AND Humanoid.JumpHeight (Roblox offers
    both depending on the .UseJumpPower setting).

    Same pattern as walkspeed: read mask returns baseline, write
    mask optionally clamps external writes. We also mask the reads
    for UseJumpPower itself so AC can't side-channel the feature via
    "did the client change the jump mode?" probes.
================================================================ ]]

return function(require)

    local env    = require("core/env")
    local log    = require("core/log")
    local cfg    = require("core/config")
    local state  = require("core/state")

    local newindex = require("hooks/newindex")
    local index    = require("hooks/index")

    local M = {}
    local L = log.scoped("masks/jumppower")

    local function caller_is_us()
        if _G.__GRG_THREAD then return true end
        if env.ckcaller then
            local ok, v = pcall(env.ckcaller)
            if ok and v then return true end
        end
        return false
    end

    function M.install()
        if not cfg:get("masks.jumppower.enabled", true) then
            L:info("jumppower mask disabled")
            return
        end

        -- JumpPower reads
        if cfg:get("masks.jumppower.mask_read", true) then
            index.register({
                name     = "mask_jp_read",
                class    = "Humanoid",
                property = "JumpPower",
                priority = 30,
                handler  = function(ctx)
                    if caller_is_us() then return end
                    ctx.spoof_value = cfg:get("masks.jumppower.baseline", 50)
                    ctx.spoofed = true
                    state:bump("jumppower_read_masked")
                end,
            })
            index.register({
                name     = "mask_jh_read",
                class    = "Humanoid",
                property = "JumpHeight",
                priority = 30,
                handler  = function(ctx)
                    if caller_is_us() then return end
                    ctx.spoof_value = cfg:get("masks.jumpheight.baseline", 7.2)
                    ctx.spoofed = true
                end,
            })
            -- UseJumpPower is a bool; mask as default "true" so we can
            -- flip it on the side via our own uncheck path.
            index.register({
                name     = "mask_ujp_read",
                class    = "Humanoid",
                property = "UseJumpPower",
                priority = 30,
                handler  = function(ctx)
                    if caller_is_us() then return end
                    ctx.spoof_value = true
                    ctx.spoofed = true
                end,
            })
        end

        -- Writes
        if cfg:get("masks.jumppower.mask_write", true) then
            newindex.register({
                name     = "mask_jp_write",
                class    = "Humanoid",
                property = "JumpPower",
                priority = 30,
                handler  = function(ctx)
                    if caller_is_us() then return end
                    local cap = cfg:get("masks.jumppower.baseline", 50)
                    if type(ctx.value) == "number" and ctx.value > cap + 0.01 then
                        ctx.value = cap
                        state:bump("jumppower_write_masked")
                    end
                end,
            })
            newindex.register({
                name     = "mask_jh_write",
                class    = "Humanoid",
                property = "JumpHeight",
                priority = 30,
                handler  = function(ctx)
                    if caller_is_us() then return end
                    local cap = cfg:get("masks.jumpheight.baseline", 7.2)
                    if type(ctx.value) == "number" and ctx.value > cap + 0.01 then
                        ctx.value = cap
                    end
                end,
            })
        end

        L:info("jumppower mask active (baseline=%d)",
            cfg:get("masks.jumppower.baseline", 50))
    end

    function M.set_baseline(v)
        cfg:set("masks.jumppower.baseline", tonumber(v) or 50)
    end

    return M

end

end
__MODULES__['masks/position'] = function(require)
--[[ ================================================================
    src/masks/position.lua
    -----------------------
    Masks CFrame / Position reads on HumanoidRootPart so the AC cannot
    ground-truth where we really are.

    Core idea:
        Every Heartbeat we integrate a "safe" position that drifts
        towards the real root at a capped rate (tolerance_per_sec).
        When AC probes HumanoidRootPart.CFrame or .Position via an
        untrusted thread, we hand it this lagged, ground-hugging
        surrogate rather than the real coordinates.

        For particularly egregious vertical cheats (fly/noclip), we
        also project the returned CFrame down onto the nearest floor
        via a raycast from the root, so the reported Y never goes
        above what a running character could plausibly reach.

        The module is idempotent: install() once, then toggle via
        pause() / resume() or via cfg.masks.position.mask_* flags.

    Exposed API:
        M.set_safe_cframe(cf)
        M.get_safe_cframe()
        M.pause()
        M.resume()

    All reads from our own hub threads (marked by _G.__GRG_THREAD or
    reported via env.ckcaller) bypass the mask so features like
    tp_to_player continue to see the real location.
================================================================ ]]

return function(require)

    local env    = require("core/env")
    local log    = require("core/log")
    local cfg    = require("core/config")
    local state  = require("core/state")

    local index = require("hooks/index")

    local M = {}
    local L = log.scoped("masks/position")

    ----------------------------------------------------------------
    -- local state
    ----------------------------------------------------------------

    local SAFE_CF       = nil      -- CFrame
    local LAST_TICK     = 0
    local PAUSED        = false
    local HEARTBEAT_CN  = nil
    local INSTALLED     = false

    local FLYING_VY_THR = 18      -- studs/sec
    local RAYCAST_DOWN  = 512     -- studs

    ----------------------------------------------------------------
    -- helpers
    ----------------------------------------------------------------

    local function caller_is_us()
        if _G.__GRG_THREAD then return true end
        if env.ckcaller then
            local ok, v = pcall(env.ckcaller)
            if ok and v then return true end
        end
        return false
    end

    local function get_root()
        local c = env.get_character()
        if not c then return nil end
        return c:FindFirstChild("HumanoidRootPart")
    end

    local function get_vy()
        local r = get_root()
        if not r then return 0 end
        local ok, v = pcall(function() return r.AssemblyLinearVelocity end)
        if ok and v then return v.Y end
        local ok2, v2 = pcall(function() return r.Velocity end)
        if ok2 and v2 then return v2.Y end
        return 0
    end

    local function raycast_down_to_floor(origin)
        if not env.Workspace then return nil end
        local params = nil
        local ok_p, p = pcall(function() return RaycastParams.new() end)
        if ok_p and p then
            params = p
            params.FilterType = Enum.RaycastFilter.Exclude
            local c = env.get_character()
            if c then params.FilterDescendantsInstances = { c } end
        end
        local ok, res = pcall(function()
            return env.Workspace:Raycast(origin, Vector3.new(0, -RAYCAST_DOWN, 0), params)
        end)
        if not ok or not res then return nil end
        return res.Position
    end

    local function project_onto_floor(cf)
        if not cf then return cf end
        local origin = cf.Position + Vector3.new(0, 2, 0)
        local hit = raycast_down_to_floor(origin)
        if not hit then return cf end
        return CFrame.new(hit.X, hit.Y + 3, hit.Z) * (cf - cf.Position)
    end

    local function drift_safe_towards(real_cf, dt)
        if not SAFE_CF then
            SAFE_CF = real_cf
            return
        end
        local tol = cfg:get("masks.position.tolerance_per_sec", 60)
        local max_delta = tol * dt
        local delta = real_cf.Position - SAFE_CF.Position
        local mag = delta.Magnitude
        if mag <= max_delta or mag <= 1e-4 then
            SAFE_CF = real_cf
        else
            local step = delta.Unit * max_delta
            local new_pos = SAFE_CF.Position + step
            SAFE_CF = CFrame.new(new_pos.X, new_pos.Y, new_pos.Z)
                * (real_cf - real_cf.Position)
        end
    end

    ----------------------------------------------------------------
    -- public helpers
    ----------------------------------------------------------------

    function M.set_safe_cframe(cf)
        if typeof and typeof(cf) ~= "CFrame" then return end
        SAFE_CF = cf
    end

    function M.get_safe_cframe()
        return SAFE_CF
    end

    function M.pause()
        PAUSED = true
        L:debug("position mask paused")
    end

    function M.resume()
        PAUSED = false
        LAST_TICK = tick()
        L:debug("position mask resumed")
    end

    ----------------------------------------------------------------
    -- heartbeat driver
    ----------------------------------------------------------------

    local function on_heartbeat()
        if PAUSED then return end
        local now = tick()
        local dt = LAST_TICK > 0 and (now - LAST_TICK) or (1/60)
        LAST_TICK = now

        local r = get_root()
        if not r then return end
        local ok, real = pcall(function() return r.CFrame end)
        if not ok or not real then return end
        drift_safe_towards(real, dt)
    end

    local function start_heartbeat()
        if HEARTBEAT_CN then return end
        if not env.RunService then return end
        local ok, cn = pcall(function()
            return env.RunService.Heartbeat:Connect(on_heartbeat)
        end)
        if ok and cn then
            HEARTBEAT_CN = cn
            LAST_TICK = tick()
        else
            L:warn("failed to connect Heartbeat")
        end
    end

    ----------------------------------------------------------------
    -- hook handlers
    ----------------------------------------------------------------

    local function spoofed_cframe()
        if not SAFE_CF then return nil end
        if cfg:get("masks.position.snap_to_floor_if_flying", true)
           and math.abs(get_vy()) > FLYING_VY_THR then
            return project_onto_floor(SAFE_CF)
        end
        return SAFE_CF
    end

    local function install_index_hooks()
        if cfg:get("masks.position.mask_cframe", false) then
            index.register({
                name     = "mask_root_cframe",
                class    = "BasePart",
                property = "CFrame",
                priority = 30,
                handler  = function(ctx)
                    if PAUSED then return end
                    if caller_is_us() then return end
                    local s = ctx.self
                    if not s then return end
                    local ok, name = pcall(function() return s.Name end)
                    if not ok or name ~= "HumanoidRootPart" then return end
                    local fake = spoofed_cframe()
                    if not fake then return end
                    ctx.spoof_value = fake
                    ctx.spoofed = true
                    state:bump("position_masked")
                end,
            })
        end

        if cfg:get("masks.position.mask_position", false) then
            index.register({
                name     = "mask_root_position",
                class    = "BasePart",
                property = "Position",
                priority = 30,
                handler  = function(ctx)
                    if PAUSED then return end
                    if caller_is_us() then return end
                    local s = ctx.self
                    if not s then return end
                    local ok, name = pcall(function() return s.Name end)
                    if not ok or name ~= "HumanoidRootPart" then return end
                    local fake = spoofed_cframe()
                    if not fake then return end
                    ctx.spoof_value = fake.Position
                    ctx.spoofed = true
                    state:bump("position_masked")
                end,
            })
        end
    end

    ----------------------------------------------------------------
    -- install
    ----------------------------------------------------------------

    function M.install()
        if INSTALLED then return end
        if not cfg:get("masks.position.enabled", true) then
            L:info("position mask disabled via config")
            return
        end
        INSTALLED = true
        start_heartbeat()
        install_index_hooks()
        L:info("position mask active (tol=%d/s)",
            cfg:get("masks.position.tolerance_per_sec", 60))
    end

    return M

end

end
__MODULES__['masks/walkspeed'] = function(require)
--[[ ================================================================
    src/masks/walkspeed.lua
    ------------------------
    Masks Humanoid.WalkSpeed both ways.

    READ (index hook):
        When the AC client-side reads Humanoid.WalkSpeed to report
        back, substitute a baseline value (default 16). Skipped if
        the caller is us (the main hub).

    WRITE (newindex hook):
        When any script (including ours) sets Humanoid.WalkSpeed to
        a suspicious value, we DON'T block: the main hub needs the
        write to take effect locally. But we do bump a counter and
        journal the stack trace, so the profile_spoof module can
        later down-clamp the value before it's sent in UpdateProfile.

        If the write comes from an untrusted external cheat and the
        config says so, we MUTATE the value to something safe. The
        default shipped config only blocks the read, not the write;
        the write block is opt-in since it will also disable our
        own speed feature.
================================================================ ]]

return function(require)

    local env    = require("core/env")
    local log    = require("core/log")
    local cfg    = require("core/config")
    local state  = require("core/state")

    local newindex = require("hooks/newindex")
    local index    = require("hooks/index")

    local M = {}
    local L = log.scoped("masks/walkspeed")

    local BASELINE = cfg:get("masks.walkspeed.baseline", 16)

    local function caller_is_us()
        -- hub threads mark themselves via _G.__GRG_THREAD.
        if _G.__GRG_THREAD then return true end
        if env.ckcaller then
            local ok, v = pcall(env.ckcaller)
            if ok and v then return true end
        end
        return false
    end

    local function is_humanoid_ref(obj)
        if type(obj) ~= "userdata" then return false end
        local ok, is = pcall(function() return obj:IsA("Humanoid") end)
        return ok and is
    end

    function M.install()
        if not cfg:get("masks.walkspeed.enabled", true) then
            L:info("disabled via config")
            return
        end

        -- Read mask -----------------------------------------------
        if cfg:get("masks.walkspeed.mask_read", true) then
            index.register({
                name     = "mask_ws_read",
                class    = "Humanoid",
                property = "WalkSpeed",
                priority = 30,
                handler  = function(ctx)
                    if cfg:get("masks.walkspeed.allow_if_caller_is_us", true)
                       and caller_is_us() then
                        return
                    end
                    ctx.spoof_value = cfg:get("masks.walkspeed.baseline", BASELINE)
                    ctx.spoofed = true
                    state:bump("walkspeed_read_masked")
                end,
            })
        end

        -- Write interceptor ---------------------------------------
        newindex.register({
            name     = "mask_ws_write",
            class    = "Humanoid",
            property = "WalkSpeed",
            priority = 30,
            handler  = function(ctx)
                -- We record every write so the raptor_alibi module
                -- can later claim it was the engine's own movement
                -- controller.
                state:set_last("last_walkspeed_set", ctx.value)
                state:set_last("last_walkspeed_set_time", tick())
                if debug and type(debug.info) == "function" then
                    local ok, src = pcall(debug.info, 2, "s")
                    if ok then state:set_last("last_walkspeed_set_src", src) end
                end

                if not cfg:get("masks.walkspeed.mask_write", false) then
                    return
                end

                -- Clamp external writes only.
                if caller_is_us() then return end

                local cap = cfg:get("masks.walkspeed.baseline", BASELINE)
                local jitter = cfg:get("masks.walkspeed.random_jitter", 0)
                if type(ctx.value) == "number" and ctx.value > cap + jitter + 0.01 then
                    local jittered = cap + (jitter > 0 and (math.random() * jitter) or 0)
                    L:debug("clamped external WalkSpeed write %.2f -> %.2f",
                        ctx.value, jittered)
                    ctx.value = jittered
                    state:bump("walkspeed_write_masked")
                end
            end,
        })

        -- Newly-spawned Humanoid: register AttributeChanged listeners
        -- so we can react when some scripts use attributes to carry
        -- walk speed (a common pattern in role-based games).
        if env.Players and env.LocalPlayer then
            local function attach(char)
                if not char then return end
                local h = char:FindFirstChildOfClass("Humanoid")
                if not h then return end
                -- Nothing to attach; the write hook above covers the
                -- .WalkSpeed property. This exists as a hook point
                -- for future enhancements (attribute-based speed).
            end
            attach(env.LocalPlayer.Character)
            env.LocalPlayer.CharacterAdded:Connect(attach)
        end

        L:info("walkspeed mask active (baseline=%d)",
            cfg:get("masks.walkspeed.baseline", BASELINE))
    end

    function M.set_baseline(v)
        cfg:set("masks.walkspeed.baseline", tonumber(v) or BASELINE)
    end

    function M.get_baseline()
        return cfg:get("masks.walkspeed.baseline", BASELINE)
    end

    return M

end

end
__MODULES__['netgate/jitter'] = function(require)
--[[ ================================================================
    src/netgate/jitter.lua
    -----------------------
    Wiring module that adds a random delay budget to outgoing
    FireServer traffic via fire_handlers.on_any at priority 85.

    Blocking inside a namecall hook delays the CALLING script's
    thread, which is visible to AC (it can measure how long a
    remote:FireServer() took). We want AC to NOT see extra latency
    on the call site; instead we emit a DETACHED jitter timer per
    fire so our own telemetry / accompanying decoys (velocity decoy,
    position decoy) trigger at humanized cadence.

    So:
        - The fire itself is not delayed (ctx flows through).
        - We spawn a coroutine via task.spawn / coroutine.wrap that
          does the random wait, then bumps state:bump("jitter_delays")
          and fires any registered "after-jitter" callbacks (opt-in
          from other modules that wanted a random lead-in).

    Other modules register delayed hooks via M.on_fire_delay(cb).
    The cb receives (ctx_snapshot, waited_ms).

    Config:
        netgate.jitter.enabled  (bool, default false)
        netgate.jitter.min_ms   (number, default 0)
        netgate.jitter.max_ms   (number, default 10)
================================================================ ]]

return function(require)

    local env   = require("core/env")
    local log   = require("core/log")
    local cfg   = require("core/config")
    local state = require("core/state")

    local fire     = require("hooks/fire_handlers")
    local j_prim   = require("timing/jitter")

    local M = {}
    local L = log.scoped("netgate/jitter")

    local LISTENERS = {}
    local INSTALLED = false

    local task_spawn = (type(task) == "table" and type(task.spawn) == "function") and task.spawn or nil

    local function spawn(fn)
        if task_spawn then return task_spawn(fn) end
        return coroutine.wrap(fn)()
    end

    local function snapshot_ctx(ctx)
        local ok, n = pcall(function() return ctx.remote and ctx.remote.Name end)
        return {
            remote_name = ok and n or "?",
            kind        = ctx.kind,
            n_args      = ctx.n_args,
            ts          = tick(),
        }
    end

    local function run_listeners(snap, waited_ms)
        for i = 1, #LISTENERS do
            local ok, err = pcall(LISTENERS[i], snap, waited_ms)
            if not ok then
                L:warn("after-jitter listener %d errored: %s", i, tostring(err))
            end
        end
    end

    function M.install()
        if INSTALLED then return end
        if not cfg:get("netgate.jitter.enabled", false) then
            L:info("disabled via config")
            return
        end
        INSTALLED = true

        fire.on_any({
            name     = "netgate_jitter",
            priority = 85,
            kind     = "FireServer",
            handler  = function(ctx)
                local mn = cfg:get("netgate.jitter.min_ms", 0)
                local mx = cfg:get("netgate.jitter.max_ms", 10)
                if mx <= 0 then return end
                local delay_ms = j_prim.pick(mn, mx)
                local snap = snapshot_ctx(ctx)
                spawn(function()
                    if delay_ms > 0 then
                        j_prim.wait(delay_ms, delay_ms)
                    end
                    state:bump("jitter_delays")
                    run_listeners(snap, delay_ms)
                end)
            end,
        })

        L:info("outgoing jitter armed (min=%sms max=%sms)",
            tostring(cfg:get("netgate.jitter.min_ms", 0)),
            tostring(cfg:get("netgate.jitter.max_ms", 10)))
    end

    function M.on_fire_delay(cb)
        if type(cb) ~= "function" then return false end
        table.insert(LISTENERS, cb)
        return #LISTENERS
    end

    function M.clear_listeners()
        for i = #LISTENERS, 1, -1 do LISTENERS[i] = nil end
    end

    function M.stats()
        return {
            enabled   = cfg:get("netgate.jitter.enabled", false),
            min_ms    = cfg:get("netgate.jitter.min_ms", 0),
            max_ms    = cfg:get("netgate.jitter.max_ms", 10),
            listeners = #LISTENERS,
            delays    = state:counter("jitter_delays"),
        }
    end

    return M

end

end
__MODULES__['netgate/rate_limiter'] = function(require)
--[[ ================================================================
    src/netgate/rate_limiter.lua
    -----------------------------
    Outgoing traffic rate limiter. Uses timing/rate_limit token-bucket
    primitives and wires a global default bucket onto every outgoing
    FireServer / InvokeServer via fire_handlers.on_any at priority 40
    (early enough that logger at 90 still sees the drop).

    Public:
        M.create(name, hz, burst) -> { allow = fn, stats = fn }
            Return a named bucket that callers can use for ad-hoc
            throttling. The registry is keyed by name so a second
            create() with the same name is idempotent.

        M.set_default(hz, burst)
            Rebuild the global outgoing bucket.

        M.stats()
            Return { named = {name->stats}, default = stats }.

    When the global bucket denies a fire, ctx.drop is set and the
    shared `rate_limit_drops` counter increments.
================================================================ ]]

return function(require)

    local env   = require("core/env")
    local log   = require("core/log")
    local cfg   = require("core/config")
    local state = require("core/state")

    local fire       = require("hooks/fire_handlers")
    local rate_prim  = require("timing/rate_limit")

    local M = {}
    local L = log.scoped("netgate/rate_limiter")

    local NAMED = {}
    local DEFAULT = { allow = nil, hz = 30, burst = 5 }
    local INSTALLED = false

    local function build_default()
        local hz    = cfg:get("netgate.rate_limiter.default_hz", 30)
        local burst = cfg:get("netgate.rate_limiter.burst", 5)
        DEFAULT.allow = rate_prim.token_bucket(hz, burst)
        DEFAULT.hz    = hz
        DEFAULT.burst = burst
        L:info("default bucket rebuilt: hz=%s burst=%s", tostring(hz), tostring(burst))
    end

    function M.create(name, hz, burst)
        if type(name) ~= "string" then
            error("netgate/rate_limiter: create needs a name", 2)
        end
        if NAMED[name] then
            return NAMED[name].handle
        end
        hz    = hz    or cfg:get("netgate.rate_limiter.default_hz", 30)
        burst = burst or cfg:get("netgate.rate_limiter.burst", 5)
        local allow = rate_prim.token_bucket(hz, burst)
        local handle = {
            name  = name,
            allow = function() return allow() end,
            stats = function() return rate_prim.stats_of(allow) end,
            reset = function() rate_prim.reset(allow) end,
            hz    = hz,
            burst = burst,
        }
        NAMED[name] = { allow = allow, handle = handle, hz = hz, burst = burst }
        L:debug("created named bucket '%s' hz=%s burst=%s",
            name, tostring(hz), tostring(burst))
        return handle
    end

    function M.get(name)
        local rec = NAMED[name]
        return rec and rec.handle or nil
    end

    function M.set_default(hz, burst)
        cfg:set("netgate.rate_limiter.default_hz", tonumber(hz) or 30)
        cfg:set("netgate.rate_limiter.burst",      tonumber(burst) or 5)
        build_default()
    end

    function M.install()
        if INSTALLED then return end
        if not cfg:get("netgate.rate_limiter.enabled", true) then
            L:info("disabled via config")
            return
        end
        INSTALLED = true
        build_default()

        fire.on_any({
            name     = "netgate_rate_limiter_default",
            priority = 40,
            kind     = "FireServer",
            handler  = function(ctx)
                if not DEFAULT.allow then return end
                if not DEFAULT.allow() then
                    ctx.drop = true
                    state:bump("rate_limit_drops")
                end
            end,
        })

        L:info("global FireServer rate limiter active")
    end

    function M.stats()
        local out = {
            default = DEFAULT.allow and rate_prim.stats_of(DEFAULT.allow) or nil,
            named   = {},
        }
        for k, rec in pairs(NAMED) do
            out.named[k] = rate_prim.stats_of(rec.allow)
        end
        return out
    end

    function M.reset_all()
        if DEFAULT.allow then rate_prim.reset(DEFAULT.allow) end
        for _, rec in pairs(NAMED) do rate_prim.reset(rec.allow) end
    end

    return M

end

end
__MODULES__['netgate/recv_scrubber'] = function(require)
--[[ ================================================================
    src/netgate/recv_scrubber.lua
    ------------------------------
    Late-stage (priority 90) wildcard hook on recv_handlers. Every
    incoming server event that survives scrubbers lands here so we can
    log its payload AND pattern-match for known "you are banned / you
    are shadowbanned / you will be kicked" signatures. If we match,
    we set ctx.drop=true so the original OnClientEvent callback never
    runs and the scripts that actually control the UI/teleport never
    see the payload.

    The bad-signature set is additive: callers can use
    M.add_bad_signature(key, value) to widen it at runtime. `value`
    may be:
        true          -> match if payload has that key at all
        string        -> exact equality
        table set     -> match if payload[key] is any of its values
        function(v)   -> predicate

    A second layer matches against strings anywhere in the args tuple
    (e.g. "You have been shadowbanned" as the first positional arg of
    a generic ServerMessage event).
================================================================ ]]

return function(require)

    local env    = require("core/env")
    local log    = require("core/log")
    local cfg    = require("core/config")
    local state  = require("core/state")

    local recv = require("hooks/recv_handlers")

    local M = {}
    local L = log.scoped("netgate/recv_scrubber")

    local JOURNAL_PREFIX = "recv_"
    local SUMMARY = {}
    local INSTALLED = false

    local KEY_SIGNATURES = {
        ban          = true,
        shadowbanned = true,
        kick         = true,
        kicked       = true,
        banned       = true,
        is_banned    = true,
    }

    local STRING_SIGNATURES = {
        "You have been",
        "You have been banned",
        "You have been kicked",
        "You are banned",
        "shadowban",
        "permanently banned",
    }

    local function stringify_shallow(v, budget)
        if budget <= 0 then return "..." end
        local t = type(v)
        if t == "string" then
            if #v > budget then return string.format("%q", v:sub(1, budget) .. "...") end
            return string.format("%q", v)
        elseif t == "number" or t == "boolean" or t == "nil" then
            return tostring(v)
        elseif t == "table" then
            local parts, left = {}, budget
            for k, vv in pairs(v) do
                if left <= 4 then table.insert(parts, "..."); break end
                local piece = tostring(k) .. "=" .. stringify_shallow(vv, math.floor(left / 2))
                left = left - #piece - 1
                table.insert(parts, piece)
            end
            return "{" .. table.concat(parts, ",") .. "}"
        elseif t == "userdata" then
            local ok, ty = pcall(typeof, v)
            return ok and (ty .. "<ud>") or "userdata"
        end
        return "<" .. t .. ">"
    end

    local function serialize_args(args_t, n_args, budget)
        local parts, used = {}, 0
        for i = 1, (n_args or #args_t) do
            local left = budget - used
            if left <= 0 then table.insert(parts, "..."); break end
            local piece = stringify_shallow(args_t[i], left)
            used = used + #piece + 2
            table.insert(parts, piece)
        end
        return table.concat(parts, ", ")
    end

    local function remote_key(remote)
        if typeof(remote) ~= "Instance" then return "?" end
        local ok, n = pcall(function() return remote.Name end)
        return ok and n or "?"
    end

    local function bump_summary(name, dropped)
        local s = SUMMARY[name]
        if not s then
            s = { count = 0, dropped = 0, last_ts = 0 }
            SUMMARY[name] = s
        end
        s.count = s.count + 1
        s.last_ts = tick()
        if dropped then s.dropped = s.dropped + 1 end
    end

    local function value_matches(expected, actual)
        if expected == true then return actual ~= nil end
        local te = type(expected)
        if te == "string" or te == "number" or te == "boolean" then
            return expected == actual
        elseif te == "function" then
            local ok, r = pcall(expected, actual)
            return ok and r and true or false
        elseif te == "table" then
            for _, e in ipairs(expected) do
                if e == actual then return true end
            end
        end
        return false
    end

    local function scan_table(t, depth)
        depth = depth or 0
        if depth > 3 or type(t) ~= "table" then return nil end
        for k, sig in pairs(KEY_SIGNATURES) do
            if t[k] ~= nil and value_matches(sig, t[k]) then
                return "key:" .. tostring(k)
            end
        end
        for _, v in pairs(t) do
            if type(v) == "string" then
                for _, needle in ipairs(STRING_SIGNATURES) do
                    if v:find(needle, 1, true) then
                        return "str:" .. needle
                    end
                end
            elseif type(v) == "table" then
                local sub = scan_table(v, depth + 1)
                if sub then return sub end
            end
        end
        return nil
    end

    local function scan_args(args, n)
        for i = 1, (n or #args) do
            local v = args[i]
            if type(v) == "string" then
                for _, needle in ipairs(STRING_SIGNATURES) do
                    if v:find(needle, 1, true) then
                        return "str:" .. needle
                    end
                end
            elseif type(v) == "table" then
                local r = scan_table(v, 0)
                if r then return r end
            end
        end
        return nil
    end

    function M.install()
        if INSTALLED then return end
        if not cfg:get("netgate.recv_scrubber.enabled", true) then
            L:info("disabled via config")
            return
        end
        INSTALLED = true

        recv.on_any({
            name     = "netgate_recv_scrubber",
            priority = 90,
            kind     = "OnClientEvent",
            handler  = function(ctx)
                local budget = cfg:get("netgate.recv_scrubber.log_bytes", 256)
                local name   = remote_key(ctx.remote)
                local serial = serialize_args(ctx.args, ctx.n_args, budget)
                local match  = scan_args(ctx.args, ctx.n_args)
                local entry  = {
                    ts     = tick(),
                    kind   = ctx.kind,
                    remote = name,
                    args   = serial,
                    match  = match,
                    dropped = false,
                }
                if match then
                    ctx.drop = true
                    entry.dropped = true
                    state:bump("recv_filtered")
                    L:warn("dropped %s: matched %s", name, match)
                end
                state:journal(JOURNAL_PREFIX .. name, entry)
                bump_summary(name, entry.dropped)
            end,
        })

        L:info("recv scrubber armed at priority 90")
    end

    function M.add_bad_signature(key, value)
        if type(key) ~= "string" then return false end
        KEY_SIGNATURES[key] = (value == nil) and true or value
        return true
    end

    function M.add_bad_string(needle)
        if type(needle) ~= "string" or needle == "" then return false end
        table.insert(STRING_SIGNATURES, needle)
        return true
    end

    function M.recent(remote_name, limit)
        local j = state.Journals[JOURNAL_PREFIX .. tostring(remote_name)]
        if not j then return {} end
        limit = limit or 20
        local out = {}
        local start = math.max(1, #j - limit + 1)
        for i = start, #j do table.insert(out, j[i]) end
        return out
    end

    function M.summary()
        local out = {}
        for k, v in pairs(SUMMARY) do
            out[k] = { count = v.count, dropped = v.dropped, last_ts = v.last_ts }
        end
        return out
    end

    function M.signatures()
        local keys, strs = {}, {}
        for k in pairs(KEY_SIGNATURES) do table.insert(keys, k) end
        for _, s in ipairs(STRING_SIGNATURES) do table.insert(strs, s) end
        return { keys = keys, strings = strs }
    end

    return M

end

end
__MODULES__['netgate/send_filter'] = function(require)
--[[ ================================================================
    src/netgate/send_filter.lua
    ----------------------------
    Late-stage (priority 90) wildcard hook on fire_handlers that logs
    every outgoing FireServer / InvokeServer call. The scrubber and
    mask modules live at priority 10..50; by the time WE see a fire,
    every upstream mutator has settled and what we record is the exact
    payload that will hit the wire.

    We:
      1. Build a compact key for the remote (name + class).
      2. Serialize up to cfg.log_bytes of args (JSON if HttpService,
         else a cheap home-grown stringifier).
      3. Append {ts, kind, bytes, serialized} to a per-remote journal.
      4. Bump Counters.send_filtered (shared with netgate/rate_limiter).
      5. Never MUTATE ctx. We're observation only.

    Queries:
        M.recent(name)   -> last-N journal entries for a remote
        M.summary()      -> map{ remote_name = {count, last_ts, bytes} }
        M.top(n)         -> most frequently fired remotes
================================================================ ]]

return function(require)

    local env    = require("core/env")
    local log    = require("core/log")
    local cfg    = require("core/config")
    local state  = require("core/state")

    local fire = require("hooks/fire_handlers")

    local M = {}
    local L = log.scoped("netgate/send_filter")

    local JOURNAL_PREFIX = "send_"
    local SUMMARY = {}
    local INSTALLED = false

    local function stringify(v, budget)
        if budget <= 0 then return "..." end
        local t = type(v)
        if t == "nil" then
            return "nil"
        elseif t == "string" then
            if #v > budget then return string.format("%q", v:sub(1, budget) .. "...") end
            return string.format("%q", v)
        elseif t == "number" or t == "boolean" then
            return tostring(v)
        elseif t == "userdata" then
            local ok, ty = pcall(typeof, v)
            if ok then
                if ty == "Instance" then
                    local okn, n = pcall(function() return v:GetFullName() end)
                    return "Instance<" .. (okn and n or "?") .. ">"
                end
                return ty .. "<ud>"
            end
            return "userdata"
        elseif t == "table" then
            local parts = {}
            local remaining = budget
            for k, val in pairs(v) do
                if remaining <= 4 then
                    table.insert(parts, "...")
                    break
                end
                local piece = tostring(k) .. "=" .. stringify(val, math.floor(remaining / 2))
                remaining = remaining - #piece - 1
                table.insert(parts, piece)
            end
            return "{" .. table.concat(parts, ",") .. "}"
        elseif t == "function" then
            return "<fn>"
        end
        return "<" .. t .. ">"
    end

    local function serialize_args(args_t, n_args, budget)
        local parts = {}
        local used = 0
        for i = 1, (n_args or #args_t) do
            local left = budget - used
            if left <= 0 then
                table.insert(parts, "...")
                break
            end
            local piece = stringify(args_t[i], left)
            used = used + #piece + 2
            table.insert(parts, piece)
        end
        return table.concat(parts, ", ")
    end

    local function remote_key(remote)
        if typeof(remote) ~= "Instance" then return "?" end
        local ok, n = pcall(function() return remote.Name end)
        return ok and n or "?"
    end

    local function remote_class(remote)
        if typeof(remote) ~= "Instance" then return "?" end
        local ok, c = pcall(function() return remote.ClassName end)
        return ok and c or "?"
    end

    local function bump_summary(name, bytes)
        local s = SUMMARY[name]
        if not s then
            s = { count = 0, last_ts = 0, bytes = 0 }
            SUMMARY[name] = s
        end
        s.count = s.count + 1
        s.last_ts = tick()
        s.bytes = s.bytes + bytes
    end

    function M.install()
        if INSTALLED then return end
        if not cfg:get("netgate.send_filter.enabled", true) then
            L:info("disabled via config")
            return
        end
        INSTALLED = true

        fire.on_any({
            name     = "netgate_send_filter",
            priority = 90,
            handler  = function(ctx)
                local budget = cfg:get("netgate.send_filter.log_bytes", 256)
                local name   = remote_key(ctx.remote)
                local class  = remote_class(ctx.remote)
                local serial = serialize_args(ctx.args, ctx.n_args, budget)
                local entry  = {
                    ts     = tick(),
                    kind   = ctx.kind,
                    remote = name,
                    class  = class,
                    args   = serial,
                    bytes  = #serial,
                    drop   = ctx.drop or false,
                }
                state:journal(JOURNAL_PREFIX .. name, entry)
                bump_summary(name, #serial)
                state:bump("send_filtered")
                if cfg:get("hooks.fire_handlers.log_every_call", false) then
                    L:debug("%s %s(%s)", ctx.kind, name, serial)
                end
            end,
        })

        L:info("send filter armed at priority 90")
    end

    function M.recent(remote_name, limit)
        local j = state.Journals[JOURNAL_PREFIX .. tostring(remote_name)]
        if not j then return {} end
        limit = limit or 20
        local out = {}
        local start = math.max(1, #j - limit + 1)
        for i = start, #j do
            table.insert(out, j[i])
        end
        return out
    end

    function M.summary()
        local out = {}
        for k, v in pairs(SUMMARY) do
            out[k] = { count = v.count, last_ts = v.last_ts, bytes = v.bytes }
        end
        return out
    end

    function M.top(n)
        n = n or 10
        local rows = {}
        for k, v in pairs(SUMMARY) do
            table.insert(rows, { name = k, count = v.count, bytes = v.bytes })
        end
        table.sort(rows, function(a, b) return a.count > b.count end)
        local out = {}
        for i = 1, math.min(n, #rows) do out[i] = rows[i] end
        return out
    end

    function M.clear()
        for k in pairs(SUMMARY) do SUMMARY[k] = nil end
        for k in pairs(state.Journals) do
            if type(k) == "string" and k:sub(1, #JOURNAL_PREFIX) == JOURNAL_PREFIX then
                state.Journals[k] = {}
            end
        end
    end

    return M

end

end
__MODULES__['sandbox/debug_info_mask'] = function(require)
--[[ ================================================================
    src/sandbox/debug_info_mask.lua
    --------------------------------
    Hooks both Luau `debug.info` AND Lua 5.1-style `debug.getinfo`.

    Games probing the stack use things like:

        local src  = debug.info(2, "s")
        local line = debug.info(2, "l")
        local name = debug.info(2, "n")
        if src:find("grg/") or name:find("^__grg") then kick() end

    Our hook (for foreign callers ONLY):
        "s" (source)  -> replace any path that names grg/ or our
                         module files with a benign Roblox path
                         from `sandbox.debug_info_mask.fake_source`.
        "l" (line)    -> clamp / replace with a plausible small int
                         (same request returns the same int so the
                         probe can't diff across calls).
        "n" (name)    -> if real name begins with `__grg_` or
                         `grg_`, rewrite to one of {update, step,
                         handle, render, onTick}.
        Other tokens pass through.

    For our own callers (checkcaller / __GRG_THREAD) we return the
    real info untouched.

    The patterns list is extendable:
        M.add_fake_pattern(real_pattern, fake_replacement)
================================================================ ]]

return function(require)

    local env    = require("core/env")
    local log    = require("core/log")
    local cfg    = require("core/config")
    local state  = require("core/state")
    local hookfn = require("hooks/hookfunction")

    local M = {}
    local L = log.scoped("sandbox/debug_info_mask")

    ----------------------------------------------------------------
    -- fake patterns
    ----------------------------------------------------------------

    local SOURCE_PATTERNS = {
        { "grg/anticheat/src/[%w_/%-%.]+%.lua", nil },  -- fake filled below
        { "opiumware",                          nil },
        { "MacSploit",                          nil },
        { "Raptor",                             nil },
        { "<anonymous>",                        nil },
    }

    local NEUTRAL_NAMES = {
        "update", "step", "handle", "render", "onTick",
        "tick", "updateAll", "process", "run",
    }

    function M.add_fake_pattern(real_pattern, fake)
        if type(real_pattern) ~= "string" then return false end
        SOURCE_PATTERNS[#SOURCE_PATTERNS + 1] = { real_pattern, fake }
        return true
    end

    ----------------------------------------------------------------
    -- caller detection
    ----------------------------------------------------------------

    local function caller_is_us()
        if _G.__GRG_THREAD then return true end
        if env.ckcaller then
            local ok, v = pcall(env.ckcaller)
            if ok and v then return true end
        end
        return false
    end

    -- Second-line defence: is the frame we're about to spoof ONE OF
    -- OURS? If so we always spoof; if not, don't bother (returning
    -- fake info for unrelated frames breaks the game too often).
    local function frame_is_ours(level)
        if type(debug) ~= "table" or type(debug.info) ~= "function" then
            return false
        end
        local ok, src = pcall(debug.info, (tonumber(level) or 1) + 1, "s")
        if not ok or type(src) ~= "string" then return false end
        if string.find(src, "grg/",     1, true) then return true end
        if string.find(src, "anticheat", 1, true) then return true end
        if string.find(src, "opiumware",1, true) then return true end
        return false
    end

    ----------------------------------------------------------------
    -- source/name munging helpers
    ----------------------------------------------------------------

    local function fake_source()
        return cfg:get("sandbox.debug_info_mask.fake_source",
            "CoreGui.RobloxGui.Modules.Common.MovementController")
    end

    local function rewrite_source(s)
        if type(s) ~= "string" then return s end
        local fs = fake_source()
        local changed = false
        for _, rule in ipairs(SOURCE_PATTERNS) do
            local replacement = rule[2] or fs
            local new, n = string.gsub(s, rule[1], replacement)
            if n > 0 then
                s = new
                changed = true
            end
        end
        if changed then return s end
        -- If the real source still references our directory, nuke
        -- the whole string.
        if string.find(s, "grg/", 1, true) then return fs end
        return s
    end

    local function rewrite_name(n)
        if type(n) ~= "string" then return n end
        if string.sub(n, 1, 6) == "__grg_" or string.sub(n, 1, 4) == "grg_"
           or string.sub(n, 1, 4) == "GRG_" then
            local idx = (math.random(1, #NEUTRAL_NAMES))
            return NEUTRAL_NAMES[idx]
        end
        return n
    end

    local function plausible_line()
        -- Deterministic per-call plausibility: a random int 1..300.
        return math.random(1, 300)
    end

    ----------------------------------------------------------------
    -- rewrite engine for debug.info (Luau, variadic "what" string)
    ----------------------------------------------------------------

    local function rewrite_info_results(what, ret)
        if type(what) ~= "string" then return ret end
        -- debug.info returns one result per char in `what`; the
        -- results sit in ret[1..n]. Walk the what string and poke
        -- the matching slot.
        local i = 0
        for c in string.gmatch(what, ".") do
            i = i + 1
            local v = ret[i]
            if c == "s" then
                ret[i] = rewrite_source(v)
            elseif c == "l" then
                if type(v) == "number" and v > 0 then
                    ret[i] = plausible_line()
                end
            elseif c == "n" then
                ret[i] = rewrite_name(v)
            end
        end
        return ret
    end

    ----------------------------------------------------------------
    -- rewrite engine for debug.getinfo (Lua 5.1, returns a table)
    ----------------------------------------------------------------

    local function rewrite_getinfo_result(tbl)
        if type(tbl) ~= "table" then return tbl end
        if tbl.source          then tbl.source          = rewrite_source(tbl.source) end
        if tbl.short_src       then tbl.short_src       = rewrite_source(tbl.short_src) end
        if tbl.name            then tbl.name            = rewrite_name(tbl.name) end
        if tbl.currentline and type(tbl.currentline) == "number" and tbl.currentline > 0 then
            tbl.currentline = plausible_line()
        end
        if tbl.linedefined and type(tbl.linedefined) == "number" and tbl.linedefined > 0 then
            tbl.linedefined = plausible_line()
        end
        return tbl
    end

    ----------------------------------------------------------------
    -- install
    ----------------------------------------------------------------

    local installed = false

    function M.install()
        if not cfg:get("sandbox.debug_info_mask.enabled", true) then
            L:info("disabled via config")
            return
        end
        if installed then
            L:debug("already installed")
            return
        end
        if type(debug) ~= "table" then
            L:warn("debug table missing; skipping")
            return
        end

        local hooked_any = false

        if type(debug.info) == "function" then
            local id = hookfn.hook(debug, "info", {
                name     = "sandbox_debug_info_mask",
                priority = 20,
                handler  = function(ctx)
                    if caller_is_us() then return end
                    local level = ctx.args[1]
                    local what  = ctx.args[2]
                    if type(level) ~= "number" then return end
                    if level < 1 then return end
                    if not frame_is_ours(level) then return end
                    ctx.after = function(ret)
                        rewrite_info_results(what, ret)
                        state:bump("sandbox_debug_info_masked")
                        return ret
                    end
                end,
            })
            if id then hooked_any = true end
        end

        if type(debug.getinfo) == "function" then
            local id2 = hookfn.hook(debug, "getinfo", {
                name     = "sandbox_debug_getinfo_mask",
                priority = 20,
                handler  = function(ctx)
                    if caller_is_us() then return end
                    local level = ctx.args[1]
                    if type(level) ~= "number" or level < 1 then return end
                    if not frame_is_ours(level) then return end
                    ctx.after = function(ret)
                        ret[1] = rewrite_getinfo_result(ret[1])
                        state:bump("sandbox_debug_getinfo_masked")
                        return ret
                    end
                end,
            })
            if id2 then hooked_any = true end
        end

        if hooked_any then
            installed = true
            L:info("debug_info_mask active (fake_source=%q)", fake_source())
        else
            L:warn("no debug.* hooks installed")
        end
    end

    return M

end

end
__MODULES__['sandbox/env_shuffle'] = function(require)
--[[ ================================================================
    src/sandbox/env_shuffle.lua
    ----------------------------
    Wraps our script's _ENV (and a shadow view of _G) behind a proxy
    table so foreign threads that walk the environment don't see our
    telltale keys.

    What AC scripts actually do:
        * `for k, v in pairs(getfenv(level)) do ... end`
        * `for k, v in pairs(_G) do ... end`
        * `rawget(_G, "GRG_HUB_LOADED")`

    We can't reasonably hide every one of our keys from every code
    path, but we can:
        1. Replace our own _ENV with a proxy whose __index/__newindex
           forward to a real store (so our code still works);
        2. Interpose a __metatable marker so getrawmetatable isn't
           obviously suspicious;
        3. Override pairs/next behaviour via the proxy's __iter and
           __pairs metamethods. When a FOREIGN thread iterates us,
           we skip keys matching the hide-list and optionally shuffle
           the remaining keys so the order carries no info.

    This is defence-in-depth, NOT a full shield: a caller with raw
    access via getgenv() will still see us. It's enough to defeat
    naive "scan my env for GRG" scripts.
================================================================ ]]

return function(require)

    local env    = require("core/env")
    local log    = require("core/log")
    local cfg    = require("core/config")
    local state  = require("core/state")
    local hookfn = require("hooks/hookfunction")

    local M = {}
    local L = log.scoped("sandbox/env_shuffle")

    -- Static list of keys we always want hidden when a foreign thread
    -- enumerates our env. Config-driven additions go into `extra_hidden`.
    local HIDDEN = {
        __GRG_THREAD        = true,
        __GRG_HUB_LOADED    = true,
        __GRG_BOOT_STAMP    = true,
        __GRG_REGISTRY      = true,
        GRG_HUB_LOADED      = true,
        GRG                 = true,
    }

    local extra_hidden = {}

    local function is_hidden(k)
        if type(k) ~= "string" then return false end
        if HIDDEN[k] or extra_hidden[k] then return true end
        -- Catch-all prefixes that we use throughout the codebase.
        if string.sub(k, 1, 4) == "GRG_"   then return true end
        if string.sub(k, 1, 6) == "__GRG_" then return true end
        if string.sub(k, 1, 4) == "grg_"   then return true end
        return false
    end

    function M.hide_key(name)
        if type(name) == "string" then extra_hidden[name] = true end
    end

    function M.reveal_key(name)
        if type(name) == "string" then extra_hidden[name] = nil end
    end

    ----------------------------------------------------------------
    -- foreign-caller detection
    ----------------------------------------------------------------

    local function caller_is_us()
        if _G.__GRG_THREAD then return true end
        if env.ckcaller then
            local ok, v = pcall(env.ckcaller)
            if ok and v then return true end
        end
        return false
    end

    ----------------------------------------------------------------
    -- shuffled-iterator builder
    ----------------------------------------------------------------

    local function shuffled_keys(tbl)
        local keys = {}
        for k in pairs(tbl) do
            if not is_hidden(k) then keys[#keys + 1] = k end
        end
        local n = #keys
        for i = n, 2, -1 do
            local j = math.random(1, i)
            keys[i], keys[j] = keys[j], keys[i]
        end
        return keys
    end

    local function filtered_keys(tbl)
        local keys = {}
        for k in pairs(tbl) do
            if not is_hidden(k) then keys[#keys + 1] = k end
        end
        return keys
    end

    ----------------------------------------------------------------
    -- proxy construction
    ----------------------------------------------------------------

    local installed = false

    local function build_proxy(real_env)
        local proxy = {}
        local mt = {}

        function mt.__index(_, k)
            return real_env[k]
        end

        function mt.__newindex(_, k, v)
            real_env[k] = v
        end

        mt.__metatable = "table"

        -- Luau extension: __iter controls generic for.
        function mt.__iter(_)
            local shuffle = cfg:get("sandbox.env_shuffle.shuffle_keys", false)
            if caller_is_us() then
                -- Our code sees the real env, natural order.
                return next, real_env, nil
            end
            local keys = shuffle and shuffled_keys(real_env) or filtered_keys(real_env)
            local i = 0
            return function()
                i = i + 1
                local k = keys[i]
                if k == nil then return nil end
                return k, real_env[k]
            end
        end

        -- Lua 5.1 fallback used by `pairs` via __pairs if patched.
        function mt.__pairs(_)
            local shuffle = cfg:get("sandbox.env_shuffle.shuffle_keys", false)
            if caller_is_us() then
                return next, real_env, nil
            end
            local keys = shuffle and shuffled_keys(real_env) or filtered_keys(real_env)
            local i = 0
            local function iter()
                i = i + 1
                local k = keys[i]
                if k == nil then return nil end
                return k, real_env[k]
            end
            return iter, proxy, nil
        end

        function mt.__len(_)
            local n = 0
            for k in pairs(real_env) do
                if not is_hidden(k) then n = n + 1 end
            end
            return n
        end

        setmetatable(proxy, mt)
        return proxy, mt
    end

    function M.install()
        if not cfg:get("sandbox.env_shuffle.enabled", true) then
            L:info("disabled via config")
            return
        end
        if installed then
            L:debug("already installed")
            return
        end

        local real_env = getfenv(0)
        if type(real_env) ~= "table" then
            L:warn("getfenv(0) returned %s; cannot proxy", type(real_env))
            return
        end

        -- We don't swap the top-level env (that would brick the
        -- executor); instead we rely on the traceback/getfenv masks
        -- for foreign readers, and only swap our MODULE env so that
        -- a foreign thread calling getfenv on one of our frames
        -- gets the proxy with its hidden keys.
        local mod_env = getfenv(1)
        if type(mod_env) ~= "table" then
            L:warn("getfenv(1) returned %s; skipping module swap", type(mod_env))
        else
            local proxy = build_proxy(mod_env)
            pcall(setfenv, 1, proxy)
        end

        state:bump("sandbox_env_shuffle_installed")
        installed = true
        L:info("env_shuffle active (shuffle_keys=%s)",
            tostring(cfg:get("sandbox.env_shuffle.shuffle_keys", false)))
    end

    return M

end

end
__MODULES__['sandbox/getfenv_mask'] = function(require)
--[[ ================================================================
    src/sandbox/getfenv_mask.lua
    -----------------------------
    Intercepts global `getfenv`.

    Games' AC code uses getfenv() to snapshot an arbitrary frame's
    upvalue environment looking for fingerprints:

        local e = getfenv(2)
        if e.GRG_HUB_LOADED or e.__grg_state then
            kick("cheat")
        end

    Our hook:
        * level == 0 (current thread's real env): pass through
          UNTOUCHED. Faking level 0 breaks way too many things.
        * level >= 1 foreign caller: copy the real env, drop every
          key that matches our filter list, salt in a few vanilla
          Roblox-looking keys so the result doesn't look empty.

    If the caller IS us, we also pass through untouched so our own
    telemetry stays accurate.

    Exposes `M.add_filter(pattern)` so other modules can append new
    key-patterns to hide (e.g. raptor_alibi registers its own).
================================================================ ]]

return function(require)

    local env    = require("core/env")
    local log    = require("core/log")
    local cfg    = require("core/config")
    local state  = require("core/state")
    local hookfn = require("hooks/hookfunction")

    local M = {}
    local L = log.scoped("sandbox/getfenv_mask")

    ----------------------------------------------------------------
    -- filter patterns
    ----------------------------------------------------------------

    local FILTERS = {
        "^GRG_",
        "^__GRG_",
        "^grg_",
        "^__grg_",
        "^Raptor",
        "^OPIUM_",
    }

    function M.add_filter(pattern)
        if type(pattern) == "string" then
            FILTERS[#FILTERS + 1] = pattern
        end
    end

    local function matches_filter(k)
        if type(k) ~= "string" then return false end
        for _, p in ipairs(FILTERS) do
            if string.find(k, p) then return true end
        end
        return false
    end

    ----------------------------------------------------------------
    -- decoy keys: added to the sanitized copy so it looks populated.
    ----------------------------------------------------------------

    local function decoys()
        return {
            script    = nil,     -- filled from real env if present
            game      = game,
            workspace = workspace,
            Enum      = Enum,
            Instance  = Instance,
            math      = math,
            string    = string,
            table     = table,
            print     = print,
            warn      = warn,
            tick      = tick,
            task      = task,
            typeof    = typeof,
            wait      = wait,
        }
    end

    ----------------------------------------------------------------
    -- sanitize
    ----------------------------------------------------------------

    local function sanitize(real_env)
        if type(real_env) ~= "table" then return real_env end
        local out = {}

        for k, v in pairs(real_env) do
            if not matches_filter(k) then
                out[k] = v
            end
        end

        -- Seed decoys only where the real env doesn't already have
        -- something; we don't want to OVERWRITE a real `script`.
        for k, v in pairs(decoys()) do
            if out[k] == nil and v ~= nil then
                out[k] = v
            end
        end

        return out
    end

    ----------------------------------------------------------------
    -- caller detection
    ----------------------------------------------------------------

    local function caller_is_us()
        if _G.__GRG_THREAD then return true end
        if env.ckcaller then
            local ok, v = pcall(env.ckcaller)
            if ok and v then return true end
        end
        return false
    end

    ----------------------------------------------------------------
    -- install
    ----------------------------------------------------------------

    local installed = false

    function M.install()
        if not cfg:get("sandbox.getfenv_mask.enabled", true) then
            L:info("disabled via config")
            return
        end
        if installed then
            L:debug("already installed")
            return
        end

        local g = getfenv(0)
        if type(g.getfenv) ~= "function" then
            L:warn("global getfenv missing; skipping")
            return
        end

        local id = hookfn.hook_global("getfenv", {
            name     = "sandbox_getfenv_mask",
            priority = 20,
            handler  = function(ctx)
                if caller_is_us() then return end

                local level = ctx.args[1]
                if level == 0 or level == nil then
                    -- Too risky to fake; let it through.
                    return
                end
                if type(level) == "number" and level < 0 then
                    return
                end

                -- We rewrite the result via ctx.after.
                ctx.after = function(ret)
                    local real = ret[1]
                    if type(real) ~= "table" then return ret end
                    local ok, clean = pcall(sanitize, real)
                    if ok and type(clean) == "table" then
                        state:bump("sandbox_getfenv_masked")
                        ret[1] = clean
                    end
                    return ret
                end
            end,
        })

        if id then
            installed = true
            L:info("getfenv_mask active (id=%s, filters=%d)",
                tostring(id), #FILTERS)
        else
            L:warn("hook install failed")
        end
    end

    return M

end

end
__MODULES__['sandbox/traceback_rewrite'] = function(require)
--[[ ================================================================
    src/sandbox/traceback_rewrite.lua
    ----------------------------------
    Hooks `debug.traceback`.

    AC scripts commonly do:

        local tb = debug.traceback("", 2)
        if tb:find("Raptor") or tb:find("anonymous") then
            report("cheat detected")
        end

    Our strategy: call the real traceback, then scrub any line that
    carries our module names, executor thread markers, or Roblox
    "anonymous script" tells, and replace them with a benign call
    chain terminating in a Roblox-shipped module. The net effect:
    a traceback that looks like the game's own movement controller
    doing something innocuous.

    If the caller is us (checkcaller / __GRG_THREAD), we return the
    REAL traceback so our own logs stay useful.

    The rewrite list is data-driven; modules can call
    `M.add_rewrite(pattern, replacement)` to register more.

    Two knobs via config:
        sandbox.traceback_rewrite.enabled  (bool)
        sandbox.debug_info_mask.fake_source (string, reused as the
            terminating line's source)
================================================================ ]]

return function(require)

    local env    = require("core/env")
    local log    = require("core/log")
    local cfg    = require("core/config")
    local state  = require("core/state")
    local hookfn = require("hooks/hookfunction")

    local M = {}
    local L = log.scoped("sandbox/traceback_rewrite")

    ----------------------------------------------------------------
    -- rewrite table
    ----------------------------------------------------------------

    local REWRITES = {
        -- { pattern, replacement }
        { "Raptor%.Thread",                 "RobloxGui.Modules.PlayerList" },
        { "Script '<anonymous>'",           "Script 'CoreGui.RobloxGui.Modules.Common.MovementController'" },
        { "anonymous",                      "MovementController" },
        { "GRG_%w+",                        "PlayerController" },
        { "grg/anticheat/src/[%w_/]+%.lua", "CoreGui.RobloxGui.Modules.Common.MovementController" },
        { "opiumware",                      "Roblox" },
        { "MacSploit",                      "Roblox" },
        { "in function <[^>]+>",            "in function <MovementController>" },
        { "thread at 0x[%x]+",              "thread at 0x00000000" },
    }

    function M.add_rewrite(pattern, replacement)
        if type(pattern) ~= "string" or type(replacement) ~= "string" then
            return false
        end
        REWRITES[#REWRITES + 1] = { pattern, replacement }
        return true
    end

    ----------------------------------------------------------------
    -- caller detection
    ----------------------------------------------------------------

    local function caller_is_us()
        if _G.__GRG_THREAD then return true end
        if env.ckcaller then
            local ok, v = pcall(env.ckcaller)
            if ok and v then return true end
        end
        return false
    end

    ----------------------------------------------------------------
    -- rewrite engine
    ----------------------------------------------------------------

    local function scrub_line(line)
        local out = line
        for _, rule in ipairs(REWRITES) do
            out = string.gsub(out, rule[1], rule[2])
        end
        return out
    end

    local function rewrite_full(tb)
        if type(tb) ~= "string" or tb == "" then return tb end
        local fake_tail = cfg:get("sandbox.debug_info_mask.fake_source",
            "CoreGui.RobloxGui.Modules.Common.MovementController")

        local lines = {}
        for chunk in string.gmatch(tb, "([^\n]*)\n?") do
            -- Some Luau tracebacks put the source between quotes; we
            -- treat each chunk uniformly.
            if chunk ~= "" then
                lines[#lines + 1] = scrub_line(chunk)
            end
        end

        -- Drop obvious self-references: any line still naming a grg/*
        -- module after the first pass is dropped entirely.
        local kept = {}
        for i = 1, #lines do
            local l = lines[i]
            if not (string.find(l, "grg/", 1, true)
                 or string.find(l, "anticheat", 1, true)) then
                kept[#kept + 1] = l
            end
        end

        -- If we ended up with nothing, synthesise a plausible tail so
        -- the caller doesn't get an empty string (suspicious in itself).
        if #kept == 0 then
            kept[1] = "Stack Begin"
            kept[2] = string.format("Script '%s', Line 1", fake_tail)
            kept[3] = "Stack End"
        end

        return table.concat(kept, "\n")
    end

    ----------------------------------------------------------------
    -- install
    ----------------------------------------------------------------

    local installed = false

    function M.install()
        if not cfg:get("sandbox.traceback_rewrite.enabled", true) then
            L:info("disabled via config")
            return
        end
        if installed then
            L:debug("already installed")
            return
        end
        if type(debug) ~= "table" or type(debug.traceback) ~= "function" then
            L:warn("debug.traceback unavailable; skipping")
            return
        end

        local id = hookfn.hook(debug, "traceback", {
            name     = "sandbox_traceback_rewrite",
            priority = 20,
            handler  = function(ctx)
                -- Let our own callers pass through untouched.
                if caller_is_us() then return end

                -- We rewrite the RESULT, not the args, so set ctx.after.
                ctx.after = function(ret)
                    local first = ret[1]
                    if type(first) == "string" then
                        local rewritten = rewrite_full(first)
                        if rewritten ~= first then
                            state:bump("sandbox_traceback_rewritten")
                            ret[1] = rewritten
                        end
                    end
                    return ret
                end
            end,
        })

        if id then
            installed = true
            L:info("traceback_rewrite active (id=%s, rules=%d)",
                tostring(id), #REWRITES)
        else
            L:warn("hook install failed")
        end
    end

    return M

end

end
__MODULES__['scrubbers/coregui_warning'] = function(require)
--[[ ================================================================
    src/scrubbers/coregui_warning.lua
    ----------------------------------
    Hides the cosmetic AC warning surface from the user:
        * ScreenGuis under CoreGui / PlayerGui with warning-ish
          names (Warn*, Ban*, Kick*, Flag*, Error*).
        * StarterGui:SetCore("SendNotification", {...}) calls with
          warning Title/Text.
        * SoundService.Played events whose SoundId is in the
          configured blocklist (classic "ding ding ding" alert).

    We chose pattern-based gui sweeps rather than hooking the AC
    constructor directly because the AC has multiple paths that
    spawn an overlay (ModuleScript:require, LocalScript:Clone,
    DataStore-driven runtime construction...), and name-pattern
    matching is a lot cheaper to maintain across AC updates than
    chasing every spawn path.
================================================================ ]]

return function(require)
    local env      = require("core/env")
    local log      = require("core/log")
    local cfg      = require("core/config")
    local state    = require("core/state")
    local namecall = require("hooks/namecall")

    local M = {}
    local L = log.scoped("scrubbers/coregui_warning")

    -- ----------------------------------------------------------------
    -- name / text patterns
    -- ----------------------------------------------------------------

    local PATTERNS = {
        "Warn",
        "Ban",
        "Kick",
        "Flag",
        "Error",
        "AntiCheat",
        "ShadowBan",
    }

    local TEXT_PATTERNS = {
        "flagged",
        "shadow",
        "banned",
        "kicked",
        "AntiCheat",
        "suspicious",
    }

    local function matches_any(s, list)
        if type(s) ~= "string" then return false end
        for _, p in ipairs(list) do
            local ok, f = pcall(string.find, s, p)
            if ok and f then return true, p end
        end
        return false
    end

    -- ----------------------------------------------------------------
    -- gui sweep
    -- ----------------------------------------------------------------

    local function sweep_container(c)
        if not c then return 0 end
        local killed = 0
        for _, ch in ipairs(c:GetChildren()) do
            local ok, nm = pcall(function() return ch.Name end)
            if ok and matches_any(nm, PATTERNS) then
                local okD = pcall(function() ch:Destroy() end)
                if okD then
                    killed = killed + 1
                    state:bump("coregui_warning_blocked")
                    L:warn("deleted warning gui '%s' in %s",
                        nm, tostring(c))
                end
            end
        end
        return killed
    end

    local SWEEP_TIMER = 0
    local function on_heartbeat(dt)
        SWEEP_TIMER = SWEEP_TIMER + (dt or 0)
        if SWEEP_TIMER < 1.0 then return end
        SWEEP_TIMER = 0
        if not cfg:get("scrubbers.coregui_warning.block_warning_gui", true) then
            return
        end
        pcall(sweep_container, env.CoreGui)
        pcall(sweep_container, env.PlayerGui
            or (env.LocalPlayer and env.LocalPlayer:FindFirstChild("PlayerGui")))
    end

    -- ----------------------------------------------------------------
    -- SetCore SendNotification hook
    -- ----------------------------------------------------------------

    local function hook_setcore()
        namecall.register({
            name     = "scrub_sendnotification",
            priority = 25,
            method   = "SetCore",
            class    = "StarterGui",
            handler  = function(ctx)
                local topic = ctx.args[1]
                if topic ~= "SendNotification" then return end
                local payload = ctx.args[2]
                if type(payload) ~= "table" then return end

                local title = payload.Title or payload.title or ""
                local text  = payload.Text  or payload.text  or ""
                local hit_title, _ = matches_any(title, TEXT_PATTERNS)
                local hit_text,  _ = matches_any(text,  TEXT_PATTERNS)
                if hit_title or hit_text then
                    ctx.drop = true
                    state:bump("coregui_warning_blocked")
                    L:warn("blocked SendNotification title=%q",
                        tostring(title))
                end
            end,
        })
    end

    -- ----------------------------------------------------------------
    -- Sound blocklist
    -- ----------------------------------------------------------------

    local function hook_soundservice()
        if not env.SoundService then return end
        local ok, played = pcall(function() return env.SoundService.Played end)
        if not ok or not played then return end

        pcall(function()
            played:Connect(function(sound)
                if not cfg:get("scrubbers.coregui_warning.block_warning_sound", true) then
                    return
                end
                local sid = nil
                local ok_id, v = pcall(function() return sound.SoundId end)
                if ok_id then sid = v end
                if type(sid) ~= "string" then return end
                local list = cfg:get(
                    "silencers.sound_block.sound_id_blocklist", {})
                if type(list) ~= "table" then return end
                for _, blocked in ipairs(list) do
                    if sid == blocked then
                        pcall(function() sound:Stop() end)
                        state:bump("coregui_warning_blocked")
                        L:warn("stopped blocklisted sound %s", sid)
                        return
                    end
                end
            end)
        end)
    end

    function M.install()
        if not cfg:get("scrubbers.coregui_warning.enabled", true) then
            L:info("disabled via config")
            return
        end

        hook_setcore()
        hook_soundservice()

        if env.RunService then
            env.RunService.Heartbeat:Connect(function(dt)
                local ok, err = pcall(on_heartbeat, dt)
                if not ok then L:warn("sweep err: %s", tostring(err)) end
            end)
        end

        L:info("coregui_warning scrubber active")
    end

    -- ----------------------------------------------------------------
    -- public helpers
    -- ----------------------------------------------------------------

    function M.add_pattern(pat)
        if type(pat) ~= "string" then return false end
        for _, p in ipairs(PATTERNS) do
            if p == pat then return false end
        end
        table.insert(PATTERNS, pat)
        return true
    end

    function M.remove_pattern(pat)
        for i, p in ipairs(PATTERNS) do
            if p == pat then
                table.remove(PATTERNS, i)
                return true
            end
        end
        return false
    end

    function M.add_text_pattern(pat)
        if type(pat) ~= "string" then return false end
        table.insert(TEXT_PATTERNS, pat)
        return true
    end

    function M.patterns() return PATTERNS end
    function M.text_patterns() return TEXT_PATTERNS end
    function M.block_count() return state:counter("coregui_warning_blocked") end

    return M
end

end
__MODULES__['scrubbers/kick'] = function(require)
--[[ ================================================================
    src/scrubbers/kick.lua
    -----------------------
    Last-line-of-defence scrubber for Player:Kick. The hostile GRG
    server fires Player:Kick as the final step of its AC pipeline
    whenever earlier signals (ShadowBan, Ragdoll, UpdateProfile
    deltas) trip in a way the server deems terminal. Letting even
    ONE of those kicks through is a run-ending event for the user,
    so this module is the hardest of the scrubbers: default-deny.

    Path taken:
        * Install a namecall handler at priority 15 (runs before
          the generic fire_handlers dispatch so kicks never reach
          a remote layer -- Player:Kick is a direct instance call,
          not a RemoteEvent, but we sit above that layer anyway).
        * Match on class = "Player" method = "Kick". That covers
          both LocalPlayer:Kick and other Player objects (pre-2022
          Roblox shipped Kick on Player, not just LocalPlayer).
        * On each hit we:
            - Capture caller source via debug.info(2, "s").
            - Check the cfg-driven whitelist of allowed reasons
              (string.find pattern match, case-insensitive).
            - Consume the one-shot `allow_next_kick` token if
              present (used by integrity/recovery self-kick).
            - Otherwise set ctx.drop = true, bump counters,
              journal the event, emit KickBlocked signal.

    Whitelist behaviour: patterns are string.find patterns, so
    `^Update` matches any reason starting with "Update". An empty
    whitelist means drop everything.

    Design note: we never reply to the server about the drop. The
    client-side Kick has no server-side round-trip; it just closes
    the client. Silent drop is the correct posture.
================================================================ ]]

return function(require)
    local env      = require("core/env")
    local log      = require("core/log")
    local cfg      = require("core/config")
    local state    = require("core/state")
    local namecall = require("hooks/namecall")

    local M = {}
    local L = log.scoped("scrubbers/kick")

    -- One-shot allowance token consumed by the next Kick attempt.
    -- Recovery / self-kick testing flips this on, fires the kick,
    -- and control never returns anyway.
    local ALLOW_NEXT = false

    -- Last observed attempt, exposed for UI readout even when
    -- the attempt was allowed (pattern whitelisted).
    local LAST_ATTEMPT = {
        reason = nil,
        source = nil,
        time   = 0,
        result = nil, -- "blocked" / "allowed" / "whitelisted"
    }

    local function capture_source()
        if not debug or type(debug.info) ~= "function" then
            return "<no-debug.info>"
        end
        local ok, src = pcall(debug.info, 3, "s")
        if ok and type(src) == "string" then return src end
        local ok2, src2 = pcall(debug.info, 2, "s")
        if ok2 and type(src2) == "string" then return src2 end
        return "<unknown>"
    end

    local function matches_whitelist(reason)
        local list = cfg:get("scrubbers.kick.whitelist_reasons", {})
        if type(list) ~= "table" then return false end
        if type(reason) ~= "string" then return false end
        local r = reason
        for _, pat in ipairs(list) do
            if type(pat) == "string" and pat ~= "" then
                local ok, found = pcall(string.find, r, pat)
                if ok and found then return true, pat end
            end
        end
        return false
    end

    local function record_block(reason, source)
        local now = os.time()
        LAST_ATTEMPT.reason = reason
        LAST_ATTEMPT.source = source
        LAST_ATTEMPT.time   = now
        LAST_ATTEMPT.result = "blocked"

        state:bump("kick_attempts")
        state:bump("kick_blocked")
        state:set_last("kick_reason", reason)
        state:set_last("kick_source", source)
        state:set_last("kick_time",   now)
        state:journal("kicks", {
            reason = reason,
            source = source,
            time   = now,
            result = "blocked",
        })
        state:emit("KickBlocked", reason, source)
    end

    local function record_allow(reason, source, why)
        local now = os.time()
        LAST_ATTEMPT.reason = reason
        LAST_ATTEMPT.source = source
        LAST_ATTEMPT.time   = now
        LAST_ATTEMPT.result = why

        state:bump("kick_attempts")
        state:bump("kick_allowed")
        state:set_last("kick_reason", reason)
        state:set_last("kick_source", source)
        state:set_last("kick_time",   now)
        state:journal("kicks", {
            reason = reason,
            source = source,
            time   = now,
            result = why,
        })
    end

    function M.install()
        if not cfg:get("scrubbers.kick.enabled", true) then
            L:info("disabled via config")
            return
        end

        namecall.register({
            name     = "scrub_kick",
            priority = 15,
            method   = "Kick",
            class    = "Player",
            handler  = function(ctx)
                local reason = ctx.args[1]
                if type(reason) ~= "string" then reason = tostring(reason) end
                local source = capture_source()

                if ALLOW_NEXT then
                    ALLOW_NEXT = false
                    L:warn("one-shot allow_next_kick consumed: %s", reason)
                    record_allow(reason, source, "allowed")
                    return
                end

                local wl, pat = matches_whitelist(reason)
                if wl then
                    L:info("whitelisted kick reason matches '%s': %s",
                        pat, reason)
                    record_allow(reason, source, "whitelisted")
                    return
                end

                ctx.drop = true
                ctx.why  = "scrubbers/kick"
                L:warn("blocked Player:Kick reason=%q from=%s",
                    reason, source)
                record_block(reason, source)
            end,
        })

        L:info("kick scrubber active")
    end

    -- ----------------------------------------------------------------
    -- public helpers
    -- ----------------------------------------------------------------

    function M.allow_next_kick()
        ALLOW_NEXT = true
        L:warn("allow_next_kick armed; next Player:Kick will pass")
    end

    function M.is_armed() return ALLOW_NEXT end

    function M.last_attempt()
        return {
            reason = LAST_ATTEMPT.reason,
            source = LAST_ATTEMPT.source,
            time   = LAST_ATTEMPT.time,
            result = LAST_ATTEMPT.result,
        }
    end

    function M.block_count()
        return state:counter("kick_blocked")
    end

    function M.allow_count()
        return state:counter("kick_allowed")
    end

    function M.add_whitelist(pattern)
        if type(pattern) ~= "string" then return false end
        local list = cfg:get("scrubbers.kick.whitelist_reasons", {})
        if type(list) ~= "table" then list = {} end
        for _, p in ipairs(list) do
            if p == pattern then return false end
        end
        table.insert(list, pattern)
        cfg:set("scrubbers.kick.whitelist_reasons", list)
        return true
    end

    function M.remove_whitelist(pattern)
        local list = cfg:get("scrubbers.kick.whitelist_reasons", {})
        if type(list) ~= "table" then return false end
        for i, p in ipairs(list) do
            if p == pattern then
                table.remove(list, i)
                cfg:set("scrubbers.kick.whitelist_reasons", list)
                return true
            end
        end
        return false
    end

    return M
end

end
__MODULES__['scrubbers/ragdoll'] = function(require)
--[[ ================================================================
    src/scrubbers/ragdoll.lua
    --------------------------
    Drops RagdollEvent and undoes the side-effects if one slipped
    through.

    GRG's punitive ragdoll works in two halves:
        * server fires ReplicatedStorage.Remotes.RagdollEvent with
          the victim Player, a duration, and a joint spec
        * client-side AC module listens and creates
          BallSocketConstraint instances between body parts, then
          disables Humanoid:ChangeState(Getting Up) etc, leaving
          the player pinned and unable to move.

    Strategy:
        * recv_handlers.on_name("RagdollEvent") -> drop.
        * HOWEVER, we support a rate allowance
          (scrubbers.ragdoll.max_ragdolls_per_min). If > 0, we let
          that many per minute through so the player doesn't look
          suspiciously immune in heavily monitored PvP sessions.
        * On CharacterAdded: force SetStateEnabled(Ragdoll,false)
          and Physics,false so even a local script can't ragdoll
          us without us noticing.
        * Heartbeat sweep every ~0.5s: if any BallSocketConstraint
          appears under Character, destroy it (restore_hrp).

    force_recover() is the "oh shit" path if the scrubber missed a
    frame: clears joints, reseats the humanoid into Running state,
    and puts the root part back at last_safe_position.
================================================================ ]]

return function(require)
    local env      = require("core/env")
    local log      = require("core/log")
    local cfg      = require("core/config")
    local state    = require("core/state")
    local recv     = require("hooks/recv_handlers")

    local M = {}
    local L = log.scoped("scrubbers/ragdoll")

    local WINDOW_SECONDS = 60
    local allowance_window = {}
    local LAST_SAFE_POSITION = nil
    local SWEEP_TIMER = 0

    local function allowance_count_now()
        local now = os.time()
        local cutoff = now - WINDOW_SECONDS
        local keep = {}
        for _, t in ipairs(allowance_window) do
            if t >= cutoff then table.insert(keep, t) end
        end
        allowance_window = keep
        return #allowance_window
    end

    local function allowance_consume()
        table.insert(allowance_window, os.time())
    end

    local function destroy_ragdoll_joints(char)
        if not char then return 0 end
        local n = 0
        for _, d in ipairs(char:GetDescendants()) do
            local ok, isBSC = pcall(function() return d:IsA("BallSocketConstraint") end)
            if ok and isBSC then
                local ok2 = pcall(function() d:Destroy() end)
                if ok2 then n = n + 1 end
            end
        end
        return n
    end

    local function force_humanoid_safe(hum)
        if not hum then return end
        pcall(function()
            hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
        end)
        pcall(function()
            hum:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
        end)
        pcall(function()
            hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
        end)
        pcall(function()
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        end)
    end

    local function track_safe_position()
        local root = env.get_root()
        if not root then return end
        local ok, pos = pcall(function() return root.Position end)
        if ok then LAST_SAFE_POSITION = pos end
    end

    local function on_char_added(char)
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then force_humanoid_safe(hum) end
        char.ChildAdded:Connect(function(ch)
            local ok, isBSC = pcall(function() return ch:IsA("BallSocketConstraint") end)
            if ok and isBSC
               and cfg:get("scrubbers.ragdoll.restore_hrp", true) then
                pcall(function() ch:Destroy() end)
                L:debug("destroyed runtime-added ragdoll joint")
            end
        end)
    end

    function M.install()
        if not cfg:get("scrubbers.ragdoll.enabled", true) then
            L:info("disabled via config")
            return
        end

        recv.on_name("RagdollEvent", {
            name     = "scrub_ragdoll",
            priority = 5,
            kind     = "OnClientEvent",
            handler  = function(ctx)
                if not cfg:get("scrubbers.ragdoll.block_event", true) then
                    return
                end

                local cap = cfg:get("scrubbers.ragdoll.max_ragdolls_per_min", 0)
                if type(cap) == "number" and cap > 0
                   and allowance_count_now() < cap then
                    allowance_consume()
                    L:info("allowed ragdoll under quota (%d/%d)",
                        allowance_count_now(), cap)
                    state:journal("ragdolls", {
                        time   = os.time(),
                        result = "quota_allowed",
                    })
                    return
                end

                ctx.drop = true
                state:bump("ragdoll_dropped")
                state:set_last("ragdoll_payload",
                    ctx.args and ctx.args[1] or nil)
                state:set_last("ragdoll_time", os.time())
                state:journal("ragdolls", {
                    time    = os.time(),
                    result  = "dropped",
                    payload = ctx.args and ctx.args[1] or nil,
                })
                state:emit("RagdollBlocked")
                L:warn("dropped RagdollEvent")
            end,
        })

        -- Character hook ------------------------------------------
        if env.LocalPlayer then
            if env.LocalPlayer.Character then
                on_char_added(env.LocalPlayer.Character)
            end
            env.LocalPlayer.CharacterAdded:Connect(on_char_added)
        end

        -- Heartbeat sweep -----------------------------------------
        if env.RunService then
            env.RunService.Heartbeat:Connect(function(dt)
                SWEEP_TIMER = SWEEP_TIMER + (dt or 0)
                if SWEEP_TIMER < 0.5 then return end
                SWEEP_TIMER = 0

                track_safe_position()

                if not cfg:get("scrubbers.ragdoll.restore_hrp", true) then
                    return
                end
                local char = env.get_character()
                if not char then return end
                local n = destroy_ragdoll_joints(char)
                if n > 0 then
                    L:warn("restored char: cleared %d ragdoll joints", n)
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    force_humanoid_safe(hum)
                end
            end)
        end

        L:info("ragdoll scrubber active (quota=%s, restore_hrp=%s)",
            tostring(cfg:get("scrubbers.ragdoll.max_ragdolls_per_min", 0)),
            tostring(cfg:get("scrubbers.ragdoll.restore_hrp", true)))
    end

    -- ----------------------------------------------------------------
    -- public helpers
    -- ----------------------------------------------------------------

    function M.force_recover()
        local char = env.get_character()
        if not char then
            L:warn("force_recover: no character")
            return false
        end
        local cleared = destroy_ragdoll_joints(char)
        local hum = char:FindFirstChildOfClass("Humanoid")
        force_humanoid_safe(hum)
        local root = env.get_root()
        if root and LAST_SAFE_POSITION then
            pcall(function()
                root.CFrame = CFrame.new(LAST_SAFE_POSITION + Vector3.new(0, 3, 0))
            end)
        end
        if hum then
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
        end
        L:warn("force_recover: cleared=%d root_reset=%s",
            cleared, tostring(LAST_SAFE_POSITION ~= nil))
        return true
    end

    function M.drop_count() return state:counter("ragdoll_dropped") end
    function M.last_safe_position() return LAST_SAFE_POSITION end

    function M.set_safe_position(v)
        if typeof(v) == "Vector3" then LAST_SAFE_POSITION = v end
    end

    return M
end

end
__MODULES__['scrubbers/shadowban'] = function(require)
--[[ ================================================================
    src/scrubbers/shadowban.lua
    ----------------------------
    Drops incoming ReplicatedStorage.Remotes.ShadowBanEvent pings.

    In the wild the server fires ShadowBanEvent as a signal to the
    client-side AC module to disable controls, hide nameplates,
    and generally freeze the player without tipping them off. Our
    job is to keep the client fully functional while also not
    ACK-ing back to the server.

    We attach to recv_handlers.on_name("ShadowBanEvent"). When the
    server fires the event, the wrapped OnClientEvent callback
    reaches our dispatcher, we flip ctx.drop, and the original
    AC-side handler never sees the payload.

    Secondary surface: some versions of the AC spawn a full-screen
    "You have been shadow banned" overlay via PlayerGui. When
    block_visual_overlay is set, we scan PlayerGui every ~2s for
    ScreenGuis whose Name looks like ShadowBan*/Ban*/Kick* and
    destroy them. We don't hook gui creation (too noisy); a lazy
    sweep is enough because the overlay sits persistently.
================================================================ ]]

return function(require)
    local env      = require("core/env")
    local log      = require("core/log")
    local cfg      = require("core/config")
    local state    = require("core/state")
    local recv     = require("hooks/recv_handlers")

    local M = {}
    local L = log.scoped("scrubbers/shadowban")

    local LAST_PAYLOAD = nil
    local LAST_PAYLOAD_AT = 0
    local DROP_COUNT = 0

    local GUI_NAME_PATTERNS = {
        "[Ss]hadow[Bb]an",
        "^[Bb]an",
        "^[Kk]ick",
        "ShadowBan",
        "Banned",
        "KickScreen",
    }

    local function snapshot_args(args, n)
        local snap = {}
        for i = 1, n do
            local v = args[i]
            local tv = type(v)
            if tv == "string" or tv == "number" or tv == "boolean" or tv == "nil" then
                snap[i] = v
            elseif tv == "table" then
                -- Shallow copy; inner deep objects are tostring'd.
                local t = {}
                for k, vv in pairs(v) do
                    local tvv = type(vv)
                    if tvv == "string" or tvv == "number" or tvv == "boolean" then
                        t[k] = vv
                    else
                        t[k] = tostring(vv)
                    end
                end
                snap[i] = t
            else
                snap[i] = tostring(v)
            end
        end
        snap.n = n
        return snap
    end

    local function name_matches(nm)
        if type(nm) ~= "string" then return false end
        for _, pat in ipairs(GUI_NAME_PATTERNS) do
            local ok, found = pcall(string.find, nm, pat)
            if ok and found then return true end
        end
        return false
    end

    local function sweep_playergui()
        local pg = env.PlayerGui
        if not pg and env.LocalPlayer then
            pg = env.LocalPlayer:FindFirstChild("PlayerGui")
        end
        if not pg then return 0 end

        local killed = 0
        for _, child in ipairs(pg:GetChildren()) do
            local ok, nm = pcall(function() return child.Name end)
            if ok and name_matches(nm) then
                local ok2 = pcall(function() child:Destroy() end)
                if ok2 then
                    killed = killed + 1
                    L:warn("deleted overlay gui '%s'", nm)
                end
            end
        end
        return killed
    end

    local SWEEP_TICK = 0
    local function on_heartbeat(dt)
        if not cfg:get("scrubbers.shadowban.block_visual_overlay", true) then
            return
        end
        SWEEP_TICK = SWEEP_TICK + (dt or 0)
        if SWEEP_TICK < 2.0 then return end
        SWEEP_TICK = 0
        local n = sweep_playergui()
        if n > 0 then
            state:bump("shadowban_dropped", 0)
        end
    end

    function M.install()
        if not cfg:get("scrubbers.shadowban.enabled", true) then
            L:info("disabled via config")
            return
        end

        recv.on_name("ShadowBanEvent", {
            name     = "scrub_shadowban",
            priority = 5,
            kind     = "OnClientEvent",
            handler  = function(ctx)
                if not cfg:get("scrubbers.shadowban.block_event", true) then
                    return
                end
                local payload = snapshot_args(ctx.args, ctx.n_args)
                LAST_PAYLOAD    = payload
                LAST_PAYLOAD_AT = os.time()
                DROP_COUNT      = DROP_COUNT + 1

                state:bump("shadowban_dropped")
                state:set_last("shadowban_payload", payload)
                state:set_last("shadowban_time",    os.time())
                state:journal("shadowbans", {
                    payload = payload,
                    time    = os.time(),
                    result  = "dropped",
                })
                state:emit("ShadowbanBlocked", payload)

                L:warn("dropped ShadowBanEvent (#%d)", DROP_COUNT)
                ctx.drop = true
            end,
        })

        -- Periodic GUI sweep -- heartbeat counter.
        if env.RunService then
            env.RunService.Heartbeat:Connect(function(dt)
                local ok, err = pcall(on_heartbeat, dt)
                if not ok then
                    L:warn("heartbeat sweep errored: %s", tostring(err))
                end
            end)
        end

        L:info("shadowban scrubber active (overlay_sweep=%s)",
            tostring(cfg:get("scrubbers.shadowban.block_visual_overlay", true)))
    end

    -- ----------------------------------------------------------------
    -- public helpers
    -- ----------------------------------------------------------------

    function M.last_payload() return LAST_PAYLOAD end
    function M.last_payload_at() return LAST_PAYLOAD_AT end
    function M.drop_count() return DROP_COUNT end

    function M.force_sweep()
        return sweep_playergui()
    end

    function M.add_gui_pattern(pat)
        if type(pat) ~= "string" then return false end
        table.insert(GUI_NAME_PATTERNS, pat)
        return true
    end

    function M.clear()
        LAST_PAYLOAD    = nil
        LAST_PAYLOAD_AT = 0
        DROP_COUNT      = 0
    end

    return M
end

end
__MODULES__['scrubbers/teleport'] = function(require)
--[[ ================================================================
    src/scrubbers/teleport.lua
    ---------------------------
    Intercepts all TeleportService methods the GRG AC can use to
    evict the client. We see this in two flows in the wild:

        1. "You have been flagged" -> TeleportService:Teleport to
           a dead loadscreen place. Some versions go to placeId
           0 which simply kills the session.
        2. Reserved-server TeleportToPrivateServer with a code
           we've never negotiated -- server uses this to isolate
           suspected cheaters from the rest of the playerbase.

    We also observe TeleportToPlaceInstance being used with the
    current server's JobId as an "AC soft reset". We allow that
    when allow_same_place is on: it's load-bearing for a legit
    lobby->server flow.

    Strategy:
        * namecall handler, priority 15, class = "TeleportService"
        * match any of the four methods by name
        * allow-list if (allow_same_place and target == PlaceId)
        * allow-list if the one-shot ALLOW_NEXT token is set
        * otherwise drop, bump counter, journal target
================================================================ ]]

return function(require)
    local env      = require("core/env")
    local log      = require("core/log")
    local cfg      = require("core/config")
    local state    = require("core/state")
    local namecall = require("hooks/namecall")

    local M = {}
    local L = log.scoped("scrubbers/teleport")

    local BLOCK_ALL  = false
    local ALLOW_NEXT = false

    -- Method -> where in args[] the target place id lives. -1
    -- indicates "does not carry a place id" (Cancel).
    local METHOD_TARGET_SLOT = {
        Teleport                 = 1,
        TeleportToPlaceInstance  = 1,
        TeleportToPrivateServer  = 1,
        TeleportCancel           = -1,
    }

    local function capture_source()
        if not debug or type(debug.info) ~= "function" then
            return "<no-debug.info>"
        end
        local ok, src = pcall(debug.info, 3, "s")
        if ok and type(src) == "string" then return src end
        return "<unknown>"
    end

    local function extract_target(method, args, n)
        local slot = METHOD_TARGET_SLOT[method]
        if not slot or slot < 0 then return nil end
        if slot > n then return nil end
        local v = args[slot]
        if type(v) == "number" then return v end
        -- Some executors pass the placeId boxed in a string.
        return tonumber(tostring(v))
    end

    local function record_block(method, target, source)
        state:bump("teleport_attempts")
        state:bump("teleport_blocked")
        state:set_last("teleport_target", target)
        state:set_last("teleport_time",   os.time())
        state:journal("teleports", {
            method = method,
            target = target,
            source = source,
            time   = os.time(),
            result = "blocked",
        })
        state:emit("TeleportBlocked", method, target)
    end

    local function record_allow(method, target, why)
        state:bump("teleport_attempts")
        state:bump("teleport_allowed")
        state:set_last("teleport_target", target)
        state:set_last("teleport_time",   os.time())
        state:journal("teleports", {
            method = method,
            target = target,
            time   = os.time(),
            result = why,
        })
    end

    function M.install()
        if not cfg:get("scrubbers.teleport.enabled", true) then
            L:info("disabled via config")
            return
        end

        namecall.register({
            name     = "scrub_teleport",
            priority = 15,
            class    = "TeleportService",
            handler  = function(ctx)
                local method = ctx.method
                if METHOD_TARGET_SLOT[method] == nil then return end

                local source = capture_source()
                local target = extract_target(method, ctx.args, ctx.n_args)

                if ALLOW_NEXT then
                    ALLOW_NEXT = false
                    L:warn("one-shot allow_next consumed: %s -> %s",
                        method, tostring(target))
                    record_allow(method, target, "allowed")
                    return
                end

                if BLOCK_ALL then
                    ctx.drop = true
                    ctx.why  = "scrubbers/teleport.block_all"
                    L:warn("block_all: dropped %s target=%s from=%s",
                        method, tostring(target), source)
                    record_block(method, target, source)
                    return
                end

                -- TeleportCancel: always allow unless block_all.
                if method == "TeleportCancel" then
                    if cfg:get("scrubbers.teleport.block_cancel", false) then
                        ctx.drop = true
                        record_block(method, nil, source)
                        L:warn("dropped TeleportCancel (block_cancel on)")
                        return
                    end
                    record_allow(method, nil, "allowed")
                    return
                end

                -- Same-place allowance: AC sometimes reloads us into
                -- our own PlaceId as a soft reset; that is benign.
                if cfg:get("scrubbers.teleport.allow_same_place", true)
                   and target == env.PlaceId then
                    L:info("allow same-place teleport method=%s target=%d",
                        method, target)
                    record_allow(method, target, "same_place")
                    return
                end

                -- Default deny.
                ctx.drop = true
                ctx.why  = "scrubbers/teleport"
                L:warn("blocked %s target=%s from=%s",
                    method, tostring(target), source)
                record_block(method, target, source)
            end,
        })

        L:info("teleport scrubber active (allow_same_place=%s)",
            tostring(cfg:get("scrubbers.teleport.allow_same_place", true)))
    end

    -- ----------------------------------------------------------------
    -- public helpers
    -- ----------------------------------------------------------------

    function M.block_all()
        BLOCK_ALL = true
        L:warn("teleport block_all engaged")
    end

    function M.unblock_all()
        BLOCK_ALL = false
        L:info("teleport block_all released")
    end

    function M.allow_next()
        ALLOW_NEXT = true
        L:warn("allow_next armed; next TeleportService call passes")
    end

    function M.is_blocking_all() return BLOCK_ALL end
    function M.is_armed()        return ALLOW_NEXT end

    function M.block_count()
        return state:counter("teleport_blocked")
    end

    return M
end

end
__MODULES__['scrubbers/updateprofile'] = function(require)
--[[ ================================================================
    src/scrubbers/updateprofile.lua
    --------------------------------
    Sanitizes client-to-server telemetry sent via
    ReplicatedStorage.Remotes.UpdateProfile:FireServer(payload).

    The server uses UpdateProfile payloads as the principal input
    to its AC correlation pass: WalkSpeed, position, jump power,
    custom state flags. When the player (or any cheat in the
    process) pokes a value outside a sane window, the server
    trips and fires the kick/shadowban/ragdoll pipeline.

    We sit on the FireServer side of that remote and:

        1. Whitelist allowed fields. Anything NOT in keep_fields
           gets stripped. Attackers (or our own sloppy decoy
           modules) occasionally stuff "debugMsg" / "cheatId" in
           there; we'd rather ship a clean payload.
        2. Clamp walkSpeed to <= clamp_walkspeed.
        3. Clamp position delta from the last sent position: if
           the magnitude would be > clamp_max_distance relative to
           the last accepted send, we replace the field with the
           last valid one. This is the single most important
           guardrail: GRG's displacement check flat-out kicks on
           deltas > 40 studs.
        4. Clamp jumpPower.
        5. Record original+sanitized payload to state.LastSeen.

    We only mutate; we don't drop. A dropped UpdateProfile tells
    the server something is wrong about as loudly as an OOB one.
================================================================ ]]

return function(require)
    local env      = require("core/env")
    local log      = require("core/log")
    local cfg      = require("core/config")
    local state    = require("core/state")
    local fire     = require("hooks/fire_handlers")

    local M = {}
    local L = log.scoped("scrubbers/updateprofile")

    local LAST_SENT_POSITION = nil

    local function is_vector3(v)
        return typeof ~= nil and typeof(v) == "Vector3"
    end

    local function vec_magnitude(a, b)
        if not a or not b then return 0 end
        local dx = (a.X or 0) - (b.X or 0)
        local dy = (a.Y or 0) - (b.Y or 0)
        local dz = (a.Z or 0) - (b.Z or 0)
        return math.sqrt(dx * dx + dy * dy + dz * dz)
    end

    local function shallow_copy(t)
        if type(t) ~= "table" then return t end
        local o = {}
        for k, v in pairs(t) do o[k] = v end
        return o
    end

    local function strip_unknown_fields(tbl)
        local keep = cfg:get("scrubbers.updateprofile.keep_fields",
            { "state", "position", "walkSpeed", "jumpPower" })
        if type(keep) ~= "table" then
            return tbl, 0
        end
        local keep_set = {}
        for _, k in ipairs(keep) do keep_set[k] = true end

        local removed = 0
        for k in pairs(tbl) do
            if not keep_set[k] then
                tbl[k] = nil
                removed = removed + 1
            end
        end
        return tbl, removed
    end

    local function clamp_walkspeed(tbl)
        local cap = cfg:get("scrubbers.updateprofile.clamp_walkspeed", 16)
        if type(cap) ~= "number" then return false end
        local v = tbl.walkSpeed
        if type(v) == "number" and v > cap + 0.01 then
            tbl.walkSpeed = cap
            return true
        end
        return false
    end

    local function clamp_jumppower(tbl)
        local cap = cfg:get("scrubbers.updateprofile.clamp_jumppower", 50)
        if type(cap) ~= "number" then return false end
        local v = tbl.jumpPower
        if type(v) == "number" and v > cap + 0.01 then
            tbl.jumpPower = cap
            return true
        end
        return false
    end

    local function clamp_position(tbl)
        local cap = cfg:get("scrubbers.updateprofile.clamp_max_distance", 40)
        if type(cap) ~= "number" or cap <= 0 then return false end
        local p = tbl.position
        if p == nil then return false end

        -- Accept Vector3 or {X,Y,Z} table.
        local cur_x, cur_y, cur_z
        if is_vector3(p) then
            cur_x, cur_y, cur_z = p.X, p.Y, p.Z
        elseif type(p) == "table" then
            cur_x = p.X or p.x or p[1]
            cur_y = p.Y or p.y or p[2]
            cur_z = p.Z or p.z or p[3]
        else
            return false
        end
        if type(cur_x) ~= "number"
           or type(cur_y) ~= "number"
           or type(cur_z) ~= "number" then
            return false
        end

        local cur = { X = cur_x, Y = cur_y, Z = cur_z }

        if LAST_SENT_POSITION then
            local d = vec_magnitude(cur, LAST_SENT_POSITION)
            if d > cap then
                -- Replace with last valid, DON'T advance the
                -- stored anchor: next delta is still computed
                -- against the pre-teleport origin.
                if is_vector3(p) then
                    tbl.position = Vector3.new(
                        LAST_SENT_POSITION.X,
                        LAST_SENT_POSITION.Y,
                        LAST_SENT_POSITION.Z)
                else
                    tbl.position = {
                        X = LAST_SENT_POSITION.X,
                        Y = LAST_SENT_POSITION.Y,
                        Z = LAST_SENT_POSITION.Z,
                    }
                end
                return true, d
            end
        end
        -- Accepted position becomes the new anchor.
        LAST_SENT_POSITION = cur
        return false
    end

    local function sanitize(payload)
        if type(payload) ~= "table" then return payload, {} end
        local report = {
            ws_clamped = false,
            jp_clamped = false,
            pos_clamped = false,
            removed = 0,
            pos_delta = 0,
        }
        local _, removed = strip_unknown_fields(payload)
        report.removed = removed
        report.ws_clamped = clamp_walkspeed(payload)
        report.jp_clamped = clamp_jumppower(payload)
        local pc, d = clamp_position(payload)
        report.pos_clamped = pc
        report.pos_delta   = d or 0
        return payload, report
    end

    function M.install()
        if not cfg:get("scrubbers.updateprofile.enabled", true) then
            L:info("disabled via config")
            return
        end

        fire.on_name("UpdateProfile", {
            name     = "scrub_updateprofile",
            priority = 20,
            kind     = "FireServer",
            handler  = function(ctx)
                if not cfg:get("scrubbers.updateprofile.sanitize", true) then
                    return
                end
                local original = ctx.args[1]
                if type(original) ~= "table" then
                    return
                end

                -- Preserve a shallow original for journaling.
                local original_snap = shallow_copy(original)
                state:set_last("last_updateprofile", original_snap)

                -- In-place mutate (the args table will be
                -- forwarded to the real FireServer).
                local sanitized, report = sanitize(original)
                ctx.args[1] = sanitized
                state:set_last("last_updateprofile_sent", shallow_copy(sanitized))

                if report.ws_clamped or report.jp_clamped
                   or report.pos_clamped or report.removed > 0 then
                    state:bump("updateprofile_sanitized")
                    state:emit("ProfileMutated", original_snap, sanitized)
                    L:debug("sanitized profile: ws=%s jp=%s pos=%s strip=%d d=%.1f",
                        tostring(report.ws_clamped),
                        tostring(report.jp_clamped),
                        tostring(report.pos_clamped),
                        report.removed, report.pos_delta)
                end
            end,
        })

        L:info("updateprofile scrubber active (ws_cap=%d, pos_cap=%d)",
            cfg:get("scrubbers.updateprofile.clamp_walkspeed", 16),
            cfg:get("scrubbers.updateprofile.clamp_max_distance", 40))
    end

    -- ----------------------------------------------------------------
    -- public helpers
    -- ----------------------------------------------------------------

    function M.set_last_sent_position(p)
        if is_vector3(p) then
            LAST_SENT_POSITION = { X = p.X, Y = p.Y, Z = p.Z }
        elseif type(p) == "table" then
            LAST_SENT_POSITION = {
                X = p.X or p.x or p[1] or 0,
                Y = p.Y or p.y or p[2] or 0,
                Z = p.Z or p.z or p[3] or 0,
            }
        end
    end

    function M.get_last_sent_position()
        if not LAST_SENT_POSITION then return nil end
        return {
            X = LAST_SENT_POSITION.X,
            Y = LAST_SENT_POSITION.Y,
            Z = LAST_SENT_POSITION.Z,
        }
    end

    function M.reset_anchor()
        LAST_SENT_POSITION = nil
    end

    function M.sanitize_count()
        return state:counter("updateprofile_sanitized")
    end

    return M
end

end
__MODULES__['silencers/gui_warning_block'] = function(require)
--[[ ================================================================
    src/silencers/gui_warning_block.lua
    ------------------------------------
    The "don't let the player see the warning banner" silencer.

    Two lines of defence:

      1. A Heartbeat-driven periodic scanner (budgeted to one full
         walk per second) that walks LocalPlayer.PlayerGui and
         CoreGui looking for ScreenGuis whose Name matches a known
         AC banner name OR TextLabels whose displayed string matches
         a banned pattern. Matches are destroyed in place.

      2. A namecall hook on StarterGui:SetCore("SendNotification",...)
         so we can intercept Roblox toast notifications spawned by
         the AC. Some cheats rig the AC to tell Roblox to show a
         pop-down "You were flagged" instead of a ScreenGui.

    Patterns are mutable from outside via M.add_name_pattern /
    M.add_text_pattern so new AC variants can be handled without
    code changes.
================================================================ ]]

return function(require)

    local env      = require("core/env")
    local log      = require("core/log")
    local cfg      = require("core/config")
    local state    = require("core/state")
    local namecall = require("hooks/namecall")

    local M = {}
    local L = log.scoped("silencers/gui_warning_block")

    local INSTALLED = false

    local NAME_BLACKLIST = {
        "AntiCheatWarning",
        "BanWarning",
        "KickWarning",
        "ShadowBanUI",
        "FlagUI",
        "ErrorUI",
        "ModAction",
        "AdminPunishment",
    }

    local TEXT_PATTERNS = {
        "you have been",
        "banned",
        "shadowbanned",
        "kicked",
        "flagged",
        "exploit detected",
        "cheat detected",
    }

    local function name_blacklisted(nm)
        if type(nm) ~= "string" then return false end
        local lower = string.lower(nm)
        for _, bad in ipairs(NAME_BLACKLIST) do
            if lower == string.lower(bad) then return true, bad end
            if string.find(lower, string.lower(bad), 1, true) then
                return true, bad
            end
        end
        return false
    end

    local function text_blacklisted(txt)
        if type(txt) ~= "string" then return false end
        local lower = string.lower(txt)
        for _, pat in ipairs(TEXT_PATTERNS) do
            local ok, found = pcall(string.find, lower, pat)
            if ok and found then return true, pat end
        end
        return false
    end

    local function destroy_safely(inst, why)
        pcall(function()
            if inst:IsA("ScreenGui") then inst.Enabled = false end
            inst:ClearAllChildren()
            inst:Destroy()
        end)
        state:bump("coregui_warning_blocked")
        L:warn("destroyed %s (%s)", tostring(inst), why)
    end

    local function scan_container(container)
        if not container then return end
        local ok, kids = pcall(function() return container:GetChildren() end)
        if not ok or type(kids) ~= "table" then return end
        for _, child in ipairs(kids) do
            local ok_isa, is_sg = pcall(function() return child:IsA("ScreenGui") end)
            if ok_isa and is_sg then
                local hit, which = name_blacklisted(child.Name)
                if hit then
                    destroy_safely(child, "name=" .. tostring(which))
                end
            end
            local ok_desc, desc = pcall(function() return child:GetDescendants() end)
            if ok_desc and type(desc) == "table" then
                for _, d in ipairs(desc) do
                    local ok_isl, is_tl = pcall(function() return d:IsA("TextLabel") end)
                    if ok_isl and is_tl then
                        local ok_t, t = pcall(function() return d.Text end)
                        if ok_t then
                            local hit, pat = text_blacklisted(t)
                            if hit then
                                destroy_safely(d, "text~" .. tostring(pat))
                            end
                        end
                    end
                end
            end
        end
    end

    local HB_COUNTER = 0

    local function start_scanner()
        local rs = env.RunService
        if not rs then return end
        rs.Heartbeat:Connect(function(dt)
            if not cfg:get("silencers.gui_warning_block.enabled", true) then
                return
            end
            HB_COUNTER = HB_COUNTER + dt
            if HB_COUNTER < 1 then return end
            HB_COUNTER = 0
            pcall(scan_container, env.PlayerGui)
            pcall(scan_container, env.CoreGui)
        end)
    end

    local function install_notification_hook()
        namecall.register({
            name     = "silencer_notification_block",
            priority = 22,
            method   = "SetCore",
            class    = "StarterGui",
            handler  = function(ctx)
                local arg1 = ctx.args[1]
                if arg1 ~= "SendNotification" then return end
                local payload = ctx.args[2]
                if type(payload) ~= "table" then return end
                local title = tostring(payload.Title or "")
                local body  = tostring(payload.Text  or "")
                local h1 = select(1, text_blacklisted(title))
                local h2 = select(1, text_blacklisted(body))
                if h1 or h2 then
                    ctx.drop = true
                    ctx.why  = "silencers/gui_warning_block"
                    state:bump("coregui_warning_blocked")
                    L:warn("blocked SendNotification title=%q body=%q",
                        title, body)
                end
            end,
        })
    end

    function M.install()
        if INSTALLED then return end
        if not cfg:get("silencers.gui_warning_block.enabled", true) then
            L:info("disabled via config")
            return
        end

        start_scanner()
        install_notification_hook()
        INSTALLED = true
        L:info("gui_warning_block silencer active (%d names, %d patterns)",
            #NAME_BLACKLIST, #TEXT_PATTERNS)
    end

    function M.add_name_pattern(pat)
        if type(pat) ~= "string" or pat == "" then return false end
        for _, p in ipairs(NAME_BLACKLIST) do
            if p == pat then return false end
        end
        table.insert(NAME_BLACKLIST, pat)
        return true
    end

    function M.add_text_pattern(pat)
        if type(pat) ~= "string" or pat == "" then return false end
        for _, p in ipairs(TEXT_PATTERNS) do
            if p == pat then return false end
        end
        table.insert(TEXT_PATTERNS, pat)
        return true
    end

    function M.name_patterns() return NAME_BLACKLIST end
    function M.text_patterns() return TEXT_PATTERNS end

    return M

end

end
__MODULES__['silencers/kick_block'] = function(require)
--[[ ================================================================
    src/silencers/kick_block.lua
    -----------------------------
    Belt-and-suspenders block on kick-related user-visible effects.

    The scrubbers/kick module already drops Player:Kick namecalls.
    This silencer does three additional things, any one of which
    would stop a kick on its own:

        1. Independently registers a namecall drop for Player:Kick
           and LocalPlayer:Kick at a different priority so that even
           if the scrubber is unloaded (module swap, cfg toggle,
           integrity restore) the popup never paints.
        2. Periodically (every 2s) sweeps CoreGui for any ScreenGui
           whose name contains "KickScreen" and destroys it. The
           real Roblox kick overlay is named "KickScreen"; custom
           AC kicks often reuse the same name for mimicry.
        3. Drops game:Shutdown() namecalls. From a pure-client
           perspective this is unreachable (Shutdown is server-only),
           but several popular cheat loaders call it as a "self
           destruct" if they think they're being traced and we'd
           rather never actually send it.

    M.last_kick_attempt() returns the last kick timestamp the
    shared state module saw, so UI can surface "last blocked kick
    3s ago".
================================================================ ]]

return function(require)

    local env      = require("core/env")
    local log      = require("core/log")
    local cfg      = require("core/config")
    local state    = require("core/state")
    local namecall = require("hooks/namecall")

    local M = {}
    local L = log.scoped("silencers/kick_block")

    local INSTALLED = false
    local SCAN_ACTIVE = false

    local function is_kick_screen(inst)
        if type(inst) ~= "userdata" then return false end
        local ok_name, nm = pcall(function() return inst.Name end)
        if not ok_name or type(nm) ~= "string" then return false end
        local lower = string.lower(nm)
        return string.find(lower, "kickscreen", 1, true) ~= nil
            or string.find(lower, "kick_screen", 1, true) ~= nil
            or string.find(lower, "kickoverlay", 1, true) ~= nil
    end

    local function nuke_kick_screen(inst)
        if type(inst) ~= "userdata" then return end
        local ok = pcall(function()
            if inst:IsA("ScreenGui") then
                inst.Enabled = false
                inst:ClearAllChildren()
                inst:Destroy()
            end
        end)
        if ok then
            state:bump("coregui_warning_blocked")
            L:warn("destroyed kick screen gui: %s", tostring(inst))
        end
    end

    local function sweep_coregui()
        local cg = env.CoreGui
        if not cg then return end
        local ok, kids = pcall(function() return cg:GetChildren() end)
        if not ok or type(kids) ~= "table" then return end
        for _, child in ipairs(kids) do
            if is_kick_screen(child) then
                nuke_kick_screen(child)
            end
        end
        -- Also check CoreGui.RobloxGui where the engine-native
        -- "KickScreen" actually lives on some clients.
        local ok2, rg = pcall(function() return cg:FindFirstChild("RobloxGui") end)
        if ok2 and rg then
            local ok3, sub = pcall(function() return rg:GetChildren() end)
            if ok3 and type(sub) == "table" then
                for _, child in ipairs(sub) do
                    if is_kick_screen(child) then
                        nuke_kick_screen(child)
                    end
                end
            end
        end
    end

    local function start_sweeper()
        if SCAN_ACTIVE then return end
        SCAN_ACTIVE = true
        task.spawn(function()
            while SCAN_ACTIVE do
                if cfg:get("silencers.kick_block.enabled", true) then
                    pcall(sweep_coregui)
                end
                task.wait(2)
            end
        end)
    end

    function M.install()
        if INSTALLED then return end
        if not cfg:get("silencers.kick_block.enabled", true) then
            L:info("disabled via config")
            return
        end

        namecall.drop_method("Kick", "Player", "silencer_kick_block")
        namecall.drop_method("Kick", "LocalPlayer", "silencer_kick_block_lp")

        namecall.register({
            name     = "silencer_shutdown_block",
            priority = 18,
            method   = "Shutdown",
            handler  = function(ctx)
                ctx.drop = true
                ctx.why  = "silencers/kick_block"
                L:warn("blocked game:Shutdown() from %s",
                    tostring(ctx.self))
                state:bump("kick_blocked")
            end,
        })

        start_sweeper()
        INSTALLED = true
        L:info("kick_block silencer active (scan every 2s)")
    end

    function M.last_kick_attempt()
        return state:get_last("kick_time") or 0
    end

    function M.stop()
        SCAN_ACTIVE = false
        L:info("kick_block sweeper stopped")
    end

    return M

end

end
__MODULES__['silencers/screen_flash_block'] = function(require)
--[[ ================================================================
    src/silencers/screen_flash_block.lua
    -------------------------------------
    Kills AC "ban flash" visual effects.

    The hostile AC's favourite tell is a quick red screen flash via
    a freshly-parented ColorCorrectionEffect under Lighting (usually
    with TintColor = red, Contrast bumped). Some variants use
    BlurEffect to "freeze" the screen during a shadowban, or a
    DepthOfFieldEffect for the same effect.

    Strategy:

      * Connect Lighting.ChildAdded and CurrentCamera.ChildAdded.
      * On a new ColorCorrection/Blur/DOF effect, if it appeared
        within 0.5s of a kick attempt or a shadowban hit, destroy
        it immediately. Outside that window, let it pass (other
        parts of the game use these effects legitimately).
      * Watch Lighting.Changed for Ambient / TimeOfDay flips to
        the red/night pattern AC uses on ban.

    M.pause() / M.resume() let integrity briefly disable us when
    we suspect a false positive (a UI mode that actually wants
    color correction).
================================================================ ]]

return function(require)

    local env      = require("core/env")
    local log      = require("core/log")
    local cfg      = require("core/config")
    local state    = require("core/state")
    local namecall = require("hooks/namecall") -- required for parity

    local M = {}
    local L = log.scoped("silencers/screen_flash_block")

    local INSTALLED = false
    local PAUSED    = false

    local SUSPICIOUS_CLASSES = {
        ColorCorrectionEffect = true,
        BlurEffect            = true,
        DepthOfFieldEffect    = true,
    }

    local WINDOW_SEC = 0.5

    local function recent_danger()
        local kt = state:get_last("kick_time") or 0
        local sb = state:get_last("shadowban_time") or 0
        local latest = math.max(kt, sb)
        if latest <= 0 then return false end
        return (os.time() - latest) <= WINDOW_SEC + 0.01
    end

    local function looks_red(v)
        if typeof(v) ~= "Color3" then return false end
        local r, g, b = v.R, v.G, v.B
        return r > 0.55 and g < 0.4 and b < 0.4
    end

    local function is_effect_suspicious(inst)
        if type(inst) ~= "userdata" then return false end
        local ok, class = pcall(function() return inst.ClassName end)
        if not ok then return false end
        if not SUSPICIOUS_CLASSES[class] then return false end
        if recent_danger() then return true, "recent_danger" end
        local ok2, tint = pcall(function() return inst.TintColor end)
        if ok2 and looks_red(tint) then return true, "red_tint" end
        return false
    end

    local function nuke(inst, why)
        if PAUSED then return end
        pcall(function()
            inst.Enabled = false
            inst:Destroy()
        end)
        state:bump("coregui_warning_blocked")
        L:warn("destroyed %s (%s)", tostring(inst), why)
    end

    local function watch(container)
        if not container then return end
        pcall(function()
            container.ChildAdded:Connect(function(child)
                if PAUSED then return end
                if not cfg:get("silencers.screen_flash_block.enabled", true) then
                    return
                end
                local hit, why = is_effect_suspicious(child)
                if hit then
                    nuke(child, why)
                end
            end)
        end)
    end

    local function hook_lighting_changed()
        local lighting = env.Lighting
        if not lighting then return end
        pcall(function()
            lighting.Changed:Connect(function(prop)
                if PAUSED then return end
                if not cfg:get("silencers.screen_flash_block.enabled", true) then
                    return
                end
                if not recent_danger() then return end
                if prop == "Ambient" then
                    local ok, v = pcall(function() return lighting.Ambient end)
                    if ok and looks_red(v) then
                        pcall(function() lighting.Ambient = Color3.new(0, 0, 0) end)
                        L:warn("reverted suspicious Ambient flip")
                        state:bump("coregui_warning_blocked")
                    end
                elseif prop == "TimeOfDay" then
                    local ok, v = pcall(function() return lighting.TimeOfDay end)
                    if ok and type(v) == "string" and v:sub(1, 2) == "00" then
                        pcall(function() lighting.TimeOfDay = "14:00:00" end)
                        L:warn("reverted suspicious TimeOfDay flip")
                        state:bump("coregui_warning_blocked")
                    end
                end
            end)
        end)
    end

    local function watch_camera()
        local ws = env.Workspace
        if not ws then return end
        local cam = ws.CurrentCamera
        if cam then watch(cam) end
        pcall(function()
            ws:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
                local new_cam = ws.CurrentCamera
                if new_cam then watch(new_cam) end
            end)
        end)
    end

    function M.install()
        if INSTALLED then return end
        if not cfg:get("silencers.screen_flash_block.enabled", true) then
            L:info("disabled via config")
            return
        end

        watch(env.Lighting)
        watch_camera()
        hook_lighting_changed()
        INSTALLED = true
        L:info("screen_flash_block silencer active (window=%.2fs)", WINDOW_SEC)
    end

    function M.pause()
        PAUSED = true
        L:info("paused")
    end

    function M.resume()
        PAUSED = false
        L:info("resumed")
    end

    function M.is_paused() return PAUSED end

    return M

end

end
__MODULES__['silencers/sound_block'] = function(require)
--[[ ================================================================
    src/silencers/sound_block.lua
    ------------------------------
    Kills AC alarm sounds.

    Some AC setups play a distinct "got you" sound the moment they
    decide to ban -- rbxassetid://12222062 and friends. This module
    sweeps three likely homes (Workspace, SoundService, PlayerGui)
    every second looking for Sound instances whose SoundId is in a
    configurable blocklist or whose ancestry chain contains a
    known ban-UI container.

    Matches get Stop() + Volume = 0 (two-belt safety: some AC
    scripts have already connected to Ended to re-trigger, so
    silencing via volume prevents an audible replay even if Play
    fires again before we re-scan).

    A namecall hook on Sound:Play drops any play whose SoundId is
    currently blocked, catching newly-created sounds before they
    start.

    Config key: silencers.sound_block.sound_id_blocklist (array of
    string ids). Starts empty; hub can populate on boot.
================================================================ ]]

return function(require)

    local env      = require("core/env")
    local log      = require("core/log")
    local cfg      = require("core/config")
    local state    = require("core/state")
    local namecall = require("hooks/namecall")

    local M = {}
    local L = log.scoped("silencers/sound_block")

    local INSTALLED = false

    local UI_CONTAINER_HINTS = {
        "kickscreen",
        "banwarning",
        "shadowbanui",
        "anticheatwarning",
    }

    local function blocklist()
        return cfg:get("silencers.sound_block.sound_id_blocklist", {}) or {}
    end

    local function normalize_id(id)
        if type(id) ~= "string" then return tostring(id or "") end
        return id
    end

    local function id_blocked(id)
        local list = blocklist()
        if type(list) ~= "table" then return false end
        local want = normalize_id(id)
        for _, v in ipairs(list) do
            if normalize_id(v) == want then return true end
        end
        return false
    end

    local function ancestry_suspicious(inst)
        local cursor = inst
        for _ = 1, 8 do
            if not cursor then return false end
            local ok, nm = pcall(function() return cursor.Name end)
            if ok and type(nm) == "string" then
                local lower = string.lower(nm)
                for _, bad in ipairs(UI_CONTAINER_HINTS) do
                    if string.find(lower, bad, 1, true) then return true end
                end
            end
            local ok2, parent = pcall(function() return cursor.Parent end)
            if not ok2 then return false end
            cursor = parent
        end
        return false
    end

    local function silence(sound, why)
        pcall(function()
            sound:Stop()
            sound.Volume = 0
            sound.PlaybackSpeed = 0
        end)
        L:warn("silenced Sound id=%s (%s)",
            tostring(sound and sound.SoundId or "?"), why)
    end

    local function scan_container(container)
        if not container then return end
        local ok, desc = pcall(function() return container:GetDescendants() end)
        if not ok or type(desc) ~= "table" then return end
        for _, d in ipairs(desc) do
            local ok_isa, is_snd = pcall(function() return d:IsA("Sound") end)
            if ok_isa and is_snd then
                local ok_id, sid = pcall(function() return d.SoundId end)
                if ok_id and id_blocked(sid) then
                    silence(d, "id-blocked")
                elseif ancestry_suspicious(d) then
                    silence(d, "suspicious-parent")
                end
            end
        end
    end

    local function start_scanner()
        task.spawn(function()
            while INSTALLED do
                if cfg:get("silencers.sound_block.enabled", true) then
                    pcall(scan_container, env.Workspace)
                    pcall(scan_container, env.SoundService)
                    pcall(scan_container, env.PlayerGui)
                end
                task.wait(1)
            end
        end)
    end

    function M.install()
        if INSTALLED then return end
        if not cfg:get("silencers.sound_block.enabled", true) then
            L:info("disabled via config")
            return
        end
        INSTALLED = true

        namecall.register({
            name     = "silencer_sound_play_block",
            priority = 22,
            method   = "Play",
            class    = "Sound",
            handler  = function(ctx)
                local sid
                local ok = pcall(function() sid = ctx.self.SoundId end)
                if ok and id_blocked(sid) then
                    ctx.drop = true
                    ctx.why  = "silencers/sound_block"
                    L:warn("blocked Sound:Play id=%s", tostring(sid))
                end
            end,
        })

        start_scanner()
        L:info("sound_block silencer active")
    end

    function M.block_sound_id(id)
        if type(id) ~= "string" then return false end
        local list = blocklist()
        for _, v in ipairs(list) do
            if v == id then return false end
        end
        table.insert(list, id)
        cfg:set("silencers.sound_block.sound_id_blocklist", list)
        return true
    end

    function M.unblock_sound_id(id)
        local list = blocklist()
        for i, v in ipairs(list) do
            if v == id then
                table.remove(list, i)
                cfg:set("silencers.sound_block.sound_id_blocklist", list)
                return true
            end
        end
        return false
    end

    function M.blocklist() return blocklist() end

    return M

end

end
__MODULES__['silencers/teleport_block'] = function(require)
--[[ ================================================================
    src/silencers/teleport_block.lua
    ---------------------------------
    Silences user-visible teleport side effects.

    TeleportService.Teleport / TeleportToPlaceInstance /
    TeleportToPrivateServer / TeleportPartyAsync are all independently
    dropped. A scrubbers/teleport module drops the network-level
    signal; this silencer ensures the local UI transition (black
    loadscreen, "Teleport failed" banner) never paints even if a
    teleport call somehow slips through or the scrubber is unloaded.

    TeleportService.TeleportInitFailed is a BindableEvent that the AC
    sometimes flashes to taunt a detected cheater. We connect a
    no-op listener early so we at least have telemetry; the actual
    suppression happens by clearing any banner GUI the event might
    produce in the gui_warning_block sibling module.

    A one-shot M.allow_once() token lets callers temporarily lift
    the block for legitimate teleports (hub bootstrap, soft
    reconnects).
================================================================ ]]

return function(require)

    local env      = require("core/env")
    local log      = require("core/log")
    local cfg      = require("core/config")
    local state    = require("core/state")
    local namecall = require("hooks/namecall")

    local M = {}
    local L = log.scoped("silencers/teleport_block")

    local INSTALLED = false
    local ALLOW_ONCE = false
    local LAST_CALL = { method = nil, target = nil, time = 0 }

    local BLOCKED_METHODS = {
        "Teleport",
        "TeleportToPlaceInstance",
        "TeleportToPrivateServer",
        "TeleportPartyAsync",
    }

    local function record(method, args)
        LAST_CALL.method = method
        LAST_CALL.target = args and args[1] or nil
        LAST_CALL.time   = os.time()
        state:bump("teleport_attempts")
        state:set_last("teleport_target", LAST_CALL.target)
        state:set_last("teleport_time",   LAST_CALL.time)
        state:journal("teleports", {
            method = method,
            target = tostring(LAST_CALL.target),
            time   = LAST_CALL.time,
            result = "blocked",
        })
    end

    local function make_handler(method_name)
        return function(ctx)
            if ALLOW_ONCE then
                ALLOW_ONCE = false
                L:warn("allow_once consumed for %s", method_name)
                state:bump("teleport_allowed")
                return
            end
            ctx.drop = true
            ctx.why  = "silencers/teleport_block"
            record(method_name, ctx.args)
            state:bump("teleport_blocked")
            state:emit("TeleportBlocked", method_name, ctx.args[1])
            L:warn("blocked TeleportService:%s target=%s",
                method_name, tostring(ctx.args[1]))
        end
    end

    local function hook_init_failed()
        local ts = env.TeleportService
        if not ts then return end
        local ok, evt = pcall(function() return ts.TeleportInitFailed end)
        if not ok or not evt then return end
        pcall(function()
            evt:Connect(function(player, result, err)
                state:bump("teleport_blocked")
                L:warn("suppressed TeleportInitFailed player=%s result=%s err=%s",
                    tostring(player), tostring(result), tostring(err))
            end)
        end)
    end

    function M.install()
        if INSTALLED then return end
        if not cfg:get("silencers.teleport_block.enabled", true) then
            L:info("disabled via config")
            return
        end

        for _, m in ipairs(BLOCKED_METHODS) do
            namecall.register({
                name     = "silencer_teleport_block_" .. m,
                priority = 18,
                method   = m,
                class    = "TeleportService",
                handler  = make_handler(m),
            })
        end

        hook_init_failed()
        INSTALLED = true
        L:info("teleport_block silencer active (%d methods guarded)",
            #BLOCKED_METHODS)
    end

    function M.allow_once()
        ALLOW_ONCE = true
        L:warn("teleport allow_once armed")
    end

    function M.is_armed() return ALLOW_ONCE end

    function M.last_call()
        return {
            method = LAST_CALL.method,
            target = LAST_CALL.target,
            time   = LAST_CALL.time,
        }
    end

    function M.block_count()
        return state:counter("teleport_blocked")
    end

    return M

end

end
__MODULES__['spoof/fingerprint_cleaner'] = function(require)
--[[ ================================================================
    src/spoof/fingerprint_cleaner.lua
    ----------------------------------
    Wipes executor-identifying globals that AC scans for.

    The AC client-side probe enumerates well-known executor globals
    (syn, KRNL_LOADED, Drawing, getmacsploituser, ...) and bundles
    the hit list into its UpdateProfile telemetry. Our goal: present
    a vanilla-looking env.

    IMPORTANT: the wipe is destructive - once `Drawing` is nil'd,
    ESP modules that rely on it stop working. For this reason EVERY
    option in this module defaults to FALSE. Operators have to
    flip them on in config / profile explicitly. When enabled,
    the wipes are thorough and re-applied periodically so scripts
    that restore the globals after load get caught again.

    Strategy:
      * Three target buckets, independently toggleable:
          - wipe_drawing          (Drawing.new, Drawing, drawfont)
          - wipe_executor_globals (syn, KRNL_*, fluxus, ...)
          - wipe_syn_names        (syn_request, syn_crypt, ...)
      * `wipe_now()` performs a single pass.
      * Heartbeat task repeats the pass every N seconds so recreated
        globals don't accumulate.
      * Wipes BOTH getfenv(0) AND _G, plus getgenv() when available,
        so exec-level and shared-env-level globals both die.
      * `add_target(name)` lets other modules push extra names in.

    No module outside here should poke these globals except via the
    published `wipe_now` entry point.
================================================================ ]]

return function(require)

    local env   = require("core/env")
    local log   = require("core/log")
    local cfg   = require("core/config")
    local state = require("core/state")

    local M = {}
    local L = log.scoped("spoof/fingerprint_cleaner")

    -- ----------------------------------------------------------------
    -- target lists
    -- ----------------------------------------------------------------

    -- Drawing UI surface that most executors ship.
    local DRAWING_TARGETS = {
        "Drawing",
        "drawfont",
        "cleardrawcache",
        "isrenderobj",
        "getrenderproperty",
        "setrenderproperty",
    }

    -- Generic executor-identity globals.
    local EXECUTOR_GLOBALS = {
        -- Synapse-X family
        "syn",
        "synapse",
        -- KRNL
        "KRNL_LOADED",
        "KRNL_VERSION",
        "krnl",
        -- Fluxus
        "fluxus",
        "FLUXUS",
        -- Hydrogen
        "hydrogen",
        "HYDROGEN",
        -- Arceus
        "arceusx",
        "ARCEUS_X",
        -- Celery
        "celery",
        "CELERY_LOADED",
        -- CometX
        "cometx",
        -- Scriptware
        "scriptware",
        "SCRIPTWARE_VERSION",
        -- Delta
        "DELTA_EXECUTOR",
        "delta_executor",
        -- MacSploit
        "getmacsploituser",
        "is_macsploit_function",
        "macsploit_bypass",
        -- CodeX
        "CODEX_VERSION",
        -- Opiumware
        "OPIUMWARE",
        "opiumware",
        -- Generic probes
        "identifyexecutor",
        "getexecutorname",
        "is_sirhurt_closure",
        "is_protosmasher_closure",
    }

    -- Synapse-style named helper functions.
    local SYN_NAMES = {
        "syn_request",
        "syn_crypt",
        "syn_context_set",
        "syn_context_get",
        "syn_queue_on_teleport",
        "queue_on_teleport",
        "decompile",
        "getscriptbytecode",
        "getscripthash",
        "http_request",
        "http",
        "websocket",
        "WebSocket",
    }

    -- User-added targets. Flat strings, union'd into the default
    -- lists during a wipe. These are wiped regardless of which
    -- bucket toggles are on (an operator who added a custom target
    -- wants it gone).
    local EXTRA_TARGETS = {}

    -- Per-module stats.
    local STATS = {
        cycles        = 0,
        names_nilled  = 0,
        last_cycle_t  = 0,
        last_hit_list = {},
    }

    -- ----------------------------------------------------------------
    -- env accessors
    -- ----------------------------------------------------------------

    local function get_genv()
        if type(getgenv) == "function" then
            local ok, g = pcall(getgenv)
            if ok and type(g) == "table" then return g end
        end
        return nil
    end

    local function get_fenv0()
        local ok, g = pcall(getfenv, 0)
        if ok and type(g) == "table" then return g end
        return nil
    end

    -- Try to delete a single global name across every reachable env.
    -- Returns true if at least one env surrendered the value.
    local function nil_global(name)
        local hit = false

        local g1 = get_fenv0()
        if g1 and rawget(g1, name) ~= nil then
            local ok = pcall(function() g1[name] = nil end)
            if ok then hit = true end
        end

        if rawget(_G, name) ~= nil then
            local ok = pcall(function() _G[name] = nil end)
            if ok then hit = true end
        end

        local gg = get_genv()
        if gg and rawget(gg, name) ~= nil then
            local ok = pcall(function() gg[name] = nil end)
            if ok then hit = true end
        end

        return hit
    end

    -- ----------------------------------------------------------------
    -- special-cased wipes
    -- ----------------------------------------------------------------

    -- Drawing needs a careful touch: some executors expose it as
    -- a table whose .new is the public factory. Nilling Drawing.new
    -- alone is usually enough; nilling the table too makes the
    -- "has Drawing global?" probe fail.
    local function wipe_drawing_surface()
        local hits = 0
        local g1 = get_fenv0()
        if g1 and type(g1.Drawing) == "table" then
            local ok = pcall(function() g1.Drawing.new = nil end)
            if ok then hits = hits + 1 end
        end
        if type(_G.Drawing) == "table" then
            local ok = pcall(function() _G.Drawing.new = nil end)
            if ok then hits = hits + 1 end
        end
        local gg = get_genv()
        if gg and type(gg.Drawing) == "table" then
            local ok = pcall(function() gg.Drawing.new = nil end)
            if ok then hits = hits + 1 end
        end
        for _, n in ipairs(DRAWING_TARGETS) do
            if nil_global(n) then hits = hits + 1 end
        end
        return hits
    end

    -- ----------------------------------------------------------------
    -- wipe pass
    -- ----------------------------------------------------------------

    local function dedupe_targets()
        local seen = {}
        local function push_from(list, out)
            for _, n in ipairs(list) do
                if type(n) == "string" and not seen[n] then
                    seen[n] = true
                    table.insert(out, n)
                end
            end
        end
        local active = {}
        if cfg:get("spoof.fingerprint_cleaner.wipe_executor_globals", false) then
            push_from(EXECUTOR_GLOBALS, active)
        end
        if cfg:get("spoof.fingerprint_cleaner.wipe_syn_names", false) then
            push_from(SYN_NAMES, active)
        end
        -- extras are always applied if any bucket is enabled
        push_from(EXTRA_TARGETS, active)
        return active
    end

    local function do_pass()
        local hits = 0
        local hit_list = {}

        if cfg:get("spoof.fingerprint_cleaner.wipe_drawing", false) then
            local n = wipe_drawing_surface()
            if n > 0 then
                hits = hits + n
                table.insert(hit_list, string.format("drawing(%d)", n))
            end
        end

        local active = dedupe_targets()
        for _, name in ipairs(active) do
            if nil_global(name) then
                hits = hits + 1
                table.insert(hit_list, name)
            end
        end

        STATS.cycles       = STATS.cycles + 1
        STATS.names_nilled = STATS.names_nilled + hits
        STATS.last_cycle_t = tick()
        STATS.last_hit_list = hit_list

        if hits > 0 then
            state:bump("fingerprint_wipes")
            L:debug("wiped %d fingerprint surfaces: %s",
                hits, table.concat(hit_list, ","))
        end
        return hits
    end

    -- ----------------------------------------------------------------
    -- public API
    -- ----------------------------------------------------------------

    function M.wipe_now()
        if not cfg:get("spoof.fingerprint_cleaner.enabled", true) then
            return 0
        end
        _G.__GRG_THREAD = _G.__GRG_THREAD or true
        return do_pass()
    end

    function M.add_target(global_name)
        if type(global_name) ~= "string" or global_name == "" then
            error("add_target(name): name must be non-empty string", 2)
        end
        for _, existing in ipairs(EXTRA_TARGETS) do
            if existing == global_name then return end
        end
        table.insert(EXTRA_TARGETS, global_name)
        L:info("added target %q", global_name)
    end

    function M.remove_target(global_name)
        for i, existing in ipairs(EXTRA_TARGETS) do
            if existing == global_name then
                table.remove(EXTRA_TARGETS, i)
                return true
            end
        end
        return false
    end

    function M.targets()
        local out = {
            drawing        = {},
            executor       = {},
            syn            = {},
            extra          = {},
        }
        for _, n in ipairs(DRAWING_TARGETS)   do table.insert(out.drawing, n)  end
        for _, n in ipairs(EXECUTOR_GLOBALS)  do table.insert(out.executor, n) end
        for _, n in ipairs(SYN_NAMES)         do table.insert(out.syn, n)      end
        for _, n in ipairs(EXTRA_TARGETS)     do table.insert(out.extra, n)    end
        return out
    end

    function M.stats()
        local out = {}
        for k, v in pairs(STATS) do
            if type(v) == "table" then
                local copy = {}
                for _, vv in ipairs(v) do table.insert(copy, vv) end
                out[k] = copy
            else
                out[k] = v
            end
        end
        return out
    end

    -- ----------------------------------------------------------------
    -- heartbeat loop
    -- ----------------------------------------------------------------

    local INTERVAL = 5.0  -- seconds between periodic re-wipes

    local function start_loop()
        if not env.RunService then
            L:warn("RunService unavailable; periodic re-wipe disabled")
            return
        end

        local accum = 0
        env.RunService.Heartbeat:Connect(function(dt)
            accum = accum + dt
            if accum < INTERVAL then return end
            accum = 0
            if not cfg:get("spoof.fingerprint_cleaner.enabled", true) then return end
            -- If every bucket is off we still run, because extras
            -- may need clearing. do_pass itself no-ops when no
            -- targets match.
            _G.__GRG_THREAD = _G.__GRG_THREAD or true
            local ok, err = pcall(do_pass)
            if not ok then
                L:warn("periodic pass errored: %s", tostring(err))
            end
        end)
    end

    function M.install()
        if not cfg:get("spoof.fingerprint_cleaner.enabled", true) then
            L:info("disabled via config")
            return
        end

        -- Initial pass: fine even if every bucket is off.
        M.wipe_now()

        start_loop()

        L:info("fingerprint cleaner installed (drawing=%s, exec=%s, syn=%s)",
            tostring(cfg:get("spoof.fingerprint_cleaner.wipe_drawing", false)),
            tostring(cfg:get("spoof.fingerprint_cleaner.wipe_executor_globals", false)),
            tostring(cfg:get("spoof.fingerprint_cleaner.wipe_syn_names", false)))
    end

    return M

end

end
__MODULES__['spoof/player_telemetry'] = function(require)
--[[ ================================================================
    src/spoof/player_telemetry.lua
    -------------------------------
    Rewrites outgoing client-to-server telemetry so the AC server
    never sees cheat-like string fragments or suspicious asset
    names in our traffic. Complements scrubbers/updateprofile,
    which clamps numerics; this one targets identity/string fields.

    Two entry points:
      * Named hook on "UpdateProfile" (the main telemetry remote
        in the target game) - always scanned when the module is on.
      * Wildcard hook that opportunistically peeks at the first
        argument of every outgoing FireServer/InvokeServer; if it
        looks like a telemetry blob (plain table containing any of
        walkSpeed / position / state / currentAnimation), we scan
        and rewrite it the same way.

    Rewrite rules:
      * Strings that match a known cheat-hallmark pattern are
        replaced with a randomly-picked plausible Roblox string
        from POOL. Patterns are case-insensitive string.find
        patterns (NOT Lua %-patterns on the value itself - they
        are plain-text substrings applied with string.find(... ,
        true)).
      * Scanning is recursive with a hard depth cap so we don't
        hang on cyclic tables. Visited-table cycle break too.
      * Every per-payload rewrite counts as one `profile_spoofs`
        bump regardless of how many strings we replaced.

    Public API:
        M.install()
        M.add_pattern(pat, replacement?)  -- replacement optional,
                                             else pulls from POOL
        M.pool_add(str)
        M.stats()
================================================================ ]]

return function(require)

    local env   = require("core/env")
    local log   = require("core/log")
    local cfg   = require("core/config")
    local state = require("core/state")

    local fire  = require("hooks/fire_handlers")

    local M = {}
    local L = log.scoped("spoof/player_telemetry")

    -- ----------------------------------------------------------------
    -- configuration constants
    -- ----------------------------------------------------------------

    local MAX_DEPTH      = 6
    local MAX_TABLE_KEYS = 512
    local MAX_STRING_LEN = 8192

    -- Pool of plausible Roblox-ish strings used as replacements.
    -- The runtime can extend this via M.pool_add().
    local POOL = {
        "Workspace.Part",
        "Workspace.Terrain",
        "Workspace.Baseplate",
        "MovementController",
        "CameraController",
        "DefaultChatSystemChatEvents",
        "CoreGui.RobloxGui.Modules.Common.MovementController",
        "PlayerScripts.PlayerModule",
        "PlayerScripts.PlayerModule.ControlModule",
        "ReplicatedStorage.Shared.Replicator",
        "StarterPlayerScripts.ChatClient",
        "CoreGui.RobloxGui.Modules.PlayerList.PlayerListManager",
        "Players.LocalPlayer.Backpack",
        "Workspace.CurrentCamera",
        "Game.Chat.ChatScript",
    }

    -- Patterns flagged as "looks like a cheat fingerprint".
    -- Applied via lowercase string.find(value, pat, 1, true) so
    -- they are plain substrings, NOT Lua magic patterns.
    local PATTERNS = {
        { pat = "grg",       replacement = nil },
        { pat = "hub",       replacement = nil },
        { pat = "exploit",   replacement = nil },
        { pat = "cheat",     replacement = nil },
        { pat = "sploit",    replacement = nil },
        { pat = "synapse",   replacement = nil },
        { pat = "krnl",      replacement = nil },
        { pat = "fluxus",    replacement = nil },
        { pat = "hydrogen",  replacement = nil },
        { pat = "scriptware",replacement = nil },
        { pat = "macsploit", replacement = nil },
        { pat = "opiumware", replacement = nil },
        { pat = "bypass",    replacement = nil },
        { pat = "executor",  replacement = nil },
        { pat = "injector",  replacement = nil },
        { pat = "autofarm",  replacement = nil },
        { pat = "aimbot",    replacement = nil },
        { pat = "wallhack",  replacement = nil },
    }

    -- Field names that signal "this table is telemetry".
    local TELEMETRY_KEYS = {
        walkSpeed      = true,
        walkspeed      = true,
        WalkSpeed      = true,
        jumpPower      = true,
        JumpPower      = true,
        position       = true,
        Position       = true,
        pos            = true,
        cframe         = true,
        CFrame         = true,
        state          = true,
        State          = true,
        currentAnimation = true,
        hrpVelocity    = true,
        velocity       = true,
        health         = true,
        Health         = true,
    }

    -- Stats we keep for the UI / debugging.
    local STATS = {
        payloads_scanned  = 0,
        payloads_rewritten = 0,
        strings_rewritten = 0,
        keys_rewritten    = 0,
    }

    -- ----------------------------------------------------------------
    -- helpers
    -- ----------------------------------------------------------------

    local function pool_pick()
        if #POOL == 0 then return "MovementController" end
        return POOL[math.random(1, #POOL)]
    end

    local function lower_safe(s)
        if type(s) ~= "string" then return "" end
        local ok, v = pcall(string.lower, s)
        if ok then return v end
        return ""
    end

    local function string_is_suspicious(s)
        if type(s) ~= "string" or #s == 0 then return false, nil end
        if #s > MAX_STRING_LEN then return false, nil end
        local lowered = lower_safe(s)
        for _, p in ipairs(PATTERNS) do
            if string.find(lowered, p.pat, 1, true) then
                return true, p
            end
        end
        return false, nil
    end

    local function replacement_for(p)
        if p and type(p.replacement) == "string" then
            return p.replacement
        end
        return pool_pick()
    end

    local function looks_like_telemetry(t)
        if type(t) ~= "table" then return false end
        local n = 0
        for k in pairs(t) do
            n = n + 1
            if TELEMETRY_KEYS[k] then return true end
            if n > 32 then break end
        end
        return false
    end

    -- ----------------------------------------------------------------
    -- recursive rewrite
    -- ----------------------------------------------------------------

    -- Walk a table in-place and replace suspicious strings.
    -- Returns the number of replacements performed (0 if none).
    local function rewrite_table(t, depth, visited)
        if type(t) ~= "table" then return 0 end
        if depth > MAX_DEPTH then return 0 end
        if visited[t] then return 0 end
        visited[t] = true

        local hits = 0
        local seen_keys = 0

        -- We collect key renames and apply them after the traversal
        -- to avoid mutating the table while iterating.
        local rename_ops = nil

        for k, v in pairs(t) do
            seen_keys = seen_keys + 1
            if seen_keys > MAX_TABLE_KEYS then break end

            -- value rewrite ---------------------------------------
            if type(v) == "string" then
                local bad, p = string_is_suspicious(v)
                if bad then
                    t[k] = replacement_for(p)
                    hits = hits + 1
                    STATS.strings_rewritten = STATS.strings_rewritten + 1
                end
            elseif type(v) == "table" then
                hits = hits + rewrite_table(v, depth + 1, visited)
            end

            -- key rewrite (rare, but some payloads stuff hashes as
            -- table keys - cover that too).
            if type(k) == "string" then
                local bad, p = string_is_suspicious(k)
                if bad then
                    rename_ops = rename_ops or {}
                    table.insert(rename_ops, { old = k, new = replacement_for(p) })
                end
            end
        end

        if rename_ops then
            for _, op in ipairs(rename_ops) do
                local v = t[op.old]
                t[op.old] = nil
                if t[op.new] == nil then
                    t[op.new] = v
                end
                hits = hits + 1
                STATS.keys_rewritten = STATS.keys_rewritten + 1
            end
        end

        return hits
    end

    local function rewrite_args(args, n_args)
        if type(args) ~= "table" then return 0 end
        local visited = {}
        local total = 0
        for i = 1, n_args or #args do
            local v = args[i]
            if type(v) == "string" then
                local bad, p = string_is_suspicious(v)
                if bad then
                    args[i] = replacement_for(p)
                    total = total + 1
                    STATS.strings_rewritten = STATS.strings_rewritten + 1
                end
            elseif type(v) == "table" then
                total = total + rewrite_table(v, 1, visited)
            end
        end
        return total
    end

    -- ----------------------------------------------------------------
    -- handlers
    -- ----------------------------------------------------------------

    local function gated()
        if not cfg:get("spoof.player_telemetry.enabled", true) then
            return false
        end
        if not cfg:get("spoof.player_telemetry.forbid_suspicious_names", true) then
            return false
        end
        return true
    end

    local function on_update_profile(ctx)
        if not gated() then return end
        STATS.payloads_scanned = STATS.payloads_scanned + 1
        local hits = rewrite_args(ctx.args, ctx.n_args)
        if hits > 0 then
            STATS.payloads_rewritten = STATS.payloads_rewritten + 1
            state:bump("profile_spoofs")
            L:debug("UpdateProfile: rewrote %d suspicious values", hits)
        end
    end

    local function on_any_telemetry_like(ctx)
        if not gated() then return end
        -- We're on the wildcard path so we should be cheap: only
        -- inspect the FIRST arg and only when it looks like telemetry.
        local first = ctx.args and ctx.args[1]
        if not looks_like_telemetry(first) then return end

        STATS.payloads_scanned = STATS.payloads_scanned + 1
        local visited = {}
        local hits = rewrite_table(first, 1, visited)

        -- Also sniff sibling args if arg1 matched (some APIs split
        -- state into arg1 = position table, arg2 = extras table).
        if ctx.n_args and ctx.n_args > 1 then
            for i = 2, ctx.n_args do
                local v = ctx.args[i]
                if type(v) == "table" then
                    hits = hits + rewrite_table(v, 1, visited)
                elseif type(v) == "string" then
                    local bad, p = string_is_suspicious(v)
                    if bad then
                        ctx.args[i] = replacement_for(p)
                        hits = hits + 1
                        STATS.strings_rewritten = STATS.strings_rewritten + 1
                    end
                end
            end
        end

        if hits > 0 then
            STATS.payloads_rewritten = STATS.payloads_rewritten + 1
            state:bump("profile_spoofs")
            L:debug("wildcard telemetry payload: rewrote %d values", hits)
        end
    end

    -- ----------------------------------------------------------------
    -- public API
    -- ----------------------------------------------------------------

    function M.add_pattern(pat, replacement)
        if type(pat) ~= "string" or pat == "" then
            error("add_pattern(pat, replacement?): pat must be non-empty string", 2)
        end
        table.insert(PATTERNS, {
            pat = lower_safe(pat),
            replacement = type(replacement) == "string" and replacement or nil,
        })
        L:info("added pattern %q", pat)
    end

    function M.pool_add(s)
        if type(s) ~= "string" or s == "" then return end
        table.insert(POOL, s)
    end

    function M.stats()
        local out = {}
        for k, v in pairs(STATS) do out[k] = v end
        return out
    end

    -- Force-scan a value now (for debugging / other modules plumbing
    -- their own payloads through us). Returns number of hits.
    function M.rewrite(value)
        if type(value) ~= "table" then
            if type(value) == "string" then
                local bad, p = string_is_suspicious(value)
                if bad then
                    STATS.strings_rewritten = STATS.strings_rewritten + 1
                    return 1, replacement_for(p)
                end
            end
            return 0, value
        end
        local hits = rewrite_table(value, 1, {})
        return hits, value
    end

    function M.install()
        if not cfg:get("spoof.player_telemetry.enabled", true) then
            L:info("disabled via config")
            return
        end

        _G.__GRG_THREAD = _G.__GRG_THREAD or true

        fire.on_name("UpdateProfile", {
            name     = "spoof_telemetry_updateprofile",
            priority = 40,
            kind     = "both",
            handler  = on_update_profile,
        })

        fire.on_any({
            name     = "spoof_telemetry_wildcard",
            priority = 60,
            kind     = "both",
            handler  = on_any_telemetry_like,
        })

        L:info("telemetry spoof active (patterns=%d, pool=%d)",
            #PATTERNS, #POOL)
    end

    return M

end

end
__MODULES__['spoof/script_signature'] = function(require)
--[[ ================================================================
    src/spoof/script_signature.lua
    -------------------------------
    Renames LocalScripts / ModuleScripts in PlayerScripts whose Name
    matches cheat-hallmark patterns (or that are owned by us and
    shouldn't advertise it). Benign replacement names come from
    the config `spoof.script_signature.fake_source_patterns`.

    Two entry points:

      * Bulk scan pass (`M.rename_now`): walks every descendant of
        LocalPlayer.PlayerScripts and Backpack, renaming matches.
        Run once at install, then again when PlayerScripts gets a
        child added.

      * Instance.new hook: via hooks/hookfunction we wrap the
        global Instance.new. When a LocalScript/ModuleScript is
        created whose name already matches a suspicious pattern
        we rewrite the Name immediately - before any server-side
        replicator can observe it.

    Patterns are lowercase plain substrings matched with
    string.find(lowered, pat, 1, true). Replacement comes from a
    random pick out of the config fake_source_patterns list.

    Public API:
        M.install()
        M.rename_now()      -- returns count
        M.add_pattern(pat, replacement?)
        M.stats()
================================================================ ]]

return function(require)

    local env   = require("core/env")
    local log   = require("core/log")
    local cfg   = require("core/config")
    local state = require("core/state")

    local hookfn = require("hooks/hookfunction")

    local M = {}
    local L = log.scoped("spoof/script_signature")

    -- ----------------------------------------------------------------
    -- patterns
    -- ----------------------------------------------------------------

    -- Plain lowercase substrings. Second field is an optional
    -- hard-coded replacement; nil means pick from config list.
    local PATTERNS = {
        { pat = "grg",      replacement = nil },
        { pat = "hub",      replacement = nil },
        { pat = "cheat",    replacement = nil },
        { pat = "exploit",  replacement = nil },
        { pat = "hack",     replacement = nil },
        { pat = "injector", replacement = nil },
        { pat = "bypass",   replacement = nil },
        { pat = "sploit",   replacement = nil },
        { pat = "opium",    replacement = nil },
        { pat = "aimbot",   replacement = nil },
        { pat = "autofarm", replacement = nil },
        { pat = "wallhack", replacement = nil },
    }

    local STATS = {
        bulk_scans      = 0,
        renamed_total   = 0,
        newcreate_hits  = 0,
        last_rename_t   = 0,
    }

    -- Track what we've already renamed so we don't loop-rename in
    -- subsequent scans (the new name could itself contain a word
    -- that accidentally matches).
    local ALREADY_RENAMED = setmetatable({}, { __mode = "k" })

    -- ----------------------------------------------------------------
    -- helpers
    -- ----------------------------------------------------------------

    local function lower_safe(s)
        if type(s) ~= "string" then return "" end
        local ok, v = pcall(string.lower, s)
        if ok then return v end
        return ""
    end

    local function pick_replacement(patt_replacement)
        if type(patt_replacement) == "string" and patt_replacement ~= "" then
            return patt_replacement
        end
        local list = cfg:get("spoof.script_signature.fake_source_patterns", nil)
        if type(list) == "table" and #list > 0 then
            return list[math.random(1, #list)]
        end
        local fallback = { "MovementController", "CameraController",
                           "DefaultChatSystemChatEvents" }
        return fallback[math.random(1, #fallback)]
    end

    local function name_is_suspicious(name)
        if type(name) ~= "string" or name == "" then return false, nil end
        local low = lower_safe(name)
        for _, p in ipairs(PATTERNS) do
            if p.pat ~= "" and string.find(low, p.pat, 1, true) then
                return true, p
            end
        end
        return false, nil
    end

    local function try_rename(inst)
        if typeof(inst) ~= "Instance" then return false end
        if ALREADY_RENAMED[inst] then return false end

        local ok_cls, is_script = pcall(function()
            return inst:IsA("LocalScript") or inst:IsA("ModuleScript")
        end)
        if not ok_cls or not is_script then return false end

        local ok_n, name = pcall(function() return inst.Name end)
        if not ok_n or type(name) ~= "string" then return false end

        local bad, patt = name_is_suspicious(name)
        if not bad then return false end

        local new_name = pick_replacement(patt and patt.replacement)
        local ok_set, err = pcall(function() inst.Name = new_name end)
        if not ok_set then
            L:warn("rename failed on %s: %s", tostring(name), tostring(err))
            return false
        end

        ALREADY_RENAMED[inst] = true
        STATS.renamed_total = STATS.renamed_total + 1
        STATS.last_rename_t = tick()
        L:debug("renamed %q -> %q", name, new_name)
        return true
    end

    -- ----------------------------------------------------------------
    -- bulk scan
    -- ----------------------------------------------------------------

    local function iter_roots()
        local roots = {}
        if env.PlayerScripts then table.insert(roots, env.PlayerScripts) end
        if env.Backpack    then table.insert(roots, env.Backpack)    end
        if env.LocalPlayer then
            local pg = env.LocalPlayer:FindFirstChild("PlayerGui")
            if pg then table.insert(roots, pg) end
            local sc = env.LocalPlayer:FindFirstChild("StarterCharacter")
            if sc then table.insert(roots, sc) end
        end
        return roots
    end

    local function scan_root(root)
        local hits = 0
        local ok, descendants = pcall(function() return root:GetDescendants() end)
        if not ok or type(descendants) ~= "table" then return 0 end
        for _, inst in ipairs(descendants) do
            if try_rename(inst) then hits = hits + 1 end
        end
        return hits
    end

    function M.rename_now()
        if not cfg:get("spoof.script_signature.enabled", true) then return 0 end
        if not cfg:get("spoof.script_signature.rename_localscripts", true) then
            return 0
        end

        _G.__GRG_THREAD = _G.__GRG_THREAD or true

        local total = 0
        for _, root in ipairs(iter_roots()) do
            total = total + scan_root(root)
        end

        STATS.bulk_scans = STATS.bulk_scans + 1
        if total > 0 then
            L:info("bulk rename pass: %d scripts retagged", total)
        end
        return total
    end

    -- ----------------------------------------------------------------
    -- Instance.new hook
    -- ----------------------------------------------------------------

    local function install_instance_new_hook()
        local g = getfenv(0)
        if type(g.Instance) ~= "table" and type(g.Instance) ~= "userdata" then
            -- Instance is a global table-ish proxy on Luau; if it
            -- isn't here we can't hook Instance.new safely.
            L:warn("Instance global missing; skipping Instance.new hook")
            return
        end
        -- Instance.new is usually a plain function on the Instance
        -- table. We hook through hookfn so other modules can also
        -- layer hooks cleanly.
        local inst_table = g.Instance
        local new_fn
        local ok = pcall(function() new_fn = inst_table.new end)
        if not ok or type(new_fn) ~= "function" then
            L:warn("Instance.new not a function; skipping hook")
            return
        end

        hookfn.hook(inst_table, "new", {
            name     = "spoof_script_signature_instnew",
            priority = 80,
            handler  = function(ctx)
                -- args: (className, parent?)
                local className = ctx.args and ctx.args[1]
                if className ~= "LocalScript" and className ~= "ModuleScript" then
                    return
                end
                -- We let the original run and inspect the returned
                -- script in the after-phase so we don't have to
                -- guess what Name the engine assigns by default.
                ctx.after = function(ret)
                    if type(ret) ~= "table" then return ret end
                    local new_obj = ret[1]
                    if typeof(new_obj) == "Instance" then
                        local ok2 = pcall(function()
                            if try_rename(new_obj) then
                                STATS.newcreate_hits = STATS.newcreate_hits + 1
                            end
                        end)
                        if not ok2 then
                            -- swallowed: rename on a brand-new obj
                            -- can fail if the engine locks Name
                            -- until parented.
                        end
                    end
                    return ret
                end
            end,
        })
        L:info("Instance.new hook installed")
    end

    -- ----------------------------------------------------------------
    -- public API
    -- ----------------------------------------------------------------

    function M.add_pattern(pattern, replacement)
        if type(pattern) ~= "string" or pattern == "" then
            error("add_pattern(pat, replacement?): pat must be non-empty string", 2)
        end
        table.insert(PATTERNS, {
            pat = lower_safe(pattern),
            replacement = type(replacement) == "string" and replacement or nil,
        })
        L:info("added pattern %q", pattern)
    end

    function M.stats()
        local out = {}
        for k, v in pairs(STATS) do out[k] = v end
        return out
    end

    function M.install()
        if not cfg:get("spoof.script_signature.enabled", true) then
            L:info("disabled via config")
            return
        end

        -- Initial bulk pass.
        M.rename_now()

        -- Re-scan when new scripts arrive in PlayerScripts.
        if env.PlayerScripts then
            env.PlayerScripts.DescendantAdded:Connect(function(desc)
                if not cfg:get("spoof.script_signature.rename_localscripts", true) then
                    return
                end
                _G.__GRG_THREAD = _G.__GRG_THREAD or true
                pcall(try_rename, desc)
            end)
        end
        if env.Backpack then
            env.Backpack.DescendantAdded:Connect(function(desc)
                if not cfg:get("spoof.script_signature.rename_localscripts", true) then
                    return
                end
                _G.__GRG_THREAD = _G.__GRG_THREAD or true
                pcall(try_rename, desc)
            end)
        end

        install_instance_new_hook()

        L:info("script signature spoof active (patterns=%d)", #PATTERNS)
    end

    return M

end

end
__MODULES__['spoof/server_state'] = function(require)
--[[ ================================================================
    src/spoof/server_state.lua
    ---------------------------
    Client-side short-circuit for server-initiated probe remotes.

    The hostile GRG server periodically InvokeServers things like
    "PingCheck", "Heartbeat", "ChallengeToken", "ClientNonce" to
    build a liveness / latency / consistency profile of the client.
    A real client's replies follow a predictable shape, and missing
    or mis-shaped replies are a strong cheat signal.

    This module intercepts those invocations at the fire_handlers
    layer and short-circuits them BEFORE they hit the wire, meaning
    the server never sees the real client round-trip. We return a
    plausible reply instead:

      * Ping / Heartbeat  -> { ok = true, ts = tick() }
      * Challenge / Nonce -> echoes the first-arg nonce back, plus
                             our fake ack blob.
      * Custom            -> registered via M.add_reply_pattern().

    We also intentionally INJECT a tiny random latency between
    reply_latency_ms_min and reply_latency_ms_max before handing
    back the value, so the server-side "round-trip time" metric
    looks normal and doesn't show up as a single-tick anomaly.

    Short-circuiting uses fire_handlers' `ctx.short_circuit=true`
    plus `ctx.spoof = { ...values }` semantics.

    Public API:
        M.install()
        M.add_reply_pattern(pattern, reply_fn)
        M.drop_pattern(pattern)
        M.stats()
================================================================ ]]

return function(require)

    local env   = require("core/env")
    local log   = require("core/log")
    local cfg   = require("core/config")
    local state = require("core/state")

    local fire  = require("hooks/fire_handlers")

    local M = {}
    local L = log.scoped("spoof/server_state")

    -- ----------------------------------------------------------------
    -- default pattern book
    -- ----------------------------------------------------------------

    -- Each entry: { pat = "...", kind = "Ping"/"Challenge"/"Custom",
    --               reply_fn = function(ctx) return spoof_array end }
    -- Patterns are plain lowercased substrings applied with
    -- string.find(name, pat, 1, true).
    local PATTERNS = {}

    local STATS = {
        probes_seen      = 0,
        probes_spoofed   = 0,
        ping_spoofed     = 0,
        challenge_spoofed= 0,
        custom_spoofed   = 0,
        total_latency_ms = 0,
    }

    local function lower_safe(s)
        if type(s) ~= "string" then return "" end
        local ok, v = pcall(string.lower, s)
        if ok then return v end
        return ""
    end

    -- ----------------------------------------------------------------
    -- reply builders
    -- ----------------------------------------------------------------

    local function pack_spoof(...)
        local n = select("#", ...)
        local t = table.pack(...)
        t.n = n
        return t
    end

    local function reply_ping(ctx)
        return pack_spoof({
            ok = true,
            ts = tick(),
            seq = math.random(1, 2^20),
        })
    end

    local function reply_heartbeat(ctx)
        return pack_spoof({
            ok = true,
            ts = tick(),
            health = 1,
        })
    end

    local function reply_challenge(ctx)
        -- Echo the nonce if present. Most challenge protocols shape:
        --   InvokeServer("Challenge", nonce, optional_extra)
        -- and expect the nonce returned as-is or wrapped.
        local nonce = ctx.args and ctx.args[1]
        if nonce == nil then
            nonce = math.random(1, 2^30)
        end
        return pack_spoof({
            ok    = true,
            ts    = tick(),
            nonce = nonce,
            ack   = true,
        })
    end

    local function reply_nonce(ctx)
        local nonce = ctx.args and ctx.args[1]
        if type(nonce) == "string" then
            return pack_spoof(nonce)
        end
        if type(nonce) == "number" then
            return pack_spoof(nonce)
        end
        return pack_spoof(tostring(nonce or math.random()))
    end

    -- Seed the default book.
    local function seed_defaults()
        PATTERNS = {
            { pat = "pingcheck",  kind = "Ping",      reply_fn = reply_ping },
            { pat = "ping",       kind = "Ping",      reply_fn = reply_ping },
            { pat = "heartbeat",  kind = "Ping",      reply_fn = reply_heartbeat },
            { pat = "hb",         kind = "Ping",      reply_fn = reply_heartbeat },
            { pat = "keepalive",  kind = "Ping",      reply_fn = reply_heartbeat },
            { pat = "challenge",  kind = "Challenge", reply_fn = reply_challenge },
            { pat = "nonce",      kind = "Challenge", reply_fn = reply_nonce },
            { pat = "verifytoken",kind = "Challenge", reply_fn = reply_challenge },
            { pat = "ackclient",  kind = "Ping",      reply_fn = reply_ping },
        }
    end
    seed_defaults()

    -- ----------------------------------------------------------------
    -- matching
    -- ----------------------------------------------------------------

    local function remote_label(remote_inst)
        if typeof(remote_inst) ~= "Instance" then return nil, nil end
        local ok_n, n = pcall(function() return remote_inst.Name end)
        local ok_f, f = pcall(function() return remote_inst:GetFullName() end)
        local name = ok_n and n or nil
        local full = ok_f and f or nil
        return name, full
    end

    local function match_entry(name, full)
        local l_name = lower_safe(name or "")
        local l_full = lower_safe(full or "")
        for _, entry in ipairs(PATTERNS) do
            if entry.pat ~= "" then
                if string.find(l_name, entry.pat, 1, true)
                   or string.find(l_full, entry.pat, 1, true) then
                    return entry
                end
            end
        end
        return nil
    end

    -- ----------------------------------------------------------------
    -- latency injection
    -- ----------------------------------------------------------------

    local function inject_latency()
        local lo = cfg:get("spoof.server_state.reply_latency_ms_min", 30)
        local hi = cfg:get("spoof.server_state.reply_latency_ms_max", 120)
        if type(lo) ~= "number" or lo < 0 then lo = 0 end
        if type(hi) ~= "number" or hi < lo then hi = lo end
        local ms
        if hi == lo then
            ms = lo
        else
            ms = lo + math.random() * (hi - lo)
        end
        STATS.total_latency_ms = STATS.total_latency_ms + ms
        -- Roblox `wait()` is seconds-precision; use task.wait / wait.
        local seconds = ms / 1000
        if seconds > 0 then
            -- Don't block the namecall path forever. task.wait exists
            -- on modern engines; fall back to wait() on old ones.
            local twait = rawget(getfenv(0), "task")
            if type(twait) == "table" and type(twait.wait) == "function" then
                pcall(twait.wait, seconds)
            else
                pcall(wait, seconds)
            end
        end
    end

    -- ----------------------------------------------------------------
    -- core dispatch handler
    -- ----------------------------------------------------------------

    local function on_any_probe(ctx)
        if not cfg:get("spoof.server_state.enabled", true) then return end
        if not cfg:get("spoof.server_state.reply_to_ping", true) then return end
        if ctx.kind ~= "InvokeServer" then return end

        local name, full = remote_label(ctx.remote)
        if not name and not full then return end

        local entry = match_entry(name, full)
        if not entry then return end

        STATS.probes_seen = STATS.probes_seen + 1
        _G.__GRG_THREAD = _G.__GRG_THREAD or true

        inject_latency()

        local ok, spoof = pcall(entry.reply_fn, ctx)
        if not ok or type(spoof) ~= "table" then
            L:warn("reply_fn for pattern %q failed: %s",
                entry.pat, tostring(spoof))
            return
        end

        ctx.short_circuit = true
        ctx.spoof         = spoof

        STATS.probes_spoofed = STATS.probes_spoofed + 1
        if entry.kind == "Ping" then
            STATS.ping_spoofed = STATS.ping_spoofed + 1
        elseif entry.kind == "Challenge" then
            STATS.challenge_spoofed = STATS.challenge_spoofed + 1
        else
            STATS.custom_spoofed = STATS.custom_spoofed + 1
        end

        state:bump("send_filtered")
        L:debug("spoofed %s probe on %s (pattern=%q)",
            entry.kind, tostring(full or name), entry.pat)
    end

    -- ----------------------------------------------------------------
    -- public API
    -- ----------------------------------------------------------------

    function M.add_reply_pattern(pattern, reply_fn)
        if type(pattern) ~= "string" or pattern == "" then
            error("add_reply_pattern(pat, fn): pat must be non-empty string", 2)
        end
        if type(reply_fn) ~= "function" then
            error("add_reply_pattern(pat, fn): fn must be function", 2)
        end
        table.insert(PATTERNS, {
            pat     = lower_safe(pattern),
            kind    = "Custom",
            reply_fn = function(ctx)
                local ok, ret = pcall(reply_fn, ctx)
                if not ok then
                    L:warn("custom reply_fn errored: %s", tostring(ret))
                    return pack_spoof(nil)
                end
                if type(ret) == "table" and ret.n ~= nil then
                    return ret
                end
                if type(ret) == "table" then
                    return pack_spoof(ret)
                end
                return pack_spoof(ret)
            end,
        })
        L:info("added custom reply pattern %q", pattern)
    end

    function M.drop_pattern(pattern)
        local low = lower_safe(pattern or "")
        for i = #PATTERNS, 1, -1 do
            if PATTERNS[i].pat == low then
                table.remove(PATTERNS, i)
                return true
            end
        end
        return false
    end

    function M.list_patterns()
        local out = {}
        for _, e in ipairs(PATTERNS) do
            table.insert(out, { pattern = e.pat, kind = e.kind })
        end
        return out
    end

    function M.stats()
        local out = {}
        for k, v in pairs(STATS) do out[k] = v end
        if STATS.probes_spoofed > 0 then
            out.avg_latency_ms = STATS.total_latency_ms / STATS.probes_spoofed
        else
            out.avg_latency_ms = 0
        end
        return out
    end

    function M.reset_defaults()
        seed_defaults()
        L:info("patterns reset to defaults")
    end

    function M.install()
        if not cfg:get("spoof.server_state.enabled", true) then
            L:info("disabled via config")
            return
        end

        fire.on_any({
            name     = "spoof_server_state_probe",
            priority = 20,
            kind     = "InvokeServer",
            handler  = on_any_probe,
        })

        L:info("server-state spoof active (patterns=%d, latency=%d-%dms)",
            #PATTERNS,
            cfg:get("spoof.server_state.reply_latency_ms_min", 30),
            cfg:get("spoof.server_state.reply_latency_ms_max", 120))
    end

    return M

end

end
__MODULES__['timing/jitter'] = function(require)
--[[ ================================================================
    src/timing/jitter.lua
    ----------------------
    Pure utility module for random jitter delays. Other modules borrow
    these primitives to humanize cadence (position decoy, profile
    cadence, delayed log flush). The actual bypass wiring that slows
    outgoing FireServer traffic lives in netgate/jitter.lua; this file
    is intentionally side-effect-free.

    Exposed API:
        M.wait(min_ms, max_ms)          -- yield caller thread
        M.sleep_range(min_ms, max_ms)   -- alias of wait
        M.spawn_jittered(fn, mn, mx)    -- task.spawn with lead-in jitter
        M.stagger(fn_list, mn, mx)      -- fire each fn with staggered delay
        M.pick(min_ms, max_ms)          -- return random ms (no wait)

    Implementation notes:
        - We prefer `task.wait` (Roblox modern API) over global `wait`
          because `task.wait` is not throttled by the task scheduler's
          yield budget the same way and is more accurate at small ms.
        - min_ms/max_ms are in MILLISECONDS because most call sites
          think in ms; internally we convert to seconds.
        - We cap minimum wait at 0.005s to avoid busy loops when the
          caller passes (0,0). If they REALLY want zero, they shouldn't
          be calling this; they should skip the call entirely.
================================================================ ]]

return function(require)

    local env = require("core/env")
    local log = require("core/log")
    local cfg = require("core/config")

    local M = {}
    local L = log.scoped("timing/jitter")

    local random = math.random
    local MIN_CLAMP = 0.005

    local task_wait  = (type(task) == "table" and type(task.wait)  == "function") and task.wait  or nil
    local task_spawn = (type(task) == "table" and type(task.spawn) == "function") and task.spawn or nil
    local legacy_wait = _G.wait or wait

    local function do_wait(sec)
        if sec < MIN_CLAMP then sec = MIN_CLAMP end
        if task_wait then
            return task_wait(sec)
        elseif legacy_wait then
            return legacy_wait(sec)
        else
            -- Last-resort spin; should never happen in a real Roblox env.
            local t0 = tick()
            while tick() - t0 < sec do end
            return sec
        end
    end

    local function do_spawn(fn)
        if task_spawn then
            return task_spawn(fn)
        end
        return coroutine.wrap(fn)()
    end

    function M.pick(min_ms, max_ms)
        min_ms = tonumber(min_ms) or 0
        max_ms = tonumber(max_ms) or min_ms
        if max_ms < min_ms then max_ms = min_ms end
        if max_ms <= min_ms then return min_ms end
        return min_ms + random() * (max_ms - min_ms)
    end

    function M.wait(min_ms, max_ms)
        if max_ms == nil then max_ms = min_ms end
        local ms = M.pick(min_ms, max_ms)
        if ms <= 0 then return 0 end
        return do_wait(ms / 1000)
    end

    M.sleep_range = M.wait

    function M.spawn_jittered(fn, min_ms, max_ms)
        if type(fn) ~= "function" then
            L:warn("spawn_jittered: fn is not a function (%s)", type(fn))
            return
        end
        min_ms = min_ms or cfg:get("timing.jitter.min_ms", 0)
        max_ms = max_ms or cfg:get("timing.jitter.max_ms", 10)
        do_spawn(function()
            M.wait(min_ms, max_ms)
            local ok, err = pcall(fn)
            if not ok then
                L:warn("spawn_jittered callback errored: %s", tostring(err))
            end
        end)
    end

    function M.stagger(fn_list, min_ms, max_ms)
        if type(fn_list) ~= "table" then return end
        local acc = 0
        for i, fn in ipairs(fn_list) do
            local delay_ms = M.pick(min_ms or 0, max_ms or 0)
            acc = acc + delay_ms
            local my_wait = acc
            do_spawn(function()
                do_wait(my_wait / 1000)
                local ok, err = pcall(fn)
                if not ok then
                    L:warn("stagger[%d] errored: %s", i, tostring(err))
                end
            end)
        end
    end

    function M.from_cfg(namespace)
        namespace = namespace or "timing.jitter"
        local mn = cfg:get(namespace .. ".min_ms", 0)
        local mx = cfg:get(namespace .. ".max_ms", mn)
        return M.wait(mn, mx)
    end

    function M.install()
        -- Pure utility: nothing to install. The install hook exists so
        -- the module loader's uniform contract is satisfied.
        L:debug("timing/jitter loaded (utility-only)")
    end

    return M

end

end
__MODULES__['timing/rate_limit'] = function(require)
--[[ ================================================================
    src/timing/rate_limit.lua
    --------------------------
    Pure, reusable rate-limit primitives. Returns closures so the
    callers hold the state, and we avoid a global table keyed by name.

    Shapes offered:
        M.token_bucket(hz, burst)
            - permits `burst` calls immediately
            - refills 1 token every 1/hz seconds
            - returns function() -> boolean (true=allow, false=drop)

        M.leaky_bucket(hz)
            - at most 1 allow per 1/hz seconds (smooth)
            - returns function() -> boolean

        M.fixed_window(hz, window_sec)
            - up to hz*window_sec calls per window
            - simpler; used for low-cadence counters

    Every returned closure exposes introspection via metatable __index
    fields (used, granted, denied). Modules that want periodic stats
    call `stats_of(bucket_fn)` to read them without breaking the
    closure abstraction.
================================================================ ]]

return function(require)

    local log = require("core/log")
    local cfg = require("core/config")

    local M = {}
    local L = log.scoped("timing/rate_limit")

    local STATE_REG = setmetatable({}, { __mode = "k" })

    local function register(fn, s) STATE_REG[fn] = s end

    function M.token_bucket(hz, burst)
        hz    = tonumber(hz)    or 30
        burst = tonumber(burst) or 5
        if hz <= 0 then hz = 1 end
        if burst < 1 then burst = 1 end
        local tokens    = burst
        local last_t    = tick()
        local rate_per_s = hz
        local s = { used = 0, granted = 0, denied = 0, kind = "token_bucket",
                    hz = hz, burst = burst }
        local function allow()
            local now = tick()
            local dt  = now - last_t
            last_t = now
            tokens = tokens + dt * rate_per_s
            if tokens > burst then tokens = burst end
            s.used = s.used + 1
            if tokens >= 1 then
                tokens = tokens - 1
                s.granted = s.granted + 1
                return true
            end
            s.denied = s.denied + 1
            return false
        end
        register(allow, s)
        return allow
    end

    function M.leaky_bucket(hz)
        hz = tonumber(hz) or 30
        if hz <= 0 then hz = 1 end
        local interval = 1 / hz
        local next_t = 0
        local s = { used = 0, granted = 0, denied = 0, kind = "leaky_bucket",
                    hz = hz, interval = interval }
        local function allow()
            local now = tick()
            s.used = s.used + 1
            if now >= next_t then
                next_t = now + interval
                s.granted = s.granted + 1
                return true
            end
            s.denied = s.denied + 1
            return false
        end
        register(allow, s)
        return allow
    end

    function M.fixed_window(hz, window_sec)
        hz         = tonumber(hz)         or 30
        window_sec = tonumber(window_sec) or 1
        if hz <= 0 then hz = 1 end
        if window_sec <= 0 then window_sec = 1 end
        local cap       = math.floor(hz * window_sec + 0.5)
        local count     = 0
        local win_start = tick()
        local s = { used = 0, granted = 0, denied = 0, kind = "fixed_window",
                    hz = hz, window = window_sec, cap = cap }
        local function allow()
            local now = tick()
            if now - win_start >= window_sec then
                win_start = now
                count = 0
            end
            s.used = s.used + 1
            if count < cap then
                count = count + 1
                s.granted = s.granted + 1
                return true
            end
            s.denied = s.denied + 1
            return false
        end
        register(allow, s)
        return allow
    end

    function M.stats_of(allow_fn)
        local s = STATE_REG[allow_fn]
        if not s then return nil end
        return {
            used    = s.used,
            granted = s.granted,
            denied  = s.denied,
            kind    = s.kind,
            hz      = s.hz,
            burst   = s.burst,
        }
    end

    function M.reset(allow_fn)
        local s = STATE_REG[allow_fn]
        if not s then return end
        s.used, s.granted, s.denied = 0, 0, 0
    end

    function M.from_cfg(namespace)
        namespace = namespace or "timing.rate_limit"
        local hz = cfg:get(namespace .. ".hz_cap", 60)
        return M.token_bucket(hz, math.max(1, math.floor(hz / 6)))
    end

    function M.install()
        L:debug("timing/rate_limit loaded (utility-only)")
    end

    return M

end

end
__MODULES__['timing/tick_smoother'] = function(require)
--[[ ================================================================
    src/timing/tick_smoother.lua
    -----------------------------
    Exponential-moving-average dt smoother. The raw Heartbeat dt
    fluctuates wildly in Roblox (physics steps, GC pauses, teleport
    transitions). If a mask uses raw dt to compute a spoof value, it
    can overshoot under a 60ms spike and trigger AC's own position
    tolerance.

    We keep a shared smoother updated off Heartbeat; masks borrow
    `global().value` or create private instances for their own series.

    API:
        local ts = require("timing/tick_smoother")
        ts.install()                    -- start global heartbeat feed
        local dt = ts.global().value    -- shared smoothed dt
        local s  = ts.create(0.1)       -- private instance
        s:update(dt); print(s.value)

    Smoothing parameter alpha:
        value = (1 - alpha) * value + alpha * sample
        0 < alpha <= 1
        alpha ~= 0.05 .. 0.3 is usable.
        alpha == 1 means no smoothing (value == sample).
================================================================ ]]

return function(require)

    local env   = require("core/env")
    local log   = require("core/log")
    local cfg   = require("core/config")
    local state = require("core/state")

    local M = {}
    local L = log.scoped("timing/tick_smoother")

    local DEFAULT_ALPHA = 0.2

    local Smoother = {}
    Smoother.__index = Smoother

    function Smoother:update(dt)
        dt = tonumber(dt) or 0
        if dt < 0 then dt = 0 end
        if self._primed then
            local a = self.alpha
            self.value   = (1 - a) * self.value + a * dt
            self.last_dt = dt
            self.samples = self.samples + 1
            if dt > self.peak_dt then self.peak_dt = dt end
            if dt < self.min_dt  then self.min_dt  = dt end
        else
            self.value   = dt
            self.last_dt = dt
            self.peak_dt = dt
            self.min_dt  = dt
            self.samples = 1
            self._primed = true
        end
        return self.value
    end

    function Smoother:reset()
        self.value   = 0
        self.last_dt = 0
        self.peak_dt = 0
        self.min_dt  = math.huge
        self.samples = 0
        self._primed = false
    end

    function Smoother:snapshot()
        return {
            value   = self.value,
            last_dt = self.last_dt,
            peak_dt = self.peak_dt,
            min_dt  = self.min_dt == math.huge and 0 or self.min_dt,
            samples = self.samples,
            alpha   = self.alpha,
        }
    end

    function Smoother:set_alpha(a)
        a = tonumber(a) or DEFAULT_ALPHA
        if a <= 0 then a = 0.001 end
        if a > 1  then a = 1 end
        self.alpha = a
    end

    function M.create(smoothing)
        local s = setmetatable({}, Smoother)
        s.alpha = DEFAULT_ALPHA
        s:reset()
        s:set_alpha(smoothing or cfg:get("timing.tick_smoother.smoothing", DEFAULT_ALPHA))
        return s
    end

    local GLOBAL = nil
    local GLOBAL_CONN = nil

    function M.global()
        if not GLOBAL then
            GLOBAL = M.create(cfg:get("timing.tick_smoother.smoothing", DEFAULT_ALPHA))
        end
        return GLOBAL
    end

    local function start_feed()
        if GLOBAL_CONN then return end
        if not env.RunService then
            L:warn("no RunService; global feed cannot start")
            return
        end
        local g = M.global()
        GLOBAL_CONN = env.RunService.Heartbeat:Connect(function(dt)
            g:update(dt)
        end)
        L:info("tick smoother started (alpha=%.3f)", g.alpha)
    end

    local function stop_feed()
        if GLOBAL_CONN then
            pcall(function() GLOBAL_CONN:Disconnect() end)
            GLOBAL_CONN = nil
            L:info("tick smoother stopped")
        end
    end

    function M.install()
        if not cfg:get("timing.tick_smoother.enabled", false) then
            L:info("disabled via config; global() still works manually")
            return
        end
        start_feed()
        state:set_last("tick_smoother_active", true)
    end

    function M.shutdown()
        stop_feed()
        state:set_last("tick_smoother_active", false)
    end

    function M.snapshot()
        if not GLOBAL then return nil end
        return GLOBAL:snapshot()
    end

    return M

end

end
__MODULES__['ui/status_panel'] = function(require)
--[[ ================================================================
    src/ui/status_panel.lua
    ------------------------
    Floating corner panel: shows live counters from state.Counters,
    plus buttons for "DUMP LOGS" and "KILL SWITCH".

    Parented to gethui() when available, otherwise CoreGui. Name is
    pulled from integrity/self_protect.benign_screen_name() and also
    registered with self_protect so GetChildren filters can hide it.

    Layout:

        +-------------------------------+
        | GRG-AC           [_][ X ]    |
        +-------------------------------+
        | kicks        : 0             |
        | shadowbans   : 0             |
        | ragdolls     : 0             |
        | profile_spoofs: 0            |
        | hook_restores: 0             |
        |  ...                         |
        +-------------------------------+
        | [ DUMP LOGS ] [ KILL SWITCH ]|
        +-------------------------------+

    Position comes from cfg:get("ui.status_panel.position") -> one of
    "top_left", "top_right", "bottom_left", "bottom_right".

    The panel is draggable via Frame.Draggable=true (Roblox's built-in
    deprecated-but-still-works flag) and has a manual minimise toggle.

    Exposed:
        M.show()
        M.hide()
        M.toggle_visibility()
        M.redraw()
        M.get_gui()
================================================================ ]]

return function(require)

    local env   = require("core/env")
    local log   = require("core/log")
    local cfg   = require("core/config")
    local state = require("core/state")

    local self_protect = require("integrity/self_protect")

    local M = {}
    local L = log.scoped("ui/status_panel")

    ----------------------------------------------------------------
    -- 1. local state
    ----------------------------------------------------------------

    local GUI            = nil
    local FRAME          = nil
    local COUNTER_FRAME  = nil
    local LINES          = {}     -- [name] = TextLabel
    local MIN_BTN        = nil
    local CLOSE_BTN      = nil
    local DUMP_BTN       = nil
    local KILL_BTN       = nil
    local MINIMIZED      = false
    local HB_CONN        = nil
    local LAST_DRAW      = 0

    local BENIGN_POOL = {
        "ChatMain",
        "TopbarPlusGui",
        "BubbleChat",
        "PlayerListGui",
        "RbxHealthGui",
    }

    local KEYS_TO_SHOW = {
        "kick_blocked",
        "teleport_blocked",
        "shadowban_dropped",
        "ragdoll_dropped",
        "updateprofile_sanitized",
        "coregui_warning_blocked",
        "walkspeed_read_masked",
        "walkspeed_write_masked",
        "namecall_total",
        "namecall_blocked",
        "hook_restores",
        "hook_losses_detected",
        "profile_spoofs",
        "panics",
    }

    local PALETTE = {
        bg         = Color3.fromRGB(15, 18, 24),
        bg_header  = Color3.fromRGB(22, 28, 38),
        bg_row_a   = Color3.fromRGB(20, 24, 32),
        bg_row_b   = Color3.fromRGB(25, 30, 40),
        accent     = Color3.fromRGB(120, 220, 255),
        danger     = Color3.fromRGB(220, 80, 80),
        dim        = Color3.fromRGB(160, 170, 180),
        text       = Color3.fromRGB(230, 235, 240),
        button_bg  = Color3.fromRGB(40, 48, 60),
        button_tx  = Color3.fromRGB(230, 235, 240),
    }

    ----------------------------------------------------------------
    -- 2. helpers
    ----------------------------------------------------------------

    local function gethui_parent()
        if type(self_protect.gethui_or_coregui) == "function" then
            return self_protect.gethui_or_coregui()
        end
        return env.CoreGui
    end

    local function position_udim2(which, width, height)
        if which == "top_right" then
            return UDim2.new(1, -width - 12, 0, 12)
        elseif which == "bottom_left" then
            return UDim2.new(0, 12, 1, -height - 12)
        elseif which == "bottom_right" then
            return UDim2.new(1, -width - 12, 1, -height - 12)
        end
        return UDim2.new(0, 12, 0, 12)
    end

    local function pick_name()
        local pool = BENIGN_POOL
        local i = (env.SessionStartTime or 0) % #pool + 1
        return pool[i]
    end

    local function new(class, parent, props)
        local inst = Instance.new(class)
        if props then
            for k, v in pairs(props) do inst[k] = v end
        end
        if parent then inst.Parent = parent end
        return inst
    end

    ----------------------------------------------------------------
    -- 3. build
    ----------------------------------------------------------------

    local WIDTH  = 230
    local HEIGHT = 360

    local function build_ui()
        if GUI then return end

        local gui = Instance.new("ScreenGui")
        gui.Name = pick_name()
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.DisplayOrder = 9100
        gui.Parent = gethui_parent()
        self_protect.hide_instance(gui)

        local frame = new("Frame", gui, {
            Size             = UDim2.new(0, WIDTH, 0, HEIGHT),
            Position         = position_udim2(
                cfg:get("ui.status_panel.position", "top_left"),
                WIDTH, HEIGHT),
            BackgroundColor3 = PALETTE.bg,
            BorderSizePixel  = 0,
            Active           = true,
            Draggable        = true,
        })
        new("UICorner", frame, { CornerRadius = UDim.new(0, 6) })
        new("UIStroke", frame, {
            Color = PALETTE.bg_header,
            Thickness = 1,
        })

        -- header
        local header = new("Frame", frame, {
            Size             = UDim2.new(1, 0, 0, 24),
            BackgroundColor3 = PALETTE.bg_header,
            BorderSizePixel  = 0,
        })
        new("UICorner", header, { CornerRadius = UDim.new(0, 6) })

        new("TextLabel", header, {
            BackgroundTransparency = 1,
            Position               = UDim2.new(0, 10, 0, 0),
            Size                   = UDim2.new(1, -80, 1, 0),
            Font                   = Enum.Font.GothamBold,
            TextSize               = 13,
            TextXAlignment         = Enum.TextXAlignment.Left,
            TextColor3             = PALETTE.accent,
            Text                   = "GRG-AC",
        })

        MIN_BTN = new("TextButton", header, {
            Position         = UDim2.new(1, -52, 0, 3),
            Size             = UDim2.new(0, 22, 0, 18),
            BackgroundColor3 = PALETTE.button_bg,
            Font             = Enum.Font.GothamBold,
            TextSize         = 12,
            TextColor3       = PALETTE.button_tx,
            Text             = "_",
            BorderSizePixel  = 0,
        })
        new("UICorner", MIN_BTN, { CornerRadius = UDim.new(0, 4) })

        CLOSE_BTN = new("TextButton", header, {
            Position         = UDim2.new(1, -26, 0, 3),
            Size             = UDim2.new(0, 22, 0, 18),
            BackgroundColor3 = PALETTE.danger,
            Font             = Enum.Font.GothamBold,
            TextSize         = 12,
            TextColor3       = PALETTE.button_tx,
            Text             = "X",
            BorderSizePixel  = 0,
        })
        new("UICorner", CLOSE_BTN, { CornerRadius = UDim.new(0, 4) })

        -- body (scrolling counters)
        local body = new("ScrollingFrame", frame, {
            Position                 = UDim2.new(0, 6, 0, 30),
            Size                     = UDim2.new(1, -12, 1, -70),
            BackgroundTransparency   = 1,
            BorderSizePixel          = 0,
            CanvasSize               = UDim2.new(0, 0, 0, #KEYS_TO_SHOW * 18),
            ScrollBarThickness       = 4,
            AutomaticCanvasSize      = Enum.AutomaticSize.Y,
        })

        local layout = new("UIListLayout", body, {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding   = UDim.new(0, 2),
        })

        COUNTER_FRAME = body

        for i, key in ipairs(KEYS_TO_SHOW) do
            local row = new("Frame", body, {
                LayoutOrder = i,
                Size             = UDim2.new(1, 0, 0, 18),
                BackgroundColor3 = (i % 2 == 0) and PALETTE.bg_row_a or PALETTE.bg_row_b,
                BorderSizePixel  = 0,
            })
            new("UICorner", row, { CornerRadius = UDim.new(0, 3) })

            new("TextLabel", row, {
                BackgroundTransparency = 1,
                Position               = UDim2.new(0, 6, 0, 0),
                Size                   = UDim2.new(0.7, 0, 1, 0),
                Font                   = Enum.Font.Gotham,
                TextSize               = 11,
                TextXAlignment         = Enum.TextXAlignment.Left,
                TextColor3             = PALETTE.dim,
                Text                   = key,
            })

            local val = new("TextLabel", row, {
                BackgroundTransparency = 1,
                Position               = UDim2.new(0.7, -4, 0, 0),
                Size                   = UDim2.new(0.3, -2, 1, 0),
                Font                   = Enum.Font.GothamBold,
                TextSize               = 11,
                TextXAlignment         = Enum.TextXAlignment.Right,
                TextColor3             = PALETTE.text,
                Text                   = "0",
            })
            LINES[key] = val
        end

        -- footer buttons
        local footer = new("Frame", frame, {
            Position         = UDim2.new(0, 0, 1, -34),
            Size             = UDim2.new(1, 0, 0, 34),
            BackgroundTransparency = 1,
        })

        DUMP_BTN = new("TextButton", footer, {
            Position         = UDim2.new(0, 6, 0, 4),
            Size             = UDim2.new(0.5, -8, 0, 24),
            BackgroundColor3 = PALETTE.button_bg,
            Font             = Enum.Font.GothamBold,
            TextSize         = 11,
            TextColor3       = PALETTE.button_tx,
            Text             = "DUMP LOGS",
            BorderSizePixel  = 0,
        })
        new("UICorner", DUMP_BTN, { CornerRadius = UDim.new(0, 4) })

        KILL_BTN = new("TextButton", footer, {
            Position         = UDim2.new(0.5, 2, 0, 4),
            Size             = UDim2.new(0.5, -8, 0, 24),
            BackgroundColor3 = PALETTE.danger,
            Font             = Enum.Font.GothamBold,
            TextSize         = 11,
            TextColor3       = PALETTE.button_tx,
            Text             = "KILL SWITCH",
            BorderSizePixel  = 0,
        })
        new("UICorner", KILL_BTN, { CornerRadius = UDim.new(0, 4) })

        GUI   = gui
        FRAME = frame
    end

    ----------------------------------------------------------------
    -- 4. behaviour: minimise, buttons, heartbeat updater
    ----------------------------------------------------------------

    local function set_minimized(v)
        MINIMIZED = v and true or false
        if not FRAME then return end
        if MINIMIZED then
            FRAME.Size = UDim2.new(0, WIDTH, 0, 24)
            if COUNTER_FRAME then COUNTER_FRAME.Visible = false end
            if DUMP_BTN then DUMP_BTN.Visible = false end
            if KILL_BTN then KILL_BTN.Visible = false end
        else
            FRAME.Size = UDim2.new(0, WIDTH, 0, HEIGHT)
            if COUNTER_FRAME then COUNTER_FRAME.Visible = true end
            if DUMP_BTN then DUMP_BTN.Visible = true end
            if KILL_BTN then KILL_BTN.Visible = true end
        end
    end

    local function on_dump_clicked()
        local ok, fname = log.dump_now()
        if ok then
            L:info("dumped log to %s", tostring(fname))
            if DUMP_BTN then DUMP_BTN.Text = "DUMPED" end
            task.delay(1.2, function()
                if DUMP_BTN then DUMP_BTN.Text = "DUMP LOGS" end
            end)
        else
            L:warn("dump failed: %s", tostring(fname))
        end
    end

    local function on_kill_clicked()
        L:warn("KILL SWITCH activated by user")
        state:flag("kill_switched", true)
        -- disable all major namespaces
        for _, ns in ipairs({
            "hooks", "masks", "scrubbers", "decoys", "spoof",
            "silencers", "grg", "sandbox", "netgate", "timing",
            "integrity",
        }) do
            local tbl = cfg:get(ns, nil)
            if type(tbl) == "table" then
                for sub, sv in pairs(tbl) do
                    if type(sv) == "table" and sv.enabled ~= nil then
                        cfg:set(ns .. "." .. sub .. ".enabled", false)
                    end
                end
            end
        end
        state:emit("KillSwitchFlipped", true)
        if KILL_BTN then
            KILL_BTN.Text = "KILLED"
            KILL_BTN.AutoButtonColor = false
        end
    end

    local function wire_buttons()
        if CLOSE_BTN then
            CLOSE_BTN.MouseButton1Click:Connect(function()
                M.hide()
            end)
        end
        if MIN_BTN then
            MIN_BTN.MouseButton1Click:Connect(function()
                set_minimized(not MINIMIZED)
            end)
        end
        if DUMP_BTN then
            DUMP_BTN.MouseButton1Click:Connect(on_dump_clicked)
        end
        if KILL_BTN then
            KILL_BTN.MouseButton1Click:Connect(on_kill_clicked)
        end
    end

    local function redraw_counters()
        for key, lbl in pairs(LINES) do
            local v = state.Counters[key]
            if v == nil then v = 0 end
            lbl.Text = tostring(v)
        end
    end

    local function start_heartbeat()
        if HB_CONN then return end
        if not env.RunService then return end
        HB_CONN = env.RunService.Heartbeat:Connect(function()
            local t = tick()
            if t - LAST_DRAW < 0.1 then return end  -- ~10 Hz
            LAST_DRAW = t
            if GUI and GUI.Parent and not MINIMIZED then
                redraw_counters()
            end
        end)
    end

    local function stop_heartbeat()
        if HB_CONN then
            pcall(function() HB_CONN:Disconnect() end)
            HB_CONN = nil
        end
    end

    ----------------------------------------------------------------
    -- 5. public API
    ----------------------------------------------------------------

    function M.show()
        if not cfg:get("ui.status_panel.enabled", true) then
            L:info("disabled via config")
            return
        end
        if not GUI then
            build_ui()
            wire_buttons()
        end
        if GUI then GUI.Enabled = true end
        state:flag("ui_visible", true)
        if cfg:get("ui.status_panel.minimized_start", false) then
            set_minimized(true)
        end
        start_heartbeat()
    end

    function M.hide()
        if GUI then GUI.Enabled = false end
        state:flag("ui_visible", false)
    end

    function M.toggle_visibility()
        if GUI and GUI.Enabled then
            M.hide()
        else
            M.show()
        end
    end

    function M.redraw()
        if GUI and GUI.Parent then redraw_counters() end
    end

    function M.get_gui() return GUI end

    function M.install()
        if not cfg:get("ui.status_panel.enabled", true) then
            L:info("disabled via config")
            return
        end
        if cfg:get("ui.status_panel.start_visible", true) then
            M.show()
        end
        L:info("status_panel installed (position=%s)",
            cfg:get("ui.status_panel.position", "top_left"))
    end

    return M

end

end
__MODULES__['ui/toggle'] = function(require)
--[[ ================================================================
    src/ui/toggle.lua
    ------------------
    Binds a configurable hotkey to toggle the ui/status_panel.
    Default key is "RightControl" (see cfg.ui.toggle.hotkey).
================================================================ ]]

return function(require)

    local env   = require("core/env")
    local log   = require("core/log")
    local cfg   = require("core/config")
    local state = require("core/state")

    local status_panel = require("ui/status_panel")

    local M = {}
    local L = log.scoped("ui/toggle")

    local CONN    = nil
    local KEYCODE = nil

    local function resolve_keycode(name)
        if type(name) ~= "string" or name == "" then return nil end
        local ok, kc = pcall(function() return Enum.KeyCode[name] end)
        if ok and kc then return kc end
        return nil
    end

    local function disconnect()
        if CONN then
            pcall(function() CONN:Disconnect() end)
            CONN = nil
        end
    end

    function M.set_hotkey(key_name)
        disconnect()
        KEYCODE = resolve_keycode(key_name)
        if not KEYCODE then
            L:warn("unknown keycode '%s'", tostring(key_name))
            return false
        end
        cfg:set("ui.toggle.hotkey", key_name)
        if not env.UserInputService then
            L:warn("UserInputService missing; hotkey inactive")
            return false
        end
        CONN = env.UserInputService.InputBegan:Connect(function(input, processed)
            if processed then return end
            if input.KeyCode == KEYCODE then
                status_panel.toggle_visibility()
            end
        end)
        L:info("hotkey bound: %s", key_name)
        return true
    end

    function M.install()
        if not cfg:get("ui.toggle.enabled", true) then
            L:info("disabled via config")
            return
        end
        M.set_hotkey(cfg:get("ui.toggle.hotkey", "RightControl"))
    end

    return M

end

end

return __require('boot')
