program PseudoRoad;

{ Pseudo 3D Road racer - Lazarus / Free Pascal + SDL3 (sechshelme binding)
  Shared units: p3d_common (data files), p3d_world (road, models, scenery),
  p3d_audio (sound). Everything you can change lives in the "data" folder:
  ini files, track.txt, models\*.car, shapes\*.shape, bitmaps\*.bmp.

  Controls: Arrows / WASD = drive, R = reset, C = camera menu,
            F5 = reload data files, F6 = next season, F7 = day / night,
            M = mute, N = music, Esc = quit }

{$mode objfpc}{$H+}
{$POINTERMATH ON}
{$APPTYPE GUI}

uses
  SysUtils, Math, SDL3, p3d_common, p3d_world, p3d_audio;

const
  Centrifugal = 0.3;
  SkySpeed    = 0.001;
  HillSpeed   = 0.002;

  MapSize = 186;
  MapX    = ScreenW - MapSize - 10;
  MapY    = 50;

  MirrorW = 340;
  MirrorH = 110;
  MirrorX = (ScreenW - MirrorW) div 2;
  MirrorY = 54;

  MenuCount = 13;
  MenuValues = 8;                // rows 0..7 are changed with Left/Right
  MenuNames: array[0..MenuCount - 1] of string = (
    'Height', 'Distance', 'Side offset', 'Pitch (+ down)', 'Yaw (+ right)',
    'Field of view', 'Season', 'Time of day', 'Save camera', 'Load saved camera', 'Load default camera',
    'Reload data files', 'Close menu');

type
  TParticle = record
    x, y, vx, vy, life, maxLife, size, grow, gravity: Double;
    col: TRGB;
    spark: Boolean;
  end;

var
  Win: PSDL_Window = nil;
  MirrorTex: PSDL_Texture = nil;

  Position, PlayerX, Speed, SteerAnim: Double;
  PlayerW, PlayerHit: Double;
  MaxSpeed, AccelRate, Breaking, Decel, OffRoadDecel, OffRoadLimit: Double;
  CurLap, LastLap, BestLap: Double;
  KeyLeft, KeyRight, KeyFaster, KeySlower: Boolean;
  RaceStarted: Boolean;

  Particles: array[0..299] of TParticle;
  ShakeTime, ShakeAmp, CrashCooldown: Double;

  MenuOpen: Boolean;
  MenuSel: Integer;
  MenuMsg: string;
  MenuMsgTime: Double;

{ ------------------------------------------------------------- effects }

procedure SpawnParticle(x, y, vx, vy, life, size, grow, gravity: Double;
                        const col: TRGB; spark: Boolean);
var
  i: Integer;
begin
  for i := 0 to High(Particles) do
    if Particles[i].life <= 0 then
    begin
      Particles[i].x := x;       Particles[i].y := y;
      Particles[i].vx := vx;     Particles[i].vy := vy;
      Particles[i].life := life; Particles[i].maxLife := life;
      Particles[i].size := size; Particles[i].grow := grow;
      Particles[i].gravity := gravity;
      Particles[i].col := col;
      Particles[i].spark := spark;
      Exit;
    end;
end;

procedure SpawnSparks(x, y: Double; count: Integer);
var
  i: Integer;
begin
  for i := 1 to count do
    SpawnParticle(x + (Random - 0.5) * 60, y + (Random - 0.5) * 20,
                  (Random - 0.5) * 700, -(150 + Random * 400),
                  0.3 + Random * 0.4, 2 + Random * 3, 0, 1200,
                  MakeRGB(255, 180 + Random(75), 60), True);
end;

procedure SpawnDust(x, y: Double; count: Integer);
var
  i, v: Integer;
begin
  for i := 1 to count do
  begin
    v := Random(30);
    SpawnParticle(x + (Random - 0.5) * 30, y - Random * 10,
                  (Random - 0.5) * 160, -(30 + Random * 90),
                  0.4 + Random * 0.5, 8 + Random * 14, 50 + Random * 40, -20,
                  MakeRGB(135 + v, 110 + v, 75 + v), False);
  end;
end;

procedure UpdateParticles(dt: Double);
var
  i: Integer;
begin
  for i := 0 to High(Particles) do
    if Particles[i].life > 0 then
    begin
      Particles[i].life := Particles[i].life - dt;
      Particles[i].x := Particles[i].x + Particles[i].vx * dt;
      Particles[i].y := Particles[i].y + Particles[i].vy * dt;
      Particles[i].vy := Particles[i].vy + Particles[i].gravity * dt;
      Particles[i].size := Particles[i].size + Particles[i].grow * dt;
    end;
end;

procedure DrawParticles(sparks: Boolean);
var
  i: Integer;
  a: Double;
begin
  for i := 0 to High(Particles) do
    if (Particles[i].life > 0) and (Particles[i].spark = sparks) then
    begin
      a := Particles[i].life / Particles[i].maxLife;
      if sparks then
      begin
        SetCol(Particles[i].col, Round(255 * a));
        FillR(Particles[i].x - Particles[i].size / 2, Particles[i].y - Particles[i].size / 2,
              Particles[i].size, Particles[i].size);
      end
      else
      begin
        SetCol(Particles[i].col, Round(150 * a));
        FillEllipse(Particles[i].x, Particles[i].y, Particles[i].size, Particles[i].size * 0.7);
      end;
    end;
end;

procedure DrawDust;
begin
  DrawParticles(False);
end;

procedure DrawSparks;
begin
  DrawParticles(True);
end;

procedure Crash(strength, sparkY: Double);
begin
  SpawnSparks(PlayerSX, sparkY, 10 + Round(20 * strength));
  if CrashCooldown > 0 then Exit;
  CrashCooldown := 0.5;
  TriggerImpact(strength);
  ShakeTime := 0.25 + 0.2 * strength;
  ShakeAmp := 4 + 10 * strength;
end;

{ ----------------------------------------------------------------- game }

procedure ApplyPlayerModel;
begin
  if (PlayerModel >= 0) and (PlayerModel < Length(Models)) then
  begin
    PlayerW := Models[PlayerModel].width / RoadWidth;
    PlayerHit := Models[PlayerModel].hit;
  end
  else
  begin
    PlayerW := 0.32;
    PlayerHit := 320;
  end;
end;

procedure ResetGame;
var
  i: Integer;
begin
  Position := 0;
  PlayerX := 0;
  Speed := 0;
  SteerAnim := 0;
  CurLap := 0;
  LastLap := 0;
  RaceStarted := False;
  SkyOffset := 0;
  HillOffset := 0;
  EngineRPM := IdleRPM;
  EngineLoad := 0;
  ShakeTime := 0;
  CrashCooldown := 0;
  for i := 0 to High(Particles) do Particles[i].life := 0;
  ApplyPlayerModel;
  ResetTraffic(MaxSpeed);
end;

procedure ReloadData;
begin
  LoadAllData(False);
  ReloadWorldGraphics;
  BuildTrackFromFile(0);
  ResetGame;
  ResetMusic;
end;

procedure UpdateCars(dt: Double);
var
  i: Integer;
  d, dir, pz, oldOff, latVel, strength: Double;
  C: PCar;
begin
  pz := Increase(Position, PlayerZ, TrackLength);
  for i := 0 to High(Cars) do
  begin
    C := @Cars[i];
    oldOff := C^.offset;
    d := WrapDist(C^.z - pz);      // > 0: car ahead of us, < 0: behind us

    if (d > 0) and (d < 20 * SegLen) and (Speed > C^.speed) and
       Overlap(PlayerX, PlayerW, C^.offset, C^.w, 1.5) then
    begin
      // we are catching up: it moves aside
      if C^.offset >= PlayerX then dir := 1 else dir := -1;
      C^.offset := ClampD(C^.offset + dir * dt * 1.2 * (1 - d / (20 * SegLen)), -0.9, 0.9);
    end
    else if (d < 0) and (-d < C^.look + C^.hit) and (C^.speed > Speed) and
            Overlap(PlayerX, PlayerW, C^.offset, C^.w, 1.3) then
    begin
      // it is catching up with us: brake and try to pull out to pass
      C^.speed := MaxD(Speed * 0.92, C^.speed - C^.brake * dt);
      if C^.offset >= PlayerX then dir := 1 else dir := -1;
      if Abs(C^.offset + dir * 0.3) > 0.9 then dir := -dir;
      C^.offset := ClampD(C^.offset + dir * dt * 0.7, -0.9, 0.9);
    end
    else if C^.speed < C^.cruise then
      C^.speed := MinD(C^.cruise, C^.speed + MaxSpeed * 0.08 * dt);

    C^.z := Increase(C^.z, dt * C^.speed, TrackLength);

    // did it run into the back of us?
    d := WrapDist(C^.z - pz);
    if (d < 0) and (-d < C^.hit) and (C^.speed > Speed) and
       Overlap(PlayerX, PlayerW, C^.offset, C^.w, 0.8) then
    begin
      strength := ClampD((C^.speed - Speed) / (MaxSpeed * 0.4), 0.15, 1);
      Speed := Speed + (C^.speed - Speed) * 0.6;
      C^.speed := Speed * 0.8;
      C^.z := Increase(pz, -C^.hit - 20, TrackLength);
      Crash(strength, PlayerBY - 60 * PlayerU);
    end;

    latVel := (C^.offset - oldOff) / dt;
    C^.yaw := C^.yaw + (ClampD(latVel * 1.2, -0.7, 0.7) - C^.yaw) * MinD(1, dt * 6);
  end;
end;

procedure Update(dt: Double);
var
  playerIdx, i: Integer;
  speedPct, dxs, travelled, steerTarget, pz, d, strength: Double;
  S: PSegment;
begin
  playerIdx := FindSegment(Position + PlayerZ);
  S := @Segments[playerIdx];
  speedPct := Speed / MaxSpeed;
  dxs := dt * 2 * speedPct;

  UpdateCars(dt);

  travelled := dt * Speed;
  if Position + travelled >= TrackLength then
  begin
    LastLap := CurLap;
    if (BestLap = 0) or (CurLap < BestLap) then BestLap := CurLap;
    CurLap := 0;
  end
  else if RaceStarted then
    CurLap := CurLap + dt;
  if Speed > 0 then RaceStarted := True;
  Position := Increase(Position, travelled, TrackLength);

  steerTarget := 0;
  if KeyLeft then
  begin
    PlayerX := PlayerX - dxs;
    steerTarget := -1;
  end
  else if KeyRight then
  begin
    PlayerX := PlayerX + dxs;
    steerTarget := 1;
  end;
  if Speed < 1 then steerTarget := steerTarget * 0.3;
  SteerAnim := SteerAnim + (steerTarget - SteerAnim) * MinD(1, dt * 8);

  PlayerX := PlayerX - dxs * speedPct * S^.curve * Centrifugal;

  if KeyFaster then Speed := Speed + AccelRate * dt
  else if KeySlower then Speed := Speed + Breaking * dt
  else Speed := Speed + Decel * dt;

  // off road: slow down, plough through bushes, crash into solid scenery
  if (PlayerX < -1) or (PlayerX > 1) then
  begin
    if Speed > OffRoadLimit then Speed := Speed + OffRoadDecel * dt;
    if Speed > MaxSpeed * 0.05 then
    begin
      SpawnDust(PlayerSX - PlayerW * RoadWidth / 2 * PlayerU * 0.75, PlayerBY - 5, 1 + Round(speedPct * 2));
      SpawnDust(PlayerSX + PlayerW * RoadWidth / 2 * PlayerU * 0.75, PlayerBY - 5, 1 + Round(speedPct * 2));
    end;
    for i := 0 to High(S^.sprites) do
      if Overlap(PlayerX, PlayerW, S^.sprites[i].offset,
                 SpriteWidth(S^.sprites[i].kind) / RoadWidth, 1) then
      begin
        if IsSolid(S^.sprites[i].kind) then
        begin
          Crash(0.9, PlayerBY - 150 * PlayerU);
          Speed := MaxSpeed / 5;
          Position := Increase(S^.p1.wz, -PlayerZ, TrackLength);
          Break;
        end
        else
          Speed := Speed - MaxSpeed * 0.6 * dt;   // bush: drag
      end;
  end;

  // we rear-end a vehicle in front
  pz := Increase(Position, PlayerZ, TrackLength);
  for i := 0 to High(Cars) do
  begin
    d := WrapDist(Cars[i].z - pz);
    if (d >= 0) and (d < PlayerHit) and (Speed > Cars[i].speed) and
       Overlap(PlayerX, PlayerW, Cars[i].offset, Cars[i].w, 0.8) then
    begin
      strength := ClampD((Speed - Cars[i].speed) / (MaxSpeed * 0.4), 0.15, 1);
      Speed := Cars[i].speed * (Cars[i].speed / Speed);
      Position := Increase(Cars[i].z, -PlayerHit - PlayerZ, TrackLength);
      Crash(strength, PlayerBY - 250 * PlayerU);
      Break;
    end;
  end;

  PlayerX := ClampD(PlayerX, -3, 3);
  Speed := ClampD(Speed, 0, MaxSpeed);

  SkyOffset := WrapUnit(SkyOffset + SkySpeed * S^.curve * travelled / SegLen);
  HillOffset := WrapUnit(HillOffset + HillSpeed * S^.curve * travelled / SegLen);

  UpdateEngine(dt, Speed / MaxSpeed, KeyFaster, (PlayerX < -1) or (PlayerX > 1));
  UpdateParticles(dt);
  if ShakeTime > 0 then ShakeTime := ShakeTime - dt;
  if CrashCooldown > 0 then CrashCooldown := CrashCooldown - dt;
end;

{ ------------------------------------------------------------------ HUD }

function FormatTime(t: Double): string;
var
  total: Integer;
begin
  if t <= 0 then Exit('-:--.-');
  total := Trunc(t * 10);
  Result := Format('%d:%.2d.%d', [total div 600, (total div 10) mod 60, total mod 10]);
end;

procedure DrawMirrorPanel;
var
  src, dst: TSDL_FRect;
begin
  if MirrorTex = nil then Exit;
  SetCol(MakeRGB(15, 15, 15));
  FillR(MirrorX - 7, MirrorY - 7, MirrorW + 14, MirrorH + 14);
  SetCol(MakeRGB(80, 80, 85));
  FillR(MirrorX - 3, MirrorY - 3, MirrorW + 6, MirrorH + 6);
  src.w := ScreenW;
  src.h := ScreenW * MirrorH / MirrorW;
  src.x := 0;
  src.y := ScreenH * 0.40;
  dst.x := MirrorX; dst.y := MirrorY; dst.w := MirrorW; dst.h := MirrorH;
  SDL_RenderTexture(Ren, MirrorTex, @src, @dst);
end;

procedure DrawTacho;
var
  bx, by, bw, bh, rpmPct: Double;
  r: TSDL_FRect;
begin
  bw := 250; bh := 18;
  bx := ScreenW - bw - 14;
  by := ScreenH - 34;
  rpmPct := ClampD(EngineRPM / MaxRPM, 0, 1);
  SetCol(MakeRGB(0, 0, 0), 140);
  FillR(bx - 6, by - 30, bw + 12, bh + 38);
  if rpmPct > 0.85 then SetCol(MakeRGB(235, 50, 40))
  else if rpmPct > 0.65 then SetCol(MakeRGB(240, 200, 40))
  else SetCol(MakeRGB(70, 200, 90));
  FillR(bx, by, bw * rpmPct, bh);
  SetCol(MakeRGB(220, 220, 220));
  r.x := bx; r.y := by; r.w := bw; r.h := bh;
  SDL_RenderRect(Ren, @r);
  DrawText(bx / 2, (by - 24) / 2, Format('GEAR %d %5d RPM', [Gear, Round(EngineRPM)]));
end;

function DayNightText: string;
begin
  if NightMode then Result := ' NIGHT' else Result := ' DAY';
end;

{ switch season / time, keep the choice in seasons.ini }
procedure ChangeLook(season: Integer; night: Boolean);
begin
  SetLook((season + 4) mod 4, night);
  try SaveSeasonChoice; except end;
end;

procedure DrawHUD;
var
  help: string;
begin
  SetCol(MakeRGB(0, 0, 0), 110);
  FillR(0, 0, ScreenW, 40);
  DrawText(8, 6, Format('SPEED %3d km/h', [Round(Speed / MaxSpeed * 240)]));
  DrawText(150, 6, 'LAP ' + FormatTime(CurLap));
  DrawText(260, 6, 'LAST ' + FormatTime(LastLap));
  DrawText(380, 6, 'BEST ' + FormatTime(BestLap));
  SetCol(MakeRGB(0, 0, 0), 90);
  FillR(0, 40, 190, 26);
  DrawText(8, 22, UpperCase(SeasonTitles[SeasonIdx]) + DayNightText);
  help := 'Arrows/WASD drive  R reset  C menu  F5 reload  F6 season  F7 day/night  ';
  if Muted then help := help + 'M sound on  ' else help := help + 'M mute  ';
  if MusicOn then help := help + 'N music off  ' else help := help + 'N music on  ';
  help := help + 'Esc quit';
  DrawText(10, ScreenH - 18, help, 1);
  DrawTacho;
end;

{ ---------------------------------------------------------------- menu }

procedure MenuMessage(const s: string);
begin
  MenuMsg := s;
  MenuMsgTime := 3;
end;

function MenuValue(i: Integer): string;
begin
  case i of
    0: Result := Format('%.0f', [Cam.height]);
    1: Result := Format('%.0f', [Cam.distance]);
    2: Result := Format('%.0f', [Cam.side]);
    3: Result := Format('%.0f deg', [Cam.pitch]);
    4: Result := Format('%.0f deg', [Cam.yaw]);
    5: Result := Format('%.0f deg', [Cam.fov]);
    6: Result := SeasonTitles[SeasonIdx];
    7: if NightMode then Result := 'Night' else Result := 'Day';
  else
    Result := '';
  end;
end;

procedure MenuAdjust(dir: Integer);
begin
  case MenuSel of
    0: Cam.height := Cam.height + dir * 50;
    1: Cam.distance := Cam.distance + dir * 25;
    2: Cam.side := Cam.side + dir * 50;
    3: Cam.pitch := Cam.pitch + dir;
    4: Cam.yaw := Cam.yaw + dir;
    5: Cam.fov := Cam.fov + dir * 2;
    6: ChangeLook(SeasonIdx + dir, NightMode);
    7: ChangeLook(SeasonIdx, not NightMode);
  end;
  ClampCamera(Cam);
end;

procedure MenuActivate;
begin
  case MenuSel of
    8: try
         SaveCameraFile(DataDir + 'camera.ini', Cam);
         MenuMessage('Saved to data\camera.ini');
       except
         on E: Exception do MenuMessage('Could not save: ' + E.Message);
       end;
    9: if LoadCameraFile(DataDir + 'camera.ini', Cam) then
         MenuMessage('Loaded data\camera.ini')
       else
         MenuMessage('No saved camera yet - use Save camera first');
    10: begin
         LoadDefaultCamera;
         MenuMessage('Default camera loaded (data\camera_default.ini)');
       end;
    11: begin
         ReloadData;
         MenuMessage('All data files reloaded');
       end;
    12: MenuOpen := False;
  end;
end;

procedure MenuKey(sc: TSDL_Scancode);
begin
  if sc = SDL_SCANCODE_UP then MenuSel := (MenuSel + MenuCount - 1) mod MenuCount
  else if sc = SDL_SCANCODE_DOWN then MenuSel := (MenuSel + 1) mod MenuCount
  else if sc = SDL_SCANCODE_LEFT then MenuAdjust(-1)
  else if sc = SDL_SCANCODE_RIGHT then MenuAdjust(1)
  else if (sc = SDL_SCANCODE_RETURN) or (sc = SDL_SCANCODE_KP_ENTER) or
          (sc = SDL_SCANCODE_SPACE) then MenuActivate
  else if (sc = SDL_SCANCODE_ESCAPE) or (sc = SDL_SCANCODE_C) or
          (sc = SDL_SCANCODE_TAB) then MenuOpen := False
  else if sc = SDL_SCANCODE_F5 then
  begin
    ReloadData;
    MenuMessage('All data files reloaded');
  end;
end;

procedure DrawMenu;
const
  PX = 20; PY = 56; PW = 470; RowH = 26;
var
  i: Integer;
  y, ph: Double;
  line: string;
begin
  ph := 70 + MenuCount * RowH + 70;
  SetCol(MakeRGB(0, 0, 0), 185);
  FillR(PX, PY, PW, ph);
  SetCol(MakeRGB(255, 200, 40));
  FillR(PX, PY, PW, 3);
  DrawText((PX + 14) / 2, (PY + 14) / 2, 'CAMERA & WORLD  (paused)');
  for i := 0 to MenuCount - 1 do
  begin
    y := PY + 52 + i * RowH;
    if (i = 6) or (i = MenuValues) then
    begin
      SetCol(MakeRGB(255, 255, 255), 50);
      FillR(PX + 12, y - 6, PW - 24, 1);
    end;
    if i = MenuSel then
    begin
      SetCol(MakeRGB(255, 200, 40), 95);
      FillR(PX + 8, y - 4, PW - 16, RowH - 4);
    end;
    if i < MenuValues then
      line := Format('%-16s %10s', [MenuNames[i], MenuValue(i)])
    else
      line := '> ' + MenuNames[i];
    if (i < MenuValues) and (i = MenuSel) then line := line + '   <  >';
    DrawText((PX + 18) / 1.5, y / 1.5, line, 1.5);
  end;
  y := PY + 52 + MenuCount * RowH + 8;
  DrawText(PX + 18, y, 'Up/Down select   Left/Right change   Enter run   C/Esc close', 1);
  DrawText(PX + 18, y + 16, 'Tip: CameraEditor.exe edits the camera with sliders', 1);
  if MenuMsgTime > 0 then
  begin
    SetCol(MakeRGB(255, 200, 40), 60);
    FillR(PX + 12, y + 34, PW - 24, 20);
    DrawText((PX + 18) / 1.5, (y + 37) / 1.5, MenuMsg, 1.5);
  end;
end;

{ --------------------------------------------------------------- render }

procedure Render;
var
  vp: TSDL_Rect;
  shaking: Boolean;
  bounce: Double;
begin
  shaking := ShakeTime > 0;
  if shaking then
  begin
    vp.x := Round((Random - 0.5) * 2 * ShakeAmp);
    vp.y := Round((Random - 0.5) * 2 * ShakeAmp);
    vp.w := ScreenW; vp.h := ScreenH;
    SDL_SetRenderViewport(Ren, @vp);
  end;

  bounce := 1.5 * Random * (Speed / MaxSpeed) * (ScreenH / 480) * RandomSign;
  if Abs(PlayerX) > 1 then bounce := bounce * 3;
  RenderWorld(Cam, Position + PlayerZ, PlayerX, True, PlayerColor, SteerAnim * 0.75, bounce);

  if shaking then SDL_SetRenderViewport(Ren, nil);

  DrawMirrorPanel;
  DrawMinimap(MapX, MapY, MapSize, Position + PlayerZ, True, -1, -1);
  DrawHUD;
end;

{ ----------------------------------------------------------------- main }

var
  Ev: TSDL_Event;
  Keys: PBoolean;
  Running: Boolean;
  Freq, LastTick, NowTick: UInt64;
  FrameTime, Acc: Double;
  sc: TSDL_Scancode;
  renderer: PSDL_Renderer;

begin
  Randomize;
  InitCommon;
  InitWorld;
  LoadAllData(True);

  MaxSpeed     := SegLen / StepTime;
  AccelRate    := MaxSpeed / 5;
  Breaking     := -MaxSpeed;
  Decel        := -MaxSpeed / 5;
  OffRoadDecel := -MaxSpeed / 2;
  OffRoadLimit := MaxSpeed / 4;
  BestLap      := 0;

  if not SDL_Init(SDL_INIT_VIDEO) then
  begin
    SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, 'Pseudo 3D Road', SDL_GetError, nil);
    Halt(1);
  end;
  renderer := nil;
  if not SDL_CreateWindowAndRenderer('Pseudo 3D Road - SDL3', ScreenW, ScreenH, 0, @Win, @renderer) then
  begin
    SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, 'Pseudo 3D Road', SDL_GetError, nil);
    SDL_Quit;
    Halt(1);
  end;
  Ren := renderer;
  SDL_SetRenderVSync(Ren, 1);
  SDL_SetRenderDrawBlendMode(Ren, SDL_BLENDMODE_BLEND);
  MirrorTex := SDL_CreateTexture(Ren, SDL_PIXELFORMAT_RGBA8888, SDL_TEXTUREACCESS_TARGET,
                                 ScreenW, ScreenH);

  InitAudio;
  ReloadWorldGraphics;
  BuildTrackFromFile(0);
  ResetGame;
  ResetMusic;
  BeforePlayerHook := @DrawDust;
  AfterPlayerHook := @DrawSparks;

  Freq := SDL_GetPerformanceFrequency;
  LastTick := SDL_GetPerformanceCounter;
  Acc := 0;
  Running := True;

  while Running do
  begin
    while SDL_PollEvent(@Ev) do
    begin
      if Ev._type = SDL_EVENT_QUIT then
        Running := False
      else if Ev._type = SDL_EVENT_KEY_DOWN then
      begin
        sc := Ev.key.scancode;
        if MenuOpen then
          MenuKey(sc)
        else
        begin
          if sc = SDL_SCANCODE_ESCAPE then Running := False;
          if sc = SDL_SCANCODE_R then ResetGame;
          if sc = SDL_SCANCODE_M then Muted := not Muted;
          if sc = SDL_SCANCODE_N then MusicOn := not MusicOn;
          if (sc = SDL_SCANCODE_C) or (sc = SDL_SCANCODE_TAB) then
          begin
            MenuOpen := True;
            MenuMsgTime := 0;
          end;
          if sc = SDL_SCANCODE_F5 then ReloadData;
          if sc = SDL_SCANCODE_F6 then ChangeLook(SeasonIdx + 1, NightMode);
          if sc = SDL_SCANCODE_F7 then ChangeLook(SeasonIdx, not NightMode);
        end;
      end;
    end;

    Keys := SDL_GetKeyboardState(nil);
    KeyLeft   := Keys[Ord(SDL_SCANCODE_LEFT)]  or Keys[Ord(SDL_SCANCODE_A)];
    KeyRight  := Keys[Ord(SDL_SCANCODE_RIGHT)] or Keys[Ord(SDL_SCANCODE_D)];
    KeyFaster := Keys[Ord(SDL_SCANCODE_UP)]    or Keys[Ord(SDL_SCANCODE_W)];
    KeySlower := Keys[Ord(SDL_SCANCODE_DOWN)]  or Keys[Ord(SDL_SCANCODE_S)];

    NowTick := SDL_GetPerformanceCounter;
    FrameTime := (NowTick - LastTick) / Freq;
    LastTick := NowTick;
    if FrameTime > 0.25 then FrameTime := 0.25;
    if MenuMsgTime > 0 then MenuMsgTime := MenuMsgTime - FrameTime;

    if MenuOpen then
      Acc := 0
    else
    begin
      Acc := Acc + FrameTime;
      while Acc >= StepTime do
      begin
        Update(StepTime);
        Acc := Acc - StepTime;
      end;
    end;

    FeedAudio(Speed / MaxSpeed, Abs(PlayerX) > 1.18, (Abs(PlayerX) > 1.0) and (Abs(PlayerX) <= 1.18));

    RenderMirror(MirrorTex, Position + PlayerZ, PlayerX);
    SDL_SetRenderDrawColor(Ren, 0, 0, 0, 255);
    SDL_RenderClear(Ren);
    Render;
    if MenuOpen then DrawMenu;
    SDL_RenderPresent(Ren);
  end;

  CloseAudio;
  FreeTextures;
  if MirrorTex <> nil then SDL_DestroyTexture(MirrorTex);
  SDL_DestroyRenderer(Ren);
  SDL_DestroyWindow(Win);
  SDL_Quit;
end.
