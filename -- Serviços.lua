-- Serviços
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local VirtualUser = game:GetService("VirtualUser")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

----------------------------------------------------------------
-- LIMPEZA DE BOTÕES FLUTUANTES ANTERIORES
----------------------------------------------------------------
local function cleanupToggleGuis()
    local targets = { CoreGui, LocalPlayer:FindFirstChild("PlayerGui") }
    for _, parent in ipairs(targets) do
        if parent then
            for _, child in ipairs(parent:GetChildren()) do
                if child.Name == "ApxShouyaToggleGui" then
                    child:Destroy()
                end
            end
        end
    end
end
cleanupToggleGuis()

-- Carregamento oficial da WindUI via GitHub
local WindUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()

-- Acesso aos Remotes
local SharedRemotes = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")

local Remote_MineRock            = SharedRemotes:FindFirstChild("MineRock")
local Remote_RockHit             = SharedRemotes:FindFirstChild("RockHit")
local Remote_SellOres            = SharedRemotes:FindFirstChild("SellOres")
local Remote_Teleport            = SharedRemotes:FindFirstChild("TeleportToZone")
local Remote_ClaimDaily          = SharedRemotes:FindFirstChild("ClaimDaily")
local Remote_ClaimGift           = SharedRemotes:FindFirstChild("ClaimPlaytimeGift")
local Remote_QuestClaim          = SharedRemotes:FindFirstChild("QuestClaim")
local Remote_ClaimStarter        = SharedRemotes:FindFirstChild("ClaimStarterQuests")
local Remote_ClaimCandy          = SharedRemotes:FindFirstChild("ClaimCandyTreat")
local Remote_SpinWheel           = SharedRemotes:FindFirstChild("SpinWheel")
local Remote_Rebirth             = SharedRemotes:FindFirstChild("RequestRebirth")
local Remote_BuyUpgrade          = SharedRemotes:FindFirstChild("BuyUpgrade")
local Remote_RequestUpgrade      = SharedRemotes:FindFirstChild("RequestUpgrade")
local Remote_UpgradeCandyPickaxe = SharedRemotes:FindFirstChild("UpgradeCandyPickaxe")

-- Mapeamento das Zonas
local ZONE_DATA = {
    ["Mina 1 (HP 6)"]          = "Mine1",
    ["Gruta (HP 12)"]          = "Grotto",
    ["Mina 2 (HP 20)"]         = "Mine2",
    ["Túmulo (HP 32)"]         = "Tomb",
    ["Mina 3 (HP 50)"]         = "Mine3",
    ["Mina 4 (HP 80)"]         = "Mine4",
    ["Abismo Tóxico (HP 120)"] = "Toxic",
    ["Ruínas do Céu (HP 200)"] = "Sky"
}

local ZONE_NAMES = {
    "Mina 1 (HP 6)",
    "Gruta (HP 12)",
    "Mina 2 (HP 20)",
    "Túmulo (HP 32)",
    "Mina 3 (HP 50)",
    "Mina 4 (HP 80)",
    "Abismo Tóxico (HP 120)",
    "Ruínas do Céu (HP 200)"
}

-- Estados
local scriptRunning      = true
local autoFarmActive     = false
local autoSellActive     = false
local autoRebirthActive  = false
local autoRewardsActive  = false
local autoUpgradesActive = false
local currentZoneId      = "Mine1"

-- Ponteiro do mouse visível
UserInputService.MouseIconEnabled = true

-- Anti-AFK integrado
local idledConnection
idledConnection = LocalPlayer.Idled:Connect(function()
    if not scriptRunning then
        if idledConnection then idledConnection:Disconnect() end
        return
    end
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new(0, 0))
end)

----------------------------------------------------------------
-- SISTEMA DE FILTRO E PRIORIDADE (LUCKY / ESPECIAIS)
----------------------------------------------------------------

local function teleportToZoneServer(zoneId)
    if Remote_Teleport then
        pcall(function()
            Remote_Teleport:FireServer(zoneId)
        end)
    end
end

local function isLuckyRock(rockModel)
    if not rockModel then return false end

    local isLuckyAttr = rockModel:GetAttribute("Lucky") or rockModel:GetAttribute("Variant") or rockModel:GetAttribute("Multiplier")
    if isLuckyAttr then return true end

    if rockModel:FindFirstChildWhichIsA("Highlight", true) or rockModel:FindFirstChildWhichIsA("SelectionBox", true) then
        return true
    end

    for _, gui in ipairs(rockModel:GetDescendants()) do
        if gui:IsA("TextLabel") and gui.Text ~= "" then
            local txt = string.lower(gui.Text)
            if string.find(txt, "sorte") or string.find(txt, "lucky") or string.find(txt, "x10") or string.find(txt, "x") then
                return true
            end
        end
    end

    return false
end

local function getTargetRockInZone()
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return nil, nil end
    local hrp = char.HumanoidRootPart

    local zonesFolder = workspace:FindFirstChild("Zones")
    if not zonesFolder then return nil, nil end

    local targetZoneFolder = zonesFolder:FindFirstChild(currentZoneId)
    if not targetZoneFolder then return nil, nil end

    local rocksFolder = targetZoneFolder:FindFirstChild("Rocks")
    if not rocksFolder then return nil, nil end

    local bestSpecialStone, bestSpecialModel = nil, nil
    local shortestSpecialDist = math.huge

    local bestNormalStone, bestNormalModel = nil, nil
    local shortestNormalDist = math.huge

    for _, rockModel in ipairs(rocksFolder:GetChildren()) do
        if rockModel:IsA("Model") and rockModel.Name == "Rock" then
            local hp = rockModel:GetAttribute("HP")
            if hp == nil or tonumber(hp) > 0 then
                local stonePart = rockModel:FindFirstChild("Stone")
                if stonePart and stonePart:IsA("BasePart") then
                    local dist = (hrp.Position - stonePart.Position).Magnitude

                    if isLuckyRock(rockModel) then
                        if dist < shortestSpecialDist then
                            shortestSpecialDist = dist
                            bestSpecialStone = stonePart
                            bestSpecialModel = rockModel
                        end
                    else
                        if dist < shortestNormalDist then
                            shortestNormalDist = dist
                            bestNormalStone = stonePart
                            bestNormalModel = rockModel
                        end
                    end
                end
            end
        end
    end

    if bestSpecialStone and bestSpecialModel then
        return bestSpecialStone, bestSpecialModel
    end

    return bestNormalStone, bestNormalModel
end

-- Ciclo de Mineração
task.spawn(function()
    while scriptRunning do
        task.wait(0.05)
        if autoFarmActive then
            local char = LocalPlayer.Character
            if char and char:FindFirstChild("HumanoidRootPart") then
                local hrp = char.HumanoidRootPart
                local stonePart, rockModel = getTargetRockInZone()

                if stonePart and rockModel and rockModel.Parent then
                    pcall(function()
                        hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                        hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                        hrp.CFrame = stonePart.CFrame * CFrame.new(0, 3.5, 0)
                    end)

                    local maxTimer = 0
                    while scriptRunning and autoFarmActive and rockModel and rockModel.Parent and stonePart and stonePart.Parent and maxTimer < 8 do
                        if not isLuckyRock(rockModel) then
                            local checkSpecialStone, _ = getTargetRockInZone()
                            if checkSpecialStone and checkSpecialStone ~= stonePart then
                                break
                            end
                        end

                        local hp = rockModel:GetAttribute("HP")
                        if hp ~= nil and tonumber(hp) <= 0 then
                            break
                        end

                        pcall(function()
                            if Remote_MineRock then
                                Remote_MineRock:FireServer(stonePart)
                            end
                            if Remote_RockHit then
                                Remote_RockHit:FireServer(stonePart)
                            end
                        end)

                        if (hrp.Position - stonePart.Position).Magnitude > 9 then
                            hrp.CFrame = stonePart.CFrame * CFrame.new(0, 3.5, 0)
                        end

                        maxTimer = maxTimer + 0.1
                        task.wait(0.1)
                    end
                else
                    teleportToZoneServer(currentZoneId)
                    task.wait(0.5)
                end
            end
        end
    end
end)

-- Ciclo de Venda
task.spawn(function()
    while scriptRunning do
        task.wait(5)
        if autoSellActive and Remote_SellOres then
            pcall(function()
                Remote_SellOres:InvokeServer()
            end)
        end
    end
end)

-- Ciclo de Rebirth
task.spawn(function()
    while scriptRunning do
        task.wait(8)
        if autoRebirthActive and Remote_Rebirth then
            pcall(function()
                Remote_Rebirth:InvokeServer()
            end)
        end
    end
end)

-- Ciclo de Recompensas
task.spawn(function()
    while scriptRunning do
        task.wait(10)
        if autoRewardsActive then
            pcall(function()
                if Remote_ClaimDaily then Remote_ClaimDaily:InvokeServer() end
                if Remote_ClaimGift then Remote_ClaimGift:InvokeServer() end
                if Remote_QuestClaim then Remote_QuestClaim:InvokeServer() end
                if Remote_ClaimStarter then Remote_ClaimStarter:InvokeServer() end
                if Remote_ClaimCandy then Remote_ClaimCandy:InvokeServer() end
                if Remote_SpinWheel then Remote_SpinWheel:InvokeServer() end
            end)
        end
    end
end)

-- Ciclo de Upgrades
task.spawn(function()
    while scriptRunning do
        task.wait(6)
        if autoUpgradesActive then
            pcall(function()
                if Remote_BuyUpgrade then Remote_BuyUpgrade:InvokeServer() end
                if Remote_RequestUpgrade then Remote_RequestUpgrade:InvokeServer() end
                if Remote_UpgradeCandyPickaxe then Remote_UpgradeCandyPickaxe:InvokeServer() end
            end)
        end
    end
end)

----------------------------------------------------------------
-- INTERFACE WINDUI
----------------------------------------------------------------

local Window = WindUI:CreateWindow({
    Title = "ApxShouya Hub",
    Icon = "rbxassetid://4483345998",
    Author = "Anime Squadron",
    Folder = "ApxShouyaConfig",
    Size = UDim2.fromOffset(580, 380),
    Transparent = true,
    Theme = "Dark",
    SideBarWidth = 160,
    HasOutline = true
})

local Tabs = {
    Main = Window:Tab({ Title = "Farm", Icon = "pickaxe" }),
    Auto = Window:Tab({ Title = "Automações", Icon = "repeat" }),
    Visual = Window:Tab({ Title = "Desempenho", Icon = "zap" }),
    Settings = Window:Tab({ Title = "Configurações", Icon = "settings" })
}

-- Aba Farm
local FarmSec = Tabs.Main:Section({ Title = "Mineração por Zona" })

FarmSec:Dropdown({
    Title = "Selecionar Área de Farm",
    Desc = "Escolhe a zona e foca a mineração nela",
    Values = ZONE_NAMES,
    Value = "Mina 1 (HP 6)",
    Callback = function(chosenName)
        local zoneId = ZONE_DATA[chosenName]
        if zoneId then
            currentZoneId = zoneId
            teleportToZoneServer(zoneId)
        end
    end
})

FarmSec:Toggle({
    Title = "Auto Farm Inteligente",
    Desc = "Prioriza pedras especiais (+Sorte x10) e minera na zona",
    Value = false,
    Callback = function(state)
        autoFarmActive = state
    end
})

FarmSec:Toggle({
    Title = "Auto Vender Minérios",
    Desc = "Vende os minérios acumulados a cada 5 segundos",
    Value = false,
    Callback = function(state)
        autoSellActive = state
    end
})

-- Aba Automações
local AutoSec = Tabs.Auto:Section({ Title = "Recompensas & Melhorias" })

AutoSec:Toggle({
    Title = "Auto Recompensas (Todas)",
    Desc = "Resgata diários, missões, presentes e roleta",
    Value = false,
    Callback = function(state)
        autoRewardsActive = state
    end
})

AutoSec:Toggle({
    Title = "Auto Upgrades",
    Desc = "Compra melhorias e melhora a picareta de evento",
    Value = false,
    Callback = function(state)
        autoUpgradesActive = state
    end
})

AutoSec:Toggle({
    Title = "Auto Rebirth",
    Desc = "Executa o renascimento assim que estiver disponível",
    Value = false,
    Callback = function(state)
        autoRebirthActive = state
    end
})

-- Aba Desempenho
local VisualSec = Tabs.Visual:Section({ Title = "Otimização Gráfica" })

VisualSec:Button({
    Title = "Otimizar Gráficos (Potato FPS)",
    Desc = "Remove sombras e texturas pesadas",
    Callback = function()
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 9e9
        Lighting.Brightness = 2
        pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
        for _, v in ipairs(workspace:GetDescendants()) do
            if v:IsA("BasePart") then
                v.CastShadow = false
                v.Material = Enum.Material.SmoothPlastic
            elseif v:IsA("ParticleEmitter") or v:IsA("Trail") then
                v.Enabled = false
            end
        end
        WindUI:Notify({
            Title = "Desempenho",
            Content = "Gráficos otimizados com sucesso!",
            Duration = 3
        })
    end
})

-- Aba Configurações
local SettingsSec = Tabs.Settings:Section({ Title = "Aparência & Atalhos" })

SettingsSec:Dropdown({
    Title = "Mudar Tema",
    Desc = "Altera as cores da interface de forma animada",
    Values = { "Dark", "Light", "Rose", "Aqua", "Midnight" },
    Value = "Dark",
    Callback = function(themeName)
        WindUI:SetTheme(themeName)
    end
})

SettingsSec:Keybind({
    Title = "Tecla do Menu",
    Desc = "Abre e fecha a janela suavemente",
    Value = "RightShift",
    Callback = function()
        Window:Toggle()
    end
})

SettingsSec:Button({
    Title = "Descarregar Script (Unload)",
    Desc = "Fecha tudo, encerra loops e remove o botão flutuante",
    Callback = function()
        scriptRunning = false
        autoFarmActive = false
        autoSellActive = false
        autoRebirthActive = false
        autoRewardsActive = false
        autoUpgradesActive = false
        cleanupToggleGuis()
        pcall(function()
            Window:Destroy()
        end)
    end
})

----------------------------------------------------------------
-- BOTÃO FLUTUANTE COM EFEITO RGB
----------------------------------------------------------------
local ToggleGui = Instance.new("ScreenGui")
ToggleGui.Name = "ApxShouyaToggleGui"
ToggleGui.ResetOnSpawn = false
ToggleGui.Parent = CoreGui:FindFirstChild("RobloxGui") or CoreGui or LocalPlayer:WaitForChild("PlayerGui")

local FloatBtn = Instance.new("TextButton")
FloatBtn.Name = "FloatMenuBtn"
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0, 15, 0.5, -24)
FloatBtn.BackgroundColor3 = Color3.fromRGB(15, 17, 24)
FloatBtn.Text = "⚡"
FloatBtn.TextColor3 = Color3.fromRGB(255, 0, 0)
FloatBtn.TextSize = 22
FloatBtn.Font = Enum.Font.GothamBold
FloatBtn.Active = true
FloatBtn.Draggable = true
FloatBtn.Parent = ToggleGui

local Corner = Instance.new("UICorner", FloatBtn)
Corner.CornerRadius = UDim.new(1, 0)

local Stroke = Instance.new("UIStroke", FloatBtn)
Stroke.Color = Color3.fromRGB(255, 0, 0)
Stroke.Thickness = 2.2

FloatBtn.MouseButton1Click:Connect(function()
    Window:Toggle()
end)

-- Motor do RGB Cromático Contínuo com Checagem de Encerramento
task.spawn(function()
    local hue = 0
    while scriptRunning and FloatBtn and FloatBtn.Parent do
        task.wait(0.02)
        hue = (hue + 0.005) % 1
        local rgbColor = Color3.fromHSV(hue, 0.85, 1)
        if FloatBtn and FloatBtn.Parent then
            FloatBtn.TextColor3 = rgbColor
            Stroke.Color = rgbColor
        else
            break
        end
    end
end)