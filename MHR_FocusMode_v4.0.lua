--[[
    MHR_FocusMode v4.0 - Focus Aim for Monster Hunter Rise (REFramework)

    v4.0 변경점 (v3.8 대비):
      - 입력 장치를 "키보드+마우스(KBM)" 또는 "컨트롤러"로 선택할 수 있습니다.
        컨트롤러를 선택하면 집중모드 버튼 / 공격1 버튼 / 공격2 버튼을
        원하는 컨트롤러 버튼으로 직접 바인딩할 수 있습니다.
        (키보드 키 바인딩과 동일하게, 버튼 변경 -> 원하는 버튼을 누르면 저장됩니다.
         ESC 키로 바인딩을 취소할 수 있습니다.)
      - 컨트롤러의 공격1/공격2 버튼은 기존 좌클릭/우클릭과 동일하게 취급되어,
        탭/홀드 판정, 무기별 방향 고정, handoff 등 기존 로직이 그대로 적용됩니다.
      - 카메라 방향 자체(오른쪽 스틱으로 움직인 결과)는 게임 카메라를 그대로 읽어오므로
        입력 장치와 무관하게 항상 동일하게 동작합니다.
      - 주의: 컨트롤러 버튼 상태 조회는 REFramework의 via.hid.GamePad
        (get_LastInputDevice -> isDown) API를 사용합니다. 이 API는 공식 문서화가
        되어 있지 않아 게임/REFramework 버전에 따라 동작하지 않을 수 있습니다.
        문제가 있으면 디버그 표시를 켜고 "pad error" 항목의 문구를 알려주세요.

    v3.3 변경점 (v3.2 대비):
      - 좌/우클릭 홀드 공격은 일정 시간 이상 누른 상태로 판정되면,
        버튼을 뗀 즉시 방향 고정을 해제합니다. 버튼을 뗀 뒤에
        무기별 지정 고정시간을 추가로 기다리지 않습니다.
      - 짧게 클릭(탭)하는 경우에는 기존처럼 무기별 지정 시간만큼 고정 후
        handoff -> 평상시 추적으로 넘어갑니다.
      - 집중모드 HUD를 글씨/사각형 대신 화면 중앙의 작은 조준경(reticle)으로 변경했습니다.
        집중모드가 켜져 있을 때만 표시되며, 참고 이미지처럼 좌우에 간격이 있는 원형
        링 + 중앙 점 형태로 그립니다.

    v3.1 변경점 (v3.0 대비):
      - v1.8의 Activity Gate(정지 판정)를 되살렸습니다.
        -> "가만히 서 있을 때"는 집중모드가 켜져 있어도 평상시 카메라 추적을
           적용하지 않습니다. (ModFocusRise v1.8의 activity_active 판정 재사용)
      - Activity Gate는 "평상시 추적"에만 적용됩니다.
        공격 고정(attack lock)과 공격 종료 직후 handoff는 정지 여부와
        무관하게 항상 그대로 동작합니다. (BFM Type 기반 타이밍 그대로 사용)
      - 즉, 최종 동작:
          1) 정지 상태(이동/회전 없음): 집중모드가 켜져 있어도 방향을 돌리지 않음.
          2) 이동/회전 중: 평상시처럼 카메라 방향을 계속 따라감.
          3) 좌클릭 또는 우클릭(공격) 시: 클릭한 순간의 카메라 방향으로
             즉시 고정하고, 그 방향을 BFM Type으로 판별한 무기별 지정 시간
             동안 강제로 유지함 (정지/이동 여부와 무관).

    v3.0 핵심 (유지됨):
      - 공격 입력(L/R 클릭) 순간의 카메라 방향을 저장하고,
        현재 플레이어의 BFM Type 하나만으로 무기를 자동 판별합니다.
      - 무기 판별에 다른 무기 객체 탐색이나 부모 타입 탐색,
        수동 무기 선택을 사용하지 않습니다.
      - BFM Type을 매칭하지 못했을 때만 Generic Timing을 사용합니다.
      - 공격 고정 중에는 smooth 보정을 사용하지 않고 정확한 yaw를 강제합니다.
      - LockScene 전/후 + PrepareRendering 전/후에서 재적용합니다.
      - 공격 종료 직후에는 현재 카메라 방향을 이어받는 handoff 구간을 유지합니다.
      - v2.5의 BFM 상태 setter/getter 탐색은 제거했습니다.
        v3.1에서 필요한 BFM 정보는 무기 판별용 Type 하나뿐입니다.

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

    -- 입력 장치: 1 = 키보드+마우스(KBM), 2 = 컨트롤러
    input_device   = 1,

    -- 컨트롤러 바인딩 (input_device == 2일 때 사용).
    -- 값은 via.hid.GamePadButton의 필드 이름 문자열입니다.
    -- 빈 문자열("")이면 아직 바인딩되지 않은 상태입니다.
    pad_key_name   = "",  -- 집중모드 버튼 (KBM의 focus key에 대응)
    pad_atk1_name  = "",  -- 공격1 버튼 (좌클릭에 대응)
    pad_atk2_name  = "",  -- 공격2 버튼 (우클릭에 대응)

    smooth         = 0.35,
    yaw_offset     = 0.0,

    debug          = false,  -- 기본: 체크 해제
    show_reticle   = true,   -- 집중모드 조준경 표시
    apply_rotation = true,

    -- 무기 Timing은 항상 자동 인식.
    -- 무기가 인식되지 않을 때만 아래 Generic 값을 사용합니다.
    generic_window_seconds = 0.196,

    -- 공격 모션 중 원래 방향으로 되돌아가는 프레임을 줄이기 위한 소폭의 여유 시간.
    -- UI에는 노출하지 않고 내부에서만 적용합니다.
    attack_lock_extension_seconds = 0.040,

    -- 공격 고정 -> 평상시 추적 사이를 일부러 겹치게 만들어 1프레임 공백 방지.
    attack_handoff_seconds = 0.100,

    -- 이 시간 이상 좌/우클릭을 누르고 있으면 "홀드 공격"으로 판정합니다.
    -- 홀드 공격은 버튼을 놓는 즉시 방향 고정을 해제하며,
    -- 이 값 자체는 무기별 Timing과 무관한 공통 판정 기준입니다.
    attack_hold_threshold_seconds = 0.080,

    -- v1.8에서 가져온 Activity Gate.
    -- "평상시 추적"에만 적용됩니다 (공격 고정/handoff에는 영향 없음).
    -- true면 캐릭터가 정지해 있을 때는 카메라 방향을 따라가지 않습니다.
    activity_gate           = true,
    activity_pos_threshold  = 0.01,   -- 프레임당 위치 변화량(미터)
    activity_yaw_threshold  = 0.015,  -- 프레임당 회전 변화량(rad)
    activity_hold_frames    = 12,     -- 활동 감지 후 추적을 유지할 프레임 수
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

-- 바인딩 캡처를 취소하는 공용 키(ESC). 컨트롤러 버튼 바인딩 중에도
-- 키보드 ESC로 취소할 수 있도록 공유합니다.
local function escape_pressed()
    local d = get_keyboard()
    if not d then return false end

    local esc = get_key_value("Escape")
    if esc == nil then return false end

    local ok, down = pcall(function()
        return d:call("isDown", esc) == true
    end)

    return ok and down == true
end

--==========================================================================
-- 3b. 게임패드(컨트롤러) 입력
--==========================================================================

local pad_singleton, pad_tdef, pad_button_tdef
local pad_prev_atk1 = false
local pad_prev_atk2 = false
local pad_error = nil

local function get_gamepad()
    if not pad_singleton then
        pad_singleton   = sdk.get_native_singleton("via.hid.GamePad")
        pad_tdef        = sdk.find_type_definition("via.hid.GamePad")
        pad_button_tdef = sdk.find_type_definition("via.hid.GamePadButton")
    end

    if not pad_singleton or not pad_tdef then
        return nil
    end

    local ok, device = pcall(function()
        return sdk.call_native_func(pad_singleton, pad_tdef, "get_LastInputDevice")
    end)

    if not ok then
        pad_error = "get_LastInputDevice: " .. tostring(device)
        return nil
    end

    return device
end

local function get_pad_button_value(name)
    if not pad_button_tdef or not name or name == "" then return nil end

    local field = pad_button_tdef:get_field(name)
    if not field then
        pad_error = "GamePadButton not found: " .. tostring(name)
        return nil
    end

    local ok, value = pcall(function()
        return field:get_data(nil)
    end)

    if not ok then
        pad_error = "GamePadButton get_data: " .. tostring(value)
        return nil
    end

    return value
end

local function pad_down(name)
    local d = get_gamepad()
    if not d then return false end

    local button = get_pad_button_value(name)
    if button == nil then return false end

    local ok, result = pcall(function()
        return d:call("isDown", button) == true
    end)

    if not ok then
        pad_error = "pad isDown: " .. tostring(result)
        return false
    end

    return result
end

-- 컨트롤러 버튼 하나를 바인딩합니다.
-- ESC(키보드)를 누르면 저장하지 않고 취소만 합니다.
-- 반환값: true면 캡처 종료(저장 또는 취소), false면 계속 대기.
local function capture_pad_button(cfg_field)
    if escape_pressed() then
        return true
    end

    local d = get_gamepad()
    if not d or not pad_button_tdef then return false end

    for _, field in ipairs(pad_button_tdef:get_fields()) do
        if field:is_static() then
            local name = field:get_name()

            local ok_value, value = pcall(function()
                return field:get_data(nil)
            end)

            -- 0이거나 None/Any/All 같은 집합 성격의 필드는 건너뜁니다.
            if ok_value and value ~= nil and value ~= 0 then
                local lname = string.lower(name)
                if lname ~= "none" and lname ~= "any" and lname ~= "all" then
                    local ok_down, down = pcall(function()
                        return d:call("isDown", value) == true
                    end)

                    if ok_down and down then
                        cfg[cfg_field] = name
                        save_cfg()
                        return true
                    end
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
local attack_held = false  -- 공격1/공격2 입력(좌우클릭 또는 컨트롤러 버튼)을 "누르고 있는(홀드)" 상태
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
    attack_held  = l or r

    return trg_l or trg_r
end

-- 컨트롤러의 공격1/공격2 버튼을 좌/우클릭과 동일한 방식으로 추적합니다.
local function update_pad_attack_input()
    local a1 = pad_down(cfg.pad_atk1_name)
    local a2 = pad_down(cfg.pad_atk2_name)

    local trg1 = a1 and not pad_prev_atk1
    local trg2 = a2 and not pad_prev_atk2

    pad_prev_atk1 = a1
    pad_prev_atk2 = a2
    attack_held   = a1 or a2

    return trg1 or trg2
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

-- 바인딩 캡처 대상: nil(없음) / "kbm" / "pad_focus" / "pad_atk1" / "pad_atk2"
local binding_target = nil

-- 집중모드 버튼의 "방금 눌림" 판정에 쓰이는, 입력 장치와 무관한 공용 상태.
local focus_prev_down = false

local attack_lock_active = false
local attack_locked_yaw = nil
local attack_lock_remaining = 0.0

-- 홀드/탭 구분용. threshold를 넘으면 홀드 공격으로 판정.
local attack_hold_elapsed = 0.0
local attack_is_hold = false

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
    attack_hold_elapsed = 0.0
    attack_is_hold = false
    attack_handoff_remaining = 0.0
end

local function start_attack_handoff()
    attack_handoff_remaining = math.max(
        attack_handoff_remaining,
        math.max(0.0, cfg.attack_handoff_seconds or 0.0)
    )
end

-- 무기별 지정 시간 + 내부 고정 여유를 더한 "최소 유지 시간".
-- 좌/우클릭을 누르고 있는 동안에는 attack_lock_remaining이
-- 이 값 밑으로 떨어지지 않도록 붙잡아 두는 데 사용합니다.
local function current_lock_floor()
    return math.max(
        0.01,
        current_window_seconds +
        math.max(0.0, cfg.attack_lock_extension_seconds or 0.0)
    )
end

--==========================================================================
-- 6b. Activity Gate (v1.8 재사용) - "평상시 추적"에만 적용
--==========================================================================

-- ModFocusRise v1.8의 정지 판정을 그대로 가져옵니다.
-- 공격 고정(attack lock)/handoff에는 영향을 주지 않고,
-- "평상시 카메라 추적"에만 게이트로 사용합니다.
local activity_active = false
local activity_frames_left = 0
local activity_initialized = false
local activity_last_pos = nil
local activity_last_yaw = nil

local function copy_vec3(v)
    return { x = v.x, y = v.y, z = v.z }
end

local function reset_activity()
    activity_active = false
    activity_frames_left = 0
    activity_initialized = false
    activity_last_pos = nil
    activity_last_yaw = nil
end

local function update_activity()
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
            activity_active = false
            return false
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

        activity_active = activity_frames_left > 0
        return activity_active
    end)

    if not ok then
        last_error = "activity: " .. tostring(result)
        activity_active = false
        return false
    end

    return result
end

--==========================================================================
-- 6c. 입력 장치 통합 (집중모드 버튼)
--==========================================================================

-- cfg.input_device에 따라 KBM 키 또는 컨트롤러 버튼 중 하나로 분기합니다.
local function focus_button_down()
    if cfg.input_device == 2 then
        return pad_down(cfg.pad_key_name)
    end
    return key_down()
end

local function focus_button_trg()
    local now = focus_button_down()
    local trg = now and not focus_prev_down
    focus_prev_down = now
    return trg
end

--==========================================================================
-- 7. 입력 / 상태 업데이트
--==========================================================================

re.on_frame(function()
    frame_id = frame_id + 1

    if binding_target then
        local done = false

        if binding_target == "kbm" then
            done = capture_key()
        elseif binding_target == "pad_focus" then
            done = capture_pad_button("pad_key_name")
            if done then focus_prev_down = false end
        elseif binding_target == "pad_atk1" then
            done = capture_pad_button("pad_atk1_name")
            if done then pad_prev_atk1 = false end
        elseif binding_target == "pad_atk2" then
            done = capture_pad_button("pad_atk2_name")
            if done then pad_prev_atk2 = false end
        else
            -- 알 수 없는 값이면 안전하게 바인딩을 종료합니다.
            done = true
        end

        if done then
            binding_target = nil
        end

        focus_active = false
        reset_attack_lock()
        reset_activity()
        return
    end

    if not cfg.enabled then
        focus_active = false
        toggle_state = false
        key_prev_down = false
        mouse_prev_l = false
        mouse_prev_r = false
        focus_prev_down = false
        pad_prev_atk1 = false
        pad_prev_atk2 = false
        reset_attack_lock()
        reset_activity()
        return
    end

    if cfg.mode == 2 then
        if focus_button_trg() then
            toggle_state = not toggle_state
        end
        focus_active = toggle_state
    else
        focus_active = focus_button_down()
    end

    local attack_trg = false
    attack_held = false
    if cfg.input_device == 2 then
        attack_trg = update_pad_attack_input()
    elseif get_mouse() ~= nil then
        attack_trg = update_attack_input()
    end

    if not focus_active then
        reset_attack_lock()
        reset_activity()
        return
    end

    -- 정지/이동 판정은 공격 여부와 무관하게 매 프레임 갱신합니다.
    -- (공격 고정/handoff 적용 여부에는 영향을 주지 않고,
    --  "평상시 추적" 적용 여부에만 사용됩니다.)
    update_activity()

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

            attack_lock_remaining = current_lock_floor()
            attack_hold_elapsed = 0.0
            attack_is_hold = false

            attack_lock_active = true
            attack_handoff_remaining = 0.0

            return true
        end)

        if not ok then
            last_error = "attack trigger: " .. tostring(err)
        end
    end

    if attack_lock_active then
        local dt = get_delta_time()

        if attack_held then
            -- 홀드 여부는 무기 Timing이 아니라 실제 누르고 있는 시간으로 판정합니다.
            attack_hold_elapsed = attack_hold_elapsed + dt
            if attack_hold_elapsed >=
                math.max(0.0, cfg.attack_hold_threshold_seconds or 0.080) then
                attack_is_hold = true
            end

            -- 누르고 있는 동안에는 공격 방향 고정을 계속 유지합니다.
            -- 탭용 남은 Timing은 소비하지 않습니다.
            local floor = current_lock_floor()
            if attack_lock_remaining < floor then
                attack_lock_remaining = floor
            end
        else
            if attack_is_hold then
                -- 홀드 공격은 버튼을 뗀 즉시 고정 해제.
                -- 무기별 지정 Timing을 release 이후에 다시 기다리지 않습니다.
                attack_lock_remaining = 0.0
                attack_lock_active = false
                attack_handoff_remaining = 0.0
                attack_hold_elapsed = 0.0
                attack_is_hold = false
            else
                -- 짧은 탭은 기존 동작 유지:
                -- release 후 남은 무기별 고정시간을 소진하고 handoff.
                attack_lock_remaining =
                    attack_lock_remaining - dt

                if attack_lock_remaining <= 0.0 then
                    attack_lock_remaining = 0.0
                    attack_lock_active = false
                    start_attack_handoff()
                end
            end
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

    -- 정지 상태에서는 "평상시 추적"을 적용하지 않습니다.
    -- (공격 고정/handoff는 이 게이트의 영향을 받지 않습니다.)
    if cfg.activity_gate and not activity_active then return end

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

-- 9. HUD
--==========================================================================
-- 집중모드가 켜져 있을 때만 화면 중앙보다 살짝 아래에 작은 조준경을 표시합니다.
-- 참고 이미지 기준 약 80% 크기로 줄이고, 링은 얇은 윤곽선 2줄이 아니라
-- 실제로 흰색이 채워진 "띠"처럼 보이도록 여러 겹의 원호를 겹쳐 그립니다.
local FOCUS_RETICLE_Y_RATIO = 0.45
local FOCUS_RETICLE_BASE_RADIUS = 9.4667
local FOCUS_RETICLE_GAP_DEG = 11.0
local FOCUS_RETICLE_SEGMENTS = 20
local FOCUS_RETICLE_THICKNESS = 0.8667

local function draw_reticle_arc_band(cx, cy, outer_radius, thickness, start_deg, end_deg, color, scale)
    local start_rad = math.rad(start_deg)
    local end_rad = math.rad(end_deg)
    local segments = math.max(6, FOCUS_RETICLE_SEGMENTS)
    local step = (end_rad - start_rad) / segments

    -- 선 하나만 그리지 않고 반지름 방향으로 여러 줄을 촘촘하게 겹쳐
    -- 링 내부까지 흰색으로 채워진 것처럼 보이게 합니다.
    local layers = math.max(2, math.floor(thickness * 1.8 * scale + 0.5))
    local inner_radius = math.max(0.5, outer_radius - thickness)

    for layer = 0, layers do
        local t = layer / layers
        local radius = outer_radius - (outer_radius - inner_radius) * t

        local prev_x = cx + math.cos(start_rad) * radius
        local prev_y = cy + math.sin(start_rad) * radius

        for i = 1, segments do
            local angle = start_rad + step * i
            local x = cx + math.cos(angle) * radius
            local y = cy + math.sin(angle) * radius

            draw.line(prev_x, prev_y, x, y, color)

            prev_x = x
            prev_y = y
        end
    end
end

local function draw_focus_hud()
    if not focus_active or not cfg.show_reticle then
        return
    end

    local display = imgui.get_display_size()
    if not display then
        return
    end

    local scale = display.y / 450.0
    if scale < 0.75 then scale = 0.75 end
    if scale > 2.50 then scale = 2.50 end

    local cx = display.x * 0.5
    local cy = display.y * FOCUS_RETICLE_Y_RATIO
    local radius = FOCUS_RETICLE_BASE_RADIUS * scale
    local thickness = math.max(1.8, FOCUS_RETICLE_THICKNESS * scale)
    local gap = FOCUS_RETICLE_GAP_DEG

    -- 흰색
    local color = 0xFFFFFFFF

    -- 좌우가 살짝 끊긴 원형 조준경.
    draw_reticle_arc_band(
        cx, cy, radius, thickness,
        gap, 180.0 - gap,
        color, scale
    )
    draw_reticle_arc_band(
        cx, cy, radius, thickness,
        180.0 + gap, 360.0 - gap,
        color, scale
    )

    -- 중앙 조준점도 기존보다 약간 작고 또렷하게.
    draw.filled_circle(
        cx,
        cy,
        math.max(2.0, 2.4 * scale),
        color,
        16
    )
end

-- 조준경 HUD는 REFramework 창의 표시 여부와 무관하게
-- 게임 화면에 계속 그려져야 하므로 on_frame에서 렌더합니다.
re.on_frame(function()
    draw_focus_hud()
end)

-- 10. UI
--==========================================================================

re.on_draw_ui(function()
    if not imgui.tree_node("MHR_FocusMode") then return end

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

    imgui.separator()

    changed, val = imgui.combo(
        "입력 장치",
        cfg.input_device,
        { "키보드+마우스(KBM)", "컨트롤러" }
    )
    if changed then
        cfg.input_device = val
        binding_target = nil
        focus_prev_down = false
        pad_prev_atk1 = false
        pad_prev_atk2 = false
        reset_attack_lock()
        save_cfg()
    end

    if cfg.input_device == 2 then
        imgui.text(
            "포커스 버튼: " ..
            (cfg.pad_key_name ~= "" and cfg.pad_key_name or "미설정")
        )
        imgui.same_line()
        if binding_target == "pad_focus" then
            imgui.text("  << 컨트롤러 버튼을 누르세요 (ESC 취소)")
        elseif imgui.button("버튼 변경##pad_focus") then
            binding_target = "pad_focus"
        end

        imgui.text(
            "공격1 버튼(좌클릭 대응): " ..
            (cfg.pad_atk1_name ~= "" and cfg.pad_atk1_name or "미설정")
        )
        imgui.same_line()
        if binding_target == "pad_atk1" then
            imgui.text("  << 컨트롤러 버튼을 누르세요 (ESC 취소)")
        elseif imgui.button("버튼 변경##pad_atk1") then
            binding_target = "pad_atk1"
        end

        imgui.text(
            "공격2 버튼(우클릭 대응): " ..
            (cfg.pad_atk2_name ~= "" and cfg.pad_atk2_name or "미설정")
        )
        imgui.same_line()
        if binding_target == "pad_atk2" then
            imgui.text("  << 컨트롤러 버튼을 누르세요 (ESC 취소)")
        elseif imgui.button("버튼 변경##pad_atk2") then
            binding_target = "pad_atk2"
        end
    else
        imgui.text("현재 키: " .. key_display_name())
        imgui.same_line()

        if binding_target == "kbm" then
            imgui.text("  << 아무 키나 누르세요 (ESC 취소)")
        elseif imgui.button("키 변경") then
            binding_target = "kbm"
        end
    end

    imgui.separator()

    changed, val = imgui.checkbox(
        "집중모드 조준경 표시",
        cfg.show_reticle
    )
    if changed then
        cfg.show_reticle = val
        save_cfg()
    end

    -- 공격 방향 고정 관련 세부 설정은 일반 UI에서 숨깁니다.
    -- 무기별 자동 Timing 및 공격 고정 로직은 내부에서 그대로 동작합니다.

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

        imgui.text(
            "input_device: " ..
            (cfg.input_device == 2 and "컨트롤러" or "KBM")
        )
        imgui.text("focus_active: " .. tostring(focus_active))
        imgui.text(
            "activity_active: " ..
            tostring(activity_active) ..
            " (gate=" .. tostring(cfg.activity_gate) .. ")"
        )
        imgui.text(
            "activity_frames_left: " ..
            tostring(activity_frames_left)
        )
        imgui.text("attack lock: " .. tostring(attack_lock_active))
        imgui.text("attack_held(홀드 중): " .. tostring(attack_held))
        imgui.text("attack_is_hold: " .. tostring(attack_is_hold))
        imgui.text(
            "attack hold elapsed: " ..
            string.format("%.3f초", attack_hold_elapsed)
        )
        imgui.text(
            "hold threshold: " ..
            string.format(
                "%.3f초",
                math.max(0.0, cfg.attack_hold_threshold_seconds or 0.080)
            )
        )
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
        if pad_error then
            imgui.text("pad error: " .. pad_error)
        end
        if last_error then
            imgui.text("last error: " .. last_error)
        end
    end

    imgui.tree_pop()
end)

log.info(
    "[MHR_FocusMode v4.0] loaded. " ..
    "BFM-type-only weapon detection, instant hold-release + persistent HUD reticle + controller input" ..
    ", activity_gate=" ..
    tostring(cfg.activity_gate) ..
    ", input_device=" ..
    (cfg.input_device == 2 and "controller" or "kbm") ..
    ", key=" ..
    tostring(key_display_name()) ..
    ", lock_extension=" ..
    tostring(cfg.attack_lock_extension_seconds or 0.0) ..
    ", handoff=" ..
    tostring(cfg.attack_handoff_seconds or 0.0)
)
