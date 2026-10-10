program AudioEditor;

{ Pseudo 3D Road - audio editor.
  Opens data\audio.ini, lets you change every value with sliders and
  hear the result straight away in a test drive (engine, gears, grass,
  kerb, crash, music). Save writes data\audio.ini.

  Keys: Up/W gas, Down/S brake, G grass, K kerb, X crash, N music,
        M muted-in-game setting, F2 save, F5 reload, Esc quit }

{$mode objfpc}{$H+}
{$POINTERMATH ON}
{$APPTYPE GUI}

uses
  SysUtils, Math, SDL3, p3d_common, p3d_audio, p3d_gui;

const
  WinW = 1024;
  WinH = 660;

var
  Win: PSDL_Window = nil;
  Ren: PSDL_Renderer = nil;
  Speed, MaxSpeed: Double;
  Gas, Brake, Grass, Kerb: Boolean;
  KeyGas, KeyBrake: Boolean;
  CrashPower: Double = 0.6;
  Status: string = '';
  StatusTime: Double = 0;
  Dirty: Boolean = False;

procedure SetStatus(const s: string);
begin
  Status := s;
  StatusTime := 4;
end;

procedure DoSave;
begin
  try
    FixupData;
    SaveAudio(DataDir + 'audio.ini');
    Dirty := False;
    SetStatus('Saved data\audio.ini');
  except
    on E: Exception do SetStatus('Could not save: ' + E.Message);
  end;
end;

procedure DoReload;
begin
  SetDefaultAudio;
  try
    if FileExists(DataDir + 'audio.ini') then LoadAudio(DataDir + 'audio.ini');
  except
  end;
  FixupData;
  Dirty := False;
  SetStatus('Reloaded data\audio.ini');
end;

procedure DoDefaults;
begin
  SetDefaultAudio;
  Dirty := True;
  SetStatus('Built-in defaults restored (not saved yet)');
end;

procedure UpdateSim(dt: Double);
begin
  Gas := Gas or KeyGas;
  Brake := Brake or KeyBrake;
  if Gas then Speed := Speed + MaxSpeed / 5 * dt
  else if Brake then Speed := Speed - MaxSpeed * dt
  else Speed := Speed - MaxSpeed / 5 * dt;
  if Grass and (Speed > MaxSpeed / 4) then Speed := Speed - MaxSpeed / 2 * dt;
  Speed := ClampD(Speed, 0, MaxSpeed);
  UpdateEngine(dt, Speed / MaxSpeed, Gas, Grass);
end;

procedure DrawScope(x, y, w, h: Single);
var
  pts: array[0..1023] of TSDL_FPoint;
  i, n: Integer;
begin
  GuiColor(10, 12, 16);
  GuiFill(x, y, w, h);
  GuiColor(40, 46, 58);
  GuiFill(x, y + h / 2, w, 1);
  n := Length(Scope);
  for i := 0 to n - 1 do
  begin
    pts[i].x := x + i * w / n;
    pts[i].y := y + h / 2 - Scope[(ScopePos + i) mod n] * h / 2;
  end;
  GuiColor(90, 220, 120);
  SDL_RenderLines(Ren, @pts[0], n);
  GuiColor(70, 78, 92);
  GuiFrame(x, y, w, h);
end;

procedure DrawBar(x, y, w, h, frac: Single; r, g, b: Byte);
begin
  GuiColor(40, 45, 56);
  GuiFill(x, y, w, h);
  GuiColor(r, g, b);
  GuiFill(x, y, w * ClampD(frac, 0, 1), h);
  GuiColor(90, 100, 120);
  GuiFrame(x, y, w, h);
end;

procedure DrawUI;
var
  y, lo, hi, v: Double;
  i, n: Integer;
  bx, by: Single;
  rpmPct: Double;
begin
  GuiColor(16, 18, 24);
  GuiFill(0, 0, WinW, WinH);
  GuiText(16, 14, 'AUDIO EDITOR', 2, 255, 210, 80);
  GuiText(230, 20, DataDir + 'audio.ini');
  if Dirty then GuiText(WinW - 150, 20, '* not saved', 1, 255, 140, 90);

  // ---------------- settings
  GuiPanel(16, 50, 470, 548, 'Settings');
  y := 90;
  if GuiSlider(36, y, 430, 'Master volume', MasterVolume, 0, 2, 2) then Dirty := True;
  y := y + 40;
  if GuiSlider(36, y, 430, 'Engine volume', EngineVolume, 0, 2, 2) then Dirty := True;
  y := y + 40;
  if GuiSlider(36, y, 430, 'Ground (grass/kerb) volume', GroundVolume, 0, 2, 2) then Dirty := True;
  y := y + 40;
  if GuiSlider(36, y, 430, 'Crash volume', CrashVolume, 0, 2, 2) then Dirty := True;
  y := y + 40;
  if GuiSlider(36, y, 430, 'Idle RPM', IdleRPM, 300, 3000, 0) then Dirty := True;
  y := y + 40;
  if GuiSlider(36, y, 430, 'Max RPM', MaxRPM, IdleRPM + 1000, 15000, 0) then Dirty := True;
  y := y + 46;

  GuiText(36, y, 'Gears - top of each gear (fraction of top speed)', 1, 255, 210, 80);
  y := y + 18;
  n := Length(GearTops);
  for i := 0 to n - 2 do
  begin
    if i = 0 then lo := 0.02 else lo := GearTops[i - 1] + 0.01;
    hi := GearTops[i + 1] - 0.01;
    v := GearTops[i];
    if GuiSlider(36, y, 430, 'Gear ' + IntToStr(i + 1), v, lo, MaxD(hi, lo + 0.01), 2) then
    begin
      GearTops[i] := v;
      Dirty := True;
    end;
    y := y + 34;
  end;
  GuiText(36, y + 2, 'Gear ' + IntToStr(n) + '   1.00  (top speed)', 1, 170, 175, 190);
  y := y + 20;

  if GuiButton(36, y, 120, 24, '+ gear') and (n < 8) then
  begin
    SetLength(GearTops, n + 1);
    GearTops[n] := 1;
    if n >= 2 then GearTops[n - 1] := (GearTops[n - 2] + 1) / 2
    else GearTops[n - 1] := 0.5;
    Dirty := True;
  end;
  if GuiButton(166, y, 120, 24, '- gear') and (n > 1) then
  begin
    GearTops[n - 2] := 1;
    SetLength(GearTops, n - 1);
    Dirty := True;
  end;
  if GuiButton(296, y, 170, 24, 'Muted in game', Muted) then
  begin
    Muted := not Muted;
    Dirty := True;
  end;

  // ---------------- test drive
  GuiPanel(500, 50, 508, 548, 'Test drive');
  rpmPct := EngineRPM / MaxRPM;
  GuiText(520, 92, Format('%3d km/h', [Round(Speed / MaxSpeed * 240)]), 3, 255, 255, 255);
  GuiText(760, 92, Format('GEAR %d', [Gear]), 3, 255, 210, 80);
  GuiText(520, 132, Format('%5d RPM', [Round(EngineRPM)]), 2, 200, 220, 255);
  DrawBar(520, 156, 468, 18, rpmPct, 230, 170, 40);
  DrawBar(520, 180, 468, 8, Speed / MaxSpeed, 90, 200, 120);

  bx := 520; by := 204;
  Gas := GuiInside(bx, by, 150, 60) and MouseDown;
  GuiButton(bx, by, 150, 60, 'GAS (hold)', Gas or KeyGas);
  Brake := GuiInside(bx + 160, by, 150, 60) and MouseDown;
  GuiButton(bx + 160, by, 150, 60, 'BRAKE (hold)', Brake or KeyBrake);
  if GuiButton(bx + 320, by, 148, 60, 'CRASH!') then TriggerImpact(CrashPower);

  by := by + 72;
  if GuiButton(bx, by, 150, 28, 'On grass', Grass) then Grass := not Grass;
  if GuiButton(bx + 160, by, 150, 28, 'On kerb', Kerb) then Kerb := not Kerb;
  if GuiButton(bx + 320, by, 148, 28, 'Music', MusicOn) then MusicOn := not MusicOn;
  by := by + 40;
  GuiSlider(bx, by, 468, 'Crash strength', CrashPower, 0, 1, 2);
  by := by + 44;
  GuiText(bx, by, 'Output');
  DrawScope(bx, by + 14, 468, 150);
  by := by + 176;
  GuiText(bx, by, 'Keys: Up/W gas  Down/S brake  G grass  K kerb  X crash', 1, 170, 175, 190);
  GuiText(bx, by + 14, '      N music  M muted-in-game  F2 save  F5 reload', 1, 170, 175, 190);

  // ---------------- bottom bar
  if GuiButton(16, 612, 120, 32, 'Save (F2)') then DoSave;
  if GuiButton(146, 612, 120, 32, 'Reload (F5)') then DoReload;
  if GuiButton(276, 612, 120, 32, 'Defaults') then DoDefaults;
  if StatusTime > 0 then GuiText(420, 624, Status, 1, 255, 220, 120);
end;

var
  Ev: TSDL_Event;
  Keys: PBoolean;
  Running: Boolean;
  Freq, LastTick, NowTick: UInt64;
  FrameTime, Acc: Double;
  sc: TSDL_Scancode;
  WasMuted: Boolean;

begin
  Randomize;
  InitCommon;
  LoadAllData(False);
  MaxSpeed := SegLen / StepTime;

  if not SDL_Init(SDL_INIT_VIDEO) then Halt(1);
  if not SDL_CreateWindowAndRenderer('Pseudo 3D Road - Audio editor', WinW, WinH, 0, @Win, @Ren) then
  begin
    SDL_Quit;
    Halt(1);
  end;
  SDL_SetRenderVSync(Ren, 1);
  SDL_SetRenderDrawBlendMode(Ren, SDL_BLENDMODE_BLEND);
  GuiRen := Ren;

  MusicOn := False;               // music only when switched on here
  InitAudio;
  ResetMusic;

  Freq := SDL_GetPerformanceFrequency;
  LastTick := SDL_GetPerformanceCounter;
  Acc := 0;
  Running := True;
  while Running do
  begin
    GuiBeginFrame;
    while SDL_PollEvent(@Ev) do
    begin
      GuiEvent(Ev);
      if Ev._type = SDL_EVENT_QUIT then Running := False
      else if Ev._type = SDL_EVENT_KEY_DOWN then
      begin
        sc := Ev.key.scancode;
        if sc = SDL_SCANCODE_ESCAPE then Running := False
        else if sc = SDL_SCANCODE_G then Grass := not Grass
        else if sc = SDL_SCANCODE_K then Kerb := not Kerb
        else if sc = SDL_SCANCODE_X then TriggerImpact(CrashPower)
        else if sc = SDL_SCANCODE_N then MusicOn := not MusicOn
        else if sc = SDL_SCANCODE_M then
        begin
          Muted := not Muted;
          Dirty := True;
        end
        else if sc = SDL_SCANCODE_F2 then DoSave
        else if sc = SDL_SCANCODE_F5 then DoReload;
      end;
    end;

    Keys := SDL_GetKeyboardState(nil);
    KeyGas := Keys[Ord(SDL_SCANCODE_UP)] or Keys[Ord(SDL_SCANCODE_W)];
    KeyBrake := Keys[Ord(SDL_SCANCODE_DOWN)] or Keys[Ord(SDL_SCANCODE_S)];

    NowTick := SDL_GetPerformanceCounter;
    FrameTime := (NowTick - LastTick) / Freq;
    LastTick := NowTick;
    if FrameTime > 0.25 then FrameTime := 0.25;
    if StatusTime > 0 then StatusTime := StatusTime - FrameTime;

    SDL_SetRenderDrawColor(Ren, 0, 0, 0, 255);
    SDL_RenderClear(Ren);
    DrawUI;                       // reads the GAS / BRAKE buttons

    Acc := Acc + FrameTime;
    while Acc >= StepTime do
    begin
      UpdateSim(StepTime);
      Acc := Acc - StepTime;
    end;
    // the "muted" setting is for the game - the editor always plays
    WasMuted := Muted;
    Muted := False;
    FeedAudio(Speed / MaxSpeed, Grass, Kerb and not Grass);
    Muted := WasMuted;

    SDL_RenderPresent(Ren);
  end;

  CloseAudio;
  SDL_DestroyRenderer(Ren);
  SDL_DestroyWindow(Win);
  SDL_Quit;
end.
