local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local Cash = Player:WaitForChild("leaderstats"):WaitForChild("Cash")

local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

local CanPlaceTower = RemoteFunctions:WaitForChild("CanPlaceTower")
local PlaceTower = RemoteFunctions:WaitForChild("PlaceTower")
local UpgradeTower = RemoteFunctions:WaitForChild("UpgradeTower")
local SellTower = RemoteFunctions:WaitForChild("SellTower")
local GetGameSpeedState = RemoteFunctions:WaitForChild("GetGameSpeedState")

local SetGameSpeed = RemoteEvents:WaitForChild("SetGameSpeed")
local ReplayVote = RemoteEvents:WaitForChild("ReplayVote")

local TowerConfig = require(
    ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TowerConfig")
)

local Towers = workspace:WaitForChild("Towers")

local Window = Rayfield:CreateWindow({
    Name = "Tower Utility V3",
    LoadingTitle = "Tower Utility",
    LoadingSubtitle = "V3",
    Theme = "Default",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "TowerUtilityV3",
        FileName = "Settings"
    },
    KeySystem = false
})

local MacroTab = Window:CreateTab("Macro", 4483362458)
local GameTab = Window:CreateTab("Game", 4483362458)

local function Notify(Title, Text)
    Rayfield:Notify({
        Title = Title,
        Content = Text,
        Duration = 2
    })
end

local FileSupport =
    type(writefile) == "function"
    and type(readfile) == "function"
    and type(isfile) == "function"

local function GetSlotFile(Slot)
    local Number = string.match(tostring(Slot), "%d+") or "1"
    return "TowerUtilityV3_MacroSlot" .. Number .. ".json"
end

local ResumeFile = "TowerUtilityV3_Resume.json"

local Recording = false
local Playing = false
local WaitForCash = true
local LoopMacro = false
local AutoStartMacro = false
local RecordStart = 0
local Events = {}
local TowerCounter = 0
local CurrentSlot = "Slot 1"

local RecordTowerByInstance = {}
local PendingPlacements = {}
local RuntimeTowers = {}
local InternalCall = false

local MaxRetries = 3
local RetryDelay = 0.35

local function GetStageKey()
    return {
        PlaceId = game.PlaceId,
        GameId = game.GameId
    }
end

local function StageMatches(Data)
    if type(Data) ~= "table" or type(Data.Stage) ~= "table" then
        return false
    end
    return tonumber(Data.Stage.PlaceId) == game.PlaceId
        and tonumber(Data.Stage.GameId) == game.GameId
end

local function CFrameToTable(CF)
    return {CF:GetComponents()}
end

local function TableToCFrame(Data)
    if type(Data) ~= "table" or #Data < 12 then
        return nil
    end
    return CFrame.new(table.unpack(Data))
end

local function SaveMacro(Silent)
    if not FileSupport then
        if not Silent then
            Notify("Macro", "Executor นี้ไม่รองรับการ Save File")
        end
        return false
    end

    local Serialized = {}

    for Index, Event in ipairs(Events) do
        local NewEvent = {
            Action = Event.Action,
            TowerID = Event.TowerID,
            Unit = Event.Unit,
            Time = Event.Time
        }

        if Event.CFrame then
            NewEvent.CFrame = CFrameToTable(Event.CFrame)
        end

        Serialized[Index] = NewEvent
    end

    local Data = {
        Version = 3,
        Stage = GetStageKey(),
        Slot = CurrentSlot,
        TowerCounter = TowerCounter,
        Events = Serialized
    }

    local Success = pcall(function()
        writefile(
            GetSlotFile(CurrentSlot),
            HttpService:JSONEncode(Data)
        )
    end)

    if not Silent then
        Notify(
            "Macro",
            Success and ("Save " .. CurrentSlot .. " สำเร็จ") or "Save Macro ไม่สำเร็จ"
        )
    end

    return Success
end

local function LoadMacro(Silent)
    if not FileSupport then
        if not Silent then
            Notify("Macro", "Executor นี้ไม่รองรับการ Load File")
        end
        return false
    end

    local File = GetSlotFile(CurrentSlot)

    if not isfile(File) then
        if not Silent then
            Notify("Macro", "ยังไม่มี Macro ใน " .. CurrentSlot)
        end
        return false
    end

    local Success, Result = pcall(function()
        return HttpService:JSONDecode(readfile(File))
    end)

    if not Success or type(Result) ~= "table" then
        if not Silent then
            Notify("Macro", "ไฟล์ Macro อ่านไม่ได้")
        end
        return false
    end

    if not StageMatches(Result) then
        if not Silent then
            Notify("Macro", "Macro นี้ไม่ได้อัดใน Place นี้")
        end
        return false
    end

    if type(Result.Events) ~= "table" then
        return false
    end

    local Loaded = {}
    local HighestID = 0

    for Index, Event in ipairs(Result.Events) do
        local NewEvent = {
            Action = Event.Action,
            TowerID = tonumber(Event.TowerID),
            Unit = Event.Unit,
            Time = tonumber(Event.Time) or 0
        }

        if Event.CFrame then
            NewEvent.CFrame = TableToCFrame(Event.CFrame)
        end

        Loaded[Index] = NewEvent

        if NewEvent.TowerID and NewEvent.TowerID > HighestID then
            HighestID = NewEvent.TowerID
        end
    end

    Events = Loaded
    TowerCounter = math.max(HighestID, tonumber(Result.TowerCounter) or 0)

    if not Silent then
        Notify(
            "Macro",
            "Load " .. CurrentSlot .. " | " .. tostring(#Events) .. " Events"
        )
    end

    return true
end

local function DeleteMacro()
    if not FileSupport or type(delfile) ~= "function" then
        Notify("Macro", "ไม่สามารถลบไฟล์ได้")
        return
    end

    local File = GetSlotFile(CurrentSlot)

    if isfile(File) then
        pcall(function()
            delfile(File)
        end)
    end

    Events = {}
    TowerCounter = 0
    Notify("Macro", "ลบ " .. CurrentSlot .. " แล้ว")
end

local function SaveResumeMarker()
    if not FileSupport then
        return
    end

    pcall(function()
        writefile(
            ResumeFile,
            HttpService:JSONEncode({
                Slot = CurrentSlot,
                PlaceId = game.PlaceId,
                Time = os.time()
            })
        )
    end)
end

local function GetResumeMarker()
    if not FileSupport or not isfile(ResumeFile) then
        return nil
    end

    local Success, Data = pcall(function()
        return HttpService:JSONDecode(readfile(ResumeFile))
    end)

    if not Success or type(Data) ~= "table" then
        return nil
    end

    return Data
end

local function ClearResumeMarker()
    if not FileSupport or type(delfile) ~= "function" then
        return
    end

    if isfile(ResumeFile) then
        pcall(function()
            delfile(ResumeFile)
        end)
    end
end

local function CurrentTime()
    return os.clock() - RecordStart
end

Towers.ChildAdded:Connect(function(Tower)
    if not Recording or #PendingPlacements == 0 then
        return
    end

    local Pivot
    local GotPivot = pcall(function()
        Pivot = Tower:GetPivot()
    end)

    local BestIndex = nil
    local BestDistance = math.huge

    for Index, Pending in ipairs(PendingPlacements) do
        if Tower.Name == Pending.Unit then
            local Distance = 0

            if GotPivot and Pending.CFrame then
                Distance = (Pivot.Position - Pending.CFrame.Position).Magnitude
            end

            if Distance < BestDistance then
                BestDistance = Distance
                BestIndex = Index
            end
        end
    end

    if not BestIndex then
        return
    end

    local Pending = table.remove(PendingPlacements, BestIndex)
    RecordTowerByInstance[Tower] = Pending.TowerID
end)

local OldNamecall

OldNamecall = hookmetamethod(
    game,
    "__namecall",
    newcclosure(function(self, ...)
        local Method = getnamecallmethod()

        if not Recording or InternalCall or Method ~= "InvokeServer" then
            return OldNamecall(self, ...)
        end

        local Args = {...}

        if self == PlaceTower then
            local Unit = Args[1]
            local CF = Args[2]

            if type(Unit) == "string" and typeof(CF) == "CFrame" then
                TowerCounter += 1
                local ID = TowerCounter

                Events[#Events + 1] = {
                    Action = "Place",
                    TowerID = ID,
                    Unit = Unit,
                    CFrame = CF,
                    Time = CurrentTime()
                }

                PendingPlacements[#PendingPlacements + 1] = {
                    TowerID = ID,
                    Unit = Unit,
                    CFrame = CF
                }
            end

            return OldNamecall(self, ...)
        end

        if self == UpgradeTower then
            local Tower = Args[1]
            local ID = RecordTowerByInstance[Tower]

            if ID then
                Events[#Events + 1] = {
                    Action = "Upgrade",
                    TowerID = ID,
                    Time = CurrentTime()
                }
            end

            return OldNamecall(self, ...)
        end

        if self == SellTower then
            local Tower = Args[1]
            local ID = RecordTowerByInstance[Tower]

            if ID then
                Events[#Events + 1] = {
                    Action = "Sell",
                    TowerID = ID,
                    Time = CurrentTime()
                }

                RecordTowerByInstance[Tower] = nil
            end

            return OldNamecall(self, ...)
        end

        return OldNamecall(self, ...)
    end)
)

local function GetPlacePrice(UnitName)
    local Success, Stats = pcall(function()
        return TowerConfig.getStats(UnitName, nil)
    end)

    if not Success or not Stats or typeof(Stats.Price) ~= "number" then
        return nil
    end

    return Stats.Price
end

local function GetTowerStats(Tower)
    if not Tower then
        return nil
    end

    local Success, Stats = pcall(function()
        local UnitName = TowerConfig.getUnitId(Tower)
        return TowerConfig.getStats(UnitName, Tower)
    end)

    if not Success then
        return nil
    end

    return Stats
end

local function GetUpgradePrice(Tower)
    local Stats = GetTowerStats(Tower)

    if not Stats or typeof(Stats.UpgradePrice) ~= "number" then
        return nil
    end

    return Stats.UpgradePrice
end

local function GetTowerLevel(Tower)
    local Stats = GetTowerStats(Tower)
    if not Stats then
        return nil
    end
    return tonumber(Stats.Level)
end

local function WaitUntilCash(Amount)
    if not WaitForCash or typeof(Amount) ~= "number" then
        return true
    end

    while Playing and Cash.Value < Amount do
        task.wait(0.1)
    end

    return Playing
end

local function WaitGameReady(Timeout)
    Timeout = Timeout or 30
    local Start = os.clock()

    while os.clock() - Start < Timeout do
        if not game:IsLoaded()
        or not Cash.Parent
        or not Towers.Parent
        or not PlaceTower.Parent
        or not UpgradeTower.Parent
        or not SellTower.Parent then

            task.wait(0.25)
        else
            task.wait(1)
            return true
        end
    end

    return false
end

local function WaitForPlacedTower(UnitName, CF, Timeout)
    Timeout = Timeout or 3

    local Found = nil
    local Connection

    Connection = Towers.ChildAdded:Connect(function(Tower)
        if Found or Tower.Name ~= UnitName then
            return
        end

        local Pivot
        local Success = pcall(function()
            Pivot = Tower:GetPivot()
        end)

        if not Success then
            Found = Tower
            return
        end

        if (Pivot.Position - CF.Position).Magnitude <= 8 then
            Found = Tower
        end
    end)

    return function()
        local Start = os.clock()

        while Playing and not Found and os.clock() - Start < Timeout do
            task.wait()
        end

        Connection:Disconnect()
        return Found
    end
end

local function PlaybackPlace(Event)
    if not WaitUntilCash(GetPlacePrice(Event.Unit)) then
        return false
    end

    for Attempt = 1, MaxRetries do
        if not Playing then
            return false
        end

        local FinishWaiting = WaitForPlacedTower(
            Event.Unit,
            Event.CFrame,
            3
        )

        InternalCall = true
        pcall(function()
            CanPlaceTower:InvokeServer(Event.Unit)
        end)
        InternalCall = false

        InternalCall = true
        local Success = pcall(function()
            PlaceTower:InvokeServer(
                Event.Unit,
                Event.CFrame
            )
        end)
        InternalCall = false

        if Success then
            local NewTower = FinishWaiting()

            if NewTower and NewTower.Parent then
                RuntimeTowers[Event.TowerID] = NewTower
                return true
            end
        else
            FinishWaiting()
        end

        if Attempt < MaxRetries then
            task.wait(RetryDelay)
        end
    end

    return false
end

local function PlaybackUpgrade(Event)
    local Tower = RuntimeTowers[Event.TowerID]

    if not Tower or not Tower.Parent then
        return false
    end

    if not WaitUntilCash(GetUpgradePrice(Tower)) then
        return false
    end

    for Attempt = 1, MaxRetries do
        if not Playing or not Tower.Parent then
            return false
        end

        local BeforeLevel = GetTowerLevel(Tower)
        local BeforePrice = GetUpgradePrice(Tower)

        InternalCall = true
        local Success = pcall(function()
            UpgradeTower:InvokeServer(Tower)
        end)
        InternalCall = false

        if Success then
            local Start = os.clock()

            while Playing and os.clock() - Start < 1.5 do
                if not Tower.Parent then
                    break
                end

                local AfterLevel = GetTowerLevel(Tower)
                local AfterPrice = GetUpgradePrice(Tower)

                if (BeforeLevel and AfterLevel and AfterLevel > BeforeLevel)
                or (BeforePrice and AfterPrice and AfterPrice ~= BeforePrice) then
                    return true
                end

                task.wait(0.1)
            end
        end

        if not WaitUntilCash(GetUpgradePrice(Tower)) then
            return false
        end

        if Attempt < MaxRetries then
            task.wait(RetryDelay)
        end
    end

    return false
end

local function PlaybackSell(Event)
    local Tower = RuntimeTowers[Event.TowerID]

    if not Tower then
        return false
    end

    for Attempt = 1, MaxRetries do
        if not Playing then
            return false
        end

        if not Tower.Parent then
            RuntimeTowers[Event.TowerID] = nil
            return true
        end

        InternalCall = true
        local Success = pcall(function()
            SellTower:InvokeServer(Tower)
        end)
        InternalCall = false

        if Success then
            local Start = os.clock()

            while os.clock() - Start < 1.5 do
                if not Tower.Parent
                or not Tower:IsDescendantOf(Towers) then

                    RuntimeTowers[Event.TowerID] = nil
                    return true
                end

                task.wait(0.1)
            end
        end

        if Attempt < MaxRetries then
            task.wait(RetryDelay)
        end
    end

    return false
end

local function MacroFailure(Index, Event)
    Playing = false
    Notify(
        "Macro Error",
        tostring(Event.Action)
        .. " ล้มเหลวที่ Event #"
        .. tostring(Index)
    )
end

local function PlayOnce()
    RuntimeTowers = {}
    local StartTime = os.clock()

    for Index, Event in ipairs(Events) do
        if not Playing then
            return false
        end

        local TargetTime = tonumber(Event.Time) or 0

        while Playing and os.clock() - StartTime < TargetTime do
            task.wait()
        end

        if not Playing then
            return false
        end

        local Success = true

        if Event.Action == "Place" then
            Success = PlaybackPlace(Event)
        elseif Event.Action == "Upgrade" then
            Success = PlaybackUpgrade(Event)
        elseif Event.Action == "Sell" then
            Success = PlaybackSell(Event)
        end

        if not Success then
            MacroFailure(Index, Event)
            return false
        end
    end

    return true
end

local function StartMacro(Silent)
    if Recording or Playing then
        return false
    end

    if #Events == 0 then
        if not Silent then
            Notify("Macro", "ยังไม่มี Macro")
        end
        return false
    end

    if not WaitGameReady(30) then
        if not Silent then
            Notify("Macro", "เกมยังไม่พร้อม")
        end
        return false
    end

    Playing = true

    task.spawn(function()
        repeat
            local Success = PlayOnce()

            if not Success then
                break
            end

            if Playing and LoopMacro then
                task.wait(1)
            end

        until not Playing or not LoopMacro

        Playing = false
    end)

    if not Silent then
        Notify("Macro", "เริ่มเล่น " .. CurrentSlot)
    end

    return true
end

MacroTab:CreateSection("Macro Slot")

local SlotDropdown = MacroTab:CreateDropdown({
    Name = "Select Macro Slot",
    Options = {"Slot 1", "Slot 2", "Slot 3"},
    CurrentOption = {"Slot 1"},
    MultipleOptions = false,
    Flag = "MacroSlot",

    Callback = function(Options)
        if type(Options) == "table" and Options[1] then
            CurrentSlot = Options[1]

            if not Recording and not Playing then
                LoadMacro(true)
            end
        end
    end
})

MacroTab:CreateSection("Recording")

MacroTab:CreateButton({
    Name = "Record Macro",

    Callback = function()
        if Playing then
            Notify("Macro", "หยุด Macro ก่อน")
            return
        end

        Events = {}
        TowerCounter = 0
        RecordTowerByInstance = {}
        PendingPlacements = {}
        RuntimeTowers = {}
        RecordStart = os.clock()
        Recording = true

        Notify("Macro", "เริ่ม Record " .. CurrentSlot)
    end
})

MacroTab:CreateButton({
    Name = "Stop & Save",

    Callback = function()
        if not Recording then
            Notify("Macro", "ไม่ได้ Record อยู่")
            return
        end

        Recording = false
        PendingPlacements = {}

        local Saved = SaveMacro(true)

        if Saved then
            Notify(
                "Macro",
                "บันทึก "
                .. tostring(#Events)
                .. " Events ลง "
                .. CurrentSlot
            )
        else
            Notify(
                "Macro",
                "หยุด Record | "
                .. tostring(#Events)
                .. " Events"
            )
        end
    end
})

MacroTab:CreateSection("Playback")

MacroTab:CreateButton({
    Name = "Play Macro",
    Callback = function()
        StartMacro(false)
    end
})

MacroTab:CreateButton({
    Name = "Stop Macro",
    Callback = function()
        Playing = false
        Notify("Macro", "หยุด Macro แล้ว")
    end
})

MacroTab:CreateToggle({
    Name = "Auto Start Macro",
    CurrentValue = false,
    Flag = "AutoStartMacro",
    Callback = function(Value)
        AutoStartMacro = Value
    end
})

MacroTab:CreateToggle({
    Name = "Wait For Cash",
    CurrentValue = true,
    Flag = "WaitForCash",
    Callback = function(Value)
        WaitForCash = Value
    end
})

MacroTab:CreateToggle({
    Name = "Loop Macro",
    CurrentValue = false,
    Flag = "LoopMacro",
    Callback = function(Value)
        LoopMacro = Value
    end
})

MacroTab:CreateSection("Saved Macro")

MacroTab:CreateButton({
    Name = "Load Macro",
    Callback = function()
        LoadMacro(false)
    end
})

MacroTab:CreateButton({
    Name = "Save Macro",
    Callback = function()
        SaveMacro(false)
    end
})

MacroTab:CreateButton({
    Name = "Clear Current Macro",
    Callback = function()
        Recording = false
        Playing = false
        Events = {}
        TowerCounter = 0
        RecordTowerByInstance = {}
        PendingPlacements = {}
        RuntimeTowers = {}

        Notify("Macro", "ล้าง Macro ในหน่วยความจำแล้ว")
    end
})

MacroTab:CreateButton({
    Name = "Delete Saved Slot",
    Callback = function()
        Recording = false
        Playing = false
        DeleteMacro()
    end
})

local AutoSpeed = false
local AutoReplay = false
local SpeedWorkerID = 0
local ReplayCooldown = false

local function GetSpeedState()
    local Success, State = pcall(function()
        return GetGameSpeedState:InvokeServer()
    end)

    if not Success or type(State) ~= "table" then
        return nil
    end

    return State
end

local function GetBestSpeed(State)
    local MaxSpeed = tonumber(State.MaxSpeed) or 1
    local BestSpeed = 1

    if type(State.Options) == "table" and #State.Options > 0 then
        for _, Value in ipairs(State.Options) do
            local Speed = tonumber(Value)

            if Speed
            and Speed <= MaxSpeed + 0.001
            and Speed > BestSpeed then

                BestSpeed = Speed
            end
        end
    else
        if MaxSpeed >= 2 then
            BestSpeed = 2
        elseif MaxSpeed >= 1.5 then
            BestSpeed = 1.5
        else
            BestSpeed = 1
        end
    end

    return BestSpeed
end

local function SetMaximumSpeed()
    local State = GetSpeedState()

    if not State then
        return false
    end

    local Current = tonumber(State.Speed) or 1
    local Best = GetBestSpeed(State)

    if math.abs(Current - Best) < 0.001 then
        return true
    end

    return pcall(function()
        SetGameSpeed:FireServer(Best)
    end)
end

GameTab:CreateSection("Game Speed")

GameTab:CreateToggle({
    Name = "Auto Max Speed",
    CurrentValue = false,
    Flag = "AutoMaxSpeed",

    Callback = function(Value)
        AutoSpeed = Value
        SpeedWorkerID += 1

        local WorkerID = SpeedWorkerID

        if Value then
            task.spawn(function()
                SetMaximumSpeed()

                while AutoSpeed and WorkerID == SpeedWorkerID do
                    task.wait(3)

                    if not AutoSpeed or WorkerID ~= SpeedWorkerID then
                        break
                    end

                    SetMaximumSpeed()
                end
            end)
        end
    end
})

local function SendReplay()
    return pcall(function()
        ReplayVote:FireServer()
    end)
end

local function TryAutoReplay()
    if not AutoReplay or ReplayCooldown then
        return false
    end

    ReplayCooldown = true
    SaveResumeMarker()

    local Success = SendReplay()

    task.delay(4, function()
        ReplayCooldown = false
    end)

    return Success
end

local EndKeywords = {
    "replay",
    "victory",
    "defeat",
    "result",
    "results",
    "gameover",
    "game over",
    "playagain",
    "play again",
    "endgame",
    "end game"
}

local function ContainsEndKeyword(Text)
    if type(Text) ~= "string" then
        return false
    end

    Text = string.lower(Text)

    for _, Keyword in ipairs(EndKeywords) do
        if string.find(Text, Keyword, 1, true) then
            return true
        end
    end

    return false
end

local function LooksLikeEndGameGui(Object)
    if not Object:IsA("GuiObject") or not Object.Visible then
        return false
    end

    if ContainsEndKeyword(Object.Name) then
        return true
    end

    if Object:IsA("TextLabel")
    or Object:IsA("TextButton")
    or Object:IsA("TextBox") then

        local Success, Text = pcall(function()
            return Object.Text
        end)

        if Success and ContainsEndKeyword(Text) then
            return true
        end
    end

    return false
end

local function CheckForEndGame()
    if not AutoReplay then
        return false
    end

    for _, Object in ipairs(PlayerGui:GetDescendants()) do
        if LooksLikeEndGameGui(Object) then
            TryAutoReplay()
            return true
        end
    end

    return false
end

local WatchedObjects = {}

local function WatchGuiObject(Object)
    if WatchedObjects[Object] or not Object:IsA("GuiObject") then
        return
    end

    WatchedObjects[Object] = true

    Object:GetPropertyChangedSignal("Visible"):Connect(function()
        if not AutoReplay or not Object.Visible then
            return
        end

        if LooksLikeEndGameGui(Object) then
            task.delay(0.5, function()
                if AutoReplay then
                    TryAutoReplay()
                end
            end)
        end
    end)
end

for _, Object in ipairs(PlayerGui:GetDescendants()) do
    WatchGuiObject(Object)
end

PlayerGui.DescendantAdded:Connect(function(Object)
    WatchGuiObject(Object)

    task.defer(function()
        if AutoReplay and LooksLikeEndGameGui(Object) then
            task.wait(0.5)
            TryAutoReplay()
        end
    end)
end)

task.spawn(function()
    while true do
        if AutoReplay then
            CheckForEndGame()
        end

        task.wait(1)
    end
end)

GameTab:CreateSection("Replay")

GameTab:CreateToggle({
    Name = "Auto Replay",
    CurrentValue = false,
    Flag = "AutoReplay",

    Callback = function(Value)
        AutoReplay = Value
        ReplayCooldown = false

        if Value then
            task.defer(function()
                task.wait(0.3)
                CheckForEndGame()
            end)
        end
    end
})

GameTab:CreateButton({
    Name = "Replay Now",
    Callback = function()
        ReplayCooldown = false
        SaveResumeMarker()
        SendReplay()
    end
})

Rayfield:LoadConfiguration()

task.defer(function()
    task.wait(0.5)
    LoadMacro(true)
end)

task.spawn(function()
    task.wait(2)

    local Resume = GetResumeMarker()

    local ShouldResume =
        Resume
        and tonumber(Resume.PlaceId) == game.PlaceId

    if ShouldResume and type(Resume.Slot) == "string" then
        CurrentSlot = Resume.Slot

        pcall(function()
            SlotDropdown:Set({CurrentSlot})
        end)

        LoadMacro(true)
    end

    if AutoStartMacro or ShouldResume then
        if WaitGameReady(30) then
            task.wait(1)

            if #Events > 0 then
                StartMacro(true)
            end
        end
    end

    if ShouldResume then
        ClearResumeMarker()
    end
end)

Notify("Tower Utility V3", "Loaded")
