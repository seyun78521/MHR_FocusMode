--[[
    ModFocusRise v2.6 - Focus Aim for Monster Hunter Rise (REFramework)

    v2.3: 무기 구별은 일단 보류하고, Better Focus Mode의 11종 근접무기
    correction window 평균값을 모든 무기에 공통 적용합니다.

    평균 = 2.16 / 11 = 0.19636초 → 기본값 0.196초.

    현재 기능:
      - LALT로 집중모드 활성화
      - 이동만으로는 회전하지 않음
      - 공격 시작 시 카메라 방향을 저장
      - 평균 correction window 동안 저장 방향으로 보정
      - window 종료 후 일반 게임 회전에 반환

    v2.2의 무기 자동 판별/내부 필드 진단 코드는 제거했습니다.
    오버레이도 실제 사용에 필요한 항목만 남겼습니다.

    v2.6:
      - v2.5의 BFM 상태 실험은 유지합니다.
      - Better Focus Mode의 11종 Timing을 무기별로 자동 적용할 수 있습니다.
      - 자동 감지가 불확실하면 수동 무기를 선택할 수 있습니다.
      - 각 무기 Timing은 설정창에서 개별 수정할 수 있습니다.
]]

--==========================================================================
-- 1. 설정
--==========================================================================

local CFG_PATH = "ModFocusRise.json"

--==========================================================================
-- Better Focus Mode Timing
-- 원본에서 제공된 11종 근접무기 값
--==========================================================================
local WEAPON_TIMINGS_DEFAULT = {
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
    Generic        = "수동/미감지",
}

local WEAPON_ORDER = {
    "GreatSword", "LongSword", "ChargeBlade", "SwordAndShield",
    "DualBlades", "Hammer", "HuntingHorn", "Lance", "Gunlance",
    "SwitchAxe", "InsectGlaive"
}

-- Rise 내부 _WeaponMain 타입명에 대한 보수적 후보.
-- 실제 타입명이 다르면 자동 감지는 Generic이 되고 수동 선택을 사용할 수 있습니다.
local WEAPON_PATTERNS = {
    { key = "GreatSword",     patterns = { "GreatSword", "Greatsword", "GS" } },
    { key = "LongSword",      patterns = { "LongSword", "Longsword", "LS" } },
    { key = "ChargeBlade",    patterns = { "ChargeAxe", "ChargeBlade", "Chargeblade" } },
    { key = "SwordAndShield", patterns = { "ShortSword", "SwordAndShield", "SwordShield" } },
    { key = "DualBlades",     patterns = { "DualBlades", "DualBlade", "TwinSword" } },
    { key = "Hammer",         patterns = { "Hammer" } },
    { key = "HuntingHorn",    patterns = { "HuntingHorn", "Horn" } },
    { key = "Lance",          patterns = { "GunLance", "Gunlance" } },
    { key = "Lance",          patterns = { "Lance" } },
    { key = "Gunlance",       patterns = { "GunLance", "Gunlance" } },
    { key = "SwitchAxe",      patterns = { "SlashAxe", "SwitchAxe", "SwitchAxe" } },
    { key = "InsectGlaive",   patterns = { "InsectGlaive", "Insect" } },
}

local DEFAULTS = {
    enabled        = true,
    mode           = 1,
    key            = 0xA4,
    key_name       = "Menu",   -- via.hid.KeyboardKey.Menu = LALT
    smooth         = 0.20,
    yaw_offset     = 0.0,

    debug          = false,
    apply_rotation = false,

    -- 기본 correction window
    correction_window_seconds = 0.196,

    -- 무기별 자동 Timing
    auto_weapon_timing = true,
    manual_weapon = "GreatSword",

    -- 원본 Better Focus Timing을 개별 수정 가능
    great_sword_window_seconds      = 0.24,
    long_sword_window_seconds       = 0.18,
    charge_blade_window_seconds     = 0.22,
    sword_and_shield_window_seconds = 0.16,
    dual_blades_window_seconds      = 0.14,
    hammer_window_seconds            = 0.24,
    hunting_horn_window_seconds     = 0.22,
    lance_window_seconds             = 0.18,
    gunlance_window_seconds          = 0.20,
    switch_axe_window_seconds        = 0.20,
    insect_glaive_window_seconds     = 0.18,

    -- 기본 0.00: correction window 종료 후 즉시 게임 회전에 반환
    post_window_hold_seconds = 0.00,

    -- v2.5: BFM 구조 실험. 기본 ON. 실제 호환 멤버가 없으면 자동 fallback.
    use_bfm_state_api = true,
}

local cfg = json.load_file(CFG_PATH) or {}
for k, v in pairs(DEFAULTS) do
    if cfg[k] == nil then cfg[k] = v end
end

local function save_cfg()
    json.dump_file(CFG_PATH, cfg)
end

--==========================================================================
-- 2. 키 표시
--==========================================================================

local function key_display_name()
    if cfg.key_name == "Menu" then
        return "LALT"
    end
    return tostring(cfg.key_name or "Menu")
end

--==========================================================================
-- 3. Keyboard 입력
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
-- 4. Mouse 입력
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

    return trg_l or trg_r, l, r
end

--==========================================================================
-- 5. Player / Camera / Weapon
--==========================================================================

local function refresh_weapon_timing_config()
    WEAPON_TIMINGS_DEFAULT.GreatSword     = cfg.great_sword_window_seconds
    WEAPON_TIMINGS_DEFAULT.LongSword      = cfg.long_sword_window_seconds
    WEAPON_TIMINGS_DEFAULT.ChargeBlade    = cfg.charge_blade_window_seconds
    WEAPON_TIMINGS_DEFAULT.SwordAndShield = cfg.sword_and_shield_window_seconds
    WEAPON_TIMINGS_DEFAULT.DualBlades     = cfg.dual_blades_window_seconds
    WEAPON_TIMINGS_DEFAULT.Hammer         = cfg.hammer_window_seconds
    WEAPON_TIMINGS_DEFAULT.HuntingHorn    = cfg.hunting_horn_window_seconds
    WEAPON_TIMINGS_DEFAULT.Lance          = cfg.lance_window_seconds
    WEAPON_TIMINGS_DEFAULT.Gunlance       = cfg.gunlance_window_seconds
    WEAPON_TIMINGS_DEFAULT.SwitchAxe     = cfg.switch_axe_window_seconds
    WEAPON_TIMINGS_DEFAULT.InsectGlaive  = cfg.insect_glaive_window_seconds
end

local current_weapon_key = "Generic"
local current_weapon_type_name = "(unknown)"
local current_window_seconds = 0.196
local weapon_detect_error = nil

local function get_player()
    local pm = sdk.get_managed_singleton("snow.player.PlayerManager")
    if not pm then return nil end
    return pm:call("findMasterPlayer")
end

local function get_main_weapon(player)
    player = player or get_player()
    if not player then return nil end

    local ok, weapon = pcall(function()
        return player:get_field("_WeaponMain")
    end)

    if not ok then
        weapon_detect_error = tostring(weapon)
        return nil
    end

    return weapon
end

local function get_weapon_type_name(weapon)
    if not weapon then return nil end

    local ok, name = pcall(function()
        local td = weapon:get_type_definition()
        if not td then return nil end
        return td:get_name()
    end)

    if not ok then
        weapon_detect_error = tostring(name)
        return nil
    end

    return name
end

local function detect_weapon_key(player)
    if not cfg.auto_weapon_timing then
        return cfg.manual_weapon or "GreatSword"
    end

    local weapon = get_main_weapon(player)
    local type_name = get_weapon_type_name(weapon)

    current_weapon_type_name = type_name or "(unknown)"

    if not type_name then
        return "Generic"
    end

    for _, item in ipairs(WEAPON_PATTERNS) do
        for _, pattern in ipairs(item.patterns) do
            if string.find(type_name, pattern, 1, true) then
                return item.key
            end
        end
    end

    return "Generic"
end

local function update_weapon_profile(player)
    refresh_weapon_timing_config()

    local key = detect_weapon_key(player)
    current_weapon_key = key

    if key == "Generic" then
        current_window_seconds = cfg.correction_window_seconds
    else
        current_window_seconds = WEAPON_TIMINGS_DEFAULT[key] or cfg.correction_window_seconds
    end

    return current_window_seconds
end

local function get_window_seconds(player)
    return update_weapon_profile(player)
end

--==========================================================================
-- 5.1 Player Transform / Camera
--==========================================================================

local function get_transform(obj)
    local pm = sdk.get_managed_singleton("snow.player.PlayerManager")
    if not pm then return nil end
    return pm:call("findMasterPlayer")
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

--==========================================================================
-- 6.5. BFM 스타일 상태 API 탐색/접근 (실험)
--
-- 중요: 이 코드는 MHW의 BFM 함수를 Rise에 "동일하다고 단정"하지 않습니다.
-- Rise PlayerBase에 실제로 같은 이름의 메서드/필드가 존재하고, 호출/대입
-- 시그니처가 안전하게 확인될 때만 사용합니다.
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

local function get_type_name_safe(td)
    if not td then return nil end
    local ok, name = pcall(function() return td:get_name() end)
    if ok then return name end
    return nil
end

local function method_num_params_safe(m)
    local ok, n = pcall(function() return m:get_num_params() end)
    if ok and type(n) == "number" then return n end
    return nil
end

local function find_method_in_chain(td, name)
    local cur = td
    local guard = 0
    while cur and guard < 12 do
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
    while cur and guard < 12 do
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
    if bfm_api.initialized and bfm_api.detected then return end
    if not player then return end

    local ok_td, td = pcall(function() return player:get_type_definition() end)
    if not ok_td or not td then return end

    bfm_api.initialized = true
    bfm_api.type_name = get_type_name_safe(td) or "(unknown)"
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
            -- getter로 안전하게 부를 수 있는 것은 0-인자만 사용
            if bfm_api.getter == nil and n == 0 and name ~= "TryGetFacingDirection" then
                bfm_api.getter = name
            elseif bfm_api.getter == nil and n == 0 then
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

    bfm_api.detected = (bfm_api.getter ~= nil or bfm_api.setter ~= nil or next(bfm_api.fields) ~= nil)
end

local function read_bfm_direction(player)
    if not cfg.use_bfm_state_api then return nil end
    init_bfm_api(player)
    if not bfm_api.detected then return nil end

    -- 1) zero-arg getter: 반환값이 Vector3/Quaternion 형태일 때 채택
    if bfm_api.getter then
        local ok, value = pcall(function() return player:call(bfm_api.getter) end)
        if ok and value ~= nil then
            local ok_x, x = pcall(function() return value.x end)
            local ok_z, z = pcall(function() return value.z end)
            if ok_x and ok_z and x ~= nil and z ~= nil then
                return { x = x, y = (value.y or 0.0), z = z, source = "method:" .. bfm_api.getter }
            end
        end
    end

    -- 2) 실제 Vector3 방향 필드가 있으면 읽기
    for name, field in pairs(bfm_api.fields) do
        local ok, value = pcall(function() return field:get_data(player) end)
        if ok and value ~= nil then
            local ok_x, x = pcall(function() return value.x end)
            local ok_z, z = pcall(function() return value.z end)
            if ok_x and ok_z and x ~= nil and z ~= nil then
                return { x = x, y = (value.y or 0.0), z = z, source = "field:" .. name }
            end
        end
    end

    return nil
end

local function try_set_bfm_direction(player, direction)
    if not cfg.use_bfm_state_api then return false end
    init_bfm_api(player)
    if not bfm_api.detected then return false end

    -- Vector3 방향 setter만 보수적으로 시도.
    if bfm_api.setter then
        local vec_ok, vec = pcall(function()
            return Vector3f.new(direction.x, direction.y, direction.z)
        end)
        if vec_ok and vec then
            local ok = pcall(function() player:call(bfm_api.setter, vec) end)
            if ok then return true end
        end
    end

    -- 정확한 이름의 Vector3 필드가 실제로 존재하면 직접 대입.
    for name, field in pairs(bfm_api.fields) do
        if name:lower():find("facing", 1, true) or name:lower():find("target", 1, true) then
            local vec_ok, vec = pcall(function()
                return Vector3f.new(direction.x, direction.y, direction.z)
            end)
            if vec_ok and vec then
                local ok = pcall(function() field:set_data(player, vec) end)
                if ok then return true end
            end
        end
    end

    return false
end

local function bfm_zero_arg_call(player, name)
    local item = bfm_api.methods[name]
    if not item or item.params ~= 0 then return nil end
    local ok, result = pcall(function() return player:call(name) end)
    if ok then return result end
    return nil
end

--==========================================================================

-- 7. 수학
--==========================================================================

local function yaw_from_quat(q)
    return math.atan(
        2.0 * (q.w * q.y + q.x * q.z),
        1.0 - 2.0 * (q.y * q.y + q.x * q.x)
    )
end

-- REFramework Quaternion.new는 (w, x, y, z)
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

--==========================================================================
-- 8. 상태
--==========================================================================

local focus_active = false
local toggle_state = false
local binding_key  = false

local attack_correction_active = false
local attack_locked_yaw = nil
local attack_window_remaining = 0.0
local current_window_seconds = 0.196
local attack_triggered = false
local post_window_hold_remaining = 0.0
local attack_locked_direction = nil
local bfm_state_applied = false

local last_error = nil
local apply_count = 0
local frame_id = 0
local last_apply_frame = -1

-- 게임의 실제 DeltaTime을 사용해 초 단위 correction window 유지.
-- 실패 시 60 FPS 기준으로 fallback.
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

local function reset_attack_correction()
    attack_correction_active = false
    attack_locked_yaw = nil
    attack_window_remaining = 0.0
    attack_triggered = false
    post_window_hold_remaining = 0.0
    attack_locked_direction = nil
    bfm_state_applied = false
end

--==========================================================================
-- 9. 상태 머신
--==========================================================================

re.on_frame(function()
    frame_id = frame_id + 1
    attack_triggered = false

    if binding_key then
        if capture_key() then
            binding_key = false
        end

        focus_active = false
        reset_attack_correction()
        return
    end

    if not cfg.enabled then
        focus_active = false
        toggle_state = false
        key_prev_down = false
        mouse_prev_l = false
        mouse_prev_r = false
        reset_attack_correction()
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

    if focus_active and attack_trg then
        local ok, err = pcall(function()
            local player = get_player()
            local ptr = get_transform(player)
            local ctr = get_camera_transform()

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

            -- 공격이 시작되는 바로 그 순간의 카메라 방향을 저장.
            attack_locked_yaw = math.atan(dx, dz) + cfg.yaw_offset
            attack_locked_direction = {
                x = math.sin(attack_locked_yaw),
                y = 0.0,
                z = math.cos(attack_locked_yaw),
            }

            -- BFM 방식 1차 실험: Rise에 동일 역할의 setter가 실제 존재하면
            -- 캐릭터의 facing/target 상태 자체를 카메라 방향으로 바꿉니다.
            bfm_state_applied = try_set_bfm_direction(player, attack_locked_direction)

            current_window_seconds = math.max(0.01, get_window_seconds(player))
            attack_window_remaining = current_window_seconds
            attack_correction_active = true
            attack_triggered = true
            return true
        end)

        if not ok then
            last_error = "attack trigger: " .. tostring(err)
        end
    end

    -- 시간 기반 correction window. 실제 게임 DeltaTime을 사용.
    if attack_correction_active then
        attack_window_remaining = attack_window_remaining - get_delta_time()

        if attack_window_remaining <= 0.0 then
            attack_window_remaining = 0.0
            attack_correction_active = false
            if cfg.post_window_hold_seconds > 0.0 then
                post_window_hold_remaining = cfg.post_window_hold_seconds
            else
                attack_locked_yaw = nil
            end
        end
    elseif post_window_hold_remaining > 0.0 then
        post_window_hold_remaining = post_window_hold_remaining - get_delta_time()
        if post_window_hold_remaining <= 0.0 then
            post_window_hold_remaining = 0.0
            attack_locked_yaw = nil
        end
    end
end)

--==========================================================================
-- 10. APPLY - 공격 시작 방향 유지
--==========================================================================

local function apply_locked_yaw()
    if not attack_correction_active and post_window_hold_remaining <= 0.0 then return end
    if attack_locked_yaw == nil then return end
    if not cfg.apply_rotation then return end

    local player = get_player()
    if not player then return end

    -- BFM 스타일 direct state가 성공하면 우선 그것을 유지한다.
    if bfm_state_applied and attack_locked_direction then
        local ok = try_set_bfm_direction(player, attack_locked_direction)
        if ok then
            apply_count = apply_count + 1
            return
        end
        -- setter가 더 이상 작동하지 않으면 이 공격에서는 Transform fallback.
        bfm_state_applied = false
    end

    local ptr = get_transform(player)
    if not ptr then return end

    local current_rotation = ptr:call("get_Rotation")
    local cur_yaw = yaw_from_quat(current_rotation)
    local diff = wrap_pi(attack_locked_yaw - cur_yaw)

    local delta_yaw
    if cfg.smooth <= 0.001 then
        delta_yaw = diff
    else
        delta_yaw = diff * (1.0 - cfg.smooth)
    end

    local max_step = math.pi * 0.5
    if delta_yaw > max_step then delta_yaw = max_step end
    if delta_yaw < -max_step then delta_yaw = -max_step end

    local yaw_delta_quat = quat_from_yaw(delta_yaw)
    local new_rotation = (yaw_delta_quat * current_rotation):normalized()

    ptr:call("set_Rotation", new_rotation)
    apply_count = apply_count + 1
end

re.on_pre_application_entry("LockScene", function()
    if not attack_correction_active and post_window_hold_remaining <= 0.0 then return end
    if not cfg.apply_rotation then return end

    if last_apply_frame == frame_id then return end
    last_apply_frame = frame_id

    local ok, err = pcall(apply_locked_yaw)
    if not ok then
        last_error = "apply rotation: " .. tostring(err)
    end
end)

--==========================================================================
--==========================================================================
-- 11. UI
--==========================================================================

re.on_draw_ui(function()
    if not imgui.tree_node("Focus Aim (Rise)") then return end

    local changed, val

    changed, val = imgui.checkbox("모드 활성화", cfg.enabled)
    if changed then cfg.enabled = val; save_cfg() end

    changed, val = imgui.combo("작동 방식", cfg.mode, {
        "홀드 (누르는 동안만)",
        "토글"
    })
    if changed then
        cfg.mode = val
        toggle_state = false
        reset_attack_correction()
        save_cfg()
    end

    imgui.text("현재 키: " .. key_display_name())
    imgui.same_line()
    if binding_key then
        imgui.text("  << 아무 키나 누르세요 (ESC 취소)")
    elseif imgui.button("키 변경") then
        binding_key = true
    end

    changed, val = imgui.slider_float("부드러움", cfg.smooth, 0.0, 0.95, "%.2f")
    if changed then cfg.smooth = val; save_cfg() end

    changed, val = imgui.slider_float("Yaw 보정(rad)", cfg.yaw_offset, -3.15, 3.15, "%.3f")
    if changed then cfg.yaw_offset = val; save_cfg() end

    imgui.separator()
    imgui.text("공격 시작 보정")

    changed, val = imgui.checkbox("무기별 자동 타이밍", cfg.auto_weapon_timing)
    if changed then
        cfg.auto_weapon_timing = val
        save_cfg()
    end

    if cfg.auto_weapon_timing then
        local seconds = update_weapon_profile()
        imgui.text(
            "현재 무기: " ..
            (WEAPON_LABELS[current_weapon_key] or current_weapon_key)
        )
        imgui.text("자동 보정 시간: " .. string.format("%.3f초", seconds))
        imgui.text("내부 타입: " .. tostring(current_weapon_type_name))
    else
        local current_manual_index = 1
        for i, key in ipairs(WEAPON_ORDER) do
            if key == cfg.manual_weapon then
                current_manual_index = i
                break
            end
        end

        local labels = {}
        for _, key in ipairs(WEAPON_ORDER) do
            table.insert(labels, WEAPON_LABELS[key])
        end

        changed, val = imgui.combo("수동 무기", current_manual_index, labels)
        if changed then
            cfg.manual_weapon = WEAPON_ORDER[val]
            update_weapon_profile()
            save_cfg()
        end

        current_window_seconds = update_weapon_profile()
        imgui.text("선택 무기 보정 시간: " .. string.format("%.3f초", current_window_seconds))
    end

    changed, val = imgui.slider_float(
        "미감지/기본 보정 시간(초)",
        cfg.correction_window_seconds,
        0.05,
        0.50,
        "%.3f"
    )
    if changed then cfg.correction_window_seconds = val; save_cfg() end

    imgui.text("Better Focus Timing")

    local timing_items = {
        {"great_sword_window_seconds", "대검", 0.24},
        {"long_sword_window_seconds", "태도", 0.18},
        {"charge_blade_window_seconds", "차지액스", 0.22},
        {"sword_and_shield_window_seconds", "한손검", 0.16},
        {"dual_blades_window_seconds", "쌍검", 0.14},
        {"hammer_window_seconds", "해머", 0.24},
        {"hunting_horn_window_seconds", "수렵피리", 0.22},
        {"lance_window_seconds", "랜스", 0.18},
        {"gunlance_window_seconds", "건랜스", 0.20},
        {"switch_axe_window_seconds", "슬래시액스", 0.20},
        {"insect_glaive_window_seconds", "조충곤", 0.18},
    }

    for _, item in ipairs(timing_items) do
        local key = item[1]
        local label = item[2]
        changed, val = imgui.slider_float(
            label .. "##timing",
            cfg[key],
            0.05,
            0.50,
            "%.3f초"
        )
        if changed then
            cfg[key] = val
            refresh_weapon_timing_config()
            save_cfg()
        end
    end

    changed, val = imgui.checkbox("BFM 방식 상태값 시도", cfg.use_bfm_state_api)
    if changed then cfg.use_bfm_state_api = val; save_cfg() end

    changed, val = imgui.checkbox("디버그 표시", cfg.debug)
    if changed then cfg.debug = val; save_cfg() end

    changed, val = imgui.checkbox("회전 적용", cfg.apply_rotation)
    if changed then cfg.apply_rotation = val; save_cfg() end

    if cfg.debug then
        imgui.text("focus_active: " .. tostring(focus_active))
        imgui.text("player: " .. tostring(get_player() ~= nil))
        imgui.text("camera: " .. tostring(get_camera_transform() ~= nil))
        imgui.text("correction active: " .. tostring(attack_correction_active))
        imgui.text("window remaining: " .. string.format("%.3f", attack_window_remaining) .. " sec")
        imgui.text("weapon: " .. tostring(WEAPON_LABELS[current_weapon_key] or current_weapon_key))
        imgui.text("weapon type: " .. tostring(current_weapon_type_name))
        imgui.text("weapon window: " .. string.format("%.3f", current_window_seconds) .. " sec")
        imgui.text("apply_rotation: " .. tostring(cfg.apply_rotation))
        imgui.text("BFM API detected: " .. tostring(bfm_api.detected))
        imgui.text("BFM type: " .. tostring(bfm_api.type_name))
        imgui.text("BFM getter: " .. tostring(bfm_api.getter))
        imgui.text("BFM setter: " .. tostring(bfm_api.setter))
        imgui.text("BFM state applied: " .. tostring(bfm_state_applied))
        if bfm_api.last_error then imgui.text("BFM error: " .. tostring(bfm_api.last_error)) end
        if last_error then imgui.text("last error: " .. last_error) end
    end

    imgui.tree_pop()
end)

log.info(
    "[ModFocusRise v2.6] loaded. window=" ..
    tostring(cfg.correction_window_seconds) .. " sec, auto_weapon_timing=" .. tostring(cfg.auto_weapon_timing) .. ", key=" .. tostring(key_display_name())
)
