--[[
    MHR_FocusMode v2.9 - Focus Aim for Monster Hunter Rise (REFramework)

    v2.9 구조:
      - v2.8의 평상시 "행동 중 카메라 방향 추적"을 그대로 유지합니다.
      - 공격 입력(마우스 L/R)이 시작되면 그 순간의 카메라 방향을 저장합니다.
      - 공격 고정 중에는 보간(smooth)을 사용하지 않고 정확한 yaw를 강제합니다.
      - LockScene 전/후 및 PrepareRendering 전/후에 재적용합니다.
      - 공격 고정 만료 시 Activity가 false가 되는 1프레임 공백을 막기 위해
        공격 직후 0.100초의 핸드오프 구간을 겹치게 운용합니다.
      - 핸드오프 구간에는 현재 카메라 방향을 강제로 이어받아 원래 캐릭터 방향을 보지 않습니다.
      - 공격 고정 시간 자체의 여유도 +0.040초로 늘렸습니다.
      - 무기 Timing은 항상 자동 인식하며, 무기 미감지 시에만 Generic 값을 사용합니다.
      - v2.5의 BFM 상태 API 접근을 복구하고, BFM 무기 타입 진단을 함께 표시합니다.

    Better Focus Mode Timing:
      GreatSword=0.24
      LongSword=0.18
      ChargeBlade=0.22
      SwordAndShield=0.16
      DualBlades=0.14
      Hammer=0.24
      HuntingHorn=0.22
      Lance=0.18
      Gunlance=0.20
      SwitchAxe=0.20
      InsectGlaive=0.18

    주의:
      - 무기 감지는 _WeaponMain의 직접/상속 타입명을 자동 탐색합니다.
      - 타입명이 어느 단계에서도 매칭되지 않을 때만 Generic(미감지/기본) Timing을 사용합니다.
--]]

--==========================================================================
-- 1. 설정
--==========================================================================

local CFG_PATH = "ModFocusRise.json"

local DEFAULTS = {
    enabled        = true,
    mode           = 1,       -- 1 = 홀드, 2 = 토글
    key            = 0xA4,
    key_name       = "Menu",  -- via.hid.KeyboardKey.Menu = LALT

    smooth         = 0.35,
    yaw_offset     = 0.0,

    debug          = false,
    apply_rotation = true,

    -- v1.8 스타일: 움직이거나 회전할 때만 평상시 카메라 추적
    activity_gate          = true,
    activity_pos_threshold = 0.01,
    activity_yaw_threshold = 0.015,
    activity_hold_frames   = 12,

    -- 무기 Timing은 항상 자동 인식.
    -- 무기가 인식되지 않을 때만 아래 Generic 값을 사용합니다.
    generic_window_seconds = 0.196,

    -- v2.5에서 사용하던 BFM 상태 API를 복구합니다.
    -- 실제 호환되는 Rise 멤버가 있을 때만 적용합니다.
    use_bfm_state_api = true,

    -- 공격 고정 시간 종료 후 바로 일반 추적으로 복귀
    post_window_hold_seconds = 0.00,

    -- 공격 모션 중 원래 방향으로 되돌아가는 프레임을 줄이기 위한 소폭의 여유 시간.
    -- UI에는 노출하지 않고 내부에서만 적용합니다.
    attack_lock_extension_seconds = 0.040,

    -- 공격 고정 -> 평상시 추적 사이를 일부러 겹치게 만들어 1프레임 공백 방지.
    attack_handoff_seconds = 0.100,
}

local cfg = json.load_file(CFG_PATH) or {}
for k, v in pairs(DEFAULTS) do
    if cfg[k] == nil then cfg[k] = v end
end

local function save_cfg()
    json.dump_file(CFG_PATH, cfg)
end

--==========================================================================
-- 2. 무기 Timing
--==========================================================================

local WEAPON_LABELS = {
    GreatSword     = "대검",
    LongSword      = "태도",
    ChargeBlade    = "차지액스",
    SwordAndShield = "한손검",
    DualBlades     = "쌍검",
    Hammer         = "해머",
    HuntingHorn    = "수렵피리",
    Lance          = "랜스",
    Gunlance       = "건랜스",
    SwitchAxe      = "슬래시액스",
    InsectGlaive   = "조충곤",
    Generic        = "미감지/기본",
}

local WEAPON_ORDER = {
    "GreatSword",
    "LongSword",
    "ChargeBlade",
    "SwordAndShield",
    "DualBlades",
    "Hammer",
    "HuntingHorn",
    "Lance",
    "Gunlance",
    "SwitchAxe",
    "InsectGlaive",
}

local WEAPON_TIMINGS = {
    GreatSword     = 0.24,
    LongSword      = 0.18,
    ChargeBlade    = 0.22,
    SwordAndShield = 0.16,
    DualBlades     = 0.14,
    Hammer         = 0.24,
    HuntingHorn    = 0.22,
    Lance          = 0.18,
    Gunlance       = 0.20,
    SwitchAxe      = 0.20,
    InsectGlaive   = 0.18,
}

local WEAPON_PATTERNS = {
    { key = "GreatSword",     patterns = { "GreatSword", "Greatsword" } },
    { key = "LongSword",      patterns = { "LongSword", "Longsword" } },
    { key = "ChargeBlade",    patterns = { "ChargeAxe", "ChargeBlade", "Chargeblade" } },
    { key = "SwordAndShield", patterns = { "ShortSword", "SwordAndShield", "SwordShield" } },
    { key = "DualBlades",     patterns = { "DualBlades", "DualBlade" } },
    { key = "Hammer",         patterns = { "Hammer" } },
    { key = "HuntingHorn",    patterns = { "HuntingHorn", "Horn" } },
    { key = "Gunlance",       patterns = { "GunLance", "Gunlance" } },
    { key = "Lance",          patterns = { "Lance" } },
    { key = "SwitchAxe",      patterns = { "SlashAxe", "SwitchAxe" } },
    { key = "InsectGlaive",   patterns = { "InsectGlaive", "Insect" } },
}

--==========================================================================
-- 3. 키 입력
--==========================================================================

local kb_singleton, kb_tdef, kb_key_tdef
local key_prev_down = false
local input_error = nil

local function get_keyboard()
    if not kb_singleton then
        kb_singleton = sdk.get_native_singleton("via.hid.Keyboard")
        kb_tdef      = sdk.find_type_definition("via.hid.Keyboard")
        kb_key_tdef  = sdk.find_type_definition("via.hid.KeyboardKey")
    end

    if not kb_singleton or not kb_tdef or not kb_key_tdef then
        return nil
    end

    return sdk.call_native_func(kb_singleton, kb_tdef, "get_Device")
end

local function get_key_value(name)
    if not kb_key_tdef or not name then return nil end

    local field = kb_key_tdef:get_field(name)
    if not field then return nil end

    local ok, value = pcall(function()
        return field:get_data(nil)
    end)

    if not ok then return nil end
    return value
end

local function key_display_name()
    if cfg.key_name == "Menu" then return "LALT" end
    return tostring(cfg.key_name or "Menu")
end

local function get_bound_key_value()
    local v = get_key_value(cfg.key_name or "Menu")
    if v == nil then
        input_error = "KeyboardKey not found: " .. tostring(cfg.key_name)
    end
    return v
end

local function key_down()
    local d = get_keyboard()
    if not d then return false end

    local key = get_bound_key_value()
    if key == nil then return false end

    local ok, result = pcall(function()
        return d:call("isDown", key) == true
    end)

    if not ok then
        input_error = "keyboard isDown: " .. tostring(result)
        return false
    end

    return result
end

local function key_trg()
    local now_down = key_down()
    local trg = now_down and not key_prev_down
    key_prev_down = now_down
    return trg
end

local function capture_key()
    local d = get_keyboard()
    if not d or not kb_key_tdef then return false end

    for _, field in ipairs(kb_key_tdef:get_fields()) do
        if field:is_static() then
            local name = field:get_name()

            local ok_value, value = pcall(function()
                return field:get_data(nil)
            end)

            if ok_value and value ~= nil then
                local ok_down, down = pcall(function()
                    return d:call("isDown", value) == true
                end)

                if ok_down and down then
                    if name ~= "Escape" then
                        cfg.key_name = name
                        cfg.key = value
                        save_cfg()
                    end

                    key_prev_down = false
                    return true
                end
            end
        end
    end

    return false
end

--==========================================================================
-- 4. 마우스 입력
--==========================================================================

local mouse_singleton, mouse_tdef, mouse_button_tdef
local mouse_prev_l = false
local mouse_prev_r = false
local mouse_error = nil

local function get_mouse()
    if not mouse_singleton then
        mouse_singleton   = sdk.get_native_singleton("via.hid.Mouse")
        mouse_tdef        = sdk.find_type_definition("via.hid.Mouse")
        mouse_button_tdef = sdk.find_type_definition("via.hid.MouseButton")
    end

    if not mouse_singleton or not mouse_tdef or not mouse_button_tdef then
        return nil
    end

    return sdk.call_native_func(mouse_singleton, mouse_tdef, "get_Device")
end

local function get_mouse_button_value(name)
    if not mouse_button_tdef or not name then return nil end

    local field = mouse_button_tdef:get_field(name)
    if not field then
        mouse_error = "MouseButton not found: " .. tostring(name)
        return nil
    end

    local ok, value = pcall(function()
        return field:get_data(nil)
    end)

    if not ok then
        mouse_error = "MouseButton get_data: " .. tostring(value)
        return nil
    end

    return value
end

local function mouse_down(name)
    local m = get_mouse()
    if not m then return false end

    local button = get_mouse_button_value(name)
    if button == nil then return false end

    local ok, result = pcall(function()
        return m:call("isDown", button) == true
    end)

    if not ok then
        mouse_error = "mouse isDown: " .. tostring(result)
        return false
    end

    return result
end

local function update_attack_input()
    local l = mouse_down("L")
    local r = mouse_down("R")

    local trg_l = l and not mouse_prev_l
    local trg_r = r and not mouse_prev_r

    mouse_prev_l = l
    mouse_prev_r = r

    return trg_l or trg_r
end

--==========================================================================
-- 5. Player / Camera / Weapon
--==========================================================================

local function get_player()
    local pm = sdk.get_managed_singleton("snow.player.PlayerManager")
    if not pm then return nil end

    -- Rise 모딩에서 일반적으로 쓰이는 현재 플레이어 조회 경로를 우선 사용.
    local ok, player = pcall(function()
        return pm:call("getPlayer", 0)
    end)

    if ok and player then
        return player
    end

    -- 기존 버전 호환 fallback.
    local ok_fallback, master = pcall(function()
        return pm:call("findMasterPlayer")
    end)

    if ok_fallback then
        return master
    end

    return nil
end

local function get_transform(obj)
    if not obj then return nil end

    local go = obj:call("get_GameObject")
    if not go then return nil end

    return go:call("get_Transform")
end

local sm_singleton, sm_tdef

local function get_camera_transform()
    if not sm_singleton then
        sm_singleton = sdk.get_native_singleton("via.SceneManager")
        sm_tdef      = sdk.find_type_definition("via.SceneManager")
    end

    if not sm_singleton or not sm_tdef then return nil end

    local view = sdk.call_native_func(sm_singleton, sm_tdef, "get_MainView")
    if not view then return nil end

    local cam = view:call("get_PrimaryCamera")
    if not cam then return nil end

    return get_transform(cam)
end

local weapon_type_name = "(unknown)"
local bfm_weapon_type_name = "(unknown)"
local bfm_weapon_source = "none"
local current_weapon_key = "Generic"
local current_window_seconds = 0.196
local weapon_detect_error = nil

local function get_main_weapon(player)
    if not player then return nil end

    -- _WeaponMain이 Rise의 일반적인 런타임 필드이며, 호환성을 위해
    -- 동일 의미의 공개 필드명도 안전하게 시도합니다.
    for _, field_name in ipairs({ "_WeaponMain", "WeaponMain" }) do
        local ok, weapon = pcall(function()
            return player:get_field(field_name)
        end)

        if ok and weapon ~= nil then
            weapon_detect_error = nil
            return weapon
        end

        if not ok then
            weapon_detect_error = tostring(weapon)
        end
    end

    return nil
end

local function get_weapon_type_name(weapon)
    if not weapon then
        weapon_type_name = "(unknown)"
        return nil
    end

    local ok, name = pcall(function()
        local td = weapon:get_type_definition()
        if not td then return nil end
        return td:get_name()
    end)

    if not ok then
        weapon_detect_error = tostring(name)
        weapon_type_name = "(error)"
        return nil
    end

    weapon_type_name = name or "(unknown)"
    return name
end

local function normalize_weapon_type_name(name)
    if not name then return "" end
    local s = tostring(name):lower()
    -- namespace / punctuation 제거
    s = s:gsub("[^%w]", "")
    return s
end

local function weapon_key_from_type_name(type_name)
    if not type_name then return nil end

    -- 타입명이 정말 짧은 별칭 그 자체인 경우만 허용합니다.
    -- 일반 타입명 안의 "GS", "DB" 같은 두 글자를 부분검색하지 않아 오인식을 막습니다.
    local raw = tostring(type_name)
    local short_aliases = {
        GS = "GreatSword", LS = "LongSword", CB = "ChargeBlade",
        SA = "SwitchAxe", GL = "Gunlance", DB = "DualBlades",
        HH = "HuntingHorn", IG = "InsectGlaive", SnS = "SwordAndShield",
    }
    if short_aliases[raw] then
        return short_aliases[raw]
    end

    local normalized = normalize_weapon_type_name(type_name)
    if normalized == "" then return nil end

    -- MHRise 데이터에서 실제로 사용되는 무기 클래스명을 지원합니다.
    local patterns = {
        { key = "SwordAndShield", patterns = { "ShortSword", "SwordAndShield", "SwordShield" } },
        { key = "DualBlades",     patterns = { "DualBlades", "DualBlade" } },
        { key = "ChargeBlade",    patterns = { "ChargeAxe", "ChargeBlade" } },
        { key = "HuntingHorn",    patterns = { "HuntingHorn", "Horn" } },
        { key = "InsectGlaive",   patterns = { "InsectGlaive", "Insect" } },
        { key = "SwitchAxe",      patterns = { "SlashAxe", "SwitchAxe" } },
        { key = "Gunlance",       patterns = { "GunLance", "Gunlance" } },
        { key = "GreatSword",     patterns = { "GreatSword" } },
        { key = "LongSword",      patterns = { "LongSword" } },
        { key = "Hammer",          patterns = { "Hammer" } },
        { key = "Lance",           patterns = { "Lance" } },
    }

    for _, item in ipairs(patterns) do
        for _, pattern in ipairs(item.patterns) do
            local p = normalize_weapon_type_name(pattern)
            if p ~= "" and string.find(normalized, p, 1, true) then
                return item.key
            end
        end
    end

    return nil
end

local function get_weapon_type_chain(weapon)
    local names = {}
    if not weapon then return names end

    local ok, td = pcall(function() return weapon:get_type_definition() end)
    if not ok or not td then return names end

    local cur = td
    local guard = 0
    while cur and guard < 16 do
        local ok_name, name = pcall(function() return cur:get_name() end)
        if ok_name and name then
            names[#names + 1] = name
        end

        local ok_parent, parent = pcall(function() return cur:get_parent_type() end)
        if not ok_parent then break end
        cur = parent
        guard = guard + 1
    end

    return names
end

-- _WeaponMain의 타입에 무기명이 직접 없을 경우를 대비해,
-- 관련 하위 managed-object 타입도 최대 2단계까지만 확인합니다.
-- 동일한 weapon 객체는 캐시해서 매 프레임 재귀 탐색하지 않습니다.
local weapon_detect_cache_id = nil
local weapon_detect_cache_key = "Generic"

local function detect_nested_weapon_type(weapon, depth_limit)
    if not weapon then return nil end
    depth_limit = depth_limit or 2

    local ok_id, object_id = pcall(function() return tostring(weapon) end)
    object_id = ok_id and object_id or "(weapon)"

    if weapon_detect_cache_id == object_id then
        if weapon_detect_cache_key ~= "Generic" then
            return weapon_detect_cache_key, bfm_weapon_type_name, bfm_weapon_source
        end
        return nil
    end

    weapon_detect_cache_id = object_id
    weapon_detect_cache_key = "Generic"

    local visited = {}
    local function walk(obj, depth, field_path)
        if not obj or depth > depth_limit then return nil end

        local ok_obj, obj_id = pcall(function() return tostring(obj) end)
        obj_id = ok_obj and obj_id or tostring(obj)
        if visited[obj_id] then return nil end
        visited[obj_id] = true

        local names = get_weapon_type_chain(obj)
        for _, name in ipairs(names) do
            local key = weapon_key_from_type_name(name)
            if key then
                return key,
                    name,
                    field_path == "" and "nested-type" or ("nested:" .. field_path)
            end
        end

        if depth >= depth_limit then return nil end

        local ok_td, td = pcall(function() return obj:get_type_definition() end)
        if not ok_td or not td then return nil end

        local ok_fields, fields = pcall(function() return td:get_fields() end)
        if not ok_fields or not fields then return nil end

        for _, field in ipairs(fields) do
            local ok_static, is_static = pcall(function() return field:is_static() end)
            if not ok_static or not is_static then
                local ok_fname, fname = pcall(function() return field:get_name() end)
                fname = ok_fname and fname or "?"
                local lower = tostring(fname):lower()

                local relevant =
                    lower:find("weapon", 1, true) ~= nil or
                    lower:find("equip", 1, true) ~= nil or
                    lower:find("base", 1, true) ~= nil or
                    lower:find("data", 1, true) ~= nil or
                    lower:find("main", 1, true) ~= nil

                if relevant then
                    local ok_value, value = pcall(function() return field:get_data(obj) end)
                    if ok_value and value ~= nil then
                        local vt = type(value)
                        if vt == "userdata" or vt == "table" then
                            local next_path = field_path == ""
                                and fname
                                or (field_path .. "." .. fname)
                            local key, name, source = walk(value, depth + 1, next_path)
                            if key then
                                return key, name, source
                            end
                        end
                    end
                end
            end
        end

        return nil
    end

    local key, name, source = walk(weapon, 0, "")
    if key then
        weapon_detect_cache_key = key
        bfm_weapon_type_name = name or bfm_weapon_type_name
        bfm_weapon_source = source or bfm_weapon_source
        return key, name, source
    end

    return nil
end

local function detect_weapon_key(player)
    local weapon = get_main_weapon(player)
    if not weapon then
        bfm_weapon_type_name = "(unknown)"
        bfm_weapon_source = "none"
        weapon_type_name = "(unknown)"
        weapon_detect_cache_id = nil
        weapon_detect_cache_key = "Generic"
        return "Generic"
    end

    -- 1) 직접 타입 + 부모 타입 체인
    local names = get_weapon_type_chain(weapon)
    for i, name in ipairs(names) do
        local key = weapon_key_from_type_name(name)
        if key then
            weapon_type_name = names[1] or name
            bfm_weapon_type_name = name
            bfm_weapon_source = (i == 1) and "direct-type" or "parent-type"
            weapon_detect_cache_id = nil
            weapon_detect_cache_key = key
            return key
        end
    end

    -- 2) BFM-style 하위 managed object 타입 탐색
    local nested_key = detect_nested_weapon_type(weapon, 2)
    if nested_key then
        return nested_key
    end

    weapon_type_name = names[1] or "(unknown)"
    bfm_weapon_type_name = weapon_type_name
    bfm_weapon_source = "unmatched"
    return "Generic"
end

local function update_weapon_profile(player)
    local key = detect_weapon_key(player)
    current_weapon_key = key

    if key == "Generic" then
        current_window_seconds = cfg.generic_window_seconds
    else
        current_window_seconds = WEAPON_TIMINGS[key] or cfg.generic_window_seconds
    end

    return current_window_seconds
end

--==========================================================================
-- 6.5. v2.5 BFM 상태 API 복구
--
-- v2.5에 있던 facing/target/startRotation 계열 접근을 복구합니다.
-- 무기 판별과 BFM 상태 적용은 서로 분리되어 있습니다.
-- BFM API가 실제로 존재하지 않으면 Transform 강제 회전이 그대로 fallback 합니다.
--==========================================================================

local bfm_api = {
    initialized = false,
    type_name = "(unknown)",
    methods = {},
    fields = {},
    setter = nil,
    getter = nil,
    detected = false,
    last_error = nil,
}

local BFM_GETTERS = {
    "TryGetFacingDirection",
    "get_FacingDirection",
    "get_TargetDirection",
    "get_StartRotation",
}

local BFM_SETTERS = {
    "set_FacingDirection",
    "set_TargetDirection",
    "set_StartRotation",
}

local BFM_ZERO_METHODS = {
    "BeginCorrection",
    "ShouldRefreshCorrection",
}

local function method_num_params_safe(m)
    local ok, n = pcall(function() return m:get_num_params() end)
    if ok and type(n) == "number" then return n end
    return nil
end

local function find_method_in_chain(td, name)
    local cur = td
    local guard = 0
    while cur and guard < 16 do
        local ok, m = pcall(function() return cur:get_method(name) end)
        if ok and m then return m end
        local ok_parent, parent = pcall(function() return cur:get_parent_type() end)
        if not ok_parent then break end
        cur = parent
        guard = guard + 1
    end
    return nil
end

local function find_field_in_chain(td, name)
    local cur = td
    local guard = 0
    while cur and guard < 16 do
        local ok, f = pcall(function() return cur:get_field(name) end)
        if ok and f then return f end
        local ok_parent, parent = pcall(function() return cur:get_parent_type() end)
        if not ok_parent then break end
        cur = parent
        guard = guard + 1
    end
    return nil
end

local function init_bfm_api(player)
    if not cfg.use_bfm_state_api then return end
    if bfm_api.initialized then return end
    if not player then return end

    local ok_td, td = pcall(function() return player:get_type_definition() end)
    if not ok_td or not td then return end

    bfm_api.initialized = true
    local ok_name, player_type_name = pcall(function() return td:get_name() end)
    bfm_api.type_name = ok_name and player_type_name or "(unknown)"
    bfm_api.methods = {}
    bfm_api.fields = {}
    bfm_api.setter = nil
    bfm_api.getter = nil
    bfm_api.detected = false
    bfm_api.last_error = nil

    for _, name in ipairs(BFM_GETTERS) do
        local m = find_method_in_chain(td, name)
        if m then
            local n = method_num_params_safe(m)
            bfm_api.methods[name] = { method = m, params = n }
            if bfm_api.getter == nil and n == 0 then
                bfm_api.getter = name
            end
        end
    end

    for _, name in ipairs(BFM_SETTERS) do
        local m = find_method_in_chain(td, name)
        if m then
            local n = method_num_params_safe(m)
            bfm_api.methods[name] = { method = m, params = n }
            if bfm_api.setter == nil and n == 1 then
                bfm_api.setter = name
            end
        end
    end

    for _, name in ipairs(BFM_ZERO_METHODS) do
        local m = find_method_in_chain(td, name)
        if m then
            local n = method_num_params_safe(m)
            bfm_api.methods[name] = { method = m, params = n }
        end
    end

    for _, name in ipairs({
        "facingDirection", "targetDirection", "startRotation",
        "FacingDirection", "TargetDirection", "StartRotation",
        "_FacingDirection", "_TargetDirection", "_StartRotation"
    }) do
        local f = find_field_in_chain(td, name)
        if f then
            local ok_static, is_static = pcall(function() return f:is_static() end)
            if not ok_static or not is_static then
                bfm_api.fields[name] = f
            end
        end
    end

    bfm_api.detected =
        (bfm_api.getter ~= nil or bfm_api.setter ~= nil or next(bfm_api.fields) ~= nil)
end

local function try_set_bfm_direction(player, direction)
    if not cfg.use_bfm_state_api then return false end
    init_bfm_api(player)
    if not bfm_api.detected then return false end

    if bfm_api.setter then
        local vec_ok, vec = pcall(function()
            return Vector3f.new(direction.x, direction.y, direction.z)
        end)
        if vec_ok and vec then
            local ok, err = pcall(function()
                player:call(bfm_api.setter, vec)
            end)
            if ok then return true end
            bfm_api.last_error = tostring(err)
        end
    end

    for name, field in pairs(bfm_api.fields) do
        local lower = name:lower()
        if lower:find("facing", 1, true) or lower:find("target", 1, true) then
            local vec_ok, vec = pcall(function()
                return Vector3f.new(direction.x, direction.y, direction.z)
            end)
            if vec_ok and vec then
                local ok, err = pcall(function()
                    field:set_data(player, vec)
                end)
                if ok then return true end
                bfm_api.last_error = tostring(err)
            end
        end
    end

    return false
end

--==========================================================================
--==========================================================================
-- 6. 수학 / 상태
--==========================================================================

local function yaw_from_quat(q)
    return math.atan(
        2.0 * (q.w * q.y + q.x * q.z),
        1.0 - 2.0 * (q.y * q.y + q.x * q.x)
    )
end

local function quat_from_yaw(yaw)
    local h = yaw * 0.5
    return Quaternion.new(
        math.cos(h),
        0.0,
        math.sin(h),
        0.0
    )
end

local function wrap_pi(a)
    while a >  math.pi do a = a - math.pi * 2.0 end
    while a < -math.pi do a = a + math.pi * 2.0 end
    return a
end

local focus_active = false
local toggle_state = false
local binding_key = false

local activity_active = false
local activity_frames_left = 0
local activity_initialized = false
local activity_last_pos = nil
local activity_last_yaw = nil

-- 공격 고정 종료와 평상시 Activity 추적의 겹침 구간
local attack_handoff_remaining = 0.0
local bfm_state_applied = false
local bfm_state_direction = nil

-- 공격 시작 순간의 yaw를 고정
local attack_lock_active = false
local attack_locked_yaw = nil
local attack_lock_remaining = 0.0
local attack_triggered = false

local post_window_hold_remaining = 0.0

local last_error = nil
local apply_count = 0
local frame_id = 0
local last_apply_frame = -1

local app_singleton, app_tdef

local function get_delta_time()
    if not app_singleton then
        app_singleton = sdk.get_native_singleton("via.Application")
        app_tdef = sdk.find_type_definition("via.Application")
    end

    if app_singleton and app_tdef then
        local ok, dt = pcall(function()
            return sdk.call_native_func(app_singleton, app_tdef, "get_DeltaTime")
        end)

        if ok and type(dt) == "number" and dt > 0.0 and dt < 0.25 then
            return dt
        end
    end

    return 1.0 / 60.0
end

local function reset_activity()
    activity_active = false
    activity_frames_left = 0
    activity_initialized = false
    activity_last_pos = nil
    activity_last_yaw = nil
    attack_handoff_remaining = 0.0
end

local function start_attack_handoff()
    attack_handoff_remaining = math.max(
        attack_handoff_remaining,
        math.max(0.0, cfg.attack_handoff_seconds or 0.0)
    )
end

local function reset_attack_lock()
    attack_lock_active = false
    attack_locked_yaw = nil
    attack_lock_remaining = 0.0
    post_window_hold_remaining = 0.0
    attack_triggered = false
    bfm_state_applied = false
    bfm_state_direction = nil
end

local function copy_vec3(v)
    return {
        x = v.x,
        y = v.y,
        z = v.z,
    }
end

local function update_activity()
    -- 핸드오프는 Activity gate가 false가 되어도 추적 상태를 유지합니다.
    local dt = get_delta_time()
    if attack_handoff_remaining > 0.0 then
        attack_handoff_remaining = attack_handoff_remaining - dt
        if attack_handoff_remaining < 0.0 then
            attack_handoff_remaining = 0.0
        end
    end

    local handoff_active = attack_handoff_remaining > 0.0

    if not cfg.activity_gate then
        activity_active = true
        return true
    end

    local player = get_player()
    local ptr = get_transform(player)

    if not ptr then
        activity_active = false
        return false
    end

    local ok, result = pcall(function()
        local pos = ptr:call("get_Position")
        local rot = ptr:call("get_Rotation")
        local yaw = yaw_from_quat(rot)

        if not activity_initialized or not activity_last_pos or activity_last_yaw == nil then
            activity_last_pos = copy_vec3(pos)
            activity_last_yaw = yaw
            activity_initialized = true
            activity_active = handoff_active
            return activity_active
        end

        local dx = pos.x - activity_last_pos.x
        local dy = pos.y - activity_last_pos.y
        local dz = pos.z - activity_last_pos.z

        local moved =
            (dx * dx + dy * dy + dz * dz) >=
            (cfg.activity_pos_threshold * cfg.activity_pos_threshold)

        local yaw_delta = math.abs(wrap_pi(yaw - activity_last_yaw))
        local rotated = yaw_delta >= cfg.activity_yaw_threshold

        activity_last_pos = copy_vec3(pos)
        activity_last_yaw = yaw

        if moved or rotated then
            activity_frames_left = cfg.activity_hold_frames
        elseif activity_frames_left > 0 then
            activity_frames_left = activity_frames_left - 1
        end

        activity_active = (activity_frames_left > 0) or handoff_active
        return activity_active
    end)

    if not ok then
        last_error = "activity: " .. tostring(result)
        activity_active = handoff_active
        return activity_active
    end

    return result or handoff_active
end

--==========================================================================
-- 7. 입력 / 상태 업데이트
--==========================================================================

re.on_frame(function()
    frame_id = frame_id + 1
    attack_triggered = false

    if binding_key then
        if capture_key() then
            binding_key = false
        end

        focus_active = false
        reset_activity()
        reset_attack_lock()
        return
    end

    if not cfg.enabled then
        focus_active = false
        toggle_state = false
        key_prev_down = false
        mouse_prev_l = false
        mouse_prev_r = false
        reset_activity()
        reset_attack_lock()
        return
    end

    if cfg.mode == 2 then
        if key_trg() then
            toggle_state = not toggle_state
        end
        focus_active = toggle_state
    else
        focus_active = key_down()
    end

    local attack_trg = false
    if get_mouse() ~= nil then
        attack_trg = update_attack_input()
    end

    if not focus_active then
        reset_activity()
        reset_attack_lock()
        return
    end

    -- 집중모드 중에는 현재 무기를 계속 자동 갱신합니다.
    -- 따라서 공격 입력 순간에 별도의 수동 무기 선택이 필요 없습니다.
    local current_player = get_player()
    if current_player then
        init_bfm_api(current_player)
        update_weapon_profile(current_player)
    end

    -- 공격 시작: 이 순간의 카메라 방향을 고정
    if attack_trg then
        local player = get_player()
        local ptr = get_transform(player)
        local ctr = get_camera_transform()

        local ok, err = pcall(function()
            if not player or not ptr or not ctr then
                return false
            end

            local ppos = ptr:call("get_Position")
            local cpos = ctr:call("get_Position")

            local dx = ppos.x - cpos.x
            local dz = ppos.z - cpos.z

            if (dx * dx + dz * dz) < 0.0001 then
                return false
            end

            attack_locked_yaw =
                math.atan(dx, dz) + cfg.yaw_offset

            update_weapon_profile(player)

            bfm_state_direction = {
                x = math.sin(attack_locked_yaw),
                y = 0.0,
                z = math.cos(attack_locked_yaw),
            }
            bfm_state_applied = try_set_bfm_direction(player, bfm_state_direction)

            attack_lock_remaining =
                math.max(
                    0.01,
                    current_window_seconds +
                    math.max(0.0, cfg.attack_lock_extension_seconds or 0.0)
                )

            attack_lock_active = true
            -- 공격 고정이 끝나는 지점과 평상시 추적을 일부러 겹치게 예약합니다.
            start_attack_handoff()
            attack_triggered = true

            return true
        end)

        if not ok then
            last_error = "attack trigger: " .. tostring(err)
        end
    end

    -- 공격 고정 시간이 끝날 때까지 감소
    if attack_lock_active then
        attack_lock_remaining =
            attack_lock_remaining - get_delta_time()

        if attack_lock_remaining <= 0.0 then
            attack_lock_remaining = 0.0
            attack_lock_active = false

            -- 만료 순간부터 다시 0.100초를 확보하여 Activity false와 겹칩니다.
            start_attack_handoff()

            if cfg.post_window_hold_seconds > 0.0 then
                post_window_hold_remaining =
                    cfg.post_window_hold_seconds
            else
                if attack_handoff_remaining <= 0.0 then
                    attack_locked_yaw = nil
                end
            end
        end
    elseif post_window_hold_remaining > 0.0 then
        post_window_hold_remaining =
            post_window_hold_remaining - get_delta_time()

        if post_window_hold_remaining <= 0.0 then
            post_window_hold_remaining = 0.0
            if attack_handoff_remaining <= 0.0 then
                attack_locked_yaw = nil
            end
        end
    end

    -- 공격 중이 아니면 v1.8식 활동 감지로 평상시 추적 여부 결정
    if not attack_lock_active and post_window_hold_remaining <= 0.0 then
        update_activity()
        if attack_handoff_remaining > 0.0 then
            activity_active = true
        end
    end

    if not attack_lock_active
        and post_window_hold_remaining <= 0.0
        and attack_handoff_remaining <= 0.0 then
        attack_locked_yaw = nil
    end
end)

--==========================================================================
-- 8. APPLY
--==========================================================================

-- 현재 카메라 기준의 목표 yaw를 계산합니다.
local function get_camera_target_yaw()
    local player = get_player()
    local ptr = get_transform(player)
    local ctr = get_camera_transform()

    if not player or not ptr or not ctr then
        return nil
    end

    local ppos = ptr:call("get_Position")
    local cpos = ctr:call("get_Position")

    local dx = ppos.x - cpos.x
    local dz = ppos.z - cpos.z

    if (dx * dx + dz * dz) < 0.0001 then
        return nil
    end

    return math.atan(dx, dz) + cfg.yaw_offset
end

-- 일반 카메라 추적용: smooth를 유지합니다.
local function apply_yaw(target_yaw)
    local player = get_player()
    if not player then return end

    local ptr = get_transform(player)
    if not ptr then return end

    local current_rotation = ptr:call("get_Rotation")
    local cur_yaw = yaw_from_quat(current_rotation)
    local diff = wrap_pi(target_yaw - cur_yaw)

    local delta_yaw
    if cfg.smooth <= 0.001 then
        delta_yaw = diff
    else
        delta_yaw = diff * (1.0 - cfg.smooth)
    end

    -- 한 번의 적용에서 너무 큰 회전은 제한
    local max_step = math.pi * 0.5
    if delta_yaw > max_step then delta_yaw = max_step end
    if delta_yaw < -max_step then delta_yaw = -max_step end

    local yaw_delta_quat = quat_from_yaw(delta_yaw)
    local new_rotation =
        (yaw_delta_quat * current_rotation):normalized()

    ptr:call("set_Rotation", new_rotation)
    apply_count = apply_count + 1
end

-- 공격 고정용: 보간하지 않고 목표 yaw를 정확히 맞춥니다.
-- 현재 회전의 pitch/roll은 유지하고 yaw만 목표값으로 정렬합니다.
local function force_locked_yaw(target_yaw)
    local player = get_player()
    if not player then return end

    local ptr = get_transform(player)
    if not ptr then return end

    local current_rotation = ptr:call("get_Rotation")
    local cur_yaw = yaw_from_quat(current_rotation)
    local diff = wrap_pi(target_yaw - cur_yaw)

    if math.abs(diff) > 0.0001 then
        local yaw_delta_quat = quat_from_yaw(diff)
        local new_rotation =
            (yaw_delta_quat * current_rotation):normalized()

        ptr:call("set_Rotation", new_rotation)
        apply_count = apply_count + 1
    end
end

local function apply_attack_lock_now()
    if not focus_active then return end
    if not cfg.apply_rotation then return end
    if attack_locked_yaw == nil then return end

    if attack_lock_active or post_window_hold_remaining > 0.0 then
        local ok, err = pcall(function()
            local player = get_player()
            local bfm_ok = false

            if bfm_state_direction and player then
                bfm_ok = try_set_bfm_direction(player, bfm_state_direction)
                if bfm_ok then
                    bfm_state_applied = true
                else
                    bfm_state_applied = false
                end
            end

            -- BFM 상태값이 없는 버전에서도 반드시 Transform으로 최종 방향을 확정합니다.
            force_locked_yaw(attack_locked_yaw)

            if bfm_ok then
                apply_count = apply_count + 1
            end
        end)

        if not ok then
            last_error = "attack force apply: " .. tostring(err)
        end
    end
end

local function apply_attack_handoff_now()
    if not focus_active then return end
    if not cfg.apply_rotation then return end
    if attack_lock_active then return end
    if post_window_hold_remaining > 0.0 then return end
    if attack_handoff_remaining <= 0.0 then return end

    -- 핸드오프에서는 저장된 공격 yaw가 아니라 현재 카메라 방향을 바로 따라갑니다.
    -- 이 구간이 기존 Activity false 1프레임을 완전히 덮어줍니다.
    local target_yaw = get_camera_target_yaw()
    if target_yaw == nil then return end

    local ok, err = pcall(function()
        force_locked_yaw(target_yaw)
    end)

    if not ok then
        last_error = "attack handoff apply: " .. tostring(err)
    end
end

-- LockScene 직전: 게임 로직이 회전을 쓰기 전에 먼저 정렬
re.on_pre_application_entry("LockScene", function()
    if not focus_active then return end
    if not cfg.apply_rotation then return end

    if attack_lock_active and attack_locked_yaw ~= nil then
        apply_attack_lock_now()
        return
    end

    if post_window_hold_remaining > 0.0
        and attack_locked_yaw ~= nil then
        apply_attack_lock_now()
        return
    end

    if attack_handoff_remaining > 0.0 then
        apply_attack_handoff_now()
        return
    end

    -- 공격이 없을 때는 v1.8 스타일 활동 중에만 카메라 추적
    if cfg.activity_gate and not activity_active then
        return
    end

    local ok, err = pcall(function()
        local player = get_player()
        local ptr = get_transform(player)
        local ctr = get_camera_transform()

        if not player or not ptr or not ctr then
            return
        end

        local target_yaw = get_camera_target_yaw()
        if target_yaw == nil then
            return
        end

        if last_apply_frame == frame_id then
            return
        end

        last_apply_frame = frame_id
        apply_yaw(target_yaw)
    end)

    if not ok then
        last_error = "normal apply: " .. tostring(err)
    end
end)

-- LockScene 직후: 게임 쪽에서 원래 방향을 다시 썼다면 즉시 되돌립니다.
re.on_application_entry("LockScene", function()
    apply_attack_lock_now()
    apply_attack_handoff_now()
end)

-- 실제 렌더 직전/직후에도 공격 고정 방향을 한 번 더 확정합니다.
-- 이 구간은 화면에 보이기 직전의 마지막 방어선 역할을 합니다.
re.on_pre_application_entry("PrepareRendering", function()
    apply_attack_lock_now()
    apply_attack_handoff_now()
end)

re.on_application_entry("PrepareRendering", function()
    apply_attack_lock_now()
    apply_attack_handoff_now()
end)

--==========================================================================
-- 9. UI
--==========================================================================

re.on_draw_ui(function()
    if not imgui.tree_node("Focus Aim (Rise)") then return end

    local changed, val

    changed, val = imgui.checkbox("모드 활성화", cfg.enabled)
    if changed then
        cfg.enabled = val
        save_cfg()
    end

    changed, val = imgui.combo(
        "작동 방식",
        cfg.mode,
        { "홀드 (누르는 동안만)", "토글" }
    )
    if changed then
        cfg.mode = val
        toggle_state = false
        reset_attack_lock()
        save_cfg()
    end

    imgui.text("현재 키: " .. key_display_name())
    imgui.same_line()

    if binding_key then
        imgui.text("  << 아무 키나 누르세요 (ESC 취소)")
    elseif imgui.button("키 변경") then
        binding_key = true
    end

    changed, val = imgui.slider_float(
        "부드러움",
        cfg.smooth,
        0.0,
        0.95,
        "%.2f"
    )
    if changed then
        cfg.smooth = val
        save_cfg()
    end

    changed, val = imgui.slider_float(
        "Yaw 보정(rad)",
        cfg.yaw_offset,
        -3.15,
        3.15,
        "%.3f"
    )
    if changed then
        cfg.yaw_offset = val
        save_cfg()
    end

    changed, val = imgui.checkbox(
        "행동할 때만 평상시 추적",
        cfg.activity_gate
    )
    if changed then
        cfg.activity_gate = val
        reset_activity()
        save_cfg()
    end

    if cfg.activity_gate then
        changed, val = imgui.slider_float(
            "움직임 감도(m)",
            cfg.activity_pos_threshold,
            0.001,
            0.05,
            "%.3f"
        )
        if changed then
            cfg.activity_pos_threshold = val
            save_cfg()
        end

        changed, val = imgui.slider_float(
            "회전 감도(rad)",
            cfg.activity_yaw_threshold,
            0.001,
            0.10,
            "%.3f"
        )
        if changed then
            cfg.activity_yaw_threshold = val
            save_cfg()
        end

        changed, val = imgui.slider_int(
            "추적 유지 프레임",
            cfg.activity_hold_frames,
            1,
            60
        )
        if changed then
            cfg.activity_hold_frames = val
            save_cfg()
        end
    end

    imgui.separator()
    imgui.text("공격 시작 방향 고정")

    update_weapon_profile(get_player())

    imgui.text(
        "현재 무기: " ..
        (WEAPON_LABELS[current_weapon_key] or current_weapon_key)
    )

    imgui.text(
        "런타임 타입: " .. tostring(weapon_type_name)
    )

    imgui.text(
        "현재 적용 보정 시간: " ..
        string.format("%.3f초", current_window_seconds) ..
        " + 여유 " ..
        string.format("%.3f초", math.max(0.0, cfg.attack_lock_extension_seconds or 0.0))
    )

    changed, val = imgui.slider_float(
        "공격 종료 핸드오프(초)",
        cfg.attack_handoff_seconds,
        0.000,
        0.250,
        "%.3f"
    )
    if changed then
        cfg.attack_handoff_seconds = val
        save_cfg()
    end

    imgui.text("※ 무기 Timing은 자동 적용됩니다. 수동 무기/무기별 Timing 변경은 없습니다.")

    if current_weapon_key == "Generic" then
        changed, val = imgui.slider_float(
            "미감지/기본 보정 시간(초)",
            cfg.generic_window_seconds,
            0.05,
            0.50,
            "%.3f"
        )

        if changed then
            cfg.generic_window_seconds = val
            update_weapon_profile(get_player())
            save_cfg()
        end

        imgui.text("현재 무기명을 인식하지 못해 Generic 값이 사용됩니다.")
    end

    imgui.separator()

    changed, val = imgui.checkbox(
        "BFM 상태값 복구 사용",
        cfg.use_bfm_state_api
    )
    if changed then
        cfg.use_bfm_state_api = val
        if not val then
            bfm_state_applied = false
            bfm_state_direction = nil
        end
        save_cfg()
    end

    changed, val = imgui.checkbox(
        "디버그 표시",
        cfg.debug
    )
    if changed then
        cfg.debug = val
        save_cfg()
    end

    changed, val = imgui.checkbox(
        "회전 적용",
        cfg.apply_rotation
    )
    if changed then
        cfg.apply_rotation = val
        save_cfg()
    end

    if cfg.debug then
        update_weapon_profile(get_player())

        imgui.text("focus_active: " .. tostring(focus_active))
        imgui.text("player: " .. tostring(get_player() ~= nil))
        imgui.text("camera: " .. tostring(get_camera_transform() ~= nil))

        imgui.text(
            "activity_active: " ..
            tostring(activity_active)
        )

        imgui.text(
            "attack lock: " ..
            tostring(attack_lock_active)
        )

        imgui.text(
            "attack remaining: " ..
            string.format("%.3f초", attack_lock_remaining)
        )

        imgui.text(
            "weapon: " ..
            tostring(
                WEAPON_LABELS[current_weapon_key] or
                current_weapon_key
            )
        )

        imgui.text(
            "weapon type: " ..
            tostring(weapon_type_name)
        )

        imgui.text(
            "BFM weapon type: " ..
            tostring(bfm_weapon_type_name)
        )

        imgui.text(
            "BFM weapon source: " ..
            tostring(bfm_weapon_source)
        )

        imgui.text(
            "BFM player type: " ..
            tostring(bfm_api.type_name)
        )

        imgui.text(
            "BFM API detected: " ..
            tostring(bfm_api.detected)
        )

        imgui.text(
            "BFM setter: " ..
            tostring(bfm_api.setter)
        )

        imgui.text(
            "BFM state applied: " ..
            tostring(bfm_state_applied)
        )

        imgui.text(
            "weapon window: " ..
            string.format("%.3f초", current_window_seconds)
        )

        imgui.text(
            "lock extension: " ..
            string.format("%.3f초", math.max(0.0, cfg.attack_lock_extension_seconds or 0.0))
        )

        imgui.text(
            "attack handoff remaining: " ..
            string.format("%.3f초", attack_handoff_remaining)
        )

        imgui.text(
            "apply_count: " ..
            tostring(apply_count)
        )

        if input_error then
            imgui.text("input error: " .. input_error)
        end

        if mouse_error then
            imgui.text("mouse error: " .. mouse_error)
        end

        if weapon_detect_error then
            imgui.text(
                "weapon error: " ..
                weapon_detect_error
            )
        end

        if last_error then
            imgui.text("last error: " .. last_error)
        end
    end

    imgui.tree_pop()
end)

log.info(
    "[MHR_FocusMode v2.9] loaded with BFM weapon-type restore. " ..
    "auto_weapon_detection=true" ..
    ", key=" ..
    tostring(key_display_name()) ..
    ", lock_extension=" ..
    tostring(cfg.attack_lock_extension_seconds or 0.0) ..
    ", handoff=" ..
    tostring(cfg.attack_handoff_seconds or 0.0)
)
