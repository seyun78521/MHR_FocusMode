--[[
    ModFocusRise v2.1 - Focus Aim for Monster Hunter Rise (REFramework)

    v2.1: Better Focus Mode의 무기별 correction window 시간을 반영.

    기본 타이밍(원본 Better Focus Mode 설정값):
      GreatSword          0.24 s
      LongSword           0.18 s
      ChargeBlade         0.22 s
      SwordAndShield      0.16 s
      DualBlades          0.14 s
      Hammer              0.24 s
      HuntingHorn         0.22 s
      Lance               0.18 s
      Gunlance            0.20 s
      SwitchAxe           0.20 s
      InsectGlaive        0.18 s

    동작:
      1) LALT로 Focus Mode 활성화
      2) 이동만으로는 회전하지 않음
      3) 공격 입력 시작 시 현재 카메라 방향을 저장
      4) 현재 무기별 correction window 동안 저장 방향을 유지
      5) correction window가 끝나면 게임의 일반 회전에 맡김
      6) 공격 중 카메라가 계속 움직여도 저장 방향은 자동으로 바뀌지 않음

    주의:
      - Rise의 내부 무기 클래스명은 버전에 따라 다를 수 있어 자동 감지는
        _WeaponMain의 타입명을 기반으로 보수적으로 판별합니다.
      - 자동 감지가 안 되면 Generic(0.20초)로 동작하며 디버그 창에서
        현재 무기 타입명을 확인할 수 있습니다.
      - autorun 폴더에는 테스트 시 이 파일 하나만 넣는 것을 권장합니다.
--]]

--==========================================================================
-- 1. 설정
--==========================================================================

local CFG_PATH = "ModFocusRise.json"

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
    Generic        = "미감지/기타",
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

    auto_weapon_timing = true,
    generic_window_seconds = 0.20,

    -- 아래 값들은 원본 Better Focus Mode의 Timing 섹션을 그대로 반영.
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
}

local cfg = json.load_file(CFG_PATH) or {}
for k, v in pairs(DEFAULTS) do
    if cfg[k] == nil then cfg[k] = v end
end

local function refresh_weapon_timings()
    WEAPON_TIMINGS.GreatSword     = cfg.great_sword_window_seconds
    WEAPON_TIMINGS.LongSword      = cfg.long_sword_window_seconds
    WEAPON_TIMINGS.ChargeBlade    = cfg.charge_blade_window_seconds
    WEAPON_TIMINGS.SwordAndShield = cfg.sword_and_shield_window_seconds
    WEAPON_TIMINGS.DualBlades     = cfg.dual_blades_window_seconds
    WEAPON_TIMINGS.Hammer         = cfg.hammer_window_seconds
    WEAPON_TIMINGS.HuntingHorn    = cfg.hunting_horn_window_seconds
    WEAPON_TIMINGS.Lance          = cfg.lance_window_seconds
    WEAPON_TIMINGS.Gunlance       = cfg.gunlance_window_seconds
    WEAPON_TIMINGS.SwitchAxe      = cfg.switch_axe_window_seconds
    WEAPON_TIMINGS.InsectGlaive   = cfg.insect_glaive_window_seconds
end

refresh_weapon_timings()

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

local function get_player()
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

local function get_main_weapon(player)
    player = player or get_player()
    if not player then return nil end

    local ok, weapon = pcall(function()
        return player:get_field("_WeaponMain")
    end)

    if not ok then return nil end
    return weapon
end

local function get_weapon_type_name(weapon)
    if not weapon then return nil end

    local ok, name = pcall(function()
        local td = weapon:get_type_definition()
        if not td then return nil end
        return td:get_name()
    end)

    if not ok then return nil end
    return name
end

--==========================================================================
-- 6. 무기 자동 감지
--==========================================================================

local weapon_patterns = {
    { key = "GreatSword",     patterns = { "GreatSword" } },
    { key = "LongSword",      patterns = { "LongSword" } },
    { key = "ChargeBlade",    patterns = { "ChargeAxe", "ChargeBlade" } },
    { key = "SwordAndShield", patterns = { "ShortSword", "SwordAndShield" } },
    { key = "DualBlades",     patterns = { "DualBlades" } },
    { key = "Hammer",         patterns = { "Hammer" } },
    { key = "HuntingHorn",    patterns = { "Horn", "HuntingHorn" } },
    { key = "Lance",          patterns = { "Lance" } },
    { key = "Gunlance",       patterns = { "GunLance", "Gunlance" } },
    { key = "SwitchAxe",      patterns = { "SlashAxe", "SwitchAxe" } },
    { key = "InsectGlaive",   patterns = { "InsectGlaive" } },
}

local current_weapon_key = "Generic"
local current_weapon_type_name = "(unknown)"
local current_weapon_seconds = 0.20

local function detect_weapon_key()
    if not cfg.auto_weapon_timing then
        return "Generic"
    end

    local weapon = get_main_weapon()
    local type_name = get_weapon_type_name(weapon)
    current_weapon_type_name = type_name or "(unknown)"

    if not type_name then
        return "Generic"
    end

    for _, item in ipairs(weapon_patterns) do
        for _, pattern in ipairs(item.patterns) do
            if string.find(type_name, pattern, 1, true) then
                return item.key
            end
        end
    end

    return "Generic"
end

local function update_weapon_profile()
    current_weapon_key = detect_weapon_key()

    if current_weapon_key == "Generic" then
        current_weapon_seconds = cfg.generic_window_seconds
    else
        current_weapon_seconds = WEAPON_TIMINGS[current_weapon_key] or cfg.generic_window_seconds
    end
end

local function get_window_seconds()
    update_weapon_profile()
    return current_weapon_seconds
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
-- 8. v2.1 상태
--==========================================================================

local focus_active = false
local toggle_state = false
local binding_key  = false

local attack_correction_active = false
local attack_locked_yaw = nil
local attack_window_remaining = 0.0
local attack_triggered = false
local attack_window_started_for_weapon = "Generic"

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
    attack_window_started_for_weapon = "Generic"
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
            current_weapon_key = detect_weapon_key()
            current_weapon_type_name = current_weapon_type_name or "(unknown)"

            if current_weapon_key == "Generic" then
                current_weapon_seconds = cfg.generic_window_seconds
            else
                current_weapon_seconds = WEAPON_TIMINGS[current_weapon_key] or cfg.generic_window_seconds
            end

            attack_window_remaining = math.max(0.01, current_weapon_seconds)
            attack_window_started_for_weapon = current_weapon_key
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
            attack_locked_yaw = nil
        end
    end
end)

--==========================================================================
-- 10. APPLY - 공격 시작 방향 유지
--==========================================================================

local function apply_locked_yaw()
    if not attack_correction_active then return end
    if attack_locked_yaw == nil then return end
    if not cfg.apply_rotation then return end

    local player = get_player()
    if not player then return end

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
    if not attack_correction_active then return end
    if not cfg.apply_rotation then return end

    if last_apply_frame == frame_id then return end
    last_apply_frame = frame_id

    local ok, err = pcall(apply_locked_yaw)
    if not ok then
        last_error = "apply rotation: " .. tostring(err)
    end
end)

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
    imgui.text("Better Focus식 무기별 공격 보정")

    changed, val = imgui.checkbox("무기별 자동 타이밍", cfg.auto_weapon_timing)
    if changed then
        cfg.auto_weapon_timing = val
        reset_attack_correction()
        save_cfg()
    end

    if cfg.auto_weapon_timing then
        imgui.text("현재 무기: " .. (WEAPON_LABELS[current_weapon_key] or current_weapon_key))
        imgui.text("보정 시간: " .. string.format("%.2f초", current_weapon_seconds))
    else
        changed, val = imgui.slider_float(
            "기본 보정 시간(초)",
            cfg.generic_window_seconds,
            0.05,
            0.50,
            "%.2f"
        )
        if changed then cfg.generic_window_seconds = val; save_cfg() end
    end

    imgui.text("대검 0.24 / 태도 0.18 / 차지액스 0.22")
    imgui.text("한손검 0.16 / 쌍검 0.14 / 해머 0.24")
    imgui.text("피리 0.22 / 랜스 0.18 / 건랜스 0.20")
    imgui.text("슬액 0.20 / 조충곤 0.18")

    changed, val = imgui.slider_float("미감지 무기 기본(초)", cfg.generic_window_seconds, 0.05, 0.50, "%.2f")
    if changed then cfg.generic_window_seconds = val; save_cfg() end

    changed, val = imgui.checkbox("디버그 표시", cfg.debug)
    if changed then cfg.debug = val; save_cfg() end

    changed, val = imgui.checkbox("회전 적용", cfg.apply_rotation)
    if changed then cfg.apply_rotation = val; save_cfg() end

    if cfg.debug then
        update_weapon_profile()

        imgui.text("focus_active: " .. tostring(focus_active))
        imgui.text("keyboard: " .. tostring(get_keyboard() ~= nil))
        imgui.text("KeyboardKey: " .. key_display_name())
        imgui.text("key value: " .. tostring(get_bound_key_value()))
        imgui.text("key_down: " .. tostring(key_down()))

        imgui.text("mouse: " .. tostring(get_mouse() ~= nil))
        imgui.text("normal attack: " .. tostring(mouse_down("L")))
        imgui.text("special attack: " .. tostring(mouse_down("R")))
        imgui.text("attack_triggered: " .. tostring(attack_triggered))

        imgui.text("player: " .. tostring(get_player() ~= nil))
        imgui.text("camera: " .. tostring(get_camera_transform() ~= nil))

        imgui.text("weapon: " .. tostring(WEAPON_LABELS[current_weapon_key] or current_weapon_key))
        imgui.text("weapon type: " .. tostring(current_weapon_type_name))
        imgui.text("window: " .. string.format("%.3f", current_weapon_seconds) .. " sec")
        imgui.text("window remaining: " .. string.format("%.3f", attack_window_remaining) .. " sec")
        imgui.text("correction active: " .. tostring(attack_correction_active))
        imgui.text("attack locked yaw: " .. tostring(attack_locked_yaw))
        imgui.text("apply_rotation: " .. tostring(cfg.apply_rotation))
        imgui.text("apply_count: " .. tostring(apply_count))

        if input_error then imgui.text("input error: " .. input_error) end
        if mouse_error then imgui.text("mouse error: " .. mouse_error) end
        if last_error then imgui.text("last error: " .. last_error) end
    end

    imgui.tree_pop()
end)

log.info(
    "[ModFocusRise v2.1] loaded. key=" .. tostring(key_display_name()) ..
    ", auto_weapon_timing=" .. tostring(cfg.auto_weapon_timing)
)
