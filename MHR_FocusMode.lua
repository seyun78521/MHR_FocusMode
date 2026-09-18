--[[
    ModFocusRise v2.2 - Focus Aim for Monster Hunter Rise (REFramework)

    v2.2: 무기 자동 판별 추측을 제거하고, 수동 무기 프로필 + Rise 내부 무기/회전 필드 진단을 추가.

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
      - v2.2에서는 Rise 내부 무기 클래스명을 추측해 자동 매핑하지 않습니다.
      - 수동 무기 프로필을 선택하면 Better Focus의 해당 correction window를 확실히 사용합니다.
      - 디버그를 켜면 _WeaponMain의 실제 타입/후보 필드/메서드를 로그로 덤프합니다.
        이 정보로 다음 버전에서 Rise의 진짜 무기 자동 감지를 고정할 수 있습니다.
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

    auto_weapon_timing = false,
    manual_weapon = "GreatSword",
    generic_window_seconds = 0.20,
    post_window_hold_seconds = 0.00, -- 0 = 사용 안 함; 공격 후 원래 방향 복귀를 확인하기 위한 실험값

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
-- 6. 무기 프로필 / Rise 내부 진단
--==========================================================================

-- v2.2에서는 자동 타입명 매칭을 기본으로 사용하지 않습니다.
-- _WeaponMain의 존재는 Rise용 공개 유틸에서도 확인되지만, 객체 type name이
-- 실제 무기 종류명을 그대로 담는다는 보장이 없어 수동 프로필을 우선합니다.

local current_weapon_key = "GreatSword"
local current_weapon_type_name = "(manual profile)"
local current_weapon_seconds = 0.24

local weapon_profile_names = {
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
    Generic        = "기타",
}

local function selected_window_seconds()
    if cfg.auto_weapon_timing then
        -- v2.2에서는 자동 감지하지 않으므로 Generic을 안전값으로 사용.
        return cfg.generic_window_seconds
    end
    return WEAPON_TIMINGS[cfg.manual_weapon] or cfg.generic_window_seconds
end

local function update_weapon_profile()
    if cfg.auto_weapon_timing then
        current_weapon_key = "Generic"
        current_weapon_seconds = cfg.generic_window_seconds
        current_weapon_type_name = "(auto disabled in v2.2)"
    else
        current_weapon_key = cfg.manual_weapon or "GreatSword"
        current_weapon_seconds = WEAPON_TIMINGS[current_weapon_key] or cfg.generic_window_seconds
        current_weapon_type_name = "(manual: " .. current_weapon_key .. ")"
    end
end

update_weapon_profile()

local diagnostics_dumped = false
local function safe_type_name(obj)
    if not obj then return "(nil)" end
    local ok, name = pcall(function()
        local td = obj:get_type_definition()
        return td and td:get_name() or "(no type)"
    end)
    return ok and name or "(type error: " .. tostring(name) .. ")"
end

local function dump_candidates(label, td, patterns)
    if not td then return end
    for _, field in ipairs(td:get_fields()) do
        local n = field:get_name()
        local low = string.lower(n)
        for _, p in ipairs(patterns) do
            if string.find(low, p, 1, true) then
                log.info("[ModFocusRise v2.2] " .. label .. " FIELD " .. n)
                break
            end
        end
    end
    for _, method in ipairs(td:get_methods()) do
        local n = method:get_name()
        local low = string.lower(n)
        for _, p in ipairs(patterns) do
            if string.find(low, p, 1, true) then
                log.info("[ModFocusRise v2.2] " .. label .. " METHOD " .. n)
                break
            end
        end
    end
end

local function dump_runtime_diagnostics()
    if diagnostics_dumped then return end
    local player = get_player()
    local weapon = get_main_weapon(player)

    log.info("[ModFocusRise v2.2] ===== RUNTIME DIAGNOSTIC BEGIN =====")
    log.info("[ModFocusRise v2.2] player type=" .. safe_type_name(player))
    log.info("[ModFocusRise v2.2] _WeaponMain=" .. tostring(weapon))
    log.info("[ModFocusRise v2.2] _WeaponMain type=" .. safe_type_name(weapon))

    if player then
        local ptd = player:get_type_definition()
        dump_candidates("PlayerBase", ptd, {
            "angle", "direction", "rotation", "weapon", "action", "motion", "fsm"
        })
    end

    if weapon then
        local wtd = weapon:get_type_definition()
        dump_candidates("WeaponMain", wtd, {
            "weapon", "type", "id", "action", "motion"
        })
    end

    log.info("[ModFocusRise v2.2] ===== RUNTIME DIAGNOSTIC END =====")
    diagnostics_dumped = true
end

--=========================================================================
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
local post_window_hold_remaining = 0.0

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
    post_window_hold_remaining = 0.0
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

    if cfg.debug then
        pcall(dump_runtime_diagnostics)
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
            update_weapon_profile()
            current_weapon_type_name = safe_type_name(get_main_weapon(player))

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

    local weapon_items = {
        "GreatSword", "LongSword", "ChargeBlade", "SwordAndShield", "DualBlades",
        "Hammer", "HuntingHorn", "Lance", "Gunlance", "SwitchAxe", "InsectGlaive"
    }
    local weapon_labels = {
        "대검", "태도", "차지액스", "한손검", "쌍검", "해머", "수렵피리",
        "랜스", "건랜스", "슬래시액스", "조충곤"
    }

    local manual_index = 1
    for i, name in ipairs(weapon_items) do
        if name == cfg.manual_weapon then manual_index = i break end
    end

    changed, val = imgui.combo("무기 프로필", manual_index, weapon_labels)
    if changed then
        cfg.manual_weapon = weapon_items[val]
        update_weapon_profile()
        reset_attack_correction()
        save_cfg()
    end

    imgui.text("선택된 보정 시간: " .. string.format("%.2f초", current_weapon_seconds))
    imgui.text("자동 무기 감지는 현재 비활성화(v2.2)")

    changed, val = imgui.slider_float(
        "공격 후 방향 유지(실험, 초)",
        cfg.post_window_hold_seconds,
        0.0,
        1.0,
        "%.2f"
    )
    if changed then
        cfg.post_window_hold_seconds = val
        save_cfg()
    end
    imgui.text("0.00 = correction window 종료와 함께 게임 회전에 반환")

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

        imgui.text("weapon profile: " .. tostring(weapon_profile_names[current_weapon_key] or current_weapon_key))
        imgui.text("_WeaponMain type: " .. tostring(current_weapon_type_name))
        imgui.text("window: " .. string.format("%.3f", current_weapon_seconds) .. " sec")
        imgui.text("window remaining: " .. string.format("%.3f", attack_window_remaining) .. " sec")
        imgui.text("post hold remaining: " .. string.format("%.3f", post_window_hold_remaining) .. " sec")
        imgui.text("correction active: " .. tostring(attack_correction_active))
        imgui.text("attack locked yaw: " .. tostring(attack_locked_yaw))
        imgui.text("diagnostics dumped: " .. tostring(diagnostics_dumped))
        imgui.text("apply_rotation: " .. tostring(cfg.apply_rotation))
        imgui.text("apply_count: " .. tostring(apply_count))

        if input_error then imgui.text("input error: " .. input_error) end
        if mouse_error then imgui.text("mouse error: " .. mouse_error) end
        if last_error then imgui.text("last error: " .. last_error) end
    end

    imgui.tree_pop()
end)

log.info(
    "[ModFocusRise v2.2] loaded. key=" .. tostring(key_display_name()) ..
    ", auto_weapon_timing=" .. tostring(cfg.auto_weapon_timing)
)
