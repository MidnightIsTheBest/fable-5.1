--[[
    ╔═══════════════════════════════════════════════════════════════╗
    ║  Noir UI  v1.0  —  Linoria-style Roblox UI library, rebuilt    ║
    ║                                                               ║
    ║  • Windows, tabs, two-column groupboxes, tabboxes             ║
    ║  • Toggle / Slider / Dropdown (multi) / Button / Input        ║
    ║    Label / Divider / KeyPicker / ColorPicker (HSV + hex)      ║
    ║  • Addons: Toggle:AddColorPicker(), Toggle:AddKeyPicker()     ║
    ║  • Flags table, OnChanged callbacks, live theme recolouring   ║
    ║  • Notifications, watermark, menu toggle key, Unload()        ║
    ║  • Config save/load (JSON, uses writefile/readfile if present)║
    ║  • Built-in Settings tab:  Library:BuildSettingsTab(Window)   ║
    ║                                                               ║
    ║  Usage:  local Library = loadstring(game:HttpGet(url))()      ║
    ║     or:  local Library = require(script.NoirUI)               ║
    ╚═══════════════════════════════════════════════════════════════╝
]]

local Players      = game:GetService("Players")
local UIS          = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService   = game:GetService("RunService")
local HttpService  = game:GetService("HttpService")
local CoreGui      = game:GetService("CoreGui")

local LocalPlayer  = Players.LocalPlayer

-- ─────────────────────────────────────────────────────────────────
--  Library root
-- ─────────────────────────────────────────────────────────────────
local Library = {
    Flags    = {},   -- idx -> current value (quick reads)
    Toggles  = {},   -- idx -> Toggle object
    Options  = {},   -- idx -> Slider/Dropdown/Input/KeyPicker/ColorPicker object
    Windows  = {},
    Unloaded = false,

    Font      = Enum.Font.Code,
    TextSize  = 13,
    ToggleKey = Enum.KeyCode.RightShift,

    ConfigFolder = "NoirUI",

    Theme = {
        Background = Color3.fromRGB(12, 12, 14),
        Main       = Color3.fromRGB(20, 20, 23),
        Element    = Color3.fromRGB(28, 28, 32),
        Outline    = Color3.fromRGB(44, 44, 50),
        Accent     = Color3.fromRGB(0, 220, 170),
        Text       = Color3.fromRGB(235, 235, 240),
        DimText    = Color3.fromRGB(140, 140, 150),
        Risky      = Color3.fromRGB(255, 85, 85),
    },

    _themed = {},    -- { {obj, prop, key}, ... }
    _conns  = {},
    _keybinds = {},  -- KeyPicker objects, polled on input
}
Library.__index = Library

-- ─────────────────────────────────────────────────────────────────
--  Small helpers
-- ─────────────────────────────────────────────────────────────────
local function Tween(obj, props, t, style)
    local tw = TweenService:Create(obj, TweenInfo.new(t or 0.15, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
    tw:Play()
    return tw
end

function Library:Connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(self._conns, c)
    return c
end

-- Apply a theme colour and remember it so SetTheme() can recolour live
function Library:ThemeProp(obj, prop, key)
    obj[prop] = self.Theme[key]
    table.insert(self._themed, { obj, prop, key })
    return obj
end

-- New("Frame", {Size=..., Theme={BackgroundColor3="Main"}}, {children})
local function New(class, props, children)
    local obj = Instance.new(class)
    local theme = props and props.Theme
    local parent = props and props.Parent
    if props then
        props.Theme, props.Parent = nil, nil
        for k, v in pairs(props) do obj[k] = v end
    end
    if class:match("Text") then
        if not props or props.Font == nil then obj.Font = Library.Font end
        if not props or props.TextSize == nil then obj.TextSize = Library.TextSize end
    end
    if theme then
        for prop, key in pairs(theme) do Library:ThemeProp(obj, prop, key) end
    end
    if children then for _, c in ipairs(children) do c.Parent = obj end end
    if parent then obj.Parent = parent end
    return obj
end

local function Stroke(parent, key, thickness)
    local s = New("UIStroke", {
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Theme = { Color = key or "Outline" },
        Parent = parent,
    })
    return s
end

local function Corner(parent, r)
    return New("UICorner", { CornerRadius = UDim.new(0, r or 3), Parent = parent })
end

local function Padding(parent, t, r, b, l)
    return New("UIPadding", {
        PaddingTop = UDim.new(0, t or 0), PaddingRight = UDim.new(0, r or t or 0),
        PaddingBottom = UDim.new(0, b or t or 0), PaddingLeft = UDim.new(0, l or r or t or 0),
        Parent = parent,
    })
end

local function List(parent, pad, dir)
    return New("UIListLayout", {
        Padding = UDim.new(0, pad or 6),
        FillDirection = dir or Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = parent,
    })
end

local function IsHovering(obj)
    local m = UIS:GetMouseLocation()
    local p, s = obj.AbsolutePosition, obj.AbsoluteSize
    return m.X >= p.X and m.X <= p.X + s.X and m.Y >= p.Y and m.Y <= p.Y + s.Y
end

local function Round(n, step)
    if step == 0 then return n end
    return math.floor(n / step + 0.5) * step
end

local function MakeDraggable(frame, handle)
    local dragging, startInput, startPos
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging, startInput, startPos = true, input.Position, frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    Library:Connect(UIS.InputChanged, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - startInput
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
end

local function GetGuiParent()
    local ok, hui = pcall(function() return gethui and gethui() end)
    if ok and hui then return hui end
    local ok2 = pcall(function() return CoreGui.Name end)
    if ok2 then return CoreGui end
    return LocalPlayer:WaitForChild("PlayerGui")
end

-- ─────────────────────────────────────────────────────────────────
--  ScreenGui / overlay (shared by all windows)
-- ─────────────────────────────────────────────────────────────────
Library.ScreenGui = New("ScreenGui", {
    Name = "NoirUI",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Global,
    DisplayOrder = 999,
    Parent = GetGuiParent(),
})

-- Overlay layer for dropdown lists / colour pickers so they never get clipped
Library.Overlay = New("Frame", {
    Name = "Overlay", BackgroundTransparency = 1,
    Size = UDim2.fromScale(1, 1), ZIndex = 500, Parent = Library.ScreenGui,
})
Library._openPopups = {} -- popup frames currently shown

function Library:ClosePopups(except)
    for popup in pairs(self._openPopups) do
        if popup ~= except then
            popup.Visible = false
            self._openPopups[popup] = nil
        end
    end
end

Library:Connect(UIS.InputBegan, function(input, gpe)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.MouseButton2 then
        for popup, anchor in pairs(Library._openPopups) do
            if not IsHovering(popup) and not (anchor and IsHovering(anchor)) then
                popup.Visible = false
                Library._openPopups[popup] = nil
            end
        end
    end
end)

-- ─────────────────────────────────────────────────────────────────
--  Theme
-- ─────────────────────────────────────────────────────────────────
function Library:SetTheme(key, color)
    self.Theme[key] = color
    for i = #self._themed, 1, -1 do
        local t = self._themed[i]
        if not t[1].Parent then
            table.remove(self._themed, i)
        elseif t[3] == key then
            t[1][t[2]] = color
        end
    end
end

-- ─────────────────────────────────────────────────────────────────
--  Notifications
-- ─────────────────────────────────────────────────────────────────
Library.NotifHolder = New("Frame", {
    BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1),
    Position = UDim2.new(1, -12, 1, -12), Size = UDim2.fromOffset(280, 400),
    ZIndex = 600, Parent = Library.ScreenGui,
}, {
    New("UIListLayout", {
        Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Bottom,
        HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder,
    }),
})

function Library:Notify(text, duration)
    duration = duration or 3
    local frame = New("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, ZIndex = 601, Parent = self.NotifHolder,
        LayoutOrder = tick(),
    })
    local inner = New("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        Position = UDim2.fromOffset(300, 0), ZIndex = 601,
        Theme = { BackgroundColor3 = "Main" }, Parent = frame,
    })
    Corner(inner, 4); Stroke(inner)
    New("Frame", { Size = UDim2.new(0, 2, 1, 0), BorderSizePixel = 0, ZIndex = 602,
        Theme = { BackgroundColor3 = "Accent" }, Parent = inner })
    New("TextLabel", {
        Text = text, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1, Size = UDim2.new(1, -18, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        Position = UDim2.fromOffset(10, 0), ZIndex = 602, Theme = { TextColor3 = "Text" }, Parent = inner,
    })
    Padding(inner, 8, 8, 8, 0)
    local bar = New("Frame", { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1),
        BorderSizePixel = 0, ZIndex = 603, Theme = { BackgroundColor3 = "Accent" }, Parent = inner })

    Tween(inner, { Position = UDim2.fromOffset(0, 0) }, 0.25, Enum.EasingStyle.Back)
    Tween(bar, { Size = UDim2.new(0, 0, 0, 1) }, duration, Enum.EasingStyle.Linear)
    task.delay(duration, function()
        Tween(inner, { Position = UDim2.fromOffset(300, 0) }, 0.2).Completed:Wait()
        frame:Destroy()
    end)
end

-- ─────────────────────────────────────────────────────────────────
--  Watermark
-- ─────────────────────────────────────────────────────────────────
function Library:SetWatermark(text)
    if not self.Watermark then
        local wm = New("Frame", {
            Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X,
            ZIndex = 50, Theme = { BackgroundColor3 = "Main" }, Parent = self.ScreenGui,
        })
        Corner(wm, 3); Stroke(wm)
        New("Frame", { Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0, ZIndex = 51,
            Theme = { BackgroundColor3 = "Accent" }, Parent = wm })
        local lbl = New("TextLabel", {
            BackgroundTransparency = 1, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
            ZIndex = 51, Theme = { TextColor3 = "Text" }, Parent = wm,
        })
        Padding(wm, 0, 8, 0, 8)
        MakeDraggable(wm, wm)
        self.Watermark, self.WatermarkLabel = wm, lbl
    end
    self.WatermarkLabel.Text = text
    self.Watermark.Visible = text ~= nil and text ~= ""
end

-- ─────────────────────────────────────────────────────────────────
--  Popup helper (dropdown lists, colour pickers)
-- ─────────────────────────────────────────────────────────────────
local function MakePopup(anchor, width, height)
    local popup = New("Frame", {
        Visible = false, Size = UDim2.fromOffset(width, height), ZIndex = 510,
        Theme = { BackgroundColor3 = "Main" }, Parent = Library.Overlay,
    })
    Corner(popup, 3); Stroke(popup)
    local function Open()
        Library:ClosePopups(popup)
        local p = anchor.AbsolutePosition
        local x = p.X
        local y = p.Y + anchor.AbsoluteSize.Y + 4
        local vp = Library.ScreenGui.AbsoluteSize
        if x + popup.AbsoluteSize.X > vp.X then x = vp.X - popup.AbsoluteSize.X - 4 end
        if y + popup.AbsoluteSize.Y > vp.Y then y = p.Y - popup.AbsoluteSize.Y - 4 end
        popup.Position = UDim2.fromOffset(x, y)
        popup.Visible = true
        Library._openPopups[popup] = anchor
    end
    local function Close()
        popup.Visible = false
        Library._openPopups[popup] = nil
    end
    return popup, Open, Close
end

-- ─────────────────────────────────────────────────────────────────
--  Addon: ColorPicker
-- ─────────────────────────────────────────────────────────────────
local function CreateColorPicker(holder, idx, info)
    info = info or {}
    local picker = { Type = "ColorPicker", Value = info.Default or Color3.new(1, 1, 1), Callback = info.Callback or function() end }
    local h, s, v = picker.Value:ToHSV()

    local swatch = New("TextButton", {
        Text = "", AutoButtonColor = false, Size = UDim2.fromOffset(22, 14), BackgroundColor3 = picker.Value,
        ZIndex = 5, Parent = holder,
    })
    Corner(swatch, 2); Stroke(swatch)

    local popup, Open, Close = MakePopup(swatch, 200, 196)
    Padding(popup, 8)

    New("TextLabel", { Text = info.Title or idx, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 14),
        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 511, Theme = { TextColor3 = "Text" }, Parent = popup })

    -- Saturation / value square
    local sv = New("TextButton", { Text = "", AutoButtonColor = false, Position = UDim2.fromOffset(0, 20),
        Size = UDim2.fromOffset(184, 120), BackgroundColor3 = Color3.fromHSV(h, 1, 1), ZIndex = 511, Parent = popup })
    Corner(sv, 2)
    New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 512, Parent = sv }, {
        New("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }) }),
        New("UICorner", { CornerRadius = UDim.new(0, 2) }),
    })
    New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 513, Parent = sv }, {
        New("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }) }),
        New("UICorner", { CornerRadius = UDim.new(0, 2) }),
    })
    local svCursor = New("Frame", { Size = UDim2.fromOffset(8, 8), AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 514, Parent = sv })
    Corner(svCursor, 4); New("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, Parent = svCursor })

    -- Hue bar
    local hue = New("TextButton", { Text = "", AutoButtonColor = false, Position = UDim2.fromOffset(0, 146),
        Size = UDim2.fromOffset(184, 12), ZIndex = 511, Parent = popup })
    Corner(hue, 2)
    local keys = {}
    for i = 0, 6 do keys[#keys + 1] = ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 1, 1)) end
    New("UIGradient", { Color = ColorSequence.new(keys), Parent = hue })
    local hueCursor = New("Frame", { Size = UDim2.new(0, 3, 1, 2), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5),
        BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 512, Parent = hue })
    New("UIStroke", { Color = Color3.new(0, 0, 0), Parent = hueCursor })

    -- Hex box
    local hex = New("TextBox", { Position = UDim2.fromOffset(0, 164), Size = UDim2.fromOffset(184, 18), ClearTextOnFocus = false,
        Text = "#FFFFFF", ZIndex = 511, Theme = { BackgroundColor3 = "Element", TextColor3 = "Text" }, Parent = popup })
    Corner(hex, 2); Stroke(hex)

    local function Refresh(fire)
        picker.Value = Color3.fromHSV(h, s, v)
        swatch.BackgroundColor3 = picker.Value
        sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
        svCursor.Position = UDim2.fromScale(s, 1 - v)
        hueCursor.Position = UDim2.fromScale(h, 0.5)
        hex.Text = "#" .. picker.Value:ToHex():upper()
        Library.Flags[idx] = picker.Value
        if fire ~= false then picker.Callback(picker.Value) end
        if picker.Changed then picker.Changed(picker.Value) end
    end

    local draggingSV, draggingHue = false, false
    sv.MouseButton1Down:Connect(function() draggingSV = true end)
    hue.MouseButton1Down:Connect(function() draggingHue = true end)
    Library:Connect(UIS.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then draggingSV, draggingHue = false, false end
    end)
    Library:Connect(RunService.RenderStepped, function()
        if not popup.Visible then return end
        local m = UIS:GetMouseLocation()
        if draggingSV then
            s = math.clamp((m.X - sv.AbsolutePosition.X) / sv.AbsoluteSize.X, 0, 1)
            v = 1 - math.clamp((m.Y - sv.AbsolutePosition.Y) / sv.AbsoluteSize.Y, 0, 1)
            Refresh()
        elseif draggingHue then
            h = math.clamp((m.X - hue.AbsolutePosition.X) / hue.AbsoluteSize.X, 0, 0.999)
            Refresh()
        end
    end)
    hex.FocusLost:Connect(function()
        local ok, c = pcall(Color3.fromHex, hex.Text)
        if ok then h, s, v = c:ToHSV(); Refresh() else Refresh(false) end
    end)
    swatch.MouseButton1Click:Connect(function()
        if popup.Visible then Close() else Open() end
    end)

    function picker:SetValue(c) h, s, v = c:ToHSV(); Refresh() end
    function picker:SetValueRGB(c) self:SetValue(c) end
    function picker:OnChanged(fn) self.Changed = fn end

    Refresh(false)
    Library.Options[idx] = picker
    return picker
end

-- ─────────────────────────────────────────────────────────────────
--  Addon: KeyPicker
-- ─────────────────────────────────────────────────────────────────
local function CreateKeyPicker(holder, idx, info)
    info = info or {}
    local kp = {
        Type = "KeyPicker", Value = info.Default or "None", Mode = info.Mode or "Toggle",
        Modes = info.Modes or { "Always", "Toggle", "Hold" },
        Toggled = false, Listening = false, Callback = info.Callback or function() end,
        ChangedCallback = info.ChangedCallback or function() end,
    }
    local box = New("TextButton", {
        Text = "", AutoButtonColor = false, Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X,
        ZIndex = 5, Theme = { BackgroundColor3 = "Element" }, Parent = holder,
    })
    Corner(box, 2); Stroke(box)
    local lbl = New("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
        TextSize = 11, ZIndex = 6, Theme = { TextColor3 = "DimText" }, Parent = box })
    Padding(box, 0, 5, 0, 5)

    local function Display()
        lbl.Text = kp.Listening and "..." or ("[" .. tostring(kp.Value):gsub("MouseButton", "MB") .. "]")
    end

    -- mode menu (right-click)
    local popup, Open, Close = MakePopup(box, 80, #kp.Modes * 20 + 8)
    Padding(popup, 4); List(popup, 2)
    for _, mode in ipairs(kp.Modes) do
        local b = New("TextButton", { Text = mode, Size = UDim2.new(1, 0, 0, 18), ZIndex = 511, AutoButtonColor = false,
            Theme = { BackgroundColor3 = "Element", TextColor3 = mode == kp.Mode and "Accent" or "DimText" }, Parent = popup })
        Corner(b, 2)
        b.MouseButton1Click:Connect(function()
            kp.Mode = mode
            for _, c in ipairs(popup:GetChildren()) do
                if c:IsA("TextButton") then Library:ThemeProp(c, "TextColor3", c.Text == mode and "Accent" or "DimText") end
            end
            kp.Toggled = false
            Close()
        end)
    end

    box.MouseButton1Click:Connect(function()
        kp.Listening = true; Display()
    end)
    box.MouseButton2Click:Connect(function()
        if popup.Visible then Close() else Open() end
    end)

    Library:Connect(UIS.InputBegan, function(input, gpe)
        if kp.Listening then
            local key
            if input.UserInputType == Enum.UserInputType.Keyboard then
                key = input.KeyCode.Name
            elseif input.UserInputType.Name:match("MouseButton") then
                key = input.UserInputType.Name
            end
            if key then
                kp.Value = (key == "Escape" or key == "Backspace") and "None" or key
                kp.Listening = false
                Display(); kp.ChangedCallback(kp.Value)
            end
            return
        end
        if gpe or kp.Value == "None" then return end
        local match = (input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode.Name == kp.Value)
            or input.UserInputType.Name == kp.Value
        if match then
            if kp.Mode == "Toggle" then
                kp.Toggled = not kp.Toggled
                kp.Callback(kp.Toggled)
            elseif kp.Mode == "Hold" then
                kp.Toggled = true
                kp.Callback(true)
            end
        end
    end)
    Library:Connect(UIS.InputEnded, function(input)
        if kp.Mode == "Hold" and kp.Value ~= "None" then
            local match = (input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode.Name == kp.Value)
                or input.UserInputType.Name == kp.Value
            if match then kp.Toggled = false; kp.Callback(false) end
        end
    end)

    function kp:GetState()
        if self.Mode == "Always" then return true end
        return self.Toggled
    end
    function kp:SetValue(data) -- {key, mode}
        self.Value = data[1] or self.Value
        self.Mode = data[2] or self.Mode
        Display()
    end
    function kp:OnClick(fn) self.Callback = fn end
    function kp:OnChanged(fn) self.ChangedCallback = fn end

    Display()
    Library.Options[idx] = kp
    return kp
end

-- ─────────────────────────────────────────────────────────────────
--  Element container (shared by Groupbox and Tabbox tabs)
-- ─────────────────────────────────────────────────────────────────
local Container = {}
Container.__index = Container

-- Each element row: a frame with Theme Element bg, consistent height, hover highlight.
local function Row(parent, height)
    local row = New("Frame", { Size = UDim2.new(1, 0, 0, height), BackgroundTransparency = 1, Parent = parent })
    return row
end

local function AddonHolder(row)
    local holder = New("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0, 0, 0, 16), AutomaticSize = Enum.AutomaticSize.X, Parent = row })
    New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4),
        HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder, Parent = holder })
    return holder
end

function Container:AddLabel(text, wrap)
    local row = Row(self.Frame, 16)
    if wrap then row.AutomaticSize = Enum.AutomaticSize.Y; row.Size = UDim2.new(1, 0, 0, 0) end
    local lbl = New("TextLabel", { Text = text, TextWrapped = wrap or false, BackgroundTransparency = 1,
        Size = UDim2.new(1, -60, wrap and 0 or 1, 0), AutomaticSize = wrap and Enum.AutomaticSize.Y or Enum.AutomaticSize.None,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
        Theme = { TextColor3 = "DimText" }, Parent = row })
    local holder = AddonHolder(row)
    local label = { Type = "Label", Frame = row }
    function label:SetText(t) lbl.Text = t end
    function label:AddColorPicker(idx, info) CreateColorPicker(holder, idx, info); return self end
    function label:AddKeyPicker(idx, info) CreateKeyPicker(holder, idx, info); return self end
    return label
end

function Container:AddDivider()
    local row = Row(self.Frame, 1)
    New("Frame", { Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0, Theme = { BackgroundColor3 = "Outline" }, Parent = row })
end

function Container:AddToggle(idx, info)
    info = info or {}
    local toggle = { Type = "Toggle", Value = info.Default or false, Callback = info.Callback or function() end, Risky = info.Risky }
    local row = Row(self.Frame, 18)
    local btn = New("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = row })
    local box = New("Frame", { Size = UDim2.fromOffset(14, 14), Position = UDim2.fromOffset(0, 2),
        Theme = { BackgroundColor3 = "Element" }, Parent = row })
    Corner(box, 3); local boxStroke = Stroke(box)
    local check = New("ImageLabel", { Image = "rbxassetid://3926305904", ImageRectOffset = Vector2.new(312, 4), ImageRectSize = Vector2.new(24, 24),
        BackgroundTransparency = 1, Size = UDim2.fromOffset(12, 12), Position = UDim2.fromOffset(1, 1), ImageTransparency = 1,
        ImageColor3 = Color3.new(0, 0, 0), ZIndex = 3, Parent = box })
    local lbl = New("TextLabel", { Text = info.Text or idx, BackgroundTransparency = 1, Position = UDim2.fromOffset(20, 0),
        Size = UDim2.new(1, -20, 1, 0), TextXAlignment = Enum.TextXAlignment.Left,
        Theme = { TextColor3 = info.Risky and "Risky" or "Text" }, Parent = row })
    local holder = AddonHolder(row)

    local function Display()
        if toggle.Value then
            Tween(box, { BackgroundColor3 = Library.Theme.Accent }); Library:ThemeProp(box, "BackgroundColor3", "Accent")
            Tween(check, { ImageTransparency = 0 })
        else
            Tween(box, { BackgroundColor3 = Library.Theme.Element }); Library:ThemeProp(box, "BackgroundColor3", "Element")
            Tween(check, { ImageTransparency = 1 })
        end
    end
    function toggle:SetValue(v, silent)
        self.Value = v and true or false
        Library.Flags[idx] = self.Value
        Display()
        if not silent then self.Callback(self.Value) end
        if self.Changed then self.Changed(self.Value) end
    end
    function toggle:OnChanged(fn) self.Changed = fn end
    function toggle:AddColorPicker(cidx, cinfo) CreateColorPicker(holder, cidx, cinfo); return self end
    function toggle:AddKeyPicker(kidx, kinfo) CreateKeyPicker(holder, kidx, kinfo); return self end

    btn.MouseButton1Click:Connect(function() toggle:SetValue(not toggle.Value) end)
    btn.MouseEnter:Connect(function() Tween(boxStroke, { Color = Library.Theme.Accent }) end)
    btn.MouseLeave:Connect(function() Tween(boxStroke, { Color = Library.Theme.Outline }) end)

    if info.Tooltip then
        btn.MouseEnter:Connect(function() lbl.Text = info.Tooltip end)
        btn.MouseLeave:Connect(function() lbl.Text = info.Text or idx end)
    end

    toggle:SetValue(toggle.Value, true)
    Library.Toggles[idx] = toggle
    return toggle
end

function Container:AddSlider(idx, info)
    info = info or {}
    local min, max = info.Min or 0, info.Max or 100
    local slider = { Type = "Slider", Min = min, Max = max, Rounding = info.Rounding or 0,
        Suffix = info.Suffix or "", Callback = info.Callback or function() end, Value = info.Default or min }
    local step = slider.Rounding == 0 and 1 or 10 ^ -slider.Rounding

    local compact = info.Compact
    local row = Row(self.Frame, compact and 14 or 30)
    if not compact then
        New("TextLabel", { Text = info.Text or idx, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 14),
            TextXAlignment = Enum.TextXAlignment.Left, Theme = { TextColor3 = "Text" }, Parent = row })
    end
    local bar = New("TextButton", { Text = "", AutoButtonColor = false, Size = UDim2.new(1, 0, 0, 12),
        Position = UDim2.fromOffset(0, compact and 1 or 17), Theme = { BackgroundColor3 = "Element" }, Parent = row })
    Corner(bar, 3); local barStroke = Stroke(bar)
    local fill = New("Frame", { Size = UDim2.fromScale(0, 1), BorderSizePixel = 0, Theme = { BackgroundColor3 = "Accent" }, Parent = bar })
    Corner(fill, 3)
    local valLbl = New("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), TextSize = 11, ZIndex = 3,
        Theme = { TextColor3 = "Text" }, Parent = bar })
    New("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, Transparency = 0.5, Parent = valLbl }).ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

    local function Display()
        local a = (slider.Value - min) / (max - min)
        Tween(fill, { Size = UDim2.fromScale(a, 1) }, 0.08)
        local txt = slider.Rounding == 0 and tostring(math.floor(slider.Value)) or string.format("%." .. slider.Rounding .. "f", slider.Value)
        valLbl.Text = (compact and (info.Text or idx) .. ": " or "") .. txt .. slider.Suffix .. (info.HideMax and "" or ("/" .. max .. slider.Suffix))
    end
    function slider:SetValue(v, silent)
        self.Value = math.clamp(Round(v, step), self.Min, self.Max)
        Library.Flags[idx] = self.Value
        Display()
        if not silent then self.Callback(self.Value) end
        if self.Changed then self.Changed(self.Value) end
    end
    function slider:SetMax(m) self.Max = m; max = m; self:SetValue(self.Value) end
    function slider:SetMin(m) self.Min = m; min = m; self:SetValue(self.Value) end
    function slider:OnChanged(fn) self.Changed = fn end

    local dragging = false
    local function Update()
        local m = UIS:GetMouseLocation()
        local a = math.clamp((m.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        slider:SetValue(min + (max - min) * a)
    end
    bar.MouseButton1Down:Connect(function() dragging = true; Update() end)
    Library:Connect(UIS.InputEnded, function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end end)
    Library:Connect(UIS.InputChanged, function(i)
        if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then Update() end
    end)
    bar.MouseEnter:Connect(function() Tween(barStroke, { Color = Library.Theme.Accent }) end)
    bar.MouseLeave:Connect(function() Tween(barStroke, { Color = Library.Theme.Outline }) end)

    slider:SetValue(slider.Value, true)
    Library.Options[idx] = slider
    return slider
end

function Container:AddDropdown(idx, info)
    info = info or {}
    local dd = { Type = "Dropdown", Values = info.Values or {}, Multi = info.Multi, AllowNull = info.AllowNull,
        Callback = info.Callback or function() end }
    dd.Value = info.Multi and (info.Default or {}) or info.Default

    local row = Row(self.Frame, 36)
    New("TextLabel", { Text = info.Text or idx, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 14),
        TextXAlignment = Enum.TextXAlignment.Left, Theme = { TextColor3 = "Text" }, Parent = row })
    local box = New("TextButton", { Text = "", AutoButtonColor = false, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 16),
        Theme = { BackgroundColor3 = "Element" }, Parent = row })
    Corner(box, 3); Stroke(box)
    local sel = New("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(6, 0), Size = UDim2.new(1, -24, 1, 0),
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Theme = { TextColor3 = "Text" }, Parent = box })
    local arrow = New("ImageLabel", { Image = "rbxassetid://6031091004", BackgroundTransparency = 1, Size = UDim2.fromOffset(14, 14),
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -4, 0.5, 0), Theme = { ImageColor3 = "DimText" }, Parent = box })

    local popup, Open, Close = MakePopup(box, 100, 100)
    local scroll = New("ScrollingFrame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ScrollBarThickness = 2,
        BorderSizePixel = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 511,
        Theme = { ScrollBarImageColor3 = "Accent" }, Parent = popup })
    Padding(scroll, 4); List(scroll, 2)

    local function Display()
        if dd.Multi then
            local t = {}
            for _, v in ipairs(dd.Values) do if dd.Value[v] then t[#t + 1] = tostring(v) end end
            sel.Text = #t > 0 and table.concat(t, ", ") or "---"
        else
            sel.Text = dd.Value ~= nil and tostring(dd.Value) or "---"
        end
        for _, b in ipairs(scroll:GetChildren()) do
            if b:IsA("TextButton") then
                local on = dd.Multi and dd.Value[b.Name] or (dd.Value == b.Name)
                Library:ThemeProp(b, "TextColor3", on and "Accent" or "DimText")
            end
        end
    end
    local function Build()
        for _, c in ipairs(scroll:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
        for _, v in ipairs(dd.Values) do
            local b = New("TextButton", { Name = tostring(v), Text = tostring(v), Size = UDim2.new(1, 0, 0, 18), AutoButtonColor = false,
                TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 512, Theme = { BackgroundColor3 = "Element", TextColor3 = "DimText" }, Parent = scroll })
            Corner(b, 2); Padding(b, 0, 6, 0, 6)
            b.MouseButton1Click:Connect(function()
                if dd.Multi then
                    if dd.Value[v] then
                        local count = 0; for _ in pairs(dd.Value) do count += 1 end
                        if count > 1 or dd.AllowNull then dd.Value[v] = nil end
                    else dd.Value[v] = true end
                else
                    if dd.Value == v and dd.AllowNull then dd.Value = nil else dd.Value = v end
                    Close()
                end
                dd:SetValue(dd.Value)
            end)
        end
        popup.Size = UDim2.fromOffset(box.AbsoluteSize.X, math.min(#dd.Values, 8) * 20 + 8)
    end

    function dd:SetValue(v, silent)
        self.Value = v
        Library.Flags[idx] = v
        Display()
        if not silent then self.Callback(v) end
        if self.Changed then self.Changed(v) end
    end
    function dd:SetValues(vals) self.Values = vals; Build(); Display() end
    function dd:OnChanged(fn) self.Changed = fn end

    box.MouseButton1Click:Connect(function()
        if popup.Visible then Close() else
            popup.Size = UDim2.fromOffset(box.AbsoluteSize.X, math.min(#dd.Values, 8) * 20 + 8)
            Tween(arrow, { Rotation = 180 }); Open()
        end
    end)
    Library:Connect(RunService.Heartbeat, function()
        if not popup.Visible and arrow.Rotation ~= 0 then Tween(arrow, { Rotation = 0 }) end
    end)

    Build(); dd:SetValue(dd.Value, true)
    Library.Options[idx] = dd
    return dd
end

function Container:AddButton(info, callback)
    if type(info) == "string" then info = { Text = info, Func = callback } end
    local row = Row(self.Frame, 22)
    local btn = New("TextButton", { Text = info.Text, AutoButtonColor = false, Size = UDim2.fromScale(1, 1),
        Theme = { BackgroundColor3 = "Element", TextColor3 = "Text" }, Parent = row })
    Corner(btn, 3); local st = Stroke(btn)
    local lastClick = 0
    btn.MouseButton1Click:Connect(function()
        if info.DoubleClick then
            if tick() - lastClick < 0.4 then lastClick = 0; info.Func() else
                lastClick = tick(); local old = btn.Text; btn.Text = "Click again to confirm"
                task.delay(0.4, function() if btn.Text == "Click again to confirm" then btn.Text = old end end)
            end
        else info.Func() end
    end)
    btn.MouseEnter:Connect(function() Tween(st, { Color = Library.Theme.Accent }) end)
    btn.MouseLeave:Connect(function() Tween(st, { Color = Library.Theme.Outline }) end)
    btn.MouseButton1Down:Connect(function() Tween(btn, { BackgroundColor3 = Library.Theme.Outline }, 0.05) end)
    btn.MouseButton1Up:Connect(function() Tween(btn, { BackgroundColor3 = Library.Theme.Element }, 0.1) end)

    local button = { Type = "Button", Frame = row }
    function button:AddButton(sub, subcb) -- side-by-side sub button
        if type(sub) == "string" then sub = { Text = sub, Func = subcb } end
        btn.Size = UDim2.new(0.5, -3, 1, 0)
        local b2 = New("TextButton", { Text = sub.Text, AutoButtonColor = false, Size = UDim2.new(0.5, -3, 1, 0), Position = UDim2.new(0.5, 3, 0, 0),
            Theme = { BackgroundColor3 = "Element", TextColor3 = "Text" }, Parent = row })
        Corner(b2, 3); local st2 = Stroke(b2)
        b2.MouseButton1Click:Connect(sub.Func)
        b2.MouseEnter:Connect(function() Tween(st2, { Color = Library.Theme.Accent }) end)
        b2.MouseLeave:Connect(function() Tween(st2, { Color = Library.Theme.Outline }) end)
        return self
    end
    return button
end

function Container:AddInput(idx, info)
    info = info or {}
    local input = { Type = "Input", Value = info.Default or "", Callback = info.Callback or function() end }
    local row = Row(self.Frame, 36)
    New("TextLabel", { Text = info.Text or idx, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 14),
        TextXAlignment = Enum.TextXAlignment.Left, Theme = { TextColor3 = "Text" }, Parent = row })
    local box = New("TextBox", { Text = input.Value, PlaceholderText = info.Placeholder or "", ClearTextOnFocus = false,
        Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 16), TextXAlignment = Enum.TextXAlignment.Left,
        Theme = { BackgroundColor3 = "Element", TextColor3 = "Text", PlaceholderColor3 = "DimText" }, Parent = row })
    Corner(box, 3); local st = Stroke(box); Padding(box, 0, 6, 0, 6)
    box.Focused:Connect(function() Tween(st, { Color = Library.Theme.Accent }) end)
    box.FocusLost:Connect(function(enter)
        Tween(st, { Color = Library.Theme.Outline })
        if info.Numeric and tonumber(box.Text) == nil then box.Text = input.Value; return end
        if info.MaxLength then box.Text = box.Text:sub(1, info.MaxLength) end
        if info.Finished and not enter then return end
        input:SetValue(box.Text)
    end)
    if not info.Finished then
        box:GetPropertyChangedSignal("Text"):Connect(function()
            if info.Numeric then return end
            input.Value = box.Text; Library.Flags[idx] = box.Text; input.Callback(box.Text)
        end)
    end
    function input:SetValue(v, silent)
        self.Value = v; box.Text = v; Library.Flags[idx] = v
        if not silent then self.Callback(v) end
        if self.Changed then self.Changed(v) end
    end
    function input:OnChanged(fn) self.Changed = fn end
    Library.Flags[idx] = input.Value
    Library.Options[idx] = input
    return input
end

-- ─────────────────────────────────────────────────────────────────
--  Groupbox / Tabbox
-- ─────────────────────────────────────────────────────────────────
local function CreateGroupbox(column, title)
    local gb = New("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        Theme = { BackgroundColor3 = "Main" }, Parent = column })
    Corner(gb, 4); Stroke(gb)
    New("Frame", { Size = UDim2.new(1, 0, 0, 2), BorderSizePixel = 0, Theme = { BackgroundColor3 = "Accent" }, Parent = gb })
    New("TextLabel", { Text = title, BackgroundTransparency = 1, Size = UDim2.new(1, -16, 0, 24), Position = UDim2.fromOffset(10, 2),
        TextXAlignment = Enum.TextXAlignment.Left, Theme = { TextColor3 = "Text" }, Parent = gb })
    local content = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -20, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        Position = UDim2.fromOffset(10, 26), Parent = gb })
    List(content, 6)
    Padding(gb, 0, 0, 10, 0)
    return setmetatable({ Type = "Groupbox", Frame = content, Root = gb }, Container)
end

local function CreateTabbox(column)
    local tb = New("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        Theme = { BackgroundColor3 = "Main" }, Parent = column })
    Corner(tb, 4); Stroke(tb)
    local bar = New("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Parent = tb })
    New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder, Parent = bar })
    New("Frame", { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.fromOffset(0, 24), BorderSizePixel = 0, Theme = { BackgroundColor3 = "Outline" }, Parent = tb })
    Padding(tb, 0, 0, 10, 0)

    local tabbox = { Type = "Tabbox", Tabs = {} }
    function tabbox:AddTab(name)
        local btn = New("TextButton", { Text = name, AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.new(0, 0, 1, 0),
            Theme = { TextColor3 = "DimText" }, Parent = bar })
        local underline = New("Frame", { Size = UDim2.new(1, 0, 0, 2), Position = UDim2.new(0, 0, 1, -1), BorderSizePixel = 0,
            BackgroundTransparency = 1, Theme = { BackgroundColor3 = "Accent" }, Parent = btn })
        local content = New("Frame", { Visible = false, BackgroundTransparency = 1, Size = UDim2.new(1, -20, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
            Position = UDim2.fromOffset(10, 32), Parent = tb })
        List(content, 6)
        local tab = setmetatable({ Type = "Tab", Frame = content, Button = btn, Underline = underline }, Container)
        table.insert(self.Tabs, tab)
        local n = #self.Tabs
        for _, t in ipairs(self.Tabs) do t.Button.Size = UDim2.new(1 / n, 0, 1, 0) end
        btn.MouseButton1Click:Connect(function() self:Select(tab) end)
        if n == 1 then self:Select(tab) end
        return tab
    end
    function tabbox:Select(tab)
        for _, t in ipairs(self.Tabs) do
            local on = t == tab
            t.Frame.Visible = on
            Tween(t.Underline, { BackgroundTransparency = on and 0 or 1 })
            Library:ThemeProp(t.Button, "TextColor3", on and "Text" or "DimText")
        end
    end
    return tabbox
end

-- ─────────────────────────────────────────────────────────────────
--  Window
-- ─────────────────────────────────────────────────────────────────
function Library:CreateWindow(info)
    info = info or {}
    local Window = { Tabs = {}, Visible = true }
    local size = info.Size or UDim2.fromOffset(560, 600)

    local main = New("Frame", {
        Name = "Window", Size = size, AnchorPoint = Vector2.new(0.5, 0.5),
        Position = info.Position or UDim2.fromScale(0.5, 0.5), ClipsDescendants = true,
        Theme = { BackgroundColor3 = "Background" }, Parent = self.ScreenGui,
    })
    Corner(main, 5); Stroke(main)

    -- title bar
    local titleBar = New("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, Parent = main })
    New("Frame", { Size = UDim2.new(1, 0, 0, 2), BorderSizePixel = 0, Theme = { BackgroundColor3 = "Accent" }, Parent = main })
    New("TextLabel", { Text = info.Title or "Noir UI", BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0),
        TextXAlignment = Enum.TextXAlignment.Left, Theme = { TextColor3 = "Text" }, Parent = titleBar })
    local hint = New("TextLabel", { Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, -12, 1, 0), TextXAlignment = Enum.TextXAlignment.Right,
        TextSize = 11, Theme = { TextColor3 = "DimText" }, Parent = titleBar })
    MakeDraggable(main, titleBar)

    -- tab bar
    local tabBar = New("Frame", { Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 30),
        Theme = { BackgroundColor3 = "Main" }, Parent = main })
    Corner(tabBar, 4); Stroke(tabBar)
    New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2), Parent = tabBar })
    Padding(tabBar, 3)

    local tabHolder = New("Frame", { Size = UDim2.new(1, -20, 1, -66), Position = UDim2.fromOffset(10, 62), BackgroundTransparency = 1, Parent = main })

    function Window:UpdateHint()
        hint.Text = "toggle: " .. tostring(Library.ToggleKey.Name)
    end
    Window:UpdateHint()

    function Window:AddTab(name)
        local btn = New("TextButton", { Text = name, AutoButtonColor = false, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
            Theme = { BackgroundColor3 = "Main", TextColor3 = "DimText" }, Parent = tabBar })
        Corner(btn, 3); Padding(btn, 0, 12, 0, 12)

        local page = New("Frame", { Visible = false, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = tabHolder })
        local function Column(x)
            local col = New("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(0.5, -5, 1, 0),
                Position = UDim2.new(x, x == 0 and 0 or 5, 0, 0), ScrollBarThickness = 2, CanvasSize = UDim2.new(),
                AutomaticCanvasSize = Enum.AutomaticSize.Y, Theme = { ScrollBarImageColor3 = "Accent" }, Parent = page })
            List(col, 10); Padding(col, 0, 4, 10, 0)
            return col
        end
        local left, right = Column(0), Column(0.5)

        local tab = { Name = name, Button = btn, Page = page, Left = left, Right = right }
        function tab:AddLeftGroupbox(title) return CreateGroupbox(left, title) end
        function tab:AddRightGroupbox(title) return CreateGroupbox(right, title) end
        function tab:AddLeftTabbox() return CreateTabbox(left) end
        function tab:AddRightTabbox() return CreateTabbox(right) end

        btn.MouseButton1Click:Connect(function() Window:SelectTab(tab) end)
        btn.MouseEnter:Connect(function() if Window.Current ~= tab then Tween(btn, { TextColor3 = Library.Theme.Text }) end end)
        btn.MouseLeave:Connect(function() if Window.Current ~= tab then Tween(btn,... (9 KB left)
