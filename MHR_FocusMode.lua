--[[
    MHR_FocusMode v3.0 - Focus Aim for Monster Hunter Rise (REFramework)

    v3.0 핵심:
      - 평상시 카메라 추적은 별도의 Activity 상태에 의존하지 않습니다.
        -> Activity 상태 전환 때문에 생기던 1프레임 방향 복귀 가능성을 제거합니다.
      - 공격 입력(L/R 클릭) 순간의 카메라 방향을 저장하고,
        현재 플레이어의 BFM Type 하나만으로 무기를 자동 판별합니다.
      - 무기 판별에 다른 무기 객체 탐색이나 부모 타입 탐색,
        수동 무기 선택을 사용하지 않습니다.
      - BFM Type을 매칭하지 못했을 때만 Generic Timing을 사용합니다.
      - 공격 고정 중에는 smooth 보정을 사용하지 않고 정확한 yaw를 강제합니다.
      - LockScene 전/후 + PrepareRendering 전/후에서 재적용합니다.
      - 공격 종료 직후에는 현재 카메라 방향을 이어받는 handoff 구간을 유지합니다.
      - v2.5의 BFM 상태 setter/getter 탐색은 제거했습니다.
        v3.0에서 필요한 BFM 정보는 무기 판별용 Type 하나뿐입니다.

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
      - 무기 감지는 player:get_type_definition():get_name() 결과 하나만 사용합니다.
      - BFM Type이 매칭되지 않을 때만 Generic(미감지/기본) Timing을 사용합니다.
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

    -- 무기 Timing은 항상 자동 인식.
    -- 무기가 인식되지 않을 때만 아래 Generic 값을 사용합니다.
    generic_window_seconds = 0.196,

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
-- 5. Player / Camera / BFM Type
--==========================================================================

local function get_player()
    local pm = sdk.get_managed_singleton("snow.player.PlayerManager")
    if not pm then return nil end

    local ok, player = pcall(function()
        return pm:call("getPlayer", 0)
    end)

    if ok and player then
        return player
    end

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

-- BFM Type 하나만 이용한 무기 자동 판별
local bfm_type_name = "(unknown)"
local current_weapon_key = "Generic"
local current_window_seconds = 0.196
local weapon_detect_error = nil

local BFM_WEAPON_PATTERNS = {
    { key = "GreatSword",     patterns = { "GreatSword", "Greatsword" } },
    { key = "LongSword",      patterns = { "LongSword", "Longsword" } },
    { key = "ChargeBlade",    patterns = { "ChargeBlade", "Chargeblade", "ChargeAxe" } },
    { key = "SwordAndShield", patterns = { "SwordAndShield", "SwordShield", "ShortSword" } },
    { key = "DualBlades",     patterns = { "DualBlades", "DualBlade" } },
    { key = "Hammer",         patterns = { "Hammer" } },
    { key = "HuntingHorn",    patterns = { "HuntingHorn", "Horn" } },
    { key = "Lance",          patterns = { "Lance" } },
    { key = "Gunlance",       patterns = { "GunLance", "Gunlance" } },
    { key = "SwitchAxe",      patterns = { "SwitchAxe", "SlashAxe" } },
    { key = "InsectGlaive",   patterns = { "InsectGlaive", "Insect" } },
}

local function normalize_bfm_type(name)
    if not name then return "" end
    local s = tostring(name):lower()
    s = s:gsub("[^%w]", "")
    return s
end

local function get_bfm_type_name(player)
    if not player then
        bfm_type_name = "(unknown)"
        return nil
    end

    local ok, name = pcall(function()
        local td = player:get_type_definition()
        if not td then return nil end
        return td:get_name()
    end)

    if not ok then
        bfm_type_name = "(error)"
        weapon_detect_error = tostring(name)
        return nil
    end

    bfm_type_name = name or "(unknown)"
    weapon_detect_error = nil
    return name
end

local function detect_weapon_key(player)
    local type_name = get_bfm_type_name(player)

    if not type_name then
        current_weapon_key = "Generic"
        return "Generic"
    end

    local normalized = normalize_bfm_type(type_name)

    for _, item in ipairs(BFM_WEAPON_PATTERNS) do
        for _, pattern in ipairs(item.patterns) do
            local p = normalize_bfm_type(pattern)
            if p ~= "" and string.find(normalized, p, 1, true) then
                current_weapon_key = item.key
                return item.key
            end
        end
    end

    current_weapon_key = "Generic"
    return "Generic"
end

local function update_weapon_profile(player)
    local key = detect_weapon_key(player)

    if key == "Generic" then
        current_window_seconds = cfg.generic_window_seconds
    else
        current_window_seconds = WEAPON_TIMINGS[key] or cfg.generic_window_seconds
    end

    return current_window_seconds
end

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

local attack_lock_active = false
local attack_locked_yaw = nil
local attack_lock_remaining = 0.0
local attack_triggered = false

local attack_handoff_remaining = 0.0

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

local function reset_attack_lock()
    attack_lock_active = false
    attack_locked_yaw = nil
    attack_lock_remaining = 0.0
    attack_handoff_remaining = 0.0
    attack_triggered = false
end

local function start_attack_handoff()
    attack_handoff_remaining = math.max(
        attack_handoff_remaining,
        math.max(0.0, cfg.attack_handoff_seconds or 0.0)
    )
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
        reset_attack_lock()
        return
    end

    if not cfg.enabled then
        focus_active = false
        toggle_state = false
        key_prev_down = false
        mouse_prev_l = false
        mouse_prev_r = false
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
        reset_attack_lock()
        return
    end

    -- BFM Type만으로 현재 무기를 갱신합니다.
    local player = get_player()
    if player then
        update_weapon_profile(player)
    end

    if attack_trg then
        local player_at_attack = get_player()
        local ptr = get_transform(player_at_attack)
        local ctr = get_camera_transform()

        local ok, err = pcall(function()
            if not player_at_attack or not ptr or not ctr then
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

            -- 공격 직전의 BFM Type으로 Timing을 확정합니다.
            update_weapon_profile(player_at_attack)

            attack_lock_remaining =
                math.max(
                    0.01,
                    current_window_seconds +
                    math.max(0.0, cfg.attack_lock_extension_seconds or 0.0)
                )

            attack_lock_active = true
            start_attack_handoff()
            attack_triggered = true

            return true
        end)

        if not ok then
            last_error = "attack trigger: " .. tostring(err)
        end
    end

    if attack_lock_active then
        attack_lock_remaining =
            attack_lock_remaining - get_delta_time()

        if attack_lock_remaining <= 0.0 then
            attack_lock_remaining = 0.0
            attack_lock_active = false
            start_attack_handoff()
        end
    end

    if attack_handoff_remaining > 0.0 then
        attack_handoff_remaining =
            attack_handoff_remaining - get_delta_time()

        if attack_handoff_remaining < 0.0 then
            attack_handoff_remaining = 0.0
        end
    end
end)

--==========================================================================
-- 8. APPLY
--==========================================================================

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

-- 평상시에는 집중모드가 켜져 있는 동안 항상 카메라 방향을 추적합니다.
-- Activity 판정을 거치지 않아 상태 전환에 의한 방향 공백이 없습니다.
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

    local max_step = math.pi * 0.5
    if delta_yaw > max_step then delta_yaw = max_step end
    if delta_yaw < -max_step then delta_yaw = -max_step end

    local yaw_delta_quat = quat_from_yaw(delta_yaw)
    local new_rotation =
        (yaw_delta_quat * current_rotation):normalized()

    ptr:call("set_Rotation", new_rotation)
    apply_count = apply_count + 1
end

-- 공격 중에는 smooth를 사용하지 않고 저장된 yaw를 즉시 맞춥니다.
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
    if not attack_lock_active then return end
    if attack_locked_yaw == nil then return end

    local ok, err = pcall(function()
        force_locked_yaw(attack_locked_yaw)
    end)

    if not ok then
        last_error = "attack force apply: " .. tostring(err)
    end
end

local function apply_attack_handoff_now()
    if not focus_active then return end
    if not cfg.apply_rotation then return end
    if attack_lock_active then return end
    if attack_handoff_remaining <= 0.0 then return end

    -- 공격 종료 직후에는 Activity 조건 없이 곧바로 카메라 방향으로 이어집니다.
    local target_yaw = get_camera_target_yaw()
    if target_yaw == nil then return end

    local ok, err = pcall(function()
        force_locked_yaw(target_yaw)
    end)

    if not ok then
        last_error = "attack handoff apply: " .. tostring(err)
    end
end

local function apply_normal_camera_now()
    if not focus_active then return end
    if not cfg.apply_rotation then return end
    if attack_lock_active then return end
    if attack_handoff_remaining > 0.0 then return end

    local target_yaw = get_camera_target_yaw()
    if target_yaw == nil then return end

    if last_apply_frame == frame_id then
        return
    end

    last_apply_frame = frame_id

    local ok, err = pcall(function()
        apply_yaw(target_yaw)
    end)

    if not ok then
        last_error = "normal apply: " .. tostring(err)
    end
end

-- 게임의 회전 적용 전
re.on_pre_application_entry("LockScene", function()
    if not focus_active then return end
    if not cfg.apply_rotation then return end

    if attack_lock_active then
        apply_attack_lock_now()
        return
    end

    if attack_handoff_remaining > 0.0 then
        apply_attack_handoff_now()
        return
    end

    apply_normal_camera_now()
end)

-- 게임이 원래 캐릭터 방향을 다시 써버린 직후
re.on_application_entry("LockScene", function()
    if attack_lock_active then
        apply_attack_lock_now()
    elseif attack_handoff_remaining > 0.0 then
        apply_attack_handoff_now()
    end
end)

-- 렌더 직전
re.on_pre_application_entry("PrepareRendering", function()
    if attack_lock_active then
        apply_attack_lock_now()
    elseif attack_handoff_remaining > 0.0 then
        apply_attack_handoff_now()
    end
end)

-- 렌더 직후
re.on_application_entry("PrepareRendering", function()
    if attack_lock_active then
        apply_attack_lock_now()
    elseif attack_handoff_remaining > 0.0 then
        apply_attack_handoff_now()
    end
end)

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

    imgui.separator()
    imgui.text("공격 시작 방향 고정")

    update_weapon_profile(get_player())

    imgui.text("BFM Type: " .. tostring(bfm_type_name))
    imgui.text(
        "현재 무기: " ..
        (WEAPON_LABELS[current_weapon_key] or current_weapon_key)
    )
    imgui.text(
        "자동 적용 Timing: " ..
        string.format("%.3f초", current_window_seconds)
    )
    imgui.text(
        "내부 고정 여유: " ..
        string.format(
            "%.3f초",
            math.max(0.0, cfg.attack_lock_extension_seconds or 0.0)
        )
    )

    changed, val = imgui.slider_float(
        "공격 종료 핸드오프(초)",
        cfg.attack_handoff_seconds,
        0.0,
        0.250,
        "%.3f"
    )
    if changed then
        cfg.attack_handoff_seconds = val
        save_cfg()
    end

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
            current_window_seconds = val
            save_cfg()
        end

        imgui.text("※ BFM Type으로 무기를 인식하지 못한 경우입니다.")
    else
        imgui.text("※ Timing은 BFM Type 자동 인식으로만 결정됩니다.")
    end

    imgui.separator()

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
        imgui.text("attack lock: " .. tostring(attack_lock_active))
        imgui.text(
            "attack remaining: " ..
            string.format("%.3f초", attack_lock_remaining)
        )
        imgui.text(
            "handoff remaining: " ..
            string.format("%.3f초", attack_handoff_remaining)
        )
        imgui.text("BFM Type: " .. tostring(bfm_type_name))
        imgui.text(
            "weapon: " ..
            tostring(
                WEAPON_LABELS[current_weapon_key] or
                current_weapon_key
            )
        )
        imgui.text(
            "weapon window: " ..
            string.format("%.3f초", current_window_seconds)
        )
        imgui.text(
            "apply_count: " ..
            tostring(apply_count)
        )

        if weapon_detect_error then
            imgui.text("weapon error: " .. weapon_detect_error)
        end
        if input_error then
            imgui.text("input error: " .. input_error)
        end
        if mouse_error then
            imgui.text("mouse error: " .. mouse_error)
        end
        if last_error then
            imgui.text("last error: " .. last_error)
        end
    end

    imgui.tree_pop()
end)

log.info(
    "[MHR_FocusMode v3.0] loaded. " ..
    "BFM-type-only weapon detection" ..
    ", key=" ..
    tostring(key_display_name()) ..
    ", lock_extension=" ..
    tostring(cfg.attack_lock_extension_seconds or 0.0) ..
    ", handoff=" ..
    tostring(cfg.attack_handoff_seconds or 0.0)
)
