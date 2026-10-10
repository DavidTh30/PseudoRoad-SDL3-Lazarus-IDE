program CameraEditor;

{ Pseudo 3D Road - camera editor.
  Shows the real road, scenery, traffic and your car while you change the
  camera with sliders. Save writes data\camera.ini (used by the game),
  "Save as default" writes data\camera_default.ini.

  Keys: Space drive/stop, H hide panel, F2 save, F5 reload, Esc quit }

{$mode objfpc}{$H+}
{$POINTERMATH ON}
{$APPTYPE GUI}

uses
  SysUtils, Math, SDL3, p3d_common, p3d_world, p3d_gui;

var
  Win: PSDL_Window = nil;
  CarZ: Double = 0;
  Lane: Double = 0;
  Steer: Double = 0;
  DriveSpeed: Double = 0.4;
  Driving: Boolean = True;
  PanelOn: Boolean = True;
  MaxSpeed: Double;
  Status: string = '';
  StatusTime: Double = 0;
  Dirty: Boolean = False;

procedure SetStatus(const s: string);
begin
  Status := s;
  StatusTime := 4;
end;

procedure UpdateSim(dt: Double);
var
  i: Integer;
  travelled, curve: Double;
begin
  if Driving then
  begin
    travelled := DriveSpeed * MaxSpeed * dt;
    curve := Segments[FindSegment(CarZ)].curve;
    CarZ := Increase(CarZ, travelled, TrackLength);
    SkyOffset := WrapUnit(SkyOffset + 0.001 * curve * travelled / SegLen);
    HillOffset := WrapUnit(HillOffset + 0.002 * curve * travelled / SegLen);
  end;
  for i := 0 to High(Cars) do
    Cars[i].z := Increase(Cars[i].z, Cars[i].speed * dt, TrackLength);
end;

procedure DrawPanel;
var
  y: Single;
begin
  GuiPanel(12, 12, 330, 744, 'Camera');
  y := 50;
  if GuiSlider(28, y, 298, 'Height above road', Cam.height, 200, 4000, 0) then Dirty := True;
  y := y + 40;
  if GuiSlider(28, y, 298, 'Distance behind car', Cam.distance, 300, 4000, 0) then Dirty := True;
  y := y + 40;
  if GuiSlider(28, y, 298, 'Side offset (+ right)', Cam.side, -2500, 2500, 0) then Dirty := True;
  y := y + 40;
  if GuiSlider(28, y, 298, 'Pitch, degrees (+ down)', Cam.pitch, -20, 20, 0) then Dirty := True;
  y := y + 40;
  if GuiSlider(28, y, 298, 'Yaw, degrees (+ right)', Cam.yaw, -35, 35, 0) then Dirty := True;
  y := y + 40;
  if GuiSlider(28, y, 298, 'Field of view, degrees', Cam.fov, 50, 150, 0) then Dirty := True;
  y := y + 48;

  if GuiButton(28, y, 145, 28, 'Save (F2)') then
  begin
    try
      SaveCameraFile(DataDir + 'camera.ini', Cam);
      Dirty := False;
      SetStatus('Saved data\camera.ini');
    except
      on E: Exception do SetStatus('Could not save: ' + E.Message);
    end;
  end;
  if GuiButton(181, y, 145, 28, 'Load saved (F5)') then
  begin
    if LoadCameraFile(DataDir + 'camera.ini', Cam) then
    begin
      Dirty := False;
      SetStatus('Loaded data\camera.ini');
    end
    else SetStatus('No data\camera.ini yet');
  end;
  y := y + 34;
  if GuiButton(28, y, 145, 28, 'Load default') then
  begin
    LoadDefaultCamera;
    Dirty := True;
    SetStatus('Loaded data\camera_default.ini');
  end;
  if GuiButton(181, y, 145, 28, 'Save as default') then
  begin
    try
      SaveCameraFile(DataDir + 'camera_default.ini', Cam);
      SetStatus('Saved data\camera_default.ini');
    except
      on E: Exception do SetStatus('Could not save: ' + E.Message);
    end;
  end;
  y := y + 34;
  if GuiButton(28, y, 298, 28, 'Built-in camera') then
  begin
    Cam := BuiltInCamera;
    Dirty := True;
    SetStatus('Built-in camera (not saved yet)');
  end;
  y := y + 48;

  GuiText(28, y, 'Preview', 1.5, 255, 210, 80);
  y := y + 24;
  if GuiButton(28, y, 298, 28, 'Drive (Space)', Driving) then Driving := not Driving;
  y := y + 38;
  GuiSlider(28, y, 298, 'Speed', DriveSpeed, 0, 1, 2);
  y := y + 40;
  GuiSlider(28, y, 298, 'Lane (-1 left edge .. 1 right edge)', Lane, -1.5, 1.5, 2);
  y := y + 40;
  GuiSlider(28, y, 298, 'Steering animation', Steer, -1, 1, 2);
  y := y + 44;

  if Dirty then GuiText(28, y, '* camera not saved', 1, 255, 140, 90);
  if StatusTime > 0 then GuiText(28, y + 18, Status, 1, 255, 220, 120);
  GuiText(28, 730, 'H hides this panel   Esc quits', 1, 170, 175, 190);
end;

var
  Ev: TSDL_Event;
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
  MaxSpeed := SegLen / StepTime;

  if not SDL_Init(SDL_INIT_VIDEO) then Halt(1);
  renderer := nil;
  if not SDL_CreateWindowAndRenderer('Pseudo 3D Road - Camera editor', ScreenW, ScreenH, 0, @Win, @renderer) then
  begin
    SDL_Quit;
    Halt(1);
  end;
  Ren := renderer;
  GuiRen := renderer;
  SDL_SetRenderVSync(Ren, 1);
  SDL_SetRenderDrawBlendMode(Ren, SDL_BLENDMODE_BLEND);

  ReloadWorldGraphics;
  BuildTrackFromFile(12345);
  ResetTraffic(MaxSpeed);

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
        else if sc = SDL_SCANCODE_SPACE then Driving := not Driving
        else if sc = SDL_SCANCODE_H then PanelOn := not PanelOn
        else if sc = SDL_SCANCODE_F2 then
        begin
          try
            SaveCameraFile(DataDir + 'camera.ini', Cam);
            Dirty := False;
            SetStatus('Saved data\camera.ini');
          except
            on E: Exception do SetStatus('Could not save: ' + E.Message);
          end;
        end
        else if sc = SDL_SCANCODE_F5 then
        begin
          if LoadCameraFile(DataDir + 'camera.ini', Cam) then
          begin
            Dirty := False;
            SetStatus('Loaded data\camera.ini');
          end;
        end;
      end;
    end;

    NowTick := SDL_GetPerformanceCounter;
    FrameTime := (NowTick - LastTick) / Freq;
    LastTick := NowTick;
    if FrameTime > 0.25 then FrameTime := 0.25;
    if StatusTime > 0 then StatusTime := StatusTime - FrameTime;
    Acc := Acc + FrameTime;
    while Acc >= StepTime do
    begin
      UpdateSim(StepTime);
      Acc := Acc - StepTime;
    end;

    SDL_SetRenderDrawColor(Ren, 0, 0, 0, 255);
    SDL_RenderClear(Ren);
    RenderWorld(Cam, CarZ, Lane, True, PlayerColor, Steer, 0);
    DrawMinimap(ScreenW - 196, 10, 186, CarZ, True, -1, -1);
    if PanelOn then DrawPanel
    else DrawText(10, ScreenH - 18, 'H shows the camera panel', 1);
    SDL_RenderPresent(Ren);
  end;

  FreeTextures;
  SDL_DestroyRenderer(Ren);
  SDL_DestroyWindow(Win);
  SDL_Quit;
end.
