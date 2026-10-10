program ShapeEditor;

{ Pseudo 3D Road - scenery shape editor.
  Left: the shape files in data\shapes. Middle: the .shape file as text -
  type to edit it. Right: the shape drawn live, rebuilt as you type; the
  parts made by the line under the cursor glow yellow. Problems in the file
  are listed under the view (click one to jump to its line).
  Season and Day/Night buttons show the shape the way each season colours
  it ($named leaf colours, flowers, glows at night).
  "On the road" puts the edited shape into the game world, so you see it
  along the real track among the traffic (only for the names the game
  places: pine, tree, bush, flowerbush, billboard, lamp, chevron, warning).

  Keys: type in the text after clicking it; F2 save, F5 reload,
        Esc leaves the text (press again to quit). Outside the text:
        Left/Right variant, S side, N day/night, 1-4 season, Space drive. }

{$mode objfpc}{$H+}
{$APPTYPE GUI}

uses
  SysUtils, Classes, Math, SDL3, p3d_common, p3d_world, p3d_gui, p3d_textedit;

const
  WinW = 1280;
  WinH = 800;
  FilesX = 10;
  FilesY = 70;
  FilesW = 160;
  TextX = 180;
  TextY = 50;
  TextW = 610;
  TextH = 692;
  ViewX = 800;
  ViewY = 50;
  ViewW = 470;
  ViewH = 352;

var
  Win: PSDL_Window = nil;
  ViewTex: PSDL_Texture = nil;
  Ed: TTextEdit;
  Warnings, FileNames: TStringList;
  CurKey: string = 'pine';
  Dirty: Boolean = False;
  NeedParse: Boolean = True;
  EditShape: TShape;
  VariantNo: Integer = 0;
  RightSide: Boolean = False;
  Zoom: Double = 1;
  ShowCar: Boolean = True;
  AllVariants: Boolean = False;
  RoadMode: Boolean = False;
  Driving: Boolean = True;
  CarZ: Double = 0;
  MaxSpeed: Double;
  Status: string = '';
  StatusTime: Double = 0;
  NameMode: Boolean = False;
  NameBuf: string = '';
  QuitAsked: Boolean = False;
  Running: Boolean = True;
  FileScroll: Integer = 0;

procedure SetStatus(const s: string);
begin
  Status := s;
  StatusTime := 5;
end;

{ which sprite kind of the game uses this file (-1 = none) }
function KindOfKey(const key: string; out k: TSpriteKind): Boolean;
var
  i: TSpriteKind;
begin
  Result := False;
  k := skPine;
  for i := Low(TSpriteKind) to High(TSpriteKind) do
    if SameText(ShapeFile[i], key) then
    begin
      k := i;
      Exit(True);
    end;
end;

function IsDefaultName(const key: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to High(DefaultShapeNames) do
    if SameText(DefaultShapeNames[i], key) then Exit(True);
end;

{ ------------------------------------------------------------- files }

procedure ScanFiles;
var
  sr: TSearchRec;
begin
  FileNames.Clear;
  if FindFirst(DataDir + 'shapes' + DirectorySeparator + '*.shape', faAnyFile, sr) = 0 then
  begin
    repeat
      FileNames.Add(LowerCase(ChangeFileExt(sr.Name, '')));
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;
  FileNames.Sort;
end;

procedure OpenShape(const key: string);
begin
  LoadShapes;                       // the world gets the saved files back
  TE_LoadFile(Ed, ShapePath(key));
  Ed.Changed := False;
  CurKey := LowerCase(key);
  Dirty := False;
  NeedParse := True;
  QuitAsked := False;
  VariantNo := 0;
end;

procedure SaveShapeAs(const key: string);
begin
  try
    Ed.Lines.SaveToFile(ShapePath(key));
    CurKey := LowerCase(key);
    Dirty := False;
    ScanFiles;
    NeedParse := True;
    SetStatus('Saved ' + ShapePath(key));
  except
    on E: Exception do SetStatus('Could not save: ' + E.Message);
  end;
end;

procedure Parse;
var
  k: TSpriteKind;
begin
  Warnings.Clear;
  LoadShapeLines(Ed.Lines, EditShape, Warnings);
  TE_SetWarnings(Ed, Warnings);
  // the road view uses the edited shape for its kind
  if KindOfKey(CurKey, k) then Shapes[k] := EditShape;
  NeedParse := False;
end;

procedure ChangeLook(season: Integer; night: Boolean);
begin
  SetLook(season, night);           // also reloads the world's shapes from disk
  NeedParse := True;                // $named colours change with the season
end;

{ ------------------------------------------------------------- drawing }

procedure DrawFiles;
var
  i, n, rows: Integer;
  y: Single;
begin
  GuiText(FilesX, FilesY - 16, 'Shapes', 1, 170, 175, 190);
  rows := 30;
  if GuiInside(FilesX, FilesY, FilesW, rows * 20) and (WheelY <> 0) then
    FileScroll := EnsureRange(FileScroll - Round(WheelY), 0, Max(0, FileNames.Count - rows));
  n := Min(FileNames.Count - FileScroll, rows);
  for i := 0 to n - 1 do
  begin
    y := FilesY + i * 20;
    if GuiButton(FilesX, y, FilesW, 18, FileNames[FileScroll + i],
                 SameText(FileNames[FileScroll + i], CurKey)) then
    begin
      if Dirty then
        SetStatus('Save first (F2) - or Reload to drop the changes')
      else
        OpenShape(FileNames[FileScroll + i]);
    end;
  end;
end;

procedure DrawGroundAndSky;
var
  y: Integer;
begin
  DrawBackground(0);
  y := Round(ViewCY);
  SetCol(Fogged(ColGrassL, 1));
  FillR(0, y, ScreenW, ScreenH - y);
  // a strip of road in front for scale
  SetCol(Fogged(ColRoadD, 1));
  FillR(0, y + (ScreenH - y) * 0.55, ScreenW, (ScreenH - y) * 0.3);
  SetCol(Fogged(MakeRGB(220, 220, 220), 1));
  FillR(0, y + (ScreenH - y) * 0.55, ScreenW, 4);
end;

procedure RenderView;
var
  i, cnt: Integer;
  u, sx, sy, w, h, span, carU, gap: Double;
  sp: TSprite;
  dst: TSDL_FRect;
  car: Integer;
begin
  if ViewTex = nil then Exit;
  SDL_SetRenderTarget(Ren, ViewTex);
  SDL_SetRenderDrawColor(Ren, 0, 0, 0, 255);
  SDL_RenderClear(Ren);

  ShapeHighlightLine := Ed.CurRow;
  if RoadMode then
  begin
    ShapeHighlightLine := -1;       // keep the road view clean
    RenderWorld(Cam, CarZ, 0, True, PlayerColor, 0, 0);
  end
  else
  begin
    ViewDepth := CameraDepth;
    ViewCX := ScreenW / 2;
    ViewCY := ScreenH * 0.66;
    SkyOffset := 0;
    HillOffset := 0;
    DrawGroundAndSky;

    w := MaxD(EditShape.width, 50);
    h := MaxD(EditShape.height, 50);
    if AllVariants then cnt := Max(1, EditShape.variants) else cnt := 1;
    car := -1;
    if ShowCar and (Length(Models) > 0) then car := EnsureRange(PlayerModel, 0, High(Models));
    gap := w * 0.25;
    span := cnt * w + (cnt - 1) * gap;
    if car >= 0 then span := span + Models[car].width * 1.4 + gap;
    u := MinD(ScreenH * 0.6 / h, ScreenW * 0.85 / span) * Zoom;
    sy := ViewCY + 40;
    sx := ScreenW / 2 - span * u / 2 + w * u / 2;

    BeginGlows;
    for i := 0 to cnt - 1 do
    begin
      sp.kind := skPine;
      if RightSide then sp.offset := 1.5 else sp.offset := -1.5;
      if AllVariants then sp.variant := i else sp.variant := VariantNo;
      DrawShapeAt(EditShape, sp, sx, sy, u, ScreenH, 1);
      if not AllVariants then Break;
      sx := sx + (w + gap) * u;
    end;
    if car >= 0 then
    begin
      // the car stands a little behind, seen from the rear, for scale
      if AllVariants then sx := sx - w * u / 2 + gap * u
      else sx := sx + w * u / 2 + gap * u;
      carU := u;
      DrawCarAngle(Models[car], sx + Models[car].width * 0.7 * carU, sy, carU, PlayerColor, 1, 0.5, ScreenH);
    end;
    FlushGlows;
    DrawWeather;
  end;

  SDL_SetRenderTarget(Ren, nil);
  dst.x := ViewX; dst.y := ViewY; dst.w := ViewW; dst.h := ViewH;
  SDL_RenderTexture(Ren, ViewTex, nil, @dst);
  GuiColor(70, 78, 92);
  GuiFrame(ViewX, ViewY, ViewW, ViewH);
end;

procedure DrawViewControls;
var
  y: Single;
  i, n, d: Integer;
  k: TSpriteKind;
  s, sideText: string;
begin
  if not RoadMode and GuiInside(ViewX, ViewY, ViewW, ViewH) and (WheelY <> 0) then
    Zoom := ClampD(Zoom * (1 + WheelY * 0.1), 0.3, 4);

  y := ViewY + ViewH + 8;
  if GuiButton(ViewX, y, 150, 24, 'Shape view', not RoadMode) then RoadMode := False;
  if GuiButton(ViewX + 156, y, 150, 24, 'On the road', RoadMode) then RoadMode := True;
  if GuiButton(ViewX + 312, y, 158, 24, 'Drive (Space)', Driving) then Driving := not Driving;
  y := y + 30;

  // season and time
  for i := 0 to 3 do
    if GuiButton(ViewX + i * 80, y, 76, 22, SeasonTitles[i], SeasonIdx = i) then
      ChangeLook(i, NightMode);
  if GuiButton(ViewX + 324, y, 70, 22, 'Day', not NightMode) then ChangeLook(SeasonIdx, False);
  if GuiButton(ViewX + 400, y, 70, 22, 'Night', NightMode) then ChangeLook(SeasonIdx, True);
  y := y + 28;

  // variant, side, zoom
  d := GuiSpin(ViewX, y, 150, 'Variant', IntToStr(VariantNo));
  if d <> 0 then VariantNo := EnsureRange(VariantNo + d, -9, 9);
  if RightSide then sideText := 'right' else sideText := 'left';
  if GuiSpin(ViewX + 160, y, 150, 'Side', sideText) <> 0 then RightSide := not RightSide;
  if GuiButton(ViewX + 320, y, 150, 22, 'All variants', AllVariants) then AllVariants := not AllVariants;
  y := y + 28;
  GuiSlider(ViewX, y, 228, 'Zoom', Zoom, 0.3, 4, 2);
  if GuiButton(ViewX + 242, y + 8, 110, 22, 'Car for scale', ShowCar) then ShowCar := not ShowCar;
  if GuiButton(ViewX + 360, y + 8, 110, 22, 'Weather', ShowWeather) then ShowWeather := not ShowWeather;
  y := y + 38;

  // info
  s := Format('w %.0f  h %.0f  shadow %.0f  variants %d  %d commands',
              [EditShape.width, EditShape.height, EditShape.shadow, EditShape.variants, Length(EditShape.cmds)]);
  if EditShape.solid then s := s + '  solid';
  GuiText(ViewX, y, s);
  if KindOfKey(CurKey, k) then
    GuiText(ViewX, y + 14, Format('Placed by the game as "%s"   (yellow = line %d)', [ShapeFile[k], Ed.CurRow + 1]),
            1, 170, 175, 190)
  else
    GuiText(ViewX, y + 14, 'Not placed by the game - only the 8 default names are', 1, 255, 190, 110);
  y := y + 34;

  // problems
  if Warnings.Count = 0 then
    GuiText(ViewX, y, 'No problems found.', 1, 120, 220, 140)
  else
  begin
    GuiText(ViewX, y, Format('%d problem(s) - click to jump:', [Warnings.Count]), 1, 255, 140, 90);
    n := Min(Warnings.Count, 8);
    for i := 0 to n - 1 do
    begin
      s := Warnings[i];
      if Length(s) > 58 then s := Copy(s, 1, 56) + '..';
      GuiText(ViewX, y + 16 + i * 14, s, 1, 255, 170, 150);
      if MousePressed and GuiInside(ViewX, y + 14 + i * 14, ViewW, 14) and
         (TE_LineOfWarning(Warnings[i]) >= 0) then
        TE_GotoLine(Ed, TE_LineOfWarning(Warnings[i]));
    end;
  end;
end;

procedure DrawNameBox;
begin
  GuiColor(0, 0, 0, 150);
  GuiFill(0, 0, WinW, WinH);
  GuiPanel(WinW / 2 - 220, WinH / 2 - 70, 440, 140, 'Save as new shape');
  GuiText(WinW / 2 - 200, WinH / 2 - 26, 'Name (letters, digits, - and _):');
  GuiColor(20, 23, 30);
  GuiFill(WinW / 2 - 200, WinH / 2 - 8, 400, 26);
  GuiText(WinW / 2 - 192, WinH / 2 - 1, NameBuf + '_', 1.5, 255, 230, 120);
  GuiText(WinW / 2 - 200, WinH / 2 + 34, 'Enter = save    Esc = cancel', 1, 170, 175, 190);
end;

procedure DrawUI(dt: Double);
var
  y: Single;
begin
  GuiColor(16, 18, 24);
  GuiFill(0, 0, WinW, WinH);
  GuiText(10, 14, 'SHAPE EDITOR', 2, 255, 210, 80);
  GuiText(230, 20, ShapePath(CurKey));
  if Dirty then GuiText(WinW - 150, 20, '* not saved', 1, 255, 140, 90);

  DrawFiles;
  TE_Draw(Ed, dt, not NameMode);
  GuiText(TextX, TextY + TextH + 4, Format('%s.shape   line %d/%d  col %d',
          [CurKey, Ed.CurRow + 1, Ed.Lines.Count, Ed.CurCol + 1]), 1, 170, 175, 190);
  RenderView;
  DrawViewControls;

  y := WinH - 38;
  if GuiButton(FilesX, y, 76, 28, 'Save F2') then SaveShapeAs(CurKey);
  if GuiButton(FilesX + 84, y, 76, 28, 'Save as') then
  begin
    NameMode := True;
    NameBuf := '';
  end;
  if GuiButton(FilesX, y - 34, 76, 28, 'Reload') then
  begin
    OpenShape(CurKey);
    SetStatus('Reloaded ' + ShapePath(CurKey));
  end;
  if GuiButton(FilesX + 84, y - 34, 76, 28, 'Default') then
  begin
    if IsDefaultName(CurKey) then
    begin
      Ed.Lines.Clear;
      WriteShapeText(CurKey, Ed.Lines);
      TE_GotoLine(Ed, 0);
      Ed.Changed := True;
      SetStatus('Default text of ' + CurKey + ' loaded - F2 saves it');
    end
    else
    begin
      WriteDefaultShapes(False);
      ScanFiles;
      SetStatus('Missing default shapes were written again');
    end;
  end;
  if GuiButton(TextX + 300, TextY + TextH + 2, 150, 18, 'Duplicate line') then TE_DuplicateLine(Ed);
  if GuiButton(TextX + 460, TextY + TextH + 2, 150, 18, 'Delete line') then TE_DeleteLine(Ed);
  if StatusTime > 0 then GuiText(TextX, WinH - 20, Status, 1, 255, 220, 120);

  if NameMode then DrawNameBox;
end;

{ ----------------------------------------------------------------- main }

procedure HandleKey(sc: TSDL_Scancode);
var
  key: string;
begin
  if NameMode then
  begin
    if sc = SDL_SCANCODE_ESCAPE then NameMode := False
    else if sc = SDL_SCANCODE_BACKSPACE then Delete(NameBuf, Length(NameBuf), 1)
    else if (sc = SDL_SCANCODE_RETURN) or (sc = SDL_SCANCODE_KP_ENTER) then
    begin
      key := LowerCase(Trim(NameBuf));
      NameMode := False;
      if key <> '' then SaveShapeAs(key);
    end;
    Exit;
  end;

  if sc = SDL_SCANCODE_F2 then SaveShapeAs(CurKey)
  else if sc = SDL_SCANCODE_F5 then
  begin
    OpenShape(CurKey);
    SetStatus('Reloaded ' + ShapePath(CurKey));
  end
  else if Ed.Focus then
  begin
    if sc = SDL_SCANCODE_ESCAPE then Ed.Focus := False
    else TE_Key(Ed, sc);
  end
  else if sc = SDL_SCANCODE_SPACE then Driving := not Driving
  else if sc = SDL_SCANCODE_LEFT then VariantNo := Max(-9, VariantNo - 1)
  else if sc = SDL_SCANCODE_RIGHT then VariantNo := Min(9, VariantNo + 1)
  else if sc = SDL_SCANCODE_S then RightSide := not RightSide
  else if sc = SDL_SCANCODE_N then ChangeLook(SeasonIdx, not NightMode)
  else if sc = SDL_SCANCODE_1 then ChangeLook(0, NightMode)
  else if sc = SDL_SCANCODE_2 then ChangeLook(1, NightMode)
  else if sc = SDL_SCANCODE_3 then ChangeLook(2, NightMode)
  else if sc = SDL_SCANCODE_4 then ChangeLook(3, NightMode)
  else if sc = SDL_SCANCODE_ESCAPE then
  begin
    if Dirty and not QuitAsked then
    begin
      QuitAsked := True;
      SetStatus('Unsaved changes - press Esc again to quit without saving');
    end
    else Running := False;
  end;
end;

procedure HandleText(const s: string);
var
  i: Integer;
begin
  if NameMode then
  begin
    for i := 1 to Length(s) do
      if (s[i] in ['a'..'z', 'A'..'Z', '0'..'9', '-', '_']) and (Length(NameBuf) < 32) then
        NameBuf := NameBuf + s[i];
  end
  else if Ed.Focus then
    TE_Text(Ed, s);
end;

var
  Ev: TSDL_Event;
  Freq, LastTick, NowTick: UInt64;
  FrameTime: Double;
  renderer: PSDL_Renderer;
  i: Integer;

begin
  Randomize;
  InitCommon;
  InitWorld;
  LoadAllData(True);
  MaxSpeed := SegLen / StepTime;
  Warnings := TStringList.Create;
  FileNames := TStringList.Create;
  TE_Init(Ed, TextX, TextY, TextW, TextH);

  if not SDL_Init(SDL_INIT_VIDEO) then Halt(1);
  renderer := nil;
  if not SDL_CreateWindowAndRenderer('Pseudo 3D Road - Shape editor', WinW, WinH, 0, @Win, @renderer) then
  begin
    SDL_Quit;
    Halt(1);
  end;
  Ren := renderer;
  GuiRen := renderer;
  SDL_SetRenderVSync(Ren, 1);
  SDL_SetRenderDrawBlendMode(Ren, SDL_BLENDMODE_BLEND);
  ViewTex := SDL_CreateTexture(Ren, SDL_PIXELFORMAT_RGBA8888, SDL_TEXTUREACCESS_TARGET, ScreenW, ScreenH);
  SDL_StartTextInput(Win);

  ReloadWorldGraphics;
  BuildTrackFromFile(99);
  ResetTraffic(MaxSpeed);
  ScanFiles;
  if FileNames.IndexOf('tree') >= 0 then OpenShape('tree')
  else if FileNames.Count > 0 then OpenShape(FileNames[0])
  else OpenShape('pine');

  Freq := SDL_GetPerformanceFrequency;
  LastTick := SDL_GetPerformanceCounter;
  while Running do
  begin
    GuiBeginFrame;
    while SDL_PollEvent(@Ev) do
    begin
      GuiEvent(Ev);
      if Ev._type = SDL_EVENT_QUIT then Running := False
      else if Ev._type = SDL_EVENT_KEY_DOWN then HandleKey(Ev.key.scancode)
      else if Ev._type = SDL_EVENT_TEXT_INPUT then HandleText(string(Ev.text.text));
    end;

    NowTick := SDL_GetPerformanceCounter;
    FrameTime := (NowTick - LastTick) / Freq;
    LastTick := NowTick;
    if FrameTime > 0.25 then FrameTime := 0.25;
    if StatusTime > 0 then StatusTime := StatusTime - FrameTime;

    if Ed.Changed then
    begin
      Ed.Changed := False;
      Dirty := True;
      QuitAsked := False;
      NeedParse := True;
    end;
    if NeedParse then Parse;

    if RoadMode and Driving then
    begin
      CarZ := Increase(CarZ, 0.45 * MaxSpeed * FrameTime, TrackLength);
      for i := 0 to High(Cars) do
        Cars[i].z := Increase(Cars[i].z, Cars[i].speed * FrameTime, TrackLength);
    end;

    SDL_SetRenderDrawColor(Ren, 0, 0, 0, 255);
    SDL_RenderClear(Ren);
    DrawUI(FrameTime);
    SDL_RenderPresent(Ren);
  end;

  SDL_StopTextInput(Win);
  TE_Free(Ed);
  FreeTextures;
  if ViewTex <> nil then SDL_DestroyTexture(ViewTex);
  SDL_DestroyRenderer(Ren);
  SDL_DestroyWindow(Win);
  SDL_Quit;
end.
